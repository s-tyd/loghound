/// Redacts common secret keys and token-like values from log records.
class LogHoundRedactor {
  /// Creates a redactor with the default sensitive keys plus [sensitiveKeys].
  LogHoundRedactor({Set<String> sensitiveKeys = const {}})
    : _sensitiveKeys = {
        ..._defaultSensitiveKeys,
        ...sensitiveKeys.map(_normalizeKey),
      };

  static const _defaultSensitiveKeys = {
    'authorization',
    'cookie',
    'password',
    'secret',
    'token',
    'x-api-key',
    'x-staging-auth',
  };

  final Set<String> _sensitiveKeys;

  /// Returns a recursively redacted copy of [value].
  Object? redact(Object? value) {
    if (value is String) {
      return _redactString(value);
    }
    if (value is List) {
      return value.map(redact).toList(growable: false);
    }
    if (value is Map) {
      return value.map<String, Object?>((key, nestedValue) {
        final keyText = key.toString();
        if (_sensitiveKeys.contains(_normalizeKey(keyText))) {
          return MapEntry(keyText, '***');
        }
        return MapEntry(keyText, redact(nestedValue));
      });
    }
    return value;
  }

  String _redactString(String value) {
    var redacted = value;

    if (_sensitiveKeys.isEmpty) {
      return _redactCommonValuePatterns(redacted);
    }

    final pattern = _sensitiveKeys.map(RegExp.escape).join('|');
    redacted = redacted.replaceAllMapped(
      RegExp('($pattern)\\s*:\\s*[^,}\\]\\n]+', caseSensitive: false),
      (match) => '${match.group(1)}: ***',
    );
    return _redactCommonValuePatterns(redacted);
  }

  String _redactCommonValuePatterns(String value) {
    var redacted = value;
    redacted = redacted.replaceAllMapped(
      RegExp(r'\bBearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
      (_) => 'Bearer ***',
    );
    redacted = redacted.replaceAll(
      RegExp(r'\bgh[pousr]_[A-Za-z0-9_]{20,}\b'),
      '***',
    );
    redacted = redacted.replaceAll(
      RegExp(r'\b(?:AKIA|ASIA)[0-9A-Z]{16}\b'),
      '***',
    );
    // JWTs are base64url and their header segment almost always starts with
    // `eyJ` (the encoding of `{"`). Anchoring on that prefix avoids masking
    // ordinary dotted identifiers such as `auth.login.success`.
    redacted = redacted.replaceAll(
      RegExp(r'\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b'),
      '***',
    );
    redacted = redacted.replaceAllMapped(
      RegExp(
        r'([?&](?:access_token|api_key|key|password|secret|token)=)[^&\s]+',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}***',
    );
    redacted = redacted.replaceAll(
      RegExp(
        r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
        caseSensitive: false,
      ),
      '***',
    );
    return redacted;
  }

  static String _normalizeKey(String key) => key.trim().toLowerCase();
}
