import 'dart:async';
import 'dart:developer' as developer;

import 'json_safe.dart';
import 'loghound_vm_service.dart';

/// Fire-and-forget client for emitting structured records as VM Service events.
class LogHoundClient {
  /// Creates a client that posts records to [postEvent].
  LogHoundClient({
    LogHoundVmServiceEventSink? postEvent,
    this.eventKind = logHoundVmServiceEventKind,
  }) : _postEvent = postEvent ?? developer.postEvent;

  /// VM Service extension event kind used by this client.
  final String eventKind;

  final LogHoundVmServiceEventSink _postEvent;

  /// Emits [record] as a VM Service extension event and swallows sink failures.
  void send(Map<String, Object?> record) {
    final safeRecord = loghoundJsonSafe(record);
    if (safeRecord is! Map) {
      return;
    }
    final eventData = safeRecord.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );
    try {
      _postEvent(eventKind, eventData);
    } on Object {
      // Development logging must not break the app.
    }
  }

  /// Kept for API symmetry with async transports.
  Future<void> flush() => Future<void>.value();

  /// Kept for API symmetry with owned-resource transports.
  void close() {}
}
