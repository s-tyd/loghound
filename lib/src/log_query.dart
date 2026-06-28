import 'dart:convert';

import 'json_safe.dart';

/// Filters JSONL log records by common log metadata and text content.
class LogHoundQuery {
  /// Creates a query with optional filters.
  const LogHoundQuery({
    this.contains,
    this.name,
    this.minimumLevel,
    this.since,
    this.traceId,
    this.requestId,
    this.sessionId,
    this.userId,
  });

  /// Case-insensitive text that must appear in the encoded record.
  final String? contains;

  /// Exact `name` field to match.
  final String? name;

  /// Minimum numeric level to include.
  final int? minimumLevel;

  /// Earliest timestamp to include.
  final DateTime? since;

  /// Trace identifier to match from top-level, `data`, or `attributes`.
  final String? traceId;

  /// Request identifier to match from top-level, `data`, or `attributes`.
  final String? requestId;

  /// Session identifier to match from top-level, `data`, or `attributes`.
  final String? sessionId;

  /// User identifier to match from top-level, `data`, or `attributes`.
  final String? userId;

  /// Returns records that match this query.
  List<Map<String, Object?>> filter(Iterable<Map<String, Object?>> records) {
    return records.where(matches).toList(growable: false);
  }

  /// Returns whether [record] matches this query.
  bool matches(Map<String, Object?> record) {
    if (name != null && record['name'] != name) {
      return false;
    }

    if (!_matchesIdentifier(record, const ['trace_id', 'traceId'], traceId)) {
      return false;
    }

    if (!_matchesIdentifier(record, const [
      'request_id',
      'requestId',
    ], requestId)) {
      return false;
    }

    if (!_matchesIdentifier(record, const [
      'session_id',
      'sessionId',
    ], sessionId)) {
      return false;
    }

    if (!_matchesIdentifier(record, const ['user_id', 'userId'], userId)) {
      return false;
    }

    final minimumLevel = this.minimumLevel;
    if (minimumLevel != null && _recordLevel(record) < minimumLevel) {
      return false;
    }

    final since = this.since;
    if (since != null) {
      final timestamp = _recordTimestamp(record);
      if (timestamp == null || timestamp.isBefore(since)) {
        return false;
      }
    }

    final contains = this.contains;
    if (contains != null && contains.isNotEmpty) {
      final encoded = jsonEncode(loghoundJsonSafe(record)).toLowerCase();
      if (!encoded.contains(contains.toLowerCase())) {
        return false;
      }
    }

    return true;
  }

  bool _matchesIdentifier(
    Map<String, Object?> record,
    List<String> keys,
    String? expected,
  ) {
    if (expected == null || expected.isEmpty) {
      return true;
    }

    final value =
        _lookup(record, keys) ??
        _lookup(record['data'], keys) ??
        _lookup(record['attributes'], keys);
    return value?.toString() == expected;
  }

  Object? _lookup(Object? source, List<String> keys) {
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

  int _recordLevel(Map<String, Object?> record) {
    final level = record['level'];
    if (level is int) {
      return level;
    }
    if (level is num) {
      return level.toInt();
    }

    final severityNumber = record['severity_number'];
    if (severityNumber is num) {
      return _levelFromOpenTelemetrySeverityNumber(severityNumber.toInt());
    }

    final severityText = record['severity_text'];
    if (severityText is String) {
      return _levelFromSeverityText(severityText);
    }

    return 0;
  }

  int _levelFromOpenTelemetrySeverityNumber(int severityNumber) {
    if (severityNumber >= 17) {
      return 1000;
    }
    if (severityNumber >= 13) {
      return 900;
    }
    if (severityNumber >= 9) {
      return 800;
    }
    return 0;
  }

  int _levelFromSeverityText(String severityText) {
    final normalized = severityText.trim().toUpperCase();
    if (normalized.startsWith('FATAL') || normalized.startsWith('ERROR')) {
      return 1000;
    }
    if (normalized.startsWith('WARN')) {
      return 900;
    }
    if (normalized.startsWith('INFO')) {
      return 800;
    }
    return 0;
  }

  DateTime? _recordTimestamp(Map<String, Object?> record) {
    final value = record['timestamp'] ?? record['time'];
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}
