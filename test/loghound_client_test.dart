import 'dart:convert';
import 'dart:io';

import 'package:loghound/loghound.dart';
import 'package:test/test.dart';

void main() {
  group('LogHoundClient', () {
    test('posts JSON records to the configured endpoint', () async {
      final received = <Map<String, Object?>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        received.add(jsonDecode(body) as Map<String, Object?>);
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final client = LogHoundClient(
        Uri.parse('http://${server.address.address}:${server.port}/logs'),
      );
      addTearDown(client.close);

      client.send({'name': 'HTTP', 'message': 'request'});
      await client.flush();

      expect(received, [
        {'name': 'HTTP', 'message': 'request'},
      ]);
    });

    test('swallows transport failures', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final endpoint = Uri.parse(
        'http://${server.address.address}:${server.port}/logs',
      );
      await server.close(force: true);

      final client = LogHoundClient(
        endpoint,
        timeout: const Duration(milliseconds: 100),
      );
      addTearDown(client.close);

      client.send({'message': 'will be ignored'});

      await expectLater(client.flush(), completes);
    });
  });
}
