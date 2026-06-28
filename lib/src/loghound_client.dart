import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'json_safe.dart';

/// Fire-and-forget HTTP client for sending records to a loghound receiver.
class LogHoundClient {
  /// Creates a client that posts JSON records to [endpoint].
  LogHoundClient(
    this.endpoint, {
    this.timeout = const Duration(seconds: 2),
    HttpClient? httpClient,
  }) : _httpClient = httpClient ?? HttpClient(),
       _closeClientOnClose = httpClient == null;

  /// The receiver endpoint, usually `http://127.0.0.1:8765/logs`.
  final Uri endpoint;

  /// Timeout used for each connection, write, and response drain.
  final Duration timeout;
  final HttpClient _httpClient;
  final bool _closeClientOnClose;
  Future<void> _pendingWrite = Future<void>.value();

  /// Queues [record] for delivery and swallows transport failures.
  void send(Map<String, Object?> record) {
    final encoded = jsonEncode(loghoundJsonSafe(record));
    _pendingWrite = _pendingWrite
        .then((_) async {
          final request = await _httpClient.postUrl(endpoint).timeout(timeout);
          request.headers.contentType = ContentType.json;
          request.write(encoded);
          final response = await request.close().timeout(timeout);
          await response.drain<void>().timeout(timeout);
        })
        .catchError((Object _) {});
  }

  /// Waits for all queued sends to finish.
  Future<void> flush() => _pendingWrite;

  /// Closes the owned HTTP client.
  void close() {
    if (_closeClientOnClose) {
      _httpClient.close(force: true);
    }
  }
}
