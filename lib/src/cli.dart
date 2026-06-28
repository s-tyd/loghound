import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:args/args.dart';

import 'banner.dart';
import 'json_safe.dart';
import 'jsonl_log_store.dart';
import 'log_query.dart';
import 'loghound_directory_store.dart';
import 'log_receiver_server.dart';

/// Runs the `loghound` command-line interface.
Future<int> runLogHoundCli(
  List<String> args, {
  StringSink? out,
  StringSink? err,
}) async {
  final output = out ?? io.stdout;
  final errors = err ?? io.stderr;
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
  if (command == null || results['help'] == true) {
    output.writeln(_usage(parser));
    return 0;
  }

  switch (command.name) {
    case 'apps':
      return _runApps(command, output);
    case 'sessions':
      return _runSessions(command, output);
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
    case 'serve':
      return _runServe(command, output);
    case 'stay':
      return _runStay(command, output);
    default:
      errors.writeln('Unknown command: ${command.name}');
      errors.writeln(_usage(parser));
      return 64;
  }
}

ArgParser _buildParser() {
  return ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show help.')
    ..addCommand('apps', ArgParser()..addOption('root', defaultsTo: 'loghound'))
    ..addCommand('sessions', _withRouteOptions(ArgParser(), includeFile: false))
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
      'serve',
      ArgParser()
        ..addOption('host', defaultsTo: '127.0.0.1')
        ..addOption('port', defaultsTo: '8765')
        ..addOption('out', defaultsTo: 'loghound/app.jsonl'),
    )
    ..addCommand(
      'stay',
      ArgParser()
        ..addOption('host', defaultsTo: '127.0.0.1')
        ..addOption('port', defaultsTo: '8765')
        ..addOption('root', defaultsTo: 'loghound'),
    );
}

ArgParser _withRouteOptions(ArgParser parser, {bool includeFile = true}) {
  if (includeFile) {
    parser.addOption('file', abbr: 'f', defaultsTo: 'loghound/app.jsonl');
  }
  return parser
    ..addOption('root', defaultsTo: 'loghound')
    ..addOption('app')
    ..addOption('flavor')
    ..addOption('platform')
    ..addOption('session');
}

Future<int> _runApps(ArgResults command, StringSink output) async {
  final apps = await LogHoundDirectoryStore(
    io.Directory(command['root'] as String),
  ).apps();
  for (final app in apps) {
    _writeRecord(output, app.toJson());
  }
  return 0;
}

Future<int> _runSessions(ArgResults command, StringSink output) async {
  final sessions =
      await LogHoundDirectoryStore(
        io.Directory(command['root'] as String),
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
  final format = command['format'] as String;
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

Future<int> _runServe(ArgResults command, StringSink output) async {
  final host = command['host'] as String;
  final port = int.parse(command['port'] as String);
  final outputPath = command['out'] as String;
  final store = JsonlLogStore(io.File(outputPath));
  final server = await LogHoundReceiverServer.start(
    address: io.InternetAddress(host),
    port: port,
    store: store,
  );

  _writeBanner(output);
  output
    ..writeln('Listening on ${server.uri.resolve('/logs')}')
    ..writeln('Writing logs to $outputPath');

  final stop = Completer<void>();
  io.ProcessSignal.sigint.watch().listen((_) {
    if (!stop.isCompleted) {
      stop.complete();
    }
  });
  await stop.future;
  await server.close();
  return 0;
}

Future<int> _runStay(ArgResults command, StringSink output) async {
  final host = command['host'] as String;
  final port = int.parse(command['port'] as String);
  final rootPath = command['root'] as String;
  final directoryStore = LogHoundDirectoryStore(io.Directory(rootPath));
  final server = await LogHoundReceiverServer.start(
    address: io.InternetAddress(host),
    port: port,
    store: JsonlLogStore(io.File('$rootPath/.receiver.jsonl')),
    onRecord: directoryStore.append,
  );

  _writeBanner(output);
  output
    ..writeln('Listening on ${server.uri.resolve('/logs')}')
    ..writeln('Routing logs under $rootPath');

  final stop = Completer<void>();
  io.ProcessSignal.sigint.watch().listen((_) {
    if (!stop.isCompleted) {
      stop.complete();
    }
  });
  await stop.future;
  await server.close();
  return 0;
}

void _writeBanner(StringSink output) {
  output
    ..writeln()
    ..writeln(logHoundBanner(color: _stdoutWantsColor()))
    ..writeln();
}

bool _stdoutWantsColor() => logHoundShouldColor(
  hasTerminal: io.stdout.hasTerminal,
  supportsAnsi: io.stdout.supportsAnsiEscapes,
  environment: io.Platform.environment,
);

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

  final root = io.Directory(_option(command, 'root')!);
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
  return _option(command, 'app') != null ||
      _option(command, 'flavor') != null ||
      _option(command, 'platform') != null ||
      _option(command, 'session') != null ||
      (command.options.contains('root') && command.wasParsed('root'));
}

String? _option(ArgResults command, String name) {
  if (!command.options.contains(name)) {
    return null;
  }
  final value = command[name];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  return null;
}

String _sourceLabel(ArgResults command) {
  if (!_usesRoutedStore(command)) {
    return _option(command, 'file') ?? 'loghound/app.jsonl';
  }
  final app = _option(command, 'app');
  final flavor = _option(command, 'flavor');
  final platform = _option(command, 'platform');
  final session = _option(command, 'session');
  final parts = <String>[
    _option(command, 'root') ?? 'loghound',
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
  stay           Receive POST /logs and route by flavor/platform/session
  apps           List discovered apps
  sessions       List discovered sessions
  serve          Receive POST /logs and append JSON Lines
  query          Filter records from a JSON Lines file
  tail           Print the latest records
  latest-error   Print the latest warning/error record
  context        Build AI-friendly context around the latest warning/error
  actions        Print semantic action records
  http           List or show HTTP records
  body           Inspect a stored HTTP request or response body
  stats          Print log volume and capture statistics

${parser.usage}''';
}
