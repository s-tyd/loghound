import 'dart:async';

import 'package:loghound/loghound.dart';
import 'package:test/test.dart';

void main() {
  group('LogHound.run', () {
    late List<LogHoundVmServiceEvent> events;

    setUp(() {
      events = [];
    });

    tearDown(LogHound.dispose);

    List<Map<String, Object?>> records() {
      return [
        for (final event in events)
          logHoundDecodeVmServiceEvent(event) ??
              fail('invalid loghound event: ${event.kind} ${event.data}'),
      ];
    }

    void captureEvent(String kind, Map<String, Object?> data) {
      events.add(LogHoundVmServiceEvent(kind: kind, data: data));
    }

    test('starts a session captures print and sends actions', () async {
      LogHound.run(
        appId: 'guide-app',
        flavor: 'staging',
        sessionId: 'session-1',
        enabled: true,
        postEvent: captureEvent,
        app: () {
          print('hello from app');
          LogHound.action('search.submit', data: {'query': 'ramen'});
        },
      );

      await LogHound.flush();

      final received = records();
      expect(received.map((record) => record['kind']), [
        'session',
        'log',
        'action',
      ]);
      expect(received.first, containsPair('name', 'session.start'));
      expect(received.first, containsPair('app_id', 'guide-app'));
      expect(received.first, containsPair('flavor', 'staging'));
      expect(received.first, containsPair('session_id', 'session-1'));
      expect(received[1], containsPair('name', 'print'));
      expect(received[1], containsPair('message', 'hello from app'));
      expect(received[2], containsPair('name', 'search.submit'));
    });

    test('captures uncaught zone errors', () async {
      LogHound.run(
        appId: 'guide-app',
        flavor: 'staging',
        sessionId: 'session-1',
        enabled: true,
        postEvent: captureEvent,
        app: () {
          scheduleMicrotask(() => throw StateError('boom'));
        },
      );

      await Future<void>.delayed(Duration.zero);
      await LogHound.flush();

      final received = records();
      expect(received.where((record) => record['kind'] == 'error'), isNotEmpty);
      final error = received.last;
      expect(error, containsPair('name', 'Zone'));
      expect(error['error'], contains('boom'));
    });

    test('zone print handler uses the current configured session', () async {
      final reconfiguredRecords = <Map<String, Object?>>[];

      LogHound.run(
        appId: 'guide-app',
        flavor: 'staging',
        sessionId: 'session-1',
        enabled: true,
        postEvent: captureEvent,
        app: () {
          scheduleMicrotask(() {
            LogHound.configure(
              LogHoundSession(
                config: const LogHoundSessionConfig(
                  appId: 'guide-app',
                  flavor: 'staging',
                  sessionId: 'session-2',
                ),
                sendRecord: reconfiguredRecords.add,
              ),
            );
            print('after reconfigure');
          });
        },
      );

      await Future<void>.delayed(Duration.zero);
      await LogHound.flush();

      expect(
        records().where((record) => record['message'] == 'after reconfigure'),
        isEmpty,
      );
      expect(
        reconfiguredRecords.single,
        containsPair('session_id', 'session-2'),
      );
      expect(
        reconfiguredRecords.single,
        containsPair('message', 'after reconfigure'),
      );
    });

    test('disabled mode runs the app without configuring LogHound', () async {
      var ran = false;

      LogHound.run(
        appId: 'guide-app',
        flavor: 'staging',
        enabled: false,
        postEvent: captureEvent,
        app: () {
          ran = true;
          LogHound.action('search.submit');
        },
      );

      await LogHound.flush();

      expect(ran, isTrue);
      expect(events, isEmpty);
    });

    test('event sink failures do not break app', () async {
      var ran = false;

      LogHound.run(
        appId: 'guide-app',
        flavor: 'staging',
        sessionId: 'session-1',
        enabled: true,
        postEvent: (_, _) => throw StateError('VM service unavailable'),
        app: () {
          ran = true;
          LogHound.action('search.submit');
        },
      );

      await expectLater(LogHound.flush(), completes);
      expect(ran, isTrue);
    });
  });
}
