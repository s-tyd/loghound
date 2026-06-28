import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'json_safe.dart';
import 'loghound_client.dart';
import 'redactor.dart';

/// Sends one fully assembled log record.
typedef LogHoundRecordSender = void Function(Map<String, Object?> record);

/// Controls which development signals [LogHound.run] captures automatically.
class LogHoundCapture {
  /// Creates capture options for a loghound session.
  const LogHoundCapture({
    this.sessionLifecycle = true,
    this.prints = true,
    this.errors = true,
    this.actions = true,
    this.http = true,
  });

  /// Whether to send a `session.start` record.
  final bool sessionLifecycle;

  /// Whether to capture `print` calls from the app zone.
  final bool prints;

  /// Whether to capture uncaught zone errors.
  final bool errors;

  /// Whether semantic action helpers are expected to be used.
  final bool actions;

  /// Whether HTTP helper events are expected to be used.
  final bool http;
}

/// Metadata stamped onto every record in a loghound session.
class LogHoundSessionConfig {
  /// Creates immutable session metadata.
  const LogHoundSessionConfig({
    required this.appId,
    required this.flavor,
    required this.sessionId,
    this.platform,
    this.device,
    this.extra = const {},
  });

  /// Stable application identifier, such as `guide-app`.
  final String appId;

  /// Flavor or environment, such as `staging`.
  final String flavor;

  /// Unique identifier for this app run.
  final String sessionId;

  /// Optional platform override.
  final String? platform;

  /// Optional device label.
  final String? device;

  /// Extra fields to merge into every emitted record.
  final Map<String, Object?> extra;
}

/// Emits structured records for one app session.
class LogHoundSession {
  /// Creates a session with custom send, flush, close, and clock hooks.
  LogHoundSession({
    required this.config,
    LogHoundRecordSender? sendRecord,
    Future<void> Function()? flush,
    void Function()? close,
    LogHoundRedactor? redactor,
    DateTime Function()? now,
  }) : _sendRecord = sendRecord ?? ((_) {}),
       _flush = flush ?? (() async {}),
       _close = close ?? (() {}),
       _redactor = redactor ?? LogHoundRedactor(),
       _now = now ?? DateTime.now;

  /// Creates a session backed by [client].
  factory LogHoundSession.client({
    required LogHoundSessionConfig config,
    required LogHoundClient client,
    DateTime Function()? now,
  }) {
    return LogHoundSession(
      config: config,
      sendRecord: client.send,
      flush: client.flush,
      close: client.close,
      now: now,
    );
  }

  /// Metadata applied to every emitted record.
  final LogHoundSessionConfig config;
  final LogHoundRecordSender _sendRecord;
  final Future<void> Function() _flush;
  final void Function() _close;
  final LogHoundRedactor _redactor;
  final DateTime Function() _now;

  /// Emits a `session.start` record.
  void sessionStart({Map<String, Object?> data = const {}}) {
    send(kind: 'session', name: 'session.start', data: data);
  }

  /// Emits a plain log record.
  void log(String message, {String name = 'log', int level = 0}) {
    send(kind: 'log', name: name, message: message, level: level);
  }

  /// Emits a semantic user or app action.
  void action(
    String name, {
    Map<String, Object?> data = const {},
    String? screen,
    String? route,
    String? operationId,
  }) {
    final fields = <String, Object?>{};
    if (screen != null) {
      fields['screen'] = screen;
    }
    if (route != null) {
      fields['route'] = route;
    }
    if (operationId != null) {
      fields['operation_id'] = operationId;
    }
    send(kind: 'action', name: name, data: data, fields: fields);
  }

  /// Emits a screen-view record.
  void screen(
    String screen, {
    String? route,
    Map<String, Object?> data = const {},
  }) {
    final fields = <String, Object?>{'screen': screen};
    if (route != null) {
      fields['route'] = route;
    }
    send(kind: 'screen', name: 'screen.view', data: data, fields: fields);
  }

