import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:loghound/loghound.dart';
import 'package:loghound/src/cli.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service_io.dart';

void main() {
  group('loghound run real VM Service', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('loghound-real-vm-');
    });

    tearDown(() async {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });

    test(
      'retries startup connection and resumes real start-paused main and worker isolates',
      () async {
        final project = Directory('${directory.path}/project')
          ..createSync(recursive: true);
        final root = Directory('${directory.path}/logs');
        final app = File('${project.path}/paused_worker_app.dart');
        final serviceInfo = File('${project.path}/service-info.json');
        await app.writeAsString(_pausedWorkerAppSource);

        Process? dartProcess;
        final appStdout = StringBuffer();
        final appStderr = StringBuffer();
        final loghoundOut = StringBuffer();
        final loghoundErr = StringBuffer();
        String? serviceUri;
        int? dartExitCode;
        var processRunnerReturning = false;
        var connectAttempts = 0;

        addTearDown(() {
          dartProcess?.kill(ProcessSignal.sigkill);
        });

        final exitCode =
            await runLogHoundCli(
              ['run', '--root', root.path],
              out: loghoundOut,
              err: loghoundErr,
              currentDirectory: project,
              processRunner: (command, args, {workingDirectory}) async {
                final uriFile = _vmServiceUriFileFrom(args);
                await uriFile.parent.create(recursive: true);

                dartProcess = await Process.start(Platform.resolvedExecutable, [
                  '--enable-vm-service=0',
                  '--pause-isolates-on-start',
                  '--write-service-info=${serviceInfo.path}',
                  app.path,
                ], workingDirectory: project.path);

                final stdoutSubscription = dartProcess!.stdout
                    .transform(utf8.decoder)
                    .listen(appStdout.write);
                final stderrSubscription = dartProcess!.stderr
                    .transform(utf8.decoder)
                    .listen(appStderr.write);

                try {
                  serviceUri = await _readDartVmServiceUri(serviceInfo).timeout(
                    const Duration(seconds: 10),
                    onTimeout: () {
                      fail(
                        'Dart VM Service URI was not written.\n'
                        'app stdout:\n$appStdout\napp stderr:\n$appStderr',
                      );
                    },
                  );
                  await uriFile.writeAsString(serviceUri!);

                  dartExitCode = await dartProcess!.exitCode;
                  processRunnerReturning = true;
                  return dartExitCode!;
                } finally {
                  unawaited(
                    Future.wait<void>([
                      stdoutSubscription.cancel(),
                      stderrSubscription.cancel(),
                    ]).timeout(const Duration(seconds: 1), onTimeout: () => []),
                  );
                }
              },
              vmServiceConnector: (wsUri) async {
                connectAttempts++;
                if (connectAttempts == 1) {
                  throw const SocketException('Connection refused');
                }
                return vmServiceConnectUri(wsUri);
              },
            ).timeout(
              const Duration(seconds: 20),
              onTimeout: () async {
                final isolateDump = await _dumpIsolates(serviceUri);
                dartProcess?.kill(ProcessSignal.sigkill);
                fail(
                  'loghound run did not finish.\n'
                  'connect attempts: $connectAttempts\n'
                  'dart exit code: $dartExitCode\n'
                  'process runner returning: $processRunnerReturning\n'
                  'service URI: $serviceUri\n'
                  'isolates:\n$isolateDump\n'
                  'loghound stdout:\n$loghoundOut\n'
                  'loghound stderr:\n$loghoundErr\n'
                  'app stdout:\n$appStdout\n'
                  'app stderr:\n$appStderr',
                );
              },
            );

        expect(exitCode, 0);
        expect(connectAttempts, greaterThanOrEqualTo(2));

        final records = await JsonlLogStore(
          File('${root.path}/e2e/test/sessions/real-vm-session.jsonl'),
        ).readAll();
        expect(records, hasLength(1));
        expect(records.single, containsPair('name', 'worker-isolate-resumed'));
      },
      timeout: const Timeout(Duration(seconds: 40)),
    );
  });
}

File _vmServiceUriFileFrom(List<String> args) {
  final uriFileArg = args.firstWhere(
    (arg) => arg.startsWith('--vmservice-out-file='),
  );
  return File(uriFileArg.split('=').last);
}

Future<String> _readDartVmServiceUri(File serviceInfo) async {
  while (true) {
    if (await serviceInfo.exists()) {
      final text = (await serviceInfo.readAsString()).trim();
      if (text.isNotEmpty) {
        final decoded = jsonDecode(text) as Map<String, Object?>;
        final uri = decoded['uri'] ?? decoded['serverUri'];
        if (uri is String && uri.isNotEmpty) {
          return uri;
        }
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<String> _dumpIsolates(String? serviceUri) async {
  if (serviceUri == null) {
    return 'VM Service URI was not available.';
  }
  try {
    final service = await vmServiceConnectUri(
      logHoundVmServiceWebSocketUri(serviceUri).toString(),
    );
    try {
      final vm = await service.getVM();
      final buffer = StringBuffer();
      for (final isolate in vm.isolates ?? const []) {
        final id = isolate.id;
        if (id == null) {
          continue;
        }
        final details = await service.getIsolate(id);
        buffer.writeln(
          '${details.name ?? id}: ${details.pauseEvent?.kind ?? 'none'}',
        );
      }
      return buffer.toString().trim();
    } finally {
      await service.dispose();
    }
  } on Object catch (error) {
    return 'Failed to inspect isolates: $error';
  }
}

const _pausedWorkerAppSource = r'''
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:isolate';

void worker(SendPort sendPort) {
  print('worker-started');
  sendPort.send('worker-resumed');
}

Future<void> main() async {
  print('main-started');
  final receivePort = ReceivePort();
  await Isolate.spawn(
    worker,
    receivePort.sendPort,
    debugName: 'UTF8 decode for "assets/language/seed.json"',
  );
  await receivePort.first.timeout(const Duration(seconds: 10));
  receivePort.close();
  print('worker-message-received');

  developer.postEvent('loghound.log', {
    'timestamp': '2026-07-07T00:00:00.000',
    'app_id': 'real-vm-app',
    'flavor': 'e2e',
    'platform': 'test',
    'session_id': 'real-vm-session',
    'kind': 'action',
    'name': 'worker-isolate-resumed',
  });
  print('event-posted');

  await Future<void>.delayed(const Duration(milliseconds: 300));
}
''';
