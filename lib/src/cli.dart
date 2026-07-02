import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:args/args.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'banner.dart';
import 'json_safe.dart';
import 'jsonl_log_store.dart';
import 'log_query.dart';
import 'loghound_directory_store.dart';
import 'loghound_settings.dart';
import 'loghound_vm_service.dart';
import 'redactor.dart';
import 'setting_interactive.dart';

const _defaultLogRoot = '.loghound';
const _legacyLogRoot = 'loghound';
const _defaultVmServiceUriFile = '.dart_tool/loghound/vm-service-url';

/// Starts a subprocess and returns its eventual exit code.
typedef LogHoundProcessRunner =
    Future<int> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

/// Starts a subprocess and returns the running process.
typedef LogHoundProcessStarter =
    Future<io.Process> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

/// Creates a stream of VM Service extension events for one VM Service URI.
typedef LogHoundVmServiceEventFactory =
    Stream<LogHoundVmServiceEvent> Function(
      String serviceUri, {
      required StringSink errors,
      required bool resumeOnListen,
    });

/// Runs the `loghound` command-line interface.
Future<int> runLogHoundCli(
  List<String> args, {
  StringSink? out,
  StringSink? err,
  Stream<LogHoundVmServiceEvent>? vmServiceEvents,
  io.Directory? currentDirectory,
  LogHoundProcessRunner? processRunner,
  LogHoundProcessStarter? processStarter,
  LogHoundVmServiceEventFactory? vmServiceEventFactory,
  int? maxVmServiceConnections,
  Duration? vmServiceUriFileTimeout,
}) async {
  final output = out ?? io.stdout;
  final errors = err ?? io.stderr;
  final workingDirectory = currentDirectory ?? io.Directory.current;
  final parser = _buildParser();

  late ArgResults results;
  try {
    results = parser.parse(args);
  } on FormatException catch (error) {
    errors.writeln(error.message);
    errors.writeln(_usage(parser));
    return 64;
  }

  final command = results.command;
  if (results['help'] == true || (command == null && args.isEmpty)) {
    output.writeln(_usage(parser));
    return 0;
  }
  if (command == null) {
    errors.writeln('Unknown command: ${args.first}');
    errors.writeln(_usage(parser));
    return 64;
  }

  switch (command.name) {
    case 'apps':
      return _runApps(command, output);
    case 'sessions':
      return _runSessions(command, output);
    case 'stay':
      return _runStay(
        command,
        output,
        errors,
        workingDirectory,
        vmServiceEvents,
        processStarter ?? _defaultProcessStarter,
        vmServiceEventFactory: vmServiceEventFactory,
        maxVmServiceConnections: maxVmServiceConnections,
        vmServiceUriFileTimeout: vmServiceUriFileTimeout,
      );
    case 'run':
      return _runRun(
        command,
        output,
        errors,
        workingDirectory,
        processRunner ?? _defaultProcessRunner,
        vmServiceEvents,
        vmServiceEventFactory: vmServiceEventFactory,
        vmServiceUriFileTimeout: vmServiceUriFileTimeout,
      );
    case 'query':
      return _runQuery(command, output);
    case 'tail':
      return _runTail(command, output);
    case 'latest-error':
      return _runLatestError(command, output);
    case 'context':
      return _runContext(command, output);
    case 'actions':
      return _runActions(command, output);
    case 'http':
      return _runHttp(command, output, errors);
    case 'body':
      return _runBody(command, output, errors);
    case 'stats':
      return _runStats(command, output);
    case 'doctor':
      return _runDoctor(command, output);
    case 'setting':
      return _runSetting(command, output, errors);
    default:
      errors.writeln('Unknown command: ${command.name}');
      errors.writeln(_usage(parser));
      return 64;
  }
}

ArgParser _buildParser() {
  return ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show help.')
    ..addCommand(
      'apps',
      ArgParser()..addOption('root', defaultsTo: _defaultLogRoot),
    )
    ..addCommand('sessions', _withRouteOptions(ArgParser(), includeFile: false))
    ..addCommand('stay', _buildStayParser())
    ..addCommand('run', _buildRunParser())
    ..addCommand(
      'query',
      _withRouteOptions(
        ArgParser()
          ..addOption('contains')
          ..addOption('name')
          ..addOption('min-level')
          ..addOption('since')
          ..addOption('trace-id')
          ..addOption('request-id')
          ..addOption('session-id')
          ..addOption('user-id'),
      ),
    )
    ..addCommand(
      'tail',
      _withRouteOptions(
        ArgParser()..addOption('count', abbr: 'n', defaultsTo: '50'),
      ),
    )
    ..addCommand('latest-error', _withRouteOptions(ArgParser()))
    ..addCommand(
      'context',
      _withRouteOptions(
        ArgParser()
          ..addFlag(
            'latest-error',
            defaultsTo: false,
            negatable: false,
            help: 'Build context around the latest warning/error record.',
          )
          ..addOption('before', defaultsTo: '50')
          ..addOption('after', defaultsTo: '20')
          ..addOption('max-lines', defaultsTo: '200')
          ..addOption('max-chars', defaultsTo: '20000')
          ..addOption(
            'format',
            defaultsTo: 'markdown',
            allowed: const ['markdown', 'jsonl'],
          ),
      ),
    )
    ..addCommand('actions', _withRouteOptions(ArgParser()))
    ..addCommand(
      'http',
      ArgParser()
        ..addCommand('list', _withRouteOptions(ArgParser()))
        ..addCommand(
          'show',
          _withRouteOptions(ArgParser()..addOption('request-id')),
        ),
    )
    ..addCommand(
      'body',
      _withRouteOptions(
        ArgParser()
          ..addOption('request-id')
          ..addFlag('request', defaultsTo: false, negatable: false)
          ..addFlag('response', defaultsTo: false, negatable: false)
          ..addOption('json-path')
          ..addOption('find')
          ..addOption('sample')
          ..addOption('count', defaultsTo: '3'),
      ),
    )
    ..addCommand('stats', _withRouteOptions(ArgParser()))
    ..addCommand(
      'doctor',
      _withRouteOptions(
        ArgParser()..addOption(
          'max-age-minutes',
          help: 'Warn when the latest record is older than this many minutes.',
        ),
        includeFile: false,
      ),
    )
    ..addCommand('setting', _buildSettingParser());
}

ArgParser _buildStayParser() {
  return ArgParser()
    ..addOption('root', defaultsTo: _defaultLogRoot)
    ..addOption('device', abbr: 'd', help: 'Flutter device id/name.')
    ..addOption(
      'app-id',
      help: 'Flutter app id/bundle id used by flutter attach.',
    )
    ..addOption(
      'flutter',
      help: 'Flutter executable. Defaults to .fvm/flutter_sdk/bin/flutter.',
    )
    ..addOption(
      'vm-service-uri',
      help: 'Dart VM Service URI. Usually written by loghound run.',
    )
    ..addOption(
      'vm-service-uri-file',
      help: 'File containing a Dart VM Service URI.',
    )
    ..addOption('event-kind', defaultsTo: logHoundVmServiceEventKind);
}

