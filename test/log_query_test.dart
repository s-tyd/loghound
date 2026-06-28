import 'package:loghound/loghound.dart';
import 'package:test/test.dart';

void main() {
  group('LogHoundQuery', () {
    final records = [
      {
        'timestamp': '2026-06-27T10:00:00.000',
        'name': 'HTTP',
        'level': 0,
        'message': 'GET /spots',
      },
      {
        'timestamp': '2026-06-27T10:01:00.000',
        'name': 'Purchase',
        'level': 900,
        'message': 'purchase.guidebook.failed',
        'trace_id': 'trace-1',
        'data': {'productId': 'natural-wine', 'request_id': 'request-1'},
      },
      {
        'timestamp': '2026-06-27T10:02:00.000',
        'name': 'Purchase',
        'level': 1000,
        'message': 'purchase.guidebook.succeeded',
        'attributes': {'session_id': 'session-2', 'user_id': 'user-2'},
      },
    ];

    test('filters records by text contained anywhere in the record', () {
      final query = LogHoundQuery(contains: 'natural-wine');

      expect(query.filter(records), [records[1]]);
    });

    test('filters records by logger name and minimum level', () {
      final query = LogHoundQuery(name: 'Purchase', minimumLevel: 1000);

      expect(query.filter(records), [records[2]]);
    });

    test('filters records at or after since timestamp', () {
      final query = LogHoundQuery(since: DateTime.parse('2026-06-27T10:01:00'));

      expect(query.filter(records), [records[1], records[2]]);
    });

    test('treats OpenTelemetry severities as log levels', () {
      const query = LogHoundQuery(minimumLevel: 900);

      expect(
        query.filter([
          {'severity_number': 12, 'body': 'info'},
          {'severity_number': 13, 'body': 'warning'},
          {'severity_text': 'ERROR', 'body': 'error'},
        ]),
        [
          {'severity_number': 13, 'body': 'warning'},
          {'severity_text': 'ERROR', 'body': 'error'},
        ],
      );
    });

    test('filters records by related identifiers', () {
      expect(LogHoundQuery(traceId: 'trace-1').filter(records), [records[1]]);
      expect(LogHoundQuery(requestId: 'request-1').filter(records), [
        records[1],
      ]);
      expect(LogHoundQuery(sessionId: 'session-2').filter(records), [
        records[2],
      ]);
      expect(LogHoundQuery(userId: 'user-2').filter(records), [records[2]]);
    });
  });
}
