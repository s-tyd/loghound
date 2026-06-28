import 'package:loghound/loghound.dart';
import 'package:test/test.dart';

void main() {
  test('public API uses LogHound word casing', () {
    expect(LogHound.defaultEndpoint, 'http://127.0.0.1:8765/logs');

    final client = LogHoundClient(Uri.parse('http://127.0.0.1:8765/logs'));
    client.close();

    final redactor = LogHoundRedactor();
    expect(redactor.redact({'token': 'secret'}), {'token': '***'});

    const query = LogHoundQuery();
    expect(query.filter(const []), isEmpty);

    void acceptsReceiver(LogHoundReceiverServer? server) {}

    acceptsReceiver(null);
  });
}
