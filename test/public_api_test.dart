import 'package:loghound/loghound.dart';
import 'package:test/test.dart';

void main() {
  test('public API uses LogHound word casing', () {
    expect(LogHound.defaultVmServiceEventKind, logHoundVmServiceEventKind);

    final client = LogHoundClient(postEvent: (_, _) {});
    client.close();
    expect(logHoundVmServiceEventKind, 'loghound.log');
    expect(
      logHoundDecodeVmServiceEvent(
        const LogHoundVmServiceEvent(
          kind: logHoundVmServiceEventKind,
          data: {'ok': true},
        ),
      ),
      {'ok': true},
    );

    final redactor = LogHoundRedactor();
    expect(redactor.redact({'token': 'secret'}), {'token': '***'});

    const query = LogHoundQuery();
    expect(query.filter(const []), isEmpty);
  });
}
