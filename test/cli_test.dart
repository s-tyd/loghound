import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:loghound/loghound.dart';
import 'package:loghound/src/cli.dart';
import 'package:loghound/src/loghound_settings.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

void main() {
  group('runLogHoundCli', () {
    late Directory directory;
    late File file;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('loghound-cli-');
      file = File('${directory.path}/app.jsonl');
      final store = JsonlLogStore(file);
      await store.append({
        'timestamp': '2026-06-27T10:00:00.000',
        'name': 'HTTP',
        'level': 0,
        'message': 'GET /spots',
      });
      await store.append({
        'timestamp': '2026-06-27T10:01:00.000',
        'name': 'Purchase',
        'level': 900,
        'message': 'purchase natural-wine failed',
        'trace_id': 'trace-1',
        'data': {'request_id': 'request-1'},
      });
      await store.append({
        'timestamp': '2026-06-27T10:02:00.000',
        'name': 'Purchase',
        'level': 1000,
        'message': 'purchase guidebook failed',
        'trace_id': 'trace-2',
      });
    });

    tearDown(() async {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });

    test('query prints matching JSON lines', () async {
      final out = StringBuffer();

      final exitCode = await runLogHoundCli([
        'query',
        '--file',
        file.path,
        '--contains',
        'natural-wine',
      ], out: out);

      expect(exitCode, 0);
      final lines = out.toString().trim().split('\n');
      expect(lines, hasLength(1));
      expect(jsonDecode(lines.single), containsPair('level', 900));
    });

    test('query filters by related identifiers', () async {
      final out = StringBuffer();

      final exitCode = await runLogHoundCli([
        'query',
        '--file',
        file.path,
        '--trace-id',
        'trace-1',
        '--request-id',
        'request-1',
      ], out: out);

      expect(exitCode, 0);
      final lines = out.toString().trim().split('\n');
      expect(lines, hasLength(1));
      expect(
        jsonDecode(lines.single),
        containsPair('message', 'purchase natural-wine failed'),
      );
    });

    test('tail prints the last count records', () async {
      final out = StringBuffer();

      final exitCode = await runLogHoundCli([
        'tail',
        '--file',
        file.path,
        '--count',
        '2',
      ], out: out);

      expect(exitCode, 0);
      final lines = out.toString().trim().split('\n');
      expect(lines, hasLength(2));
      expect(jsonDecode(lines.first), containsPair('level', 900));
      expect(jsonDecode(lines.last), containsPair('level', 1000));
    });

    test('tail reads routed logs by default', () async {
      final previousCurrent = Directory.current;
      Directory.current = directory.path;
      addTearDown(() {
        Directory.current = previousCurrent;
      });
      await LogHoundDirectoryStore(Directory('.loghound')).append({
        'timestamp': '2026-06-27T10:00:00.000',
        'app_id': 'guide-app',
        'flavor': 'staging',
        'platform': 'ios',
        'session_id': 'session-1',
        'kind': 'action',
        'name': 'search.submit',
      });
      final out = StringBuffer();

      final exitCode = await runLogHoundCli(['tail'], out: out);

      expect(exitCode, 0);
      expect(out.toString(), contains('search.submit'));
    });

    test(
      'latest-error prints the latest record at warning level or higher',
      () async {
        final out = StringBuffer();

        final exitCode = await runLogHoundCli([
          'latest-error',
          '--file',
          file.path,
        ], out: out);

        expect(exitCode, 0);
        expect(
          jsonDecode(out.toString().trim()),
          containsPair('message', 'purchase guidebook failed'),
        );
      },
    );

    test('context prints markdown around the latest error', () async {
      final store = JsonlLogStore(file);
      await store.append({
        'timestamp': '2026-06-27T10:03:00.000',
        'name': 'HTTP',
        'level': 0,
        'message': 'cleanup after failure',
      });
      final out = StringBuffer();

      final exitCode = await runLogHoundCli([
        'context',
        '--file',
        file.path,
        '--latest-error',
        '--before',
        '1',
        '--after',
        '1',
        '--max-lines',
        '3',
      ], out: out);

      expect(exitCode, 0);
      final text = out.toString();
      expect(text, contains('# loghound context'));
      expect(text, contains('## Latest Error'));
      expect(text, contains('## Related Logs'));
      expect(text, contains('purchase guidebook failed'));
      expect(text, contains('purchase natural-wine failed'));
      expect(text, contains('cleanup after failure'));
      expect(text, isNot(contains('GET /spots')));
    });

    test('context includes logs sharing the latest error trace id', () async {
      final tracedFile = File('${directory.path}/traced.jsonl');
      final store = JsonlLogStore(tracedFile);
      await store.append({
        'timestamp': '2026-06-27T10:00:00.000',
        'level': 0,
        'message': 'request started',
        'trace_id': 'trace-context',
      });
      await store.append({
        'timestamp': '2026-06-27T10:01:00.000',
        'level': 0,
        'message': 'unrelated request',
        'trace_id': 'trace-other',
      });
      await store.append({
        'timestamp': '2026-06-27T10:02:00.000',
        'level': 1000,
        'message': 'request failed',
        'trace_id': 'trace-context',
      });
      final out = StringBuffer();

      final exitCode = await runLogHoundCli([
        'context',
        '--file',
        tracedFile.path,
        '--latest-error',
        '--before',
        '0',
        '--after',
        '0',
      ], out: out);

      expect(exitCode, 0);
      final text = out.toString();
      expect(text, contains('request started'));
      expect(text, contains('request failed'));
      expect(text, isNot(contains('unrelated request')));
    });

    test('context renders an action and HTTP timeline summary', () async {
      final contextFile = File('${directory.path}/timeline.jsonl');
      final store = JsonlLogStore(contextFile);
      await store.append({
        'timestamp': '2026-06-27T10:00:00.000',
        'kind': 'action',
        'name': 'search.submit',
        'screen': 'SpotSearch',
        'data': {'query': 'ramen'},
        'request_id': 'req-1',
      });
      await store.append({
        'timestamp': '2026-06-27T10:00:01.000',
        'kind': 'http',
        'method': 'GET',
        'url': '/spots',
        'status': 200,
        'duration_ms': 120,
        'request_id': 'req-1',
        'response_body_bytes': 1200,
      });
      await store.append({
        'timestamp': '2026-06-27T10:00:02.000',
        'kind': 'error',
        'level': 1000,
        'message': 'empty title rendered',
        'request_id': 'req-1',
      });
      final out = StringBuffer();

      final exitCode = await runLogHoundCli([
        'context',
        '--file',
        contextFile.path,
        '--latest-error',
        '--before',
        '2',
        '--after',
        '0',
      ], out: out);

      expect(exitCode, 0);
      final text = out.toString();
      expect(text, contains('## Timeline Summary'));
      expect(text, contains('Action: search.submit screen=SpotSearch'));
      expect(text, contains('HTTP: GET /spots -> 200 duration=120ms'));
      expect(text, contains('response_body_bytes=1200'));
      expect(text, contains('Error: empty title rendered'));
    });

    test('context respects max chars', () async {
      final out = StringBuffer();

      final exitCode = await runLogHoundCli([
        'context',
        '--file',
        file.path,
        '--latest-error',
        '--max-chars',
        '180',
      ], out: out);

      expect(exitCode, 0);
      expect(out.toString().length, lessThanOrEqualTo(180));
      expect(out.toString(), contains('truncated'));
    });

    test('help lists available commands', () async {
      final out = StringBuffer();

      final exitCode = await runLogHoundCli(['--help'], out: out);

      expect(exitCode, 0);
      expect(out.toString(), isNot(contains('ingest')));
      expect(out.toString(), isNot(contains('listen')));
      expect(out.toString(), contains('apps'));
      expect(out.toString(), contains('sessions'));
      expect(out.toString(), contains('query'));
      expect(out.toString(), contains('tail'));
      expect(out.toString(), contains('latest-error'));
      expect(out.toString(), contains('context'));
      expect(out.toString(), contains('actions'));
      expect(out.toString(), contains('http'));
      expect(out.toString(), contains('body'));
      expect(out.toString(), contains('stats'));
      expect(out.toString(), contains('doctor'));
      expect(out.toString(), contains('setting'));
    });

    test('doctor fails when no routed sessions are available', () async {
      final root = Directory('${directory.path}/empty-doctor');
      final out = StringBuffer();

      final exitCode = await runLogHoundCli([
        'doctor',
        '--root',
        root.path,
      ], out: out);

      expect(exitCode, 1);
      final report = jsonDecode(out.toString().trim()) as Map<String, Object?>;
      expect(report, containsPair('status', 'fail'));
      expect(report, containsPair('ok', false));
      expect(report, containsPair('sessions', 0));
      final issues = report['issues'] as List<Object?>;
      expect(issues, isNotEmpty);
      expect(issues.first, containsPair('code', 'no_sessions'));
    });

    test('doctor reports AI investigation coverage for routed logs', () async {
      final root = Directory('${directory.path}/doctor-ready');
      final routedStore = LogHoundDirectoryStore(root);
      await routedStore.append({
        'timestamp': '2026-06-27T10:00:00.000',
        'app_id': 'guide-app',
        'flavor': 'staging',
        'platform': 'ios',
        'session_id': 'session-1',
        'kind': 'screen',
        'name': 'screen.view',
        'screen': 'MapRoute',
        'route': '/map',
      });
      await routedStore.append({
        'timestamp': '2026-06-27T10:00:01.000',
        'app_id': 'guide-app',
        'flavor': 'staging',
        'platform': 'ios',
        'session_id': 'session-1',
        'kind': 'action',
        'name': 'search.submit',
      });
      await routedStore.append({
        'timestamp': '2026-06-27T10:00:02.000',
        'app_id': 'guide-app',
        'flavor': 'staging',
        'platform': 'ios',
        'session_id': 'session-1',
        'kind': 'http',
        'request_id': 'req-1',
        'method': 'GET',
        'url': '/spots',
        'status': 200,
        'response_body': {'items': []},
      });
      await routedStore.append({
        'timestamp': '2026-06-27T10:00:03.000',
        'app_id': 'guide-app',
        'flavor': 'staging',
        'platform': 'ios',
        'session_id': 'session-1',
        'kind': 'error',
        'level': 1000,
        'request_id': 'req-1',
        'message': 'empty result rendered',
      });
      final out = StringBuffer();

      final exitCode = await runLogHoundCli([
        'doctor',
        '--root',
        root.path,
        '--flavor',
        'staging',
        '--platform',
        'ios',
        '--session',
        'session-1',
      ], out: out);

      expect(exitCode, 0);
      final report = jsonDecode(out.toString().trim()) as Map<String, Object?>;
      expect(report, containsPair('status', 'ok'));
      expect(report, containsPair('ok', true));
      expect(report, containsPair('sessions', 1));
      expect(report, containsPair('records', 4));
      expect(report, containsPair('screen_records', 1));
      expect(report, containsPair('action_records', 1));
      expect(report, containsPair('http_records', 1));
      expect(report, containsPair('error_records', 1));
      expect(report, containsPair('http_body_records', 1));
      expect(report, containsPair('issues', isEmpty));
    });

    test('removed collection commands are rejected', () async {
      final out = StringBuffer();
      final err = StringBuffer();

      final ingestExit = await runLogHoundCli(['ingest'], out: out, err: err);
      final listenExit = await runLogHoundCli(
        ['listen', '--vm-service-uri', 'http://127.0.0.1:12345/abc=/'],
        out: out,
        err: err,
      );

      expect(ingestExit, 64);
      expect(listenExit, 64);
      expect(err.toString(), contains('Unknown command: ingest'));
      expect(err.toString(), contains('Could not find an option named'));
    });

    test('stay stores loghound VM service extension records', () async {
      final root = Directory('${directory.path}/stay');
      final out = StringBuffer();

      final exitCode = await runLogHoundCli(
        [
          'stay',
          '--root',
          root.path,
          '--vm-service-uri',
          'http://127.0.0.1:12345/abc=/',
        ],
        out: out,
        vmServiceEvents: Stream<LogHoundVmServiceEvent>.fromIterable([
          const LogHoundVmServiceEvent(kind: 'flutter.frame', data: {}),
          const LogHoundVmServiceEvent(
            kind: logHoundVmServiceEventKind,
            data: {
              'timestamp': '2026-06-27T10:00:00.000',
              'app_id': 'guide-app',
              'flavor': 'staging',
              'platform': 'ios',
              'session_id': 'session-1',
              'kind': 'action',
              'name': 'search.submit',
            },
          ),
        ]),
      );

      expect(exitCode, 0);
      expect(jsonDecode(out.toString().trim()), {
        'root': root.path,
        'records': 1,
        'ignored': 1,
        'vm_service_uri': 'http://127.0.0.1:12345/abc=/',
      });

      final records = await JsonlLogStore(
        File('${root.path}/staging/ios/sessions/session-1.jsonl'),
      ).readAll();
      expect(records, hasLength(1));
      expect(records.single, containsPair('name', 'search.submit'));
    });

    test('stay reads VM service URI from a file', () async {
      final root = Directory('${directory.path}/stay-file');
      final uriFile = File('${directory.path}/vm-service-url');
      await uriFile.writeAsString('http://127.0.0.1:12345/from-file=/');
      final out = StringBuffer();

      final exitCode = await runLogHoundCli(
        ['stay', '--root', root.path, '--vm-service-uri-file', uriFile.path],
        out: out,
        vmServiceEvents: Stream<LogHoundVmServiceEvent>.fromIterable([
          const LogHoundVmServiceEvent(
            kind: logHoundVmServiceEventKind,
            data: {
              'timestamp': '2026-06-27T10:00:00.000',
              'app_id': 'guide-app',
              'flavor': 'staging',
              'platform': 'ios',
              'session_id': 'session-1',
              'kind': 'action',
              'name': 'search.submit',
            },
          ),
        ]),
      );

      expect(exitCode, 0);
      expect(
        jsonDecode(out.toString().trim()),
        containsPair('vm_service_uri', 'http://127.0.0.1:12345/from-file=/'),
      );
    });

    test('stay reports flutter attach startup failures', () async {
      final project = Directory('${directory.path}/stay-missing-flutter');
      final root = Directory('${directory.path}/stay-missing-flutter-root');
      final out = StringBuffer();
      final err = StringBuffer();

      final exitCode = await runLogHoundCli(
        ['stay', '-d', 'iPhone15Pro', '--root', root.path],
        out: out,
        err: err,
        currentDirectory: project,
        processStarter: (command, args, {workingDirectory}) {
          throw const ProcessException('flutter', [], 'not found');
        },
      );

      expect(exitCode, 1);
      expect(err.toString(), contains('Failed to start Flutter'));
    });

    test('stay reconnects after a VM service stream closes', () async {
      final root = Directory('${directory.path}/stay-reconnect');
      final out = StringBuffer();
      var connections = 0;

      final exitCode = await runLogHoundCli(
        [
          'stay',
          '--root',
          root.path,
          '--vm-service-uri',
          'http://127.0.0.1:12345/abc=/',
        ],
        out: out,
        maxVmServiceConnections: 2,
        vmServiceEventFactory:
            (serviceUri, {required errors, required resumeOnListen}) {
              connections++;
              return Stream<LogHoundVmServiceEvent>.fromIterable([
                LogHoundVmServiceEvent(
                  kind: logHoundVmServiceEventKind,
                  data: {
                    'timestamp': '2026-06-27T10:00:0$connections.000',
                    'app_id': 'guide-app',
                    'flavor': 'staging',
                    'platform': 'ios',
                    'session_id': 'session-$connections',
                    'kind': 'action',
                    'name': 'search.submit.$connections',
                  },
                ),
              ]);
            },
      );

      expect(exitCode, 0);
      expect(connections, 2);
      final firstRecords = await JsonlLogStore(
        File('${root.path}/staging/ios/sessions/session-1.jsonl'),
      ).readAll();
      final secondRecords = await JsonlLogStore(
        File('${root.path}/staging/ios/sessions/session-2.jsonl'),
      ).readAll();
      expect(firstRecords.single, containsPair('name', 'search.submit.1'));
      expect(secondRecords.single, containsPair('name', 'search.submit.2'));
    });

    test('stay discovers VM service URI with flutter attach', () async {
      final project = Directory('${directory.path}/stay-attach-project');
      final flutter = File('${project.path}/.fvm/flutter_sdk/bin/flutter');
      await flutter.create(recursive: true);
      final root = Directory('${directory.path}/stay-attach');
      final out = StringBuffer();
      String? executable;
      List<String>? arguments;

      final exitCode = await runLogHoundCli(
        ['stay', '-d', 'iPhone15Pro', '--root', root.path],
        out: out,
        currentDirectory: project,
        processStarter: (command, args, {workingDirectory}) async {
          executable = command;
          arguments = args;
          return StreamProcess([
            '[{"event":"daemon.connected","params":{"version":"0.6.1"}}]',
            'Waiting for a connection from Flutter on iPhone15Pro...',
            '[{"event":"app.debugPort","params":{"port":12345,"wsUri":"ws://127.0.0.1:12345/from-attach=/ws"}}]',
          ]);
        },
        vmServiceEvents: Stream<LogHoundVmServiceEvent>.fromIterable([
          const LogHoundVmServiceEvent(
            kind: logHoundVmServiceEventKind,
            data: {
              'timestamp': '2026-06-27T10:00:00.000',
              'app_id': 'guide-app',
              'flavor': 'staging',
              'platform': 'ios',
              'session_id': 'session-1',
              'kind': 'action',
              'name': 'search.submit',
            },
          ),
        ]),
      );

      expect(exitCode, 0);
      expect(executable, flutter.path);
      expect(arguments, containsAllInOrder(['attach', '--machine']));
      expect(arguments, containsAll(['-d', 'iPhone15Pro']));
      expect(
        jsonDecode(out.toString().trim()),
        containsPair('vm_service_uri', 'ws://127.0.0.1:12345/from-attach=/ws'),
      );

      final records = await JsonlLogStore(
        File('${root.path}/staging/ios/sessions/session-1.jsonl'),
      ).readAll();
      expect(records.single, containsPair('name', 'search.submit'));
    });

    test('run resolves FVM Flutter before system Flutter', () async {
      final project = Directory('${directory.path}/fvm-project');
      final flutter = File('${project.path}/.fvm/flutter_sdk/bin/flutter');
      await flutter.create(recursive: true);

      expect(resolveFlutterExecutable(project), flutter.path);
      expect(
        resolveFlutterExecutable(Directory('${directory.path}/plain-project')),
        'flutter',
      );
    });

    test('run resolves Windows FVM Flutter bat', () async {
      final project = Directory('${directory.path}/fvm-windows-project');
      final flutter = File('${project.path}/.fvm/flutter_sdk/bin/flutter.bat');
      await flutter.create(recursive: true);

      expect(resolveFlutterExecutable(project, isWindows: true), flutter.path);
      expect(
        resolveFlutterExecutable(
          Directory('${directory.path}/plain-windows-project'),
          isWindows: true,
        ),
        'flutter.bat',
      );
    });

    test('run starts flutter with vmservice out file', () async {
      final project = Directory('${directory.path}/run-project');
      final flutter = File('${project.path}/.fvm/flutter_sdk/bin/flutter');
      await flutter.create(recursive: true);
      final root = Directory('${directory.path}/run-root');
      final out = StringBuffer();
      String? executable;
      List<String>? arguments;

      final exitCode = await runLogHoundCli(
        ['run', '-d', 'iPhone15Pro', '--root', root.path],
        out: out,
        currentDirectory: project,
        processRunner: (command, args, {workingDirectory}) async {
          executable = command;
          arguments = args;
          final uriFileArg = args.firstWhere(
            (arg) => arg.startsWith('--vmservice-out-file='),
          );
          final uriFile = File(uriFileArg.split('=').last);
          await uriFile.parent.create(recursive: true);
          await uriFile.writeAsString('http://127.0.0.1:12345/run=/');
          return 0;
        },
        vmServiceEvents: Stream<LogHoundVmServiceEvent>.fromIterable([
          const LogHoundVmServiceEvent(
            kind: logHoundVmServiceEventKind,
            data: {
              'timestamp': '2026-06-27T10:00:00.000',
              'app_id': 'guide-app',
              'flavor': 'staging',
              'platform': 'ios',
              'session_id': 'session-1',
              'kind': 'action',
              'name': 'search.submit',
            },
          ),
        ]),
      );

      expect(exitCode, 0);
      expect(executable, flutter.path);
      expect(arguments, containsAllInOrder(['run', '-d', 'iPhone15Pro']));
      expect(
        arguments,
        contains(
          '--vmservice-out-file=${project.path}/.dart_tool/loghound/vm-service-url',
        ),
      );
      expect(arguments, contains('--start-paused'));

      final records = await JsonlLogStore(
        File('${root.path}/staging/ios/sessions/session-1.jsonl'),
      ).readAll();
      expect(records.single, containsPair('name', 'search.submit'));
    });

    test(
      'run resumes isolates that pause after VM service collection starts',
      () async {
        final project = Directory('${directory.path}/run-isolate-project');
        final root = Directory('${directory.path}/run-isolate-root');
        final out = StringBuffer();
        final err = StringBuffer();
        final service = FakeVmService();

        final exitCode = await runLogHoundCli(
          ['run', '--root', root.path],
          out: out,
          err: err,
          currentDirectory: project,
          processRunner: (command, args, {workingDirectory}) async {
            final uriFileArg = args.firstWhere(
              (arg) => arg.startsWith('--vmservice-out-file='),
            );
            final uriFile = File(uriFileArg.split('=').last);
            await uriFile.parent.create(recursive: true);
            await uriFile.writeAsString('http://127.0.0.1:12345/run=/');
            await service.debugListenerAttached.future;
            service.debugEvents.add(
              Event(
                kind: EventKind.kPauseStart,
                isolate: IsolateRef(id: 'decode-isolate'),
              ),
            );
            await service.decodeResumed.future.timeout(
              const Duration(milliseconds: 100),
              onTimeout: () {},
            );
            await service.extensionEvents.close();
            await service.debugEvents.close();
            return 0;
          },
          vmServiceConnector: (uri) async => service,
        );

        expect(exitCode, 0);
        expect(service.listenedStreams, contains(EventStreams.kExtension));
        expect(service.listenedStreams, contains(EventStreams.kDebug));
        expect(service.resumedIsolates, contains('decode-isolate'));
      },
    );

    test('run passes flavor and dart define file to flutter run', () async {
      final project = Directory('${directory.path}/run-flavor-project');
      final root = Directory('${directory.path}/run-flavor-root');
      final out = StringBuffer();
      List<String>? arguments;

      final exitCode = await runLogHoundCli(
        [
          'run',
          '-d',
          'iPhone15Pro',
          '--flavor',
          'dev',
          '--dart-define-from-file=.env',
          '--root',
          root.path,
        ],
        out: out,
        currentDirectory: project,
        processRunner: (command, args, {workingDirectory}) async {
          arguments = args;
          final uriFileArg = args.firstWhere(
            (arg) => arg.startsWith('--vmservice-out-file='),
          );
          final uriFile = File(uriFileArg.split('=').last);
          await uriFile.parent.create(recursive: true);
          await uriFile.writeAsString('http://127.0.0.1:12345/run=/');
          return 0;
        },
        vmServiceEvents: Stream<LogHoundVmServiceEvent>.fromIterable([
          const LogHoundVmServiceEvent(
            kind: logHoundVmServiceEventKind,
            data: {
              'timestamp': '2026-06-27T10:00:00.000',
              'app_id': 'guide-app',
              'flavor': 'dev',
              'platform': 'ios',
              'session_id': 'session-1',
              'kind': 'action',
              'name': 'search.submit',
            },
          ),
        ]),
      );

      expect(exitCode, 0);
      expect(
        arguments,
        containsAllInOrder([
          'run',
          '-d',
          'iPhone15Pro',
          '--flavor',
          'dev',
          '--dart-define-from-file=.env',
        ]),
      );
    });

    test('run reports flutter process startup failures', () async {
      final project = Directory(
        '${directory.path}/run-missing-flutter-project',
      );
      final root = Directory('${directory.path}/run-missing-flutter-root');
      final out = StringBuffer();
      final err = StringBuffer();

      final exitCode = await runLogHoundCli(
        ['run', '-d', 'iPhone15Pro', '--root', root.path],
        out: out,
        err: err,
        currentDirectory: project,
        processRunner: (command, args, {workingDirectory}) {
          throw const ProcessException('flutter', [], 'not found');
        },
      );

      expect(exitCode, 1);
      expect(err.toString(), contains('Failed to start Flutter'));
    });

    test('run returns flutter failure before VM service timeout', () async {
      final project = Directory('${directory.path}/run-failure-project');
      final root = Directory('${directory.path}/run-failure-root');
      final out = StringBuffer();
      final err = StringBuffer();

      final exitCode = await runLogHoundCli(
        ['run', '-d', 'iPhone15Pro', '--root', root.path],
        out: out,
        err: err,
        currentDirectory: project,
        processRunner: (command, args, {workingDirectory}) async => 1,
        vmServiceUriFileTimeout: const Duration(milliseconds: 1),
      );

      expect(exitCode, 1);
      expect(err.toString(), isNot(contains('Missing required option')));
    });

    test(
      'setting with no subcommand lists structured setting records',
      () async {
        final root = Directory('${directory.path}/settings-list-root');
        final out = StringBuffer();

        final exit = await runLogHoundCli([
          'setting',
          '--root',
          root.path,
        ], out: out);

        expect(exit, 0);
        final lines = out
            .toString()
            .trim()
            .split('\n')
            .where((line) => line.isNotEmpty)
            .map((line) => jsonDecode(line) as Map<String, Object?>)
            .toList();
        expect(lines, hasLength(4));

        final language = lines.firstWhere((r) => r['key'] == 'language');
        expect(language['type'], 'enum');
        expect(language['value'], 'en');
        expect(language['options'], ['en', 'ja']);

        final responseBody = lines.firstWhere(
          (r) => r['key'] == 'capture_http_response_body',
        );
        expect(responseBody['type'], 'bool');
        expect(responseBody['value'], false);
      },
    );

    test('setting rejects unknown setting writes', () async {
      final root = Directory('${directory.path}/settings-unknown-root');
      final out = StringBuffer();
      final err = StringBuffer();

      final exit = await runLogHoundCli(
        ['setting', '--root', root.path, 'device', 'on'],
        out: out,
        err: err,
      );

      expect(exit, 64);
      expect(out.toString(), isEmpty);
      expect(err.toString(), contains('Unknown setting: device'));
    });

    test('setting writes known values non-interactively', () async {
      final root = Directory('${directory.path}/settings-write-root');
      final out = StringBuffer();

      final exit = await runLogHoundCli([
        'setting',
        '--root',
        root.path,
        'context_format',
        'jsonl',
      ], out: out);

      expect(exit, 0);
      final record = jsonDecode(out.toString().trim()) as Map<String, Object?>;
      expect(record, containsPair('key', 'context_format'));
      expect(record, containsPair('value', 'jsonl'));

      final settings = await LogHoundSettingsStore(root).read();
      expect(settings.contextFormat, 'jsonl');
    });

    test(
      'context uses context_format from settings when --format omitted',
      () async {
        final root = Directory('${directory.path}/ctx-root');
        await LogHoundSettingsStore(
          root,
        ).write(const LogHoundSettings(contextFormat: 'jsonl'));
        await LogHoundDirectoryStore(root).append({
          'timestamp': '2026-06-27T10:00:00.000',
          'name': 'Boom',
          'level': 900,
          'message': 'kaboom',
        });

        final out = StringBuffer();
        final exit = await runLogHoundCli([
          'context',
          '--root',
          root.path,
        ], out: out);

        expect(exit, 0);
        expect(out.toString().trimLeft(), startsWith('{'));
        expect(out.toString(), isNot(contains('# loghound context')));

        final markdownOut = StringBuffer();
        await runLogHoundCli([
          'context',
          '--root',
          root.path,
          '--format',
          'markdown',
        ], out: markdownOut);
        expect(markdownOut.toString(), contains('# loghound context'));
      },
    );

    test('apps and sessions discover legacy routed log files', () async {
      final root = Directory('${directory.path}/routed');
      final routedStore = JsonlLogStore(
        File('${root.path}/guide-app/staging/sessions/session-1.jsonl'),
      );
      await routedStore.append({
        'timestamp': '2026-06-27T10:00:00.000',
        'app_id': 'guide-app',
        'flavor': 'staging',
        'session_id': 'session-1',
        'kind': 'action',
        'name': 'screen.view',
      });

      final appsOut = StringBuffer();
      final appsExit = await runLogHoundCli([
        'apps',
        '--root',
        root.path,
      ], out: appsOut);

      expect(appsExit, 0);
      final app = jsonDecode(appsOut.toString().trim()) as Map<String, Object?>;
      expect(app, containsPair('app_id', 'guide-app'));
      expect(app['flavors'], contains('staging'));

      final sessionsOut = StringBuffer();
      final sessionsExit = await runLogHoundCli([
        'sessions',
        '--root',
        root.path,
        '--app',
        'guide-app',
        '--flavor',
        'staging',
      ], out: sessionsOut);

      expect(sessionsExit, 0);
      final session =
          jsonDecode(sessionsOut.toString().trim()) as Map<String, Object?>;
      expect(session, containsPair('app_id', 'guide-app'));
      expect(session, containsPair('flavor', 'staging'));
      expect(session, containsPair('platform', 'unknown'));
      expect(session, containsPair('session_id', 'session-1'));
    });

    test('sessions falls back to legacy loghound root', () async {
      final previousCurrent = Directory.current;
      Directory.current = directory.path;
      addTearDown(() {
        Directory.current = previousCurrent;
      });
      await LogHoundDirectoryStore(Directory('loghound')).append({
        'timestamp': '2026-06-27T10:00:00.000',
        'app_id': 'guide-app',
        'flavor': 'staging',
        'platform': 'ios',
        'session_id': 'legacy-session',
        'kind': 'action',
        'name': 'legacy.action',
      });

      final out = StringBuffer();
      final exit = await runLogHoundCli(['sessions'], out: out);

      expect(exit, 0);
      final session = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(session, containsPair('session_id', 'legacy-session'));
    });

    test('setting falls back to legacy loghound settings', () async {
      final previousCurrent = Directory.current;
      Directory.current = directory.path;
      addTearDown(() {
        Directory.current = previousCurrent;
      });
      await LogHoundSettingsStore(
        Directory('loghound'),
      ).write(const LogHoundSettings(contextFormat: 'jsonl'));

      final out = StringBuffer();
      final exit = await runLogHoundCli(['setting'], out: out);

      expect(exit, 0);
      final records = out
          .toString()
          .trim()
          .split('\n')
          .map((line) => jsonDecode(line) as Map<String, Object?>)
          .toList();
      final contextFormat = records.firstWhere(
        (record) => record['key'] == 'context_format',
      );
      expect(contextFormat, containsPair('value', 'jsonl'));
    });

    test('routed commands can filter sessions by platform', () async {
      final root = Directory('${directory.path}/platform-routed');
      final routedStore = LogHoundDirectoryStore(root);
      await routedStore.append({
        'timestamp': '2026-06-27T10:00:00.000',
        'app_id': 'guide-app',
        'session_id': 'session-1',
        'platform': 'ios',
        'kind': 'log',
        'message': 'ios log',
      });
      await routedStore.append({
        'timestamp': '2026-06-27T10:00:01.000',
        'app_id': 'guide-app',
        'session_id': 'session-1',
        'platform': 'android',
        'kind': 'log',
        'message': 'android log',
      });

      final sessionsOut = StringBuffer();
      final sessionsExit = await runLogHoundCli([
        'sessions',
        '--root',
        root.path,
        '--app',
        'guide-app',
        '--platform',
        'ios',
      ], out: sessionsOut);

      expect(sessionsExit, 0);
      final session =
          jsonDecode(sessionsOut.toString().trim()) as Map<String, Object?>;
      expect(session, containsPair('platform', 'ios'));
      expect(session['file'], contains('/ios/sessions/session-1.jsonl'));

      final tailOut = StringBuffer();
      final tailExit = await runLogHoundCli([
        'tail',
        '--root',
        root.path,
        '--app',
        'guide-app',
        '--session',
        'session-1',
        '--platform',
        'android',
      ], out: tailOut);

      expect(tailExit, 0);
      expect(tailOut.toString(), contains('android log'));
      expect(tailOut.toString(), isNot(contains('ios log')));
    });

    test(
      'actions, http list, body, and stats inspect a routed session',
      () async {
        final root = Directory('${directory.path}/investigation');
        final routedStore = JsonlLogStore(
          File('${root.path}/staging/ios/sessions/session-1.jsonl'),
        );
        await routedStore.append({
          'timestamp': '2026-06-27T10:00:00.000',
          'app_id': 'guide-app',
          'flavor': 'staging',
          'platform': 'ios',
          'session_id': 'session-1',
          'kind': 'action',
          'name': 'search.submit',
          'screen': 'SpotSearch',
          'data': {
            'query': 'ramen',
            'selectedFilters': ['open_now'],
          },
        });
        await routedStore.append({
          'timestamp': '2026-06-27T10:00:01.000',
          'app_id': 'guide-app',
          'flavor': 'staging',
          'platform': 'ios',
          'session_id': 'session-1',
          'kind': 'http',
          'request_id': 'req-1',
          'method': 'GET',
          'url': '/spots?query=ramen',
          'status': 200,
          'duration_ms': 120,
          'response_body': {
            'items': [
              {'id': 'spot-1', 'title': 'Ramen One'},
              {'id': 'spot-2', 'title': ''},
            ],
          },
        });
        await routedStore.append({
          'timestamp': '2026-06-27T10:00:02.000',
          'app_id': 'guide-app',
          'flavor': 'staging',
          'platform': 'ios',
          'session_id': 'session-1',
          'kind': 'error',
          'level': 1000,
          'request_id': 'req-1',
          'message': 'empty title rendered',
        });

        final actionOut = StringBuffer();
        final actionExit = await runLogHoundCli([
          'actions',
          '--root',
          root.path,
          '--flavor',
          'staging',
          '--platform',
          'ios',
          '--session',
          'session-1',
        ], out: actionOut);

        expect(actionExit, 0);
        expect(
          jsonDecode(actionOut.toString().trim()),
          containsPair('kind', 'action'),
        );

        final httpOut = StringBuffer();
        final httpExit = await runLogHoundCli([
          'http',
          'list',
          '--root',
          root.path,
          '--flavor',
          'staging',
          '--platform',
          'ios',
          '--session',
          'session-1',
        ], out: httpOut);

        expect(httpExit, 0);
        final httpSummary =
            jsonDecode(httpOut.toString().trim()) as Map<String, Object?>;
        expect(httpSummary, containsPair('request_id', 'req-1'));
        expect(httpSummary, containsPair('method', 'GET'));
        expect(httpSummary, containsPair('status', 200));
        expect(httpSummary, isNot(contains('response_body')));

        final bodyOut = StringBuffer();
        final bodyExit = await runLogHoundCli([
          'body',
          '--root',
          root.path,
          '--flavor',
          'staging',
          '--platform',
          'ios',
          '--session',
          'session-1',
          '--request-id',
          'req-1',
          '--response',
          '--json-path',
          r'$.items[1].title',
        ], out: bodyOut);

        expect(bodyExit, 0);
        expect(jsonDecode(bodyOut.toString().trim()), '');

        final statsOut = StringBuffer();
        final statsExit = await runLogHoundCli([
          'stats',
          '--root',
          root.path,
          '--flavor',
          'staging',
          '--platform',
          'ios',
          '--session',
          'session-1',
        ], out: statsOut);

        expect(statsExit, 0);
        final stats =
            jsonDecode(statsOut.toString().trim()) as Map<String, Object?>;
        expect(stats, containsPair('records', 3));
        expect(stats, containsPair('http_records', 1));
        expect(stats, containsPair('action_records', 1));
      },
    );
  });
}

