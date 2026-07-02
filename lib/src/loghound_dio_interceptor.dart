import 'package:dio/dio.dart';

import 'json_safe.dart';
import 'loghound_session.dart';

/// Dio interceptor that emits completed requests as structured LogHound HTTP
/// records.
class LogHoundDioInterceptor extends Interceptor {
  /// Creates a LogHound interceptor for Dio.
  LogHoundDioInterceptor({
    this.captureRequestBody = const bool.fromEnvironment(
      captureRequestBodyEnvironmentKey,
    ),
    this.captureResponseBody = const bool.fromEnvironment(
      captureResponseBodyEnvironmentKey,
    ),
    this.captureHeaders = true,
    this.maxRequestBodyBytes = 64 * 1024,
    this.maxResponseBodyBytes = 256 * 1024,
    this.requestIdBuilder,
  });

  /// Dart define key that enables request body capture by default.
  static const captureRequestBodyEnvironmentKey =
      'LOGHOUND_CAPTURE_HTTP_REQUEST_BODY';

  /// Dart define key that enables response body capture by default.
  static const captureResponseBodyEnvironmentKey =
      'LOGHOUND_CAPTURE_HTTP_RESPONSE_BODY';

  /// Key used in [RequestOptions.extra] for the LogHound request id.
  static const requestIdExtraKey = 'loghound_request_id';

  static const _requestStartMicrosExtraKey = 'loghound_request_start_micros';

  /// Whether request bodies should be captured.
  final bool captureRequestBody;

  /// Whether response bodies should be captured.
  final bool captureResponseBody;

  /// Whether request and response headers should be captured.
  final bool captureHeaders;

  /// Maximum captured request body bytes.
  final int maxRequestBodyBytes;

  /// Maximum captured response body bytes.
  final int maxResponseBodyBytes;

  /// Optional request id factory.
  final String Function(RequestOptions options)? requestIdBuilder;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _ensureRequestMetadata(options);
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _writeHttpRecord(response.requestOptions, response: response);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _writeHttpRecord(err.requestOptions, response: err.response, error: err);
    handler.next(err);
  }

  void _writeHttpRecord(
    RequestOptions options, {
    Response<dynamic>? response,
    DioException? error,
  }) {
    _ensureRequestMetadata(options);
    final fields = <String, Object?>{
      'path': _path(options),
      if (captureHeaders && options.headers.isNotEmpty)
        'request_headers': _jsonSafeMap(options.headers),
      if (captureHeaders && response != null && response.headers.map.isNotEmpty)
        'response_headers': _jsonSafeMap(response.headers.map),
      if (error != null) 'error_type': error.type.name,
      if (error?.message != null) 'error_message': error!.message,
    };

    LogHound.http(
      method: options.method,
      url: options.uri.toString(),
      requestId: _requestId(options),
      status: response?.statusCode,
      durationMs: _durationMs(options),
      requestBody: captureRequestBody ? options.data : null,
      responseBody: captureResponseBody ? response?.data : null,
      maxRequestBodyBytes: maxRequestBodyBytes,
      maxResponseBodyBytes: maxResponseBodyBytes,
      level: error == null ? null : 900,
      fields: fields,
    );
  }

  void _ensureRequestMetadata(RequestOptions options) {
    _requestId(options);
    options.extra[_requestStartMicrosExtraKey] ??=
        DateTime.now().microsecondsSinceEpoch;
  }

  String _requestId(RequestOptions options) {
    final existing = options.extra[requestIdExtraKey];
    if (existing is String && existing.isNotEmpty) {
      return existing;
    }

    final requestId =
        requestIdBuilder?.call(options) ??
        [
          'dio',
          DateTime.now().microsecondsSinceEpoch,
          identityHashCode(options),
        ].join('-');
    options.extra[requestIdExtraKey] = requestId;
    return requestId;
  }

  int? _durationMs(RequestOptions options) {
    final startMicros = options.extra[_requestStartMicrosExtraKey];
    if (startMicros is! int) {
      return null;
    }
    final elapsedMicros = DateTime.now().microsecondsSinceEpoch - startMicros;
    return (elapsedMicros / 1000).round();
  }

  String _path(RequestOptions options) {
    final uriPath = options.uri.path;
    if (uriPath.isNotEmpty) {
      return uriPath;
    }
    return options.path;
  }

  Map<String, Object?> _jsonSafeMap(Map<String, dynamic> values) {
    return values.map<String, Object?>(
      (key, value) => MapEntry(key, loghoundJsonSafe(value)),
    );
  }
}
