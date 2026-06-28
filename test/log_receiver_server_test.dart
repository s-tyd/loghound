import 'dart:convert';
import 'dart:io';

import 'package:loghound/loghound.dart';
import 'package:test/test.dart';

void main() {
  group('LogHoundReceiverServer', () {
    late Directory directory;
    late JsonlLogStore store;
    late LogHoundReceiverServer server;
    late HttpClient client;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('loghound-receiver-');
      store = JsonlLogStore(File('${directory.path}/app.jsonl'));
      server = await LogHoundReceiverServer.start(port: 0, store: store);
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await server.close();
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });

    test('responds to health checks', () async {
      expect(server.uri.host, InternetAddress.loopbackIPv4.address);

      final response = await client
          .getUrl(server.uri.resolve('/health'))
          .then((request) => request.close());

      expect(response.statusCode, HttpStatus.ok);
      expect(await utf8.decoder.bind(response).join(), 'ok');
    });

    test('stores redacted JSON logs posted to /logs', () async {
      final request = await client.postUrl(server.uri.resolve('/logs'));
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'name': 'HTTP',
          'message': 'Headers: {Authorization: Bearer abc}',
          'headers': {'x-staging-auth': 'secret'},
        }),
      );

      final response = await request.close();
      await response.drain<void>();

      expect(response.statusCode, HttpStatus.noContent);
      expect(await store.readAll(), [
        {
          'name': 'HTTP',
          'message': 'Headers: {Authorization: ***}',
          'headers': {'x-staging-auth': '***'},
        },
      ]);
    });

    test('can route posted records through a custom record writer', () async {
      await server.close();
      final routedStore = LogHoundDirectoryStore(directory);
      server = await LogHoundReceiverServer.start(
        port: 0,
        store: store,
        onRecord: routedStore.append,
      );

      final request = await client.postUrl(server.uri.resolve('/logs'));
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'app_id': 'guide-app',
          'flavor': 'staging',
          'session_id': 'session-1',
          'platform': 'ios',
          'kind': 'action',
          'name': 'search.submit',
        }),
      );

      final response = await request.close();
      await response.drain<void>();

      expect(response.statusCode, HttpStatus.noContent);
      final records = await JsonlLogStore(
        File('${directory.path}/staging/ios/sessions/session-1.jsonl'),
      ).readAll();
      expect(records.single, containsPair('name', 'search.submit'));
    });

    test('rejects invalid JSON bodies', () async {
      final request = await client.postUrl(server.uri.resolve('/logs'));
      request.headers.contentType = ContentType.json;
      request.write('{not-json');

      final response = await request.close();
      await response.drain<void>();

      expect(response.statusCode, HttpStatus.badRequest);
      expect(await store.readAll(), isEmpty);
    });

    test('rejects bodies larger than the configured limit', () async {
      await server.close();
      server = await LogHoundReceiverServer.start(
        port: 0,
        store: store,
        maxBodyBytes: 8,
      );

      final request = await client.postUrl(server.uri.resolve('/logs'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'message': 'too large'}));

      final response = await request.close();
      await response.drain<void>();

      expect(response.statusCode, HttpStatus.requestEntityTooLarge);
      expect(await store.readAll(), isEmpty);
    });
  });
}