ArgParser _buildRunParser() {
  return ArgParser(allowTrailingOptions: false)
    ..addOption('root', defaultsTo: _defaultLogRoot)
    ..addOption('device', abbr: 'd', help: 'Flutter device id/name.')
    ..addOption('flavor', help: 'Flutter flavor to pass to flutter run.')
    ..addMultiOption(
      'dart-define-from-file',
      help: 'Pass --dart-define-from-file to flutter run.',
      valueHelp: 'path',
    )
    ..addOption(
      'flutter',
      help: 'Flutter executable. Defaults to .fvm/flutter_sdk/bin/flutter.',
    )
    ..addOption(
      'vm-service-uri-file',
      defaultsTo: _defaultVmServiceUriFile,
      help: 'File where flutter run writes its VM Service URI.',
    )
    ..addOption('event-kind', defaultsTo: logHoundVmServiceEventKind);
}

ArgParser _buildSettingParser() {
  return ArgParser()..addOption('root', defaultsTo: _defaultLogRoot);
}

ArgParser _withRouteOptions(ArgParser parser, {bool includeFile = true}) {
  if (includeFile) {
    parser.addOption('file', abbr: 'f');
  }
  return parser
    ..addOption('root', defaultsTo: _defaultLogRoot)
    ..addOption('app')
    ..addOption('flavor')
    ..addOption('platform')
    ..addOption('session');
}

Future<int> _runApps(ArgResults command, StringSink output) async {
  final apps = await LogHoundDirectoryStore(
    _readRootDirectory(command['root'] as String),
  ).apps();
  for (final app in apps) {
    _writeRecord(output, app.toJson());
  }
  return 0;
}

Future<int> _runSessions(ArgResults command, StringSink output) async {
  final sessions =
      await LogHoundDirectoryStore(
        _readRootDirectory(command['root'] as String),
      ).sessions(
        appId: command['app'] as String?,
        flavor: command['flavor'] as String?,
        platform: command['platform'] as String?,
      );
  for (final session in sessions) {
    _writeRecord(output, session.toJson());
  }
  return 0;
}

Future<int> _runStay(
  ArgResults command,
  StringSink output,
  StringSink errors,
  io.Directory currentDirectory,
  Stream<LogHoundVmServiceEvent>? injectedEvents,
  LogHoundProcessStarter processStarter, {
  LogHoundVmServiceEventFactory? vmServiceEventFactory,
  int? maxVmServiceConnections,
  Duration? vmServiceUriFileTimeout,
}) async {
  final resolution = await _resolveStayVmServiceUri(
    command,
    currentDirectory,
    processStarter,
    timeout: vmServiceUriFileTimeout ?? const Duration(seconds: 60),
    errors: errors,
  );
  if (resolution?.exitCode case final exitCode? when exitCode != 0) {
    return exitCode;
  }
  final serviceUri = resolution?.uri;
  if (serviceUri == null && injectedEvents == null) {
    return 64;
  }

  try {
    return await _collectVmServiceEvents(
      rootPath: command['root'] as String,
      serviceUri: serviceUri,
      eventKind: command['event-kind'] as String,
      output: output,
      errors: errors,
      injectedEvents: injectedEvents,
      vmServiceEventFactory: vmServiceEventFactory,
      keepAlive: injectedEvents == null,
      maxConnections: maxVmServiceConnections,
    );
  } finally {
    resolution?.dispose();
  }
}

Future<int> _runRun(
  ArgResults command,
  StringSink output,
  StringSink errors,
  io.Directory currentDirectory,
  LogHoundProcessRunner processRunner,
  Stream<LogHoundVmServiceEvent>? injectedEvents, {
  LogHoundVmServiceEventFactory? vmServiceEventFactory,
  Duration? vmServiceUriFileTimeout,
}) async {
  final uriFile = io.File(
    _resolvePath(currentDirectory, command['vm-service-uri-file'] as String),
  );
  await uriFile.parent.create(recursive: true);
  if (await uriFile.exists()) {
    await uriFile.delete();
  }

  final flutterExecutable =
      command['flutter'] as String? ??
      resolveFlutterExecutable(currentDirectory);
  final flutterArgs = <String>[
    'run',
    if ((command['device'] as String?)?.isNotEmpty == true) ...[
      '-d',
      command['device'] as String,
    ],
    if ((command['flavor'] as String?)?.isNotEmpty == true) ...[
      '--flavor',
      command['flavor'] as String,
    ],
    for (final path in command['dart-define-from-file'] as List<String>)
      if (path.isNotEmpty) '--dart-define-from-file=$path',
    '--start-paused',
    '--vmservice-out-file=${uriFile.path}',
    ...command.rest,
  ];

  final Future<int> flutterExit;
  try {
    flutterExit =
        processRunner(
          flutterExecutable,
          flutterArgs,
          workingDirectory: currentDirectory.path,
        ).catchError((Object error) {
          errors.writeln('Failed to start Flutter: $error');
          return 1;
        });
  } on Object catch (error) {
    errors.writeln('Failed to start Flutter: $error');
    return 1;
  }

  final uriErrors = StringBuffer();
  final startup =
      await Future.any<({String kind, String? serviceUri, int? exitCode})>([
        _resolveVmServiceUri(
          explicitUri: null,
          uriFilePath: uriFile.path,
          currentDirectory: currentDirectory,
          timeout: vmServiceUriFileTimeout ?? const Duration(seconds: 60),
          errors: uriErrors,
        ).then((uri) => (kind: 'uri', serviceUri: uri, exitCode: null)),
        flutterExit.then(
          (exitCode) => (kind: 'exit', serviceUri: null, exitCode: exitCode),
        ),
      ]);
  if (startup.kind == 'exit') {
    final exitCode = startup.exitCode!;
    if (exitCode != 0) {
      return exitCode;
    }
    final fallbackUri = await _resolveVmServiceUri(
      explicitUri: null,
      uriFilePath: uriFile.path,
      currentDirectory: currentDirectory,
      timeout: Duration.zero,
      errors: StringBuffer(),
    );
    if (fallbackUri == null) {
      return exitCode;
    }
    final collectExit = await _collectVmServiceEvents(
      rootPath: command['root'] as String,
      serviceUri: fallbackUri,
      eventKind: command['event-kind'] as String,
      output: output,
      errors: errors,
      injectedEvents: injectedEvents,
      vmServiceEventFactory: vmServiceEventFactory,
      resumeOnListen: true,
    );
    if (collectExit != 0) {
      return collectExit;
    }
    return exitCode;
  }

  final serviceUri = startup.serviceUri;
  if (serviceUri == null) {
    errors.write(uriErrors.toString());
    return 64;
  }

  final collectExit = await _collectVmServiceEvents(
    rootPath: command['root'] as String,
    serviceUri: serviceUri,
    eventKind: command['event-kind'] as String,
    output: output,
    errors: errors,
    injectedEvents: injectedEvents,
    vmServiceEventFactory: vmServiceEventFactory,
    resumeOnListen: true,
  );
  final runExit = await flutterExit;
  if (collectExit != 0) {
    return collectExit;
  }
  return runExit;
}

