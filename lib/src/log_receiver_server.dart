import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'jsonl_log_store.dart';
import 'redactor.dart';

/// Writes a redacted receiver record to storage.
typedef LogHoundRecordWriter =
    Future<void> Function(Map<String, Object?> record);

/// Local HTTP receiver that accepts JSON log records at `POST /logs`.
class LogHoundReceiverServer {
  LogHoundReceiverServer._(
    this._server,
    this.store,
    this._onRecord,
    this.redactor,
    this.maxBodyBytes,
  );

  final HttpServer _server;

  /// The single-file store passed to [start].
  final JsonlLogStore store;
  final LogHoundRecordWriter _onRecord;

  /// Redactor applied before records are written.
  final LogHoundRedactor redactor;

  /// Maximum accepted request body size in bytes.
  final int maxBodyBytes;

  /// Bound HTTP URI for this receiver.
  Uri get uri =>
      Uri(scheme: 'http', host: _server.address.address, port: _server.port);

  /// Starts a receiver bound to [address] and [port].
  static Future<LogHoundReceiverServer> start({
    InternetAddress? address,
    int port = 8765,
    required JsonlLogStore store,
    LogHoundRecordWriter? onRecord,
    LogHoundRedactor? redactor,
    int maxBodyBytes = 1024 * 1024,
  }) async {
    final server = await HttpServer.bind(
      address ?? InternetAddress.loopbackIPv4,
      port,
    );
    final receiver = LogHoundReceiverServer._(
      server,
      store,
      onRecord ?? store.append,
      redactor ?? LogHoundRedactor(),
      maxBodyBytes,
    );
    server.listen(receiver._handleRequest);
    return receiver;
  }

  /// Closes the underlying HTTP server.
  Future<void> close({bool force = true}) => _server.close(force: force);

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.uri.path == '/health' && request.method == 'GET') {
      request.response
        ..statusCode = HttpStatus.ok
        ..write('ok');
      await request.response.close();
      return;
    }

    if (request.uri.path != '/logs') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    if (request.method != 'POST') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }

    try {
      final body = await _readBody(request);
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }

      final redacted = redactor.redact(decoded) as Map<String, Object?>;
      await _onRecord(redacted);
      request.response.statusCode = HttpStatus.noContent;
    } on _RequestBodyTooLarge {
      request.response.statusCode = HttpStatus.requestEntityTooLarge;
    } on FormatException {
      request.response.statusCode = HttpStatus.badRequest;
    }

    await request.response.close();
  }

  Future<String> _readBody(HttpRequest request) async {
    final body = BytesBuilder(copy: false);
    var size = 0;

    await for (final chunk in request) {
      size += chunk.length;
      if (size > maxBodyBytes) {
        throw const _RequestBodyTooLarge();
      }
      body.add(chunk);
    }

    return utf8.decode(body.takeBytes());
  }
}

class _RequestBodyTooLarge implements Exception {
  const _RequestBodyTooLarge();
}
