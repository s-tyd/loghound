import 'dart:convert';
import 'dart:io';

import 'package:loghound/loghound.dart';
import 'package:test/test.dart';

void main() {
  group('LogHoundDirectoryStore', () {
    late Directory directory;
    late Directory root;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('loghound-routed-');
      root = Directory('${directory.path}/logs');
    });

    tearDown(() async {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });

    test(
      'routes records by flavor, platform, and session under the app root',
      () async {
        final store = LogHoundDirectoryStore(root);

        await store.append({
          'timestamp': '2026-06-27T10:00:00.000',
          'app_id': 'guide-app',
          'flavor': 'staging',
          'session_id': 'session-1',
          'platform': 'ios',
          'kind': 'action',
          'name': 'search.submit',
        });

        final sessionFile = File(
          '${root.path}/staging/ios/sessions/session-1.jsonl',
        );
        final latestFile = File('${root.path}/staging/ios/latest.jsonl');
        final catalogFile = File('${root.path}/catalog.jsonl');

        expect(await sessionFile.exists(), isTrue);
        expect(await latestFile.exists(), isTrue);
        expect(await catalogFile.exists(), isTrue);

        final sessionRecord =
            jsonDecode(await sessionFile.readAsString())
                as Map<String, Object?>;
        expect(sessionRecord, containsPair('name', 'search.submit'));

        final catalogRecord =
            jsonDecode(await catalogFile.readAsString())
                as Map<String, Object?>;
        expect(catalogRecord, containsPair('kind', 'session'));
        expect(catalogRecord, containsPair('app_id', 'guide-app'));
        expect(catalogRecord, containsPair('flavor', 'staging'));
        expect(catalogRecord, containsPair('session_id', 'session-1'));
        expect(catalogRecord, containsPair('platform', 'ios'));
        expect(
          catalogRecord,
          containsPair('file', 'staging/ios/sessions/session-1.jsonl'),
        );
      },
    );

    test('keeps ios and android records in separate files', () async {
      final store = LogHoundDirectoryStore(root);

      await store.append({
        'timestamp': '2026-06-27T10:00:00.000',
        'app_id': 'guide-app',
        'session_id': 'session-1',
        'platform': 'ios',
        'kind': 'log',
        'message': 'ios log',
      });
      await store.append({
        'timestamp': '2026-06-27T10:00:01.000',
        'app_id': 'guide-app',
        'session_id': 'session-1',
        'platform': 'android',
        'kind': 'log',
        'message': 'android log',
      });

      final iosRecords = await JsonlLogStore(
        File('${root.path}/default/ios/sessions/session-1.jsonl'),
      ).readAll();
      final androidRecords = await JsonlLogStore(
        File('${root.path}/default/android/sessions/session-1.jsonl'),
      ).readAll();

      expect(iosRecords.single, containsPair('message', 'ios log'));
      expect(androidRecords.single, containsPair('message', 'android log'));

      final catalogLines = await File(
        '${root.path}/catalog.jsonl',
      ).readAsLines();
      expect(catalogLines, hasLength(2));
    });

    test(
      'falls back to safe route segments when metadata is missing',
      () async {
        final store = LogHoundDirectoryStore(root);

        await store.append({
          'timestamp': '2026-06-27T10:00:00.000',
          'kind': 'log',
          'message': 'hello',
        });

        final sessions = await store.sessions(appId: 'unknown-app');

        expect(sessions, hasLength(1));
        expect(sessions.single.appId, 'unknown-app');
        expect(sessions.single.flavor, 'default');
        expect(sessions.single.platform, 'unknown');
        expect(
          sessions.single.file.path,
          startsWith('${root.path}/default/unknown/sessions/'),
        );
        expect(sessions.single.sessionId, isNotEmpty);
      },
    );
  });
}