Future<int> _collectVmServiceEvents({
  required String rootPath,
  required String? serviceUri,
  required String eventKind,
  required StringSink output,
  required StringSink errors,
  required Stream<LogHoundVmServiceEvent>? injectedEvents,
  LogHoundVmServiceEventFactory? vmServiceEventFactory,
  bool resumeOnListen = false,
  bool keepAlive = false,
  int? maxConnections,
}) async {
  if ((serviceUri == null || serviceUri.trim().isEmpty) &&
      injectedEvents == null) {
    errors.writeln('Missing required option: --vm-service-uri');
    return 64;
  }

  final trimmedServiceUri = serviceUri?.trim();
  final store = LogHoundDirectoryStore(io.Directory(rootPath));
  final eventFactory = vmServiceEventFactory ?? _vmServiceEvents;
  var records = 0;
  var ignored = 0;
  var connections = 0;
  final redactor = LogHoundRedactor();

  while (true) {
    connections++;
    try {
      final events =
          injectedEvents ??
          eventFactory(
            trimmedServiceUri!,
            errors: errors,
            resumeOnListen: resumeOnListen,
          );

      await for (final event in events) {
        final record = logHoundDecodeVmServiceEvent(
          event,
          eventKind: eventKind,
        );
        if (record == null) {
          ignored++;
          continue;
        }
        await store.append(_redactRecord(record, redactor));
        records++;
      }
    } on Object catch (error) {
      errors.writeln('VM Service connection failed: $error');
      if (!keepAlive) {
        return 1;
      }
    }

    if (injectedEvents != null || !keepAlive) {
      break;
    }
    if (maxConnections != null && connections >= maxConnections) {
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  final result = <String, Object?>{
    'root': rootPath,
    'records': records,
    'ignored': ignored,
  };
  if (trimmedServiceUri != null && trimmedServiceUri.isNotEmpty) {
    result['vm_service_uri'] = trimmedServiceUri;
  }

  _writeRecord(output, result);
  return 0;
}

Map<String, Object?> _redactRecord(
  Map<String, Object?> record,
  LogHoundRedactor redactor,
) {
  return redactor.redact(record) as Map<String, Object?>;
}

Stream<LogHoundVmServiceEvent> _vmServiceEvents(
  String serviceUri, {
  required StringSink errors,
  bool resumeOnListen = false,
}) async* {
  final wsUri = logHoundVmServiceWebSocketUri(serviceUri).toString();
  final service = await vmServiceConnectUri(wsUri);
  try {
    await service.streamListen(EventStreams.kExtension);
    if (resumeOnListen) {
      await _resumeMainIsolate(service, errors);
    }
    errors.writeln('loghound collecting from $serviceUri');
    await for (final event in service.onExtensionEvent) {
      yield LogHoundVmServiceEvent(
        kind: event.extensionKind,
        data: event.extensionData?.data,
      );
    }
  } finally {
    await service.dispose();
  }
}

Future<void> _resumeMainIsolate(VmService service, StringSink errors) async {
  try {
    final vm = await service.getVM();
    final isolates = vm.isolates ?? const <IsolateRef>[];
    final isolate = isolates
        .where((isolate) => isolate.isSystemIsolate != true)
        .where((isolate) => isolate.id != null && isolate.id!.isNotEmpty)
        .firstOrNull;
    final isolateId = isolate?.id;
    if (isolateId == null) {
      errors.writeln('No app isolate found to resume.');
      return;
    }
    await service.resume(isolateId);
  } on Object catch (error) {
    errors.writeln('Failed to resume paused app isolate: $error');
  }
}

Future<int> _runQuery(ArgResults command, StringSink output) async {
  final query = LogHoundQuery(
    contains: command['contains'] as String?,
    name: command['name'] as String?,
    minimumLevel: _optionalInt(command['min-level'] as String?),
    since: _optionalDateTime(command['since'] as String?),
    traceId: command['trace-id'] as String?,
    requestId: command['request-id'] as String?,
    sessionId: command['session-id'] as String?,
    userId: command['user-id'] as String?,
  );

  for (final record in await _recordsFor(command)) {
    if (query.matches(record)) {
      _writeRecord(output, record);
    }
  }
  return 0;
}

Future<int> _runTail(ArgResults command, StringSink output) async {
  final count = int.parse(command['count'] as String);
  final records = await _recordsFor(command);
  if (records.length <= count) {
    _writeRecords(output, records);
  } else {
    _writeRecords(output, records.sublist(records.length - count));
  }
  return 0;
}

Future<int> _runLatestError(ArgResults command, StringSink output) async {
  final query = const LogHoundQuery(minimumLevel: 900);
  Map<String, Object?>? latest;
  for (final record in await _recordsFor(command)) {
    if (query.matches(record)) {
      latest = record;
    }
  }
  if (latest == null) {
    return 1;
  }
  _writeRecord(output, latest);
  return 0;
}

Future<int> _runContext(ArgResults command, StringSink output) async {
  final records = await _recordsFor(command);
  final latestIndex = _latestErrorIndex(records);
  if (latestIndex == -1) {
    return 1;
  }

  final before = math.max(0, int.parse(command['before'] as String));
  final after = math.max(0, int.parse(command['after'] as String));
  final maxLines = math.max(1, int.parse(command['max-lines'] as String));
  final maxChars = math.max(0, int.parse(command['max-chars'] as String));
  final relatedIndexes = _relatedContextIndexes(
    records,
    latestIndex,
    before,
    after,
  );
  final window = [for (final index in relatedIndexes) records[index]];
  final related = _limitAroundLatest(
    window,
    relatedIndexes.indexOf(latestIndex),
    maxLines,
  );
  final omitted = window.length - related.length;
  final settings = await LogHoundSettingsStore(
    _readRootDirectory(command['root'] as String),
  ).read();
  final format = command.wasParsed('format')
      ? command['format'] as String
      : settings.contextFormat;
  final text = switch (format) {
    'jsonl' => _formatJsonLines(related),
    _ => _formatMarkdownContext(
      source: _sourceLabel(command),
      latest: records[latestIndex],
      related: related,
      omitted: omitted,
    ),
  };

  output.write(_limitText(text, maxChars));
  return 0;
}

Future<int> _runActions(ArgResults command, StringSink output) async {
  for (final record in await _recordsFor(command)) {
    if (_recordKind(record) == 'action') {
      _writeRecord(output, record);
    }
  }
  return 0;
}

Future<int> _runHttp(
  ArgResults command,
  StringSink output,
  StringSink errors,
) async {
  final subcommand = command.command;
  if (subcommand == null) {
    errors.writeln('Missing http subcommand: list or show');
    return 64;
  }

  final records = await _recordsFor(subcommand);
  final httpRecords = records.where(_isHttpRecord);
  switch (subcommand.name) {
    case 'list':
      for (final record in httpRecords) {
        _writeRecord(output, _httpSummary(record));
      }
      return 0;
    case 'show':
      final requestId = subcommand['request-id'] as String?;
      if (requestId == null || requestId.isEmpty) {
        errors.writeln('Missing --request-id');
        return 64;
      }
      final record = _firstByRequestId(httpRecords, requestId);
      if (record == null) {
        return 1;
      }
      _writeRecord(output, record);
      return 0;
    default:
      errors.writeln('Unknown http subcommand: ${subcommand.name}');
      return 64;
  }
}

Future<int> _runBody(
  ArgResults command,
  StringSink output,
  StringSink errors,
) async {
  final requestId = command['request-id'] as String?;
  if (requestId == null || requestId.isEmpty) {
    errors.writeln('Missing --request-id');
    return 64;
  }
  if (command['request'] == true && command['response'] == true) {
    errors.writeln('Use only one of --request or --response');
    return 64;
  }

  final record = _firstByRequestId(
    (await _recordsFor(command)).where(_isHttpRecord),
    requestId,
  );
  if (record == null) {
    return 1;
  }

  final useRequest = command['request'] == true;
  final body = useRequest ? _requestBody(record) : _responseBody(record);
  Object? result = body;

  final sample = command['sample'] as String?;
  final find = command['find'] as String?;
  final jsonPath = command['json-path'] as String?;
  if (sample != null && sample.isNotEmpty) {
    final selected = _selectJsonPath(body, _normalizeJsonPath(sample));
    final count = int.parse(command['count'] as String);
    if (selected is List) {
      result = selected.take(count).toList(growable: false);
    } else {
      result = selected;
    }
  } else if (find != null && find.isNotEmpty) {
    result = _findInJson(body, find);
  } else if (jsonPath != null && jsonPath.isNotEmpty) {
    result = _selectJsonPath(body, jsonPath);
  }

  output.writeln(jsonEncode(loghoundJsonSafe(result)));
  return 0;
}

Future<int> _runStats(ArgResults command, StringSink output) async {
  final records = await _recordsFor(command);
  final byKind = <String, int>{};
  var httpRecords = 0;
  var actionRecords = 0;
  var requestBodyBytes = 0;
  var responseBodyBytes = 0;

  for (final record in records) {
    final kind = _recordKind(record);
    byKind[kind] = (byKind[kind] ?? 0) + 1;
    if (kind == 'http') {
      httpRecords++;
      requestBodyBytes += _bodyBytes(_requestBody(record));
      responseBodyBytes += _bodyBytes(_responseBody(record));
    } else if (kind == 'action') {
      actionRecords++;
    }
  }

  _writeRecord(output, {
    'source': _sourceLabel(command),
    'records': records.length,
    'http_records': httpRecords,
    'action_records': actionRecords,
    'request_body_bytes': requestBodyBytes,
    'response_body_bytes': responseBodyBytes,
    'by_kind': byKind,
  });
  return 0;
}

Future<int> _runDoctor(ArgResults command, StringSink output) async {
  final rootPath = command['root'] as String;
  final directoryStore = LogHoundDirectoryStore(_readRootDirectory(rootPath));
  final sessionFilter = command['session'] as String?;
  final sessions =
      (await directoryStore.sessions(
        appId: command['app'] as String?,
        flavor: command['flavor'] as String?,
        platform: command['platform'] as String?,
      )).where((session) {
        return sessionFilter == null ||
            sessionFilter.isEmpty ||
            session.sessionId == sessionFilter;
      }).toList();

  final issues = <Map<String, Object?>>[];
  final records = <Map<String, Object?>>[];
  for (final session in sessions) {
    records.addAll(await JsonlLogStore(session.file).readAll());
  }
  records.sort(_compareRecordsByTimestamp);

  if (sessions.isEmpty) {
    issues.add({
      'severity': 'error',
      'code': 'no_sessions',
      'message': 'No loghound sessions were found for the selected route.',
    });
  } else if (records.isEmpty) {
    issues.add({
      'severity': 'error',
      'code': 'no_records',
      'message': 'Sessions exist, but no records were readable.',
    });
  }

  final byKind = <String, int>{};
  var screenRecords = 0;
  var actionRecords = 0;
  var httpRecords = 0;
  var errorRecords = 0;
  var httpBodyRecords = 0;
  for (final record in records) {
    final kind = _recordKind(record);
    byKind[kind] = (byKind[kind] ?? 0) + 1;
    if (kind == 'screen') {
      screenRecords++;
    } else if (kind == 'action') {
      actionRecords++;
    } else if (kind == 'http') {
      httpRecords++;
      if (_requestBody(record) != null || _responseBody(record) != null) {
        httpBodyRecords++;
      }
    } else if (kind == 'error') {
      errorRecords++;
    }
  }

  if (records.isNotEmpty) {
    if (screenRecords == 0) {
      issues.add({
        'severity': 'warning',
        'code': 'no_screen_records',
        'message': 'No screen records were found; route context may be weak.',
      });
    }
    if (actionRecords == 0) {
      issues.add({
        'severity': 'warning',
        'code': 'no_action_records',
        'message':
            'No action records were found; user intent context may be weak.',
      });
    }
    if (httpRecords == 0) {
      issues.add({
        'severity': 'warning',
        'code': 'no_http_records',
        'message':
            'No HTTP records were found; API investigation will be limited.',
      });
    } else if (httpBodyRecords == 0) {
      issues.add({
        'severity': 'warning',
        'code': 'no_http_bodies',
        'message':
            'HTTP records exist, but request/response bodies are not captured.',
      });
    }
  }

  final latestRecordAt = records.isEmpty
      ? null
      : _recordTimestamp(records.last);
  final maxAgeMinutes = _optionalInt(command['max-age-minutes'] as String?);
  if (latestRecordAt != null && maxAgeMinutes != null) {
    final age = DateTime.now().difference(latestRecordAt).inMinutes;
    if (age > maxAgeMinutes) {
      issues.add({
        'severity': 'warning',
        'code': 'stale_records',
        'message': 'Latest record is older than $maxAgeMinutes minute(s).',
        'age_minutes': age,
      });
    }
  }

  final hasErrors = issues.any((issue) => issue['severity'] == 'error');
  final hasWarnings = issues.any((issue) => issue['severity'] == 'warning');
  final status = hasErrors ? 'fail' : (hasWarnings ? 'warn' : 'ok');
  final latestSession = sessions.isEmpty ? null : sessions.first.toJson();

  final report = <String, Object?>{
    'root': rootPath,
    'status': status,
    'ok': status == 'ok',
    'sessions': sessions.length,
    'records': records.length,
    'screen_records': screenRecords,
    'action_records': actionRecords,
    'http_records': httpRecords,
    'error_records': errorRecords,
    'http_body_records': httpBodyRecords,
    'by_kind': byKind,
    if (latestRecordAt != null)
      'latest_record_at': latestRecordAt.toIso8601String(),
    'issues': issues,
  };
  if (latestSession != null) {
    report['latest_session'] = latestSession;
  }

  _writeRecord(output, report);
  return hasErrors ? 1 : 0;
}

Future<int> _runSetting(
  ArgResults command,
  StringSink output,
  StringSink errors,
) async {
  final rootPath = command['root'] as String;
  final store = LogHoundSettingsStore(_readRootDirectory(rootPath));
  var settings = await store.read();
  final rest = command.rest;

  if (rest.isNotEmpty) {
    if (rest.length != 2) {
      errors.writeln('Usage: loghound setting <key> <value>');
      return 64;
    }
    final key = rest[0];
    final descriptor = _settingDescriptorByKey(key);
    if (descriptor == null) {
      errors.writeln('Unknown setting: $key');
      return 64;
    }
    final value = _parseSettingValue(descriptor, rest[1]);
    if (value == null) {
      errors.writeln(
        'Invalid value for $key: ${rest[1]}'
        '${descriptor.options == null ? '' : ' (expected ${descriptor.options!.join('|')})'}',
      );
      return 64;
    }
    settings = descriptor.applyValue(settings, value);
    await store.write(settings);
    final record = settings
        .toSettingRecords(language: settings.language)
        .singleWhere((record) => record['key'] == key);
    _writeRecord(output, record);
    return 0;
  }

  final subcommand = command.command;

  if (subcommand == null) {
    if (io.stdin.hasTerminal && io.stdout.hasTerminal) {
      await runSettingInteractive(
        store: store,
        initialSettings: settings,
        stdin: io.stdin,
        stdout: io.stdout,
        color: logHoundShouldColor(
          hasTerminal: io.stdout.hasTerminal,
          supportsAnsi: io.stdout.supportsAnsiEscapes,
          environment: io.Platform.environment,
        ),
      );
      return 0;
    }
    _writeRecords(output, settings.toSettingRecords());
    return 0;
  }

  errors.writeln('Unknown setting: ${subcommand.name}');
  return 64;
}

LogHoundSettingDescriptor? _settingDescriptorByKey(String key) {
  for (final descriptor in logHoundSettingDescriptors) {
    if (descriptor.key == key) {
      return descriptor;
    }
  }
  return null;
}

Object? _parseSettingValue(LogHoundSettingDescriptor descriptor, String value) {
  if (descriptor.options case final options?) {
    return options.contains(value) ? value : null;
  }
  return switch (value.toLowerCase()) {
    'true' || 'on' || 'yes' => true,
    'false' || 'off' || 'no' => false,
    _ => null,
  };
}

/// Runs the interactive `loghound setting` list on a real terminal.
///
/// Puts [stdin] into raw mode, draws the localized setting list, and loops
/// on keypresses: arrows move the selection, space advances the selected
/// setting's value and persists it through [store], right/enter expands a
/// description, and q/Esc exits. Rows colorize when [color] is true.
/// Terminal modes are always restored.
Future<void> runSettingInteractive({
  required LogHoundSettingsStore store,
  required LogHoundSettings initialSettings,
  required io.Stdin stdin,
  required io.Stdout stdout,
  required bool color,
}) async {
  final priorEcho = stdin.echoMode;
  final priorLine = stdin.lineMode;
  var settings = initialSettings;
  var state = SettingInteractiveState(
    records: settings.toSettingRecords(language: settings.language),
    selectedIndex: 0,
    expandedKeys: const <String>{},
    language: settings.language,
  );
  var priorLines = 0;

  void draw() {
    final frame = renderSettingInteractiveList(state, color: color);
    if (priorLines > 0) {
      stdout.write('\x1b[${priorLines}A\x1b[0J');
    }
    stdout.write(frame);
    priorLines = '\n'.allMatches(frame).length;
  }

  var restored = false;
  void restore() {
    if (restored) {
      return;
    }
    restored = true;
    stdout.write('\x1b[?25h');
    stdin.echoMode = priorEcho;
    stdin.lineMode = priorLine;
  }

  final done = Completer<void>();
  late StreamSubscription<List<int>> subscription;

  Future<void> handle(List<int> bytes) async {
    final result = handleSettingInteractiveKey(
      state,
      decodeSettingInteractiveKey(bytes),
    );
    state = result.state;

    final advanceKey = result.advanceKey;
    if (advanceKey != null) {
      final descriptor = logHoundSettingDescriptors.firstWhere(
        (candidate) => candidate.key == advanceKey,
      );
      settings = logHoundAdvanceSetting(descriptor, settings);
      await store.write(settings);
      state = state.copyWith(
        records: settings.toSettingRecords(language: settings.language),
        language: settings.language,
      );
    }

    draw();
    if (result.quit) {
      // Restore terminal modes while stdin is still open: cancelling the
      // subscription closes fd 0, so a later restore would throw a
      // StdinException.
      restore();
      await subscription.cancel();
      if (!done.isCompleted) {
        done.complete();
      }
    }
  }

  Future<void> handleSafely(List<int> bytes) async {
    try {
      await handle(bytes);
    } on Object catch (error, stackTrace) {
      restore();
      await subscription.cancel();
      if (!done.isCompleted) {
        done.completeError(error, stackTrace);
      }
    }
  }

  try {
    stdin.echoMode = false;
    stdin.lineMode = false;
    stdout.write('\x1b[?25l');
    draw();

    // Serialize keypresses: pause until each async handler finishes so a
    // fast burst of input cannot interleave value writes.
    subscription = stdin.listen(
      (bytes) => subscription.pause(handleSafely(bytes)),
      onDone: () {
        restore();
        if (!done.isCompleted) {
          done.complete();
        }
      },
    );

    await done.future;
  } finally {
    restore();
  }
}

/// Resolves the Flutter executable for a project directory.
///
/// FVM projects are detected through `.fvm/flutter_sdk/bin/flutter`; otherwise
/// the executable name `flutter` is returned so the user's PATH is used.
String resolveFlutterExecutable(
  io.Directory projectDirectory, {
  bool? isWindows,
}) {
  final executable = (isWindows ?? io.Platform.isWindows)
      ? 'flutter.bat'
      : 'flutter';
  final fvmFlutter = io.File(
    [
      projectDirectory.path,
      '.fvm',
      'flutter_sdk',
      'bin',
      executable,
    ].join(io.Platform.pathSeparator),
  );
  if (fvmFlutter.existsSync()) {
    return fvmFlutter.path;
  }
  return executable;
}

Future<int> _defaultProcessRunner(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async {
  final process = await io.Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    mode: io.ProcessStartMode.inheritStdio,
  );
  return process.exitCode;
}

Future<io.Process> _defaultProcessStarter(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) {
  return io.Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
}

Future<_VmServiceUriResolution?> _resolveStayVmServiceUri(
  ArgResults command,
  io.Directory currentDirectory,
  LogHoundProcessStarter processStarter, {
  required Duration timeout,
  required StringSink errors,
}) async {
  if (command.wasParsed('vm-service-uri') ||
      command.wasParsed('vm-service-uri-file')) {
    final explicitUri = await _resolveVmServiceUri(
      explicitUri: command['vm-service-uri'] as String?,
      uriFilePath: command.wasParsed('vm-service-uri-file')
          ? command['vm-service-uri-file'] as String?
          : null,
      currentDirectory: currentDirectory,
      timeout: timeout,
      errors: errors,
    );
    if (explicitUri != null) {
      return _VmServiceUriResolution(explicitUri);
    }
    return null;
  }

  final flutterExecutable =
      command['flutter'] as String? ??
      resolveFlutterExecutable(currentDirectory);
  final attachArgs = <String>[
    'attach',
    '--machine',
    if ((command['device'] as String?)?.isNotEmpty == true) ...[
      '-d',
      command['device'] as String,
    ],
    if ((command['app-id'] as String?)?.isNotEmpty == true) ...[
      '--app-id',
      command['app-id'] as String,
    ],
  ];

  late final io.Process process;
  try {
    process = await processStarter(
      flutterExecutable,
      attachArgs,
      workingDirectory: currentDirectory.path,
    );
  } on Object catch (error) {
    errors.writeln('Failed to start Flutter: $error');
    return _VmServiceUriResolution.failure(1);
  }
  unawaited(process.stderr.drain<void>());

  try {
    final uri = await process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .map(_vmServiceUriFromFlutterAttachLine)
        .where((uri) => uri != null)
        .cast<String>()
        .first
        .timeout(timeout);
    return _VmServiceUriResolution(uri, process: process);
  } on Object catch (error) {
    process.kill();
    if (error is TimeoutException) {
      errors.writeln('Timed out waiting for flutter attach VM Service URI.');
    } else {
      errors.writeln('Failed to discover VM Service URI from flutter attach.');
    }
    return _VmServiceUriResolution.failure(1);
  }
}

String? _vmServiceUriFromFlutterAttachLine(String line) {
  final text = line.trim();
  if (!text.startsWith('[')) {
    return null;
  }

  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (decoded is! List) {
    return null;
  }

  for (final event in decoded) {
    if (event is! Map || event['event'] != 'app.debugPort') {
      continue;
    }
    final params = event['params'];
    if (params is! Map) {
      continue;
    }
    final wsUri = params['wsUri'];
    if (wsUri is String && wsUri.trim().isNotEmpty) {
      return wsUri.trim();
    }
    final baseUri = params['baseUri'];
    if (baseUri is String && baseUri.trim().isNotEmpty) {
      return baseUri.trim();
    }
  }
  return null;
}

class _VmServiceUriResolution {
  _VmServiceUriResolution(this.uri, {io.Process? process})
    : exitCode = null,
      _process = process;

  _VmServiceUriResolution.failure(this.exitCode) : uri = null, _process = null;

  final String? uri;
  final int? exitCode;
  final io.Process? _process;

  void dispose() {
    _process?.kill();
  }
}

Future<String?> _resolveVmServiceUri({
  required String? explicitUri,
  required String? uriFilePath,
  required io.Directory currentDirectory,
  required Duration? timeout,
  required StringSink errors,
}) async {
  final trimmedExplicitUri = explicitUri?.trim();
  if (trimmedExplicitUri != null && trimmedExplicitUri.isNotEmpty) {
    return trimmedExplicitUri;
  }

  final trimmedFilePath = uriFilePath?.trim();
  if (trimmedFilePath == null || trimmedFilePath.isEmpty) {
    errors.writeln('Missing required option: --vm-service-uri');
    return null;
  }

  final file = io.File(_resolvePath(currentDirectory, trimmedFilePath));
  try {
    return await _readVmServiceUriFromFile(file, timeout: timeout);
  } on TimeoutException {
    errors.writeln('Timed out waiting for VM Service URI file: ${file.path}');
    return null;
  }
}

Future<String> _readVmServiceUriFromFile(
  io.File file, {
  Duration? timeout,
}) async {
  final started = DateTime.now();
  while (true) {
    if (await file.exists()) {
      final text = (await file.readAsString()).trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    if (timeout != null && DateTime.now().difference(started) >= timeout) {
      throw TimeoutException('Timed out waiting for ${file.path}', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

String _resolvePath(io.Directory currentDirectory, String path) {
  if (io.File(path).isAbsolute) {
    return path;
  }
  return [currentDirectory.path, path].join(io.Platform.pathSeparator);
}

io.Directory _readRootDirectory(String rootPath) {
  final root = io.Directory(rootPath);
  if (rootPath != _defaultLogRoot || root.existsSync()) {
    return root;
  }
  final legacyRoot = io.Directory(_legacyLogRoot);
  if (legacyRoot.existsSync()) {
    return legacyRoot;
  }
  return root;
}

Future<List<Map<String, Object?>>> _recordsFor(ArgResults command) async {
  final stores = await _storesFor(command);
  final records = <Map<String, Object?>>[];
  for (final store in stores) {
    records.addAll(await store.readAll());
  }
  records.sort(_compareRecordsByTimestamp);
  return records;
}

Future<List<JsonlLogStore>> _storesFor(ArgResults command) async {
  final app = _option(command, 'app');
  if (!_usesRoutedStore(command)) {
    return [JsonlLogStore(io.File(_option(command, 'file')!))];
  }

  final root = _readRootDirectory(_option(command, 'root')!);
  final directoryStore = LogHoundDirectoryStore(root);
  final flavor = _option(command, 'flavor');
  final platform = _option(command, 'platform');
  final session = _option(command, 'session');

  final sessions = await directoryStore.sessions(
    appId: app,
    flavor: flavor,
    platform: platform,
  );
  final matching = session == null || session.isEmpty
      ? sessions
      : sessions.where((summary) => summary.sessionId == session);
  return [for (final summary in matching) JsonlLogStore(summary.file)];
}

bool _usesRoutedStore(ArgResults command) {
  if (_hasOption(command, 'file')) {
    return _option(command, 'file') == null;
  }
  return _option(command, 'app') != null ||
      _option(command, 'flavor') != null ||
      _option(command, 'platform') != null ||
      _option(command, 'session') != null ||
      _option(command, 'root') != null;
}

String? _option(ArgResults command, String name) {
  Object? value;
  try {
    value = command[name];
  } on ArgumentError {
    return null;
  }
  if (value is String && value.isNotEmpty) {
    return value;
  }
  return null;
}

bool _hasOption(ArgResults command, String name) {
  try {
    command[name];
    return true;
  } on ArgumentError {
    return false;
  }
}

String _sourceLabel(ArgResults command) {
  if (!_usesRoutedStore(command)) {
    return _option(command, 'file')!;
  }
  final app = _option(command, 'app');
  final flavor = _option(command, 'flavor');
  final platform = _option(command, 'platform');
  final session = _option(command, 'session');
  final parts = <String>[
    _option(command, 'root') ?? _defaultLogRoot,
    if (app != null) 'app=$app',
    ?flavor,
    ?platform,
    ?session,
  ];
  return parts.join('/');
}

int? _optionalInt(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  return int.parse(value);
}

DateTime? _optionalDateTime(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  return DateTime.parse(value);
}

void _writeRecords(StringSink output, Iterable<Map<String, Object?>> records) {
  for (final record in records) {
    _writeRecord(output, record);
  }
}

void _writeRecord(StringSink output, Map<String, Object?> record) {
  output.writeln(jsonEncode(loghoundJsonSafe(record)));
}

int _compareRecordsByTimestamp(
  Map<String, Object?> left,
  Map<String, Object?> right,
) {
  final leftTimestamp = _recordTimestamp(left);
  final rightTimestamp = _recordTimestamp(right);
  if (leftTimestamp == null && rightTimestamp == null) {
    return 0;
  }
  if (leftTimestamp == null) {
    return -1;
  }
  if (rightTimestamp == null) {
    return 1;
  }
  return leftTimestamp.compareTo(rightTimestamp);
}

DateTime? _recordTimestamp(Map<String, Object?> record) {
  final value = record['timestamp'] ?? record['time'];
  if (value is String) {
    return DateTime.tryParse(value);
  }
  if (value is DateTime) {
    return value;
  }
  return null;
}

int _latestErrorIndex(List<Map<String, Object?>> records) {
  const query = LogHoundQuery(minimumLevel: 900);
  for (var index = records.length - 1; index >= 0; index--) {
    if (query.matches(records[index])) {
      return index;
    }
  }
  return -1;
}

List<Map<String, Object?>> _limitAroundLatest(
  List<Map<String, Object?>> records,
  int latestOffset,
  int maxLines,
) {
  if (records.length <= maxLines) {
    return records;
  }

  final before = (maxLines - 1) ~/ 2;
  final after = maxLines - 1 - before;
  var start = math.max(0, latestOffset - before);
  var end = math.min(records.length, latestOffset + after + 1);
  if (end - start < maxLines) {
    start = math.max(0, end - maxLines);
    end = math.min(records.length, start + maxLines);
  }
  return records.sublist(start, end);
}

List<int> _relatedContextIndexes(
  List<Map<String, Object?>> records,
  int latestIndex,
  int before,
  int after,
) {
  final indexes = <int>{};
  final windowStart = math.max(0, latestIndex - before);
  final windowEnd = math.min(records.length, latestIndex + after + 1);
  for (var index = windowStart; index < windowEnd; index++) {
    indexes.add(index);
  }

  final latestIdentifiers = _recordIdentifiers(records[latestIndex]);
  if (latestIdentifiers.isNotEmpty) {
    for (var index = 0; index < records.length; index++) {
      if (_recordIdentifiers(
        records[index],
      ).intersection(latestIdentifiers).isNotEmpty) {
        indexes.add(index);
      }
    }
  }

  return indexes.toList()..sort();
}

Set<String> _recordIdentifiers(Map<String, Object?> record) {
  const identifierKeys = [
    ['trace_id', 'traceId'],
    ['request_id', 'requestId'],
    ['session_id', 'sessionId'],
    ['user_id', 'userId'],
  ];
  final values = <String>{};
  for (final keys in identifierKeys) {
    for (final source in [record, record['data'], record['attributes']]) {
      final value = _lookupIdentifier(source, keys);
      if (value != null && value.toString().isNotEmpty) {
        values.add(value.toString());
      }
    }
  }
  return values;
}

bool _isHttpRecord(Map<String, Object?> record) {
  return _recordKind(record) == 'http';
}

String _recordKind(Map<String, Object?> record) {
  final kind = record['kind'];
  if (kind is String && kind.trim().isNotEmpty) {
    return kind.trim().toLowerCase();
  }
  if (record['name'] == 'HTTP' ||
      record.containsKey('method') ||
      record.containsKey('url') ||
      record.containsKey('status') ||
      record.containsKey('status_code') ||
      record.containsKey('request_body') ||
      record.containsKey('response_body')) {
    return 'http';
  }
  return 'log';
}

Map<String, Object?> _httpSummary(Map<String, Object?> record) {
  final requestBody = _requestBody(record);
  final responseBody = _responseBody(record);
  return {
    if (record['timestamp'] != null) 'timestamp': record['timestamp'],
    if (_recordValue(record, const ['app_id', 'appId']) != null)
      'app_id': _recordValue(record, const ['app_id', 'appId']),
    if (record['flavor'] != null) 'flavor': record['flavor'],
    if (_recordValue(record, const ['session_id', 'sessionId']) != null)
      'session_id': _recordValue(record, const ['session_id', 'sessionId']),
    if (_recordValue(record, const ['request_id', 'requestId']) != null)
      'request_id': _recordValue(record, const ['request_id', 'requestId']),
    if (record['method'] != null) 'method': record['method'],
    if (record['url'] != null) 'url': record['url'],
    if (record['path'] != null) 'path': record['path'],
    if (record['status'] != null) 'status': record['status'],
    if (record['status_code'] != null) 'status': record['status_code'],
    if (record['duration_ms'] != null) 'duration_ms': record['duration_ms'],
    'request_body_bytes':
        _recordValue(record, const [
          'request_body_bytes',
          'requestBodyBytes',
        ]) ??
        _bodyBytes(requestBody),
    'response_body_bytes':
        _recordValue(record, const [
          'response_body_bytes',
          'responseBodyBytes',
        ]) ??
        _bodyBytes(responseBody),
    if (_recordValue(record, const [
          'request_body_truncated',
          'requestBodyTruncated',
        ]) !=
        null)
      'request_body_truncated': _recordValue(record, const [
        'request_body_truncated',
        'requestBodyTruncated',
      ]),
    if (_recordValue(record, const [
          'response_body_truncated',
          'responseBodyTruncated',
        ]) !=
        null)
      'response_body_truncated': _recordValue(record, const [
        'response_body_truncated',
        'responseBodyTruncated',
      ]),
  };
}

Map<String, Object?>? _firstByRequestId(
  Iterable<Map<String, Object?>> records,
  String requestId,
) {
  for (final record in records) {
    final value = _recordValue(record, const ['request_id', 'requestId']);
    if (value?.toString() == requestId) {
      return record;
    }
  }
  return null;
}

Object? _recordValue(Map<String, Object?> record, List<String> keys) {
  return _lookupIdentifier(record, keys) ??
      _lookupIdentifier(record['data'], keys) ??
      _lookupIdentifier(record['attributes'], keys);
}

Object? _requestBody(Map<String, Object?> record) {
  return _recordValue(record, const ['request_body', 'requestBody']);
}

Object? _responseBody(Map<String, Object?> record) {
  return _recordValue(record, const ['response_body', 'responseBody']);
}

int _bodyBytes(Object? body) {
  if (body == null) {
    return 0;
  }
  return utf8.encode(jsonEncode(loghoundJsonSafe(body))).length;
}

String _normalizeJsonPath(String path) {
  if (path.startsWith(r'$')) {
    return path;
  }
  return path.startsWith('.') ? r'$' + path : r'$.' + path;
}

Object? _selectJsonPath(Object? source, String path) {
  if (path.isEmpty || path == r'$') {
    return source;
  }

  var cursor = source;
  var remaining = path;
  if (remaining.startsWith(r'$.')) {
    remaining = remaining.substring(2);
  } else if (remaining.startsWith(r'$')) {
    remaining = remaining.substring(1);
  }
  if (remaining.startsWith('.')) {
    remaining = remaining.substring(1);
  }
  if (remaining.isEmpty) {
    return cursor;
  }

  for (final part in remaining.split('.')) {
    if (part.isEmpty) {
      continue;
    }
    final match = RegExp(r'^([^\[]+)((?:\[\d+\])*)$').firstMatch(part);
    if (match == null) {
      return null;
    }
    final key = match.group(1)!;
    if (cursor is Map && cursor.containsKey(key)) {
      cursor = cursor[key];
    } else {
      return null;
    }

    final indexes = RegExp(r'\[(\d+)\]').allMatches(match.group(2)!);
    for (final indexMatch in indexes) {
      final index = int.parse(indexMatch.group(1)!);
      if (cursor is List && index < cursor.length) {
        cursor = cursor[index];
      } else {
        return null;
      }
    }
  }
  return cursor;
}

List<Map<String, Object?>> _findInJson(Object? source, String needle) {
  final results = <Map<String, Object?>>[];
  final normalizedNeedle = needle.toLowerCase();

  void visit(Object? value, String path) {
    if (results.length >= 50) {
      return;
    }
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString();
        final childPath = path == r'$' ? '$path.$key' : '$path.$key';
        if (key.toLowerCase().contains(normalizedNeedle)) {
          results.add({'path': childPath, 'value': entry.value});
        }
        visit(entry.value, childPath);
      }
    } else if (value is List) {
      for (var index = 0; index < value.length; index++) {
        visit(value[index], '$path[$index]');
      }
    } else if (value != null &&
        value.toString().toLowerCase().contains(normalizedNeedle)) {
      results.add({'path': path, 'value': value});
    }
  }

  visit(source, r'$');
  return results;
}

Object? _lookupIdentifier(Object? source, List<String> keys) {
  if (source is! Map) {
    return null;
  }

  for (final key in keys) {
    if (source.containsKey(key)) {
      return source[key];
    }
  }
  return null;
}

String _formatJsonLines(List<Map<String, Object?>> records) {
  if (records.isEmpty) {
    return '';
  }

  return '${records.map((record) => jsonEncode(loghoundJsonSafe(record))).join('\n')}\n';
}

String _formatMarkdownContext({
  required String source,
  required Map<String, Object?> latest,
  required List<Map<String, Object?>> related,
  required int omitted,
}) {
  final buffer = StringBuffer()
    ..writeln('# loghound context')
    ..writeln()
    ..writeln('Source: `$source`')
    ..writeln()
    ..writeln('## Latest Error')
    ..writeln()
    ..writeln('```json')
    ..writeln(jsonEncode(loghoundJsonSafe(latest)))
    ..writeln('```')
    ..writeln()
    ..write(_formatTimelineSummary(related))
    ..writeln('## Related Logs')
    ..writeln()
    ..writeln('```jsonl');
  for (final record in related) {
    buffer.writeln(jsonEncode(loghoundJsonSafe(record)));
  }
  buffer.writeln('```');
  if (omitted > 0) {
    buffer
      ..writeln()
      ..writeln('Omitted $omitted related log record(s) due to --max-lines.');
  }
  return buffer.toString();
}

String _formatTimelineSummary(List<Map<String, Object?>> records) {
  final lines = <String>[];
  for (final record in records) {
    final line = _formatTimelineRecord(record);
    if (line != null) {
      lines.add(line);
    }
  }
  if (lines.isEmpty) {
    return '';
  }

  final buffer = StringBuffer()
    ..writeln('## Timeline Summary')
    ..writeln();
  for (final line in lines) {
    buffer.writeln('- $line');
  }
  buffer.writeln();
  return buffer.toString();
}

String? _formatTimelineRecord(Map<String, Object?> record) {
  switch (_recordKind(record)) {
    case 'action':
      final name = record['name'] ?? 'action';
      final screen = record['screen'];
      final route = record['route'];
      final data = record['data'];
      return [
        'Action: $name',
        if (screen != null) 'screen=$screen',
        if (route != null) 'route=$route',
        if (data is Map && data.isNotEmpty)
          'data=${jsonEncode(loghoundJsonSafe(data))}',
      ].join(' ');
    case 'screen':
      final screen = record['screen'] ?? record['name'] ?? 'screen';
      final route = record['route'];
      return ['Screen: $screen', if (route != null) 'route=$route'].join(' ');
    case 'http':
      final summary = _httpSummary(record);
      final method = summary['method'] ?? 'HTTP';
      final target = summary['url'] ?? summary['path'] ?? '';
      final status = summary['status'] == null
          ? ''
          : ' -> ${summary['status']}';
      final duration = summary['duration_ms'] == null
          ? ''
          : ' duration=${summary['duration_ms']}ms';
      final requestBytes = summary['request_body_bytes'];
      final responseBytes = summary['response_body_bytes'];
      final bytes = [
        if (requestBytes != null) 'request_body_bytes=$requestBytes',
        if (responseBytes != null) 'response_body_bytes=$responseBytes',
      ].join(' ');
      return 'HTTP: $method $target$status$duration'
          '${bytes.isEmpty ? '' : ' $bytes'}';
    case 'error':
      return 'Error: ${record['message'] ?? record['error'] ?? record['name'] ?? 'error'}';
    default:
      final level = record['level'];
      if (level is num && level >= 900) {
        return 'Log: ${record['message'] ?? record['name'] ?? jsonEncode(loghoundJsonSafe(record))}';
      }
      return null;
  }
}

String _limitText(String text, int maxChars) {
  if (maxChars == 0 || text.length <= maxChars) {
    return text;
  }

  final suffix = '\n\n[truncated to $maxChars chars]\n';
  if (maxChars <= suffix.length) {
    return suffix.substring(0, maxChars);
  }

  return '${text.substring(0, maxChars - suffix.length)}$suffix';
}

String _usage(ArgParser parser) {
  return '''
Usage: loghound <command> [options]

Commands:
  run            Run Flutter and collect hidden loghound VM Service events
  stay           Keep collecting hidden loghound VM Service events
  apps           List discovered apps
  sessions       List discovered sessions
  query          Filter records from a JSON Lines file
  tail           Print the latest records
  latest-error   Print the latest warning/error record
  context        Build AI-friendly context around the latest warning/error
  actions        Print semantic action records
  http           List or show HTTP records
  body           Inspect a stored HTTP request or response body
  stats          Print log volume and capture statistics
  doctor         Check whether logs are ready for AI investigation
  setting        Show or update persistent loghound settings

${parser.usage}''';
}
