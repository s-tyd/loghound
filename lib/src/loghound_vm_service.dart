import 'json_safe.dart';

/// Extension event kind used for hidden loghound log transport.
const logHoundVmServiceEventKind = 'loghound.log';

/// Posts one VM Service extension event.
typedef LogHoundVmServiceEventSink =
    void Function(String eventKind, Map<String, Object?> eventData);

/// One extension event received from a Dart VM Service stream.
class LogHoundVmServiceEvent {
  /// Creates a VM Service extension event wrapper.
  const LogHoundVmServiceEvent({required this.kind, required this.data});

  /// The VM Service extension event kind.
  final String? kind;

  /// The VM Service extension event payload.
  final Object? data;
}

/// Converts a Flutter VM Service HTTP URI into the websocket URI used by
/// `package:vm_service`.
Uri logHoundVmServiceWebSocketUri(String serviceUri) {
  final parsed = Uri.parse(serviceUri.trim());
  final scheme = switch (parsed.scheme) {
    'http' => 'ws',
    'https' => 'wss',
    _ => parsed.scheme,
  };
  if (parsed.pathSegments.isNotEmpty && parsed.pathSegments.last == 'ws') {
    return parsed.replace(scheme: scheme);
  }

  final basePath = parsed.path.endsWith('/') ? parsed.path : '${parsed.path}/';
  return parsed.replace(scheme: scheme, path: '${basePath}ws');
}

/// Decodes a loghound VM Service extension event into a log record.
Map<String, Object?>? logHoundDecodeVmServiceEvent(
  LogHoundVmServiceEvent event, {
  String eventKind = logHoundVmServiceEventKind,
}) {
  if (event.kind != eventKind || event.data is! Map) {
    return null;
  }

  final safe = loghoundJsonSafe(event.data);
  if (safe is! Map) {
    return null;
  }

  return safe.map<String, Object?>(
    (key, value) => MapEntry(key.toString(), value),
  );
}
