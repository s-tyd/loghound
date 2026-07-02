import 'package:loghound/loghound.dart';
import 'package:test/test.dart';

void main() {
  group('LogHoundClient', () {
    test('posts records as VM service extension events', () async {
      final events = <LogHoundVmServiceEvent>[];
      final client = LogHoundClient(
        postEvent: (kind, data) {
          events.add(LogHoundVmServiceEvent(kind: kind, data: data));
        },
      );

      client.send({'name': 'HTTP', 'message': 'request'});
      await client.flush();

      expect(events, hasLength(1));
      expect(events.single.kind, logHoundVmServiceEventKind);
      expect(logHoundDecodeVmServiceEvent(events.single), {
        'name': 'HTTP',
        'message': 'request',
      });
    });

    test('swallows event sink failures', () async {
      final client = LogHoundClient(
        postEvent: (_, _) => throw StateError('VM service unavailable'),
      );

      client.send({'message': 'will be ignored'});

      await expectLater(client.flush(), completes);
    });
  });
}
