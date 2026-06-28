import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:loghound/loghound.dart';
import 'package:test/test.dart';

void main() {
  group('LogHound.run', () {
    late HttpServer server;
    late List<Map<String, Object?>> received;
    late Uri endpoint;

    setUp(() async {
      received = [];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      endpoint = Uri.parse(
        'http://${server.address.address}:${server.port}/logs',
      );
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        received.add(jsonDecode(body) as Map<String, Object?>);
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
      });
    });

    tearDown(() async {
      LogHound.dispose();
      await server.close(force: true);
    });

    test('starts a session captures print and sends actions', () async {
      LogHound.run(
        appId: 'guide-app',
        flavor: 'staging',
        sessionId: 'session-1',
        endpoint: endpoint,
        enabled: true,
        app: () {
          print('hello from app');
          LogHound.action('search.submit', data: {'query': 'ramen'});
        },
      );

      await LogHound.flush();

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
        endpoint: endpoint,
        enabled: true,
        app: () {
          scheduleMicrotask(() => throw StateError('boom'));
        },
      );

      await Future<void>.delayed(Duration.zero);
      await LogHound.flush();

      expect(received.where((record) => record['kind'] == 'error'), isNotEmpty);
      final error = received.last;
      expect(error, containsPair('name', 'Zone'));
      expect(error['error'], contains('boom'));
    });

    test('disabled mode runs the app without configuring LogHound', () async {
      var ran = false;

      LogHound.run(
        appId: 'guide-app',
        flavor: 'staging',
        endpoint: endpoint,
        enabled: false,
        app: () {
          ran = true;
          LogHound.action('search.submit');
        },
      );

      await LogHound.flush();

      expect(ran, isTrue);
      expect(received, isEmpty);
    });

    test(
      'endpoint is optional and transport failures do not break app',
      () async {
        await server.close(force: true);
        var ran = false;

        LogHound.run(
          appId: 'guide-app',
          flavor: 'staging',
          sessionId: 'session-1',
          enabled: true,
          timeout: const Duration(milliseconds: 50),
          app: () {
            ran = true;
            LogHound.action('search.submit');
          },
        );

        await expectLater(LogHound.flush(), completes);
        expect(ran, isTrue);
      },
    );
  });
}
