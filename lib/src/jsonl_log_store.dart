import 'dart:convert';
import 'dart:io';

import 'json_safe.dart';

/// A newline-delimited JSON store for local log records.
class JsonlLogStore {
  /// Creates a JSONL store backed by [file].
  JsonlLogStore(this.file);

  /// The JSONL file used by this store.
  final File file;

  static final Map<String, Future<void>> _pendingWritesByPath =
      <String, Future<void>>{};

  /// Appends one JSON-safe record as a single JSONL line.
  Future<void> append(Map<String, Object?> record) async {
    final encoded = jsonEncode(loghoundJsonSafe(record));
    final path = _lockPath(file);
    final previousWrite = _pendingWritesByPath[path] ?? Future<void>.value();
    final write = previousWrite.then((_) async {
      await file.parent.create(recursive: true);
      await file.writeAsString('$encoded\n', mode: FileMode.append);
    });
    final pending = write.catchError((Object _) {});
    _pendingWritesByPath[path] = pending;
    pending.whenComplete(() {
      if (identical(_pendingWritesByPath[path], pending)) {
        _pendingWritesByPath.remove(path);
      }
    });
    return write;
  }

  /// Reads all records from the file.
  Future<List<Map<String, Object?>>> readAll() async {
    return readStream().toList();
  }

  /// Streams records from the file in write order.
  Stream<Map<String, Object?>> readStream() async* {
    await (_pendingWritesByPath[_lockPath(file)] ?? Future<void>.value());

    if (!await file.exists()) {
      return;
    }

    final lines = file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (line.trim().isNotEmpty) {
        yield jsonDecode(line) as Map<String, Object?>;
      }
    }
  }

  /// Reads the latest [count] records from the file.
  Future<List<Map<String, Object?>>> readLast(int count) async {
    if (count <= 0) {
      return [];
    }

    final records = await readAll();
    if (records.length <= count) {
      return records;
    }
    return records.sublist(records.length - count);
  }
}

String _lockPath(File file) => file.absolute.path;