  /// Emits an error record with stack trace data.
  void error(
    Object error,
    StackTrace stackTrace, {
    String name = 'Error',
    String? message,
    int level = 1000,
    Map<String, Object?> data = const {},
  }) {
    send(
      kind: 'error',
      name: name,
      message: message ?? error.toString(),
      level: level,
      data: data,
      fields: {'error': error.toString(), 'stackTrace': stackTrace.toString()},
    );
  }

  /// Emits a structured HTTP request/response record.
  void http({
    required String method,
    required String url,
    String? requestId,
    int? status,
    int? durationMs,
    Object? requestBody,
    Object? responseBody,
    int maxRequestBodyBytes = 64 * 1024,
    int maxResponseBodyBytes = 256 * 1024,
    Map<String, Object?> data = const {},
  }) {
    final capturedRequestBody = _captureBody(
      requestBody,
      maxBytes: maxRequestBodyBytes,
    );
    final capturedResponseBody = _captureBody(
      responseBody,
      maxBytes: maxResponseBodyBytes,
    );
    final fields = <String, Object?>{
      'method': method,
      'url': url,
      'request_body_bytes': capturedRequestBody.bytes,
      'response_body_bytes': capturedResponseBody.bytes,
    };
    if (requestId != null) {
      fields['request_id'] = requestId;
    }
    if (status != null) {
      fields['status'] = status;
    }
    if (durationMs != null) {
      fields['duration_ms'] = durationMs;
    }
    if (capturedRequestBody.body != null) {
      fields['request_body'] = capturedRequestBody.body;
    }
    if (capturedResponseBody.body != null) {
      fields['response_body'] = capturedResponseBody.body;
    }
    if (capturedRequestBody.truncated) {
      fields['request_body_truncated'] = true;
    }
    if (capturedResponseBody.truncated) {
      fields['response_body_truncated'] = true;
    }
    send(kind: 'http', name: 'HTTP', data: data, fields: fields);
  }

  /// Emits a custom structured record.
  void send({
    required String kind,
    required String name,
    String? message,
    int? level,
    Map<String, Object?> data = const {},
    Map<String, Object?> fields = const {},
  }) {
    final record = <String, Object?>{
      'timestamp': _now().toIso8601String(),
      'app_id': config.appId,
      'flavor': config.flavor,
      'session_id': config.sessionId,
      'platform': config.platform ?? Platform.operatingSystem,
      ...config.extra,
      'kind': kind,
      'name': name,
      ...fields,
    };
    if (config.device != null) {
      record['device'] = config.device;
    }
    if (message != null) {
      record['message'] = message;
    }
    if (level != null) {
      record['level'] = level;
    }
    if (data.isNotEmpty) {
      record['data'] = loghoundJsonSafe(data);
    }
    _sendRecord(_redactor.redact(record) as Map<String, Object?>);
  }

  /// Waits for queued records to be sent.
  Future<void> flush() => _flush();

  /// Closes resources owned by this session.
  void close() => _close();
}

/// Static bootstrap and event helpers for app code.
class LogHound {
  LogHound._();

  /// Default endpoint used when `LOGHOUND_URL` is not provided.
  static const String defaultEndpoint = String.fromEnvironment(
    'LOGHOUND_URL',
    defaultValue: 'http://127.0.0.1:8765/logs',
  );

  static LogHoundSession? _current;

  /// Whether a session is currently configured.
  static bool get isConfigured => _current != null;

  /// Runs [app] inside a debug-only loghound session.
  static R? run<R>({
    required String appId,
    required String flavor,
    required R Function() app,
    Uri? endpoint,
    String? sessionId,
    bool? enabled,
    LogHoundCapture capture = const LogHoundCapture(),
    Duration timeout = const Duration(seconds: 2),
    Map<String, Object?> data = const {},
  }) {
    if (!(enabled ?? _debugModeEnabled())) {
      return app();
    }

    final client = LogHoundClient(
      endpoint ?? Uri.parse(defaultEndpoint),
      timeout: timeout,
    );
    final session = LogHoundSession.client(
      config: LogHoundSessionConfig(
        appId: appId,
        flavor: flavor,
        sessionId: sessionId ?? _newSessionId(),
      ),
      client: client,
    );
    configure(session);

    if (capture.sessionLifecycle) {
      session.sessionStart(data: data);
    }

    final specification = capture.prints
        ? ZoneSpecification(
            print: (self, parent, zone, line) {
              parent.print(zone, line);
              session.log(line, name: 'print');
            },
          )
        : null;

    return runZonedGuarded<R?>(app, (error, stackTrace) {
      if (capture.errors) {
        session.error(error, stackTrace, name: 'Zone');
      }
    }, zoneSpecification: specification);
  }