class StreamProcess implements Process {
  StreamProcess(this.lines);

  final List<String> lines;
  final StreamController<List<int>> _stdin = StreamController<List<int>>();

  @override
  Future<int> get exitCode async => 0;

  @override
  int get pid => 1;

  @override
  IOSink get stdin => IOSink(_stdin.sink);

  @override
  Stream<List<int>> get stdout => Stream<List<int>>.fromIterable(
    lines.map((line) => utf8.encode('$line\n')),
  );

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    unawaited(_stdin.close());
    return true;
  }
}

class FakeVmService extends VmService {
  FakeVmService() : super(const Stream<dynamic>.empty(), (_) {});

  final StreamController<Event> extensionEvents =
      StreamController<Event>.broadcast();
  late final StreamController<Event> debugEvents =
      StreamController<Event>.broadcast(
        onListen: () {
          if (!debugListenerAttached.isCompleted) {
            debugListenerAttached.complete();
          }
        },
      );
  final Completer<void> debugListenerAttached = Completer<void>();
  final Completer<void> decodeResumed = Completer<void>();
  final List<String> listenedStreams = [];
  final List<String> resumedIsolates = [];

  @override
  Stream<Event> get onExtensionEvent => extensionEvents.stream;

  @override
  Stream<Event> get onDebugEvent => debugEvents.stream;

  @override
  Future<Success> streamListen(String streamId) async {
    listenedStreams.add(streamId);
    return Success();
  }

  @override
  Future<VM> getVM() async {
    return VM(isolates: [IsolateRef(id: 'main-isolate')]);
  }

  @override
  Future<Success> resume(
    String isolateId, {
    String? step,
    int? frameIndex,
  }) async {
    resumedIsolates.add(isolateId);
    if (isolateId == 'decode-isolate' && !decodeResumed.isCompleted) {
      decodeResumed.complete();
    }
    return Success();
  }

  @override
  Future<void> dispose() async {}
}
