import 'package:loghound/loghound.dart';
import 'package:test/test.dart';

void main() {
  group('LogHoundSession', () {
    late List<Map<String, Object?>> sent;
    late LogHoundSession session;

    setUp(() {
      sent = [];
      session = LogHoundSession(
        config: const LogHoundSessionConfig(
          appId: 'guide-app',
          flavor: 'staging',
          sessionId: 'session-1',
        ),
        sendRecord: sent.add,
      );
      LogHound.configure(session);
    });

    tearDown(() {
      LogHound.dispose();
    });

    test(
      'stamps semantic action records with app flavor and session',
      () async {
        LogHound.action(
          'search.submit',
          data: {
            'query': 'ramen',
            'selectedFilters': ['open_now'],
          },
          screen: 'SpotSearch',
          route: '/spots/search',
          operationId: 'op-1',
        );

        await LogHound.flush();

        expect(sent, hasLength(1));
        expect(sent.single, {
          'app_id': 'guide-app',
          'flavor': 'staging',
          'session_id': 'session-1',
          'platform': sent.single['platform'],
          'timestamp': sent.single['timestamp'],
          'kind': 'action',
          'name': 'search.submit',
          'screen': 'SpotSearch',
          'route': '/spots/search',
          'operation_id': 'op-1',
          'data': {
            'query': 'ramen',
            'selectedFilters': ['open_now'],
          },
        });
      },
    );

    test('sends screen error and http records', () async {
      LogHound.screen('SpotDetail', route: '/spots/spot-1');
      LogHound.error(
        StateError('empty title'),
        StackTrace.fromString('stack line'),
        message: 'render failed',
      );
      LogHound.http(
        method: 'GET',
        url: '/spots',
        status: 200,
        requestId: 'req-1',
        responseBody: {
          'items': [
            {'title': ''},
          ],
        },
      );

      await LogHound.flush();

      expect(sent.map((record) => record['kind']), ['screen', 'error', 'http']);
      expect(sent[0], containsPair('screen', 'SpotDetail'));
      expect(sent[1], containsPair('level', 1000));
      expect(sent[1]['error'], contains('empty title'));
      expect(sent[2], containsPair('request_id', 'req-1'));
      expect(sent[2], containsPair('response_body_bytes', 24));
    });

    test('redacts sensitive values before sending records', () async {
      LogHound.action(
        'auth.submit',
        data: {
          'email': 'person@example.com',
          'password': 'secret-password',
          'headers': {'authorization': 'Bearer token-value'},
        },
      );

      await LogHound.flush();

      expect(sent.single['data'], {
        'email': '***',
        'password': '***',
        'headers': {'authorization': '***'},
      });
    });

    test(
      'truncates large HTTP bodies and keeps original byte counts',
      () async {
        LogHound.http(
          method: 'POST',
          url: '/search',
          requestId: 'req-large',
          requestBody: {'query': 'ramen'},
          responseBody: {
            'items': [
              {'title': 'abcdefghijklmnopqrstuvwxyz'},
            ],
          },
          maxRequestBodyBytes: 1024,
          maxResponseBodyBytes: 20,
        );

        await LogHound.flush();

        final record = sent.single;
        expect(record, containsPair('response_body_truncated', true));
        expect(record['response_body_bytes'], greaterThan(20));
        expect(record['response_body'], isA<String>());
        expect(
          record['response_body'].toString().length,
          lessThanOrEqualTo(20),
        );
        expect(record, isNot(contains('request_body_truncated')));
        expect(record['request_body'], {'query': 'ramen'});
      },
    );

    test('does nothing when no session is configured', () async {
      LogHound.dispose();

      LogHound.action('search.submit');

      await expectLater(LogHound.flush(), completes);
      expect(sent, isEmpty);
    });
  });
}
