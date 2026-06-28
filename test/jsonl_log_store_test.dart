import 'dart:io';

import 'package:loghound/loghound.dart';
import 'package:test/test.dart';

void main() {
  group('JsonlLogStore', () {
    late Directory directory;
    late File file;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('loghound-store-');
      file = File('${directory.path}/nested/app.jsonl');
    });

    tearDown(() async {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });

    test('appends records as JSON lines and reads them back', () async {
      final store = JsonlLogStore(file);

      await store.append({'name': 'HTTP', 'message': 'request'});
      await store.append({'name': 'HTTP', 'message': 'response'});

      expect(await store.readAll(), [
        {'name': 'HTTP', 'message': 'request'},
        {'name': 'HTTP', 'message': 'response'},
      ]);
      expect(await file.readAsLines(), hasLength(2));
    });

    test('returns the last records in original order', () async {
      final store = JsonlLogStore(file);

      await store.append({'message': 'one'});
      await store.append({'message': 'two'});
      await store.append({'message': 'three'});

      expect(await store.readLast(2), [
        {'message': 'two'},
        {'message': 'three'},
      ]);
    });

    test('streams records from JSON lines', () async {
      final store = JsonlLogStore(file);

      await store.append({'message': 'one'});
      await store.append({'message': 'two'});

      expect(await store.readStream().toList(), [
        {'message': 'one'},
        {'message': 'two'},
      ]);
    });

    test('serializes concurrent appends in call order', () async {
      final store = JsonlLogStore(file);

      await Future.wait([
        for (var index = 0; index < 50; index++) store.append({'index': index}),
      ]);

      final records = await store.readAll();
      expect(
        records.map((record) => record['index']),
        List.generate(50, (i) => i),
      );
    });

    test('reads wait for queued appends', () async {
      final store = JsonlLogStore(file);

      final writes = [
        for (var index = 0; index < 10; index++) store.append({'index': index}),
      ];

      final records = await store.readAll();
      await Future.wait(writes);

      expect(
        records.map((record) => record['index']),
        List.generate(10, (i) => i),
      );
    });

    test('separate stores for the same file share pending writes', () async {
      final writer = JsonlLogStore(file);
      final reader = JsonlLogStore(file);

      final write = writer.append({'message': 'queued'});

      final records = await reader.readAll();
      await write;

      expect(records, [
        {'message': 'queued'},
      ]);
    });
  });
}
