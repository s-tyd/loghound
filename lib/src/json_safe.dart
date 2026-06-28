/// Converts arbitrary values into JSON-encodable values.
Object? loghoundJsonSafe(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is DateTime) {
    return value.toIso8601String();
  }
  if (value is Iterable) {
    return value.map(loghoundJsonSafe).toList(growable: false);
  }
  if (value is Map) {
    return value.map<String, Object?>(
      (key, nestedValue) =>
          MapEntry(key.toString(), loghoundJsonSafe(nestedValue)),
    );
  }
  return value.toString();
}
