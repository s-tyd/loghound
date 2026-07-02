import 'package:loghound/loghound.dart';
import 'package:test/test.dart';

void main() {
  group('VM service log events', () {
    test('converts Flutter service URIs to websocket URIs', () {
      expect(
        logHoundVmServiceWebSocketUri(
          'http://127.0.0.1:54321/abc=/',
        ).toString(),
        'ws://127.0.0.1:54321/abc=/ws',
      );
      expect(
        logHoundVmServiceWebSocketUri(
          'ws://127.0.0.1:54321/abc=/ws',
        ).toString(),
        'ws://127.0.0.1:54321/abc=/ws',
      );
    });

    test('decodes only loghound extension events with map payloads', () {
      expect(
        logHoundDecodeVmServiceEvent(
          const LogHoundVmServiceEvent(
            kind: logHoundVmServiceEventKind,
            data: {'message': 'purchase failed'},
          ),
        ),
        {'message': 'purchase failed'},
      );
      expect(
        logHoundDecodeVmServiceEvent(
          const LogHoundVmServiceEvent(kind: 'flutter.frame', data: {}),
        ),
        isNull,
      );
      expect(
        logHoundDecodeVmServiceEvent(
          const LogHoundVmServiceEvent(
            kind: logHoundVmServiceEventKind,
            data: 'not-json',
          ),
        ),
        isNull,
      );
    });
  });
}