  /// Installs [session] as the current global session.
  static void configure(LogHoundSession session) {
    _current?.close();
    _current = session;
  }

  /// Clears and closes the current global session.
  static void dispose() {
    _current?.close();
    _current = null;
  }

  /// Emits a semantic user or app action on the current session.
  static void action(
    String name, {
    Map<String, Object?> data = const {},
    String? screen,
    String? route,
    String? operationId,
  }) {
    _current?.action(
      name,
      data: data,
      screen: screen,
      route: route,
      operationId: operationId,
    );
  }

  /// Emits a screen-view record on the current session.
  static void screen(
    String screen, {
    String? route,
    Map<String, Object?> data = const {},
  }) {
    _current?.screen(screen, route: route, data: data);
  }

  /// Emits an error record on the current session.
  static void error(
    Object error,
    StackTrace stackTrace, {
    String name = 'Error',
    String? message,
    int level = 1000,
    Map<String, Object?> data = const {},
  }) {
    _current?.error(
      error,
      stackTrace,
      name: name,
      message: message,
      level: level,
      data: data,
    );
  }

  /// Emits an HTTP request/response record on the current session.
  static void http({
    required String method,
    required String url,
    String? requestId,
    int? status,
    int? durationMs,
    Object? requestBody,
    Object? responseBody,
    int maxRequestBodyBytes = 64 * 1024,
    int maxResponseBodyBytes = 256 * 1024,
    Map<String, Object?> data = const {},
  }) {
    _current?.http(
      method: method,
      url: url,
      requestId: requestId,
      status: status,
      durationMs: durationMs,
      requestBody: requestBody,
      responseBody: responseBody,
      maxRequestBodyBytes: maxRequestBodyBytes,
      maxResponseBodyBytes: maxResponseBodyBytes,
      data: data,
    );
  }

  /// Waits for queued records on the current session.
  static Future<void> flush() => _current?.flush() ?? Future<void>.value();
}

_CapturedBody _captureBody(Object? body, {required int maxBytes}) {
  if (body == null) {
    return const _CapturedBody(body: null, bytes: 0, truncated: false);
  }

  final safeBody = loghoundJsonSafe(body);
  final encoded = utf8.encode(jsonEncode(safeBody));
  if (maxBytes <= 0 || encoded.length <= maxBytes) {
    return _CapturedBody(
      body: safeBody,
      bytes: encoded.length,
      truncated: false,
    );
  }

  return _CapturedBody(
    body: utf8.decode(encoded.take(maxBytes).toList(), allowMalformed: true),
    bytes: encoded.length,
    truncated: true,
  );
}

class _CapturedBody {
  const _CapturedBody({
    required this.body,
    required this.bytes,
    required this.truncated,
  });

  final Object? body;
  final int bytes;
  final bool truncated;
}

bool _debugModeEnabled() {
  var enabled = false;
  assert(() {
    enabled = true;
    return true;
  }());
  return enabled;
}

String _newSessionId() {
  final now = DateTime.now().toUtc();
  final random = Random.secure()
      .nextInt(0x1000000)
      .toRadixString(16)
      .padLeft(6, '0');
  String two(int value) => value.toString().padLeft(2, '0');
  return [
    now.year.toString().padLeft(4, '0'),
    two(now.month),
    two(now.day),
    'T',
    two(now.hour),
    two(now.minute),
    two(now.second),
    'Z',
    '-',
    Platform.operatingSystem,
    '-',
    random,
  ].join();
}
