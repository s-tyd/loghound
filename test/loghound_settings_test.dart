import 'dart:io';

import 'package:loghound/src/loghound_settings.dart';
import 'package:test/test.dart';

void main() {
  group('LogHoundSettingsStore', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('loghound-settings-');
    });

    tearDown(() async {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });

    test('returns defaults when no settings file exists', () async {
      final store = LogHoundSettingsStore(directory);

      final settings = await store.read();

      expect(settings.language, 'en');
      expect(settings.contextFormat, 'markdown');
      expect(settings.captureHttpRequestBody, isFalse);
      expect(settings.captureHttpResponseBody, isFalse);
    });

    test('returns defaults when settings file is malformed', () async {
      final store = LogHoundSettingsStore(directory);
      await store.file.create(recursive: true);
      await store.file.writeAsString('{not json');

      final settings = await store.read();

      expect(settings.language, 'en');
      expect(settings.contextFormat, 'markdown');
    });
  });

  group('LogHoundSettings.toSettingRecords', () {
    test('returns one record per known setting (en)', () {
      const settings = LogHoundSettings();

      final records = settings.toSettingRecords();

      expect(records, hasLength(4));

      final language = records.firstWhere((r) => r['key'] == 'language');
      expect(language['type'], 'enum');
      expect(language['value'], 'en');
      expect(language['options'], ['en', 'ja']);

      final format = records.firstWhere((r) => r['key'] == 'context_format');
      expect(format['type'], 'enum');
      expect(format['value'], 'markdown');
      expect(format['options'], ['markdown', 'jsonl']);

      final requestBody = records.firstWhere(
        (r) => r['key'] == 'capture_http_request_body',
      );
      expect(requestBody['type'], 'bool');
      expect(requestBody['value'], isFalse);
      expect(
        requestBody['command'],
        contains('LOGHOUND_CAPTURE_HTTP_REQUEST_BODY'),
      );

      final responseBody = records.firstWhere(
        (r) => r['key'] == 'capture_http_response_body',
      );
      expect(responseBody['type'], 'bool');
      expect(responseBody['value'], isFalse);
      expect(
        responseBody['command'],
        contains('LOGHOUND_CAPTURE_HTTP_RESPONSE_BODY'),
      );
    });

    test('localizes labels for ja without changing keys/values', () {
      const settings = LogHoundSettings(language: 'ja');

      final en = settings.toSettingRecords();
      final ja = settings.toSettingRecords(language: 'ja');

      expect(ja.firstWhere((r) => r['key'] == 'language')['label'], '言語');
      expect(
        ja.firstWhere((r) => r['key'] == 'context_format')['label'],
        'Context 形式',
      );
      expect(
        ja.firstWhere((r) => r['key'] == 'capture_http_request_body')['label'],
        'HTTP送信内容を記録',
      );
      expect(
        ja.firstWhere((r) => r['key'] == 'capture_http_response_body')['label'],
        'HTTP応答内容を記録',
      );
      for (var i = 0; i < en.length; i++) {
        expect(ja[i]['key'], en[i]['key']);
        expect(ja[i]['value'], en[i]['value']);
        expect(ja[i]['options'], en[i]['options']);
      }
    });
  });

  group('LogHoundSettings json round-trip', () {
    test('serializes and parses language and context_format', () {
      const settings = LogHoundSettings(
        language: 'ja',
        contextFormat: 'jsonl',
        captureHttpRequestBody: true,
        captureHttpResponseBody: true,
      );

      final parsed = LogHoundSettings.fromJson(settings.toJson());

      expect(parsed.language, 'ja');
      expect(parsed.contextFormat, 'jsonl');
      expect(parsed.captureHttpRequestBody, isTrue);
      expect(parsed.captureHttpResponseBody, isTrue);
    });

    test('falls back to defaults for missing or invalid values', () {
      final parsed = LogHoundSettings.fromJson({
        'language': 'fr',
        'context_format': 'yaml',
        'capture_http_request_body': 'yes',
        'capture_http_response_body': 1,
      });

      expect(parsed.language, 'en');
      expect(parsed.contextFormat, 'markdown');
      expect(parsed.captureHttpRequestBody, isFalse);
      expect(parsed.captureHttpResponseBody, isFalse);
    });
  });

  group('logHoundAdvanceSetting', () {
    LogHoundSettingDescriptor descriptorFor(String key) =>
        logHoundSettingDescriptors.singleWhere((d) => d.key == key);

    test('cycles an enum setting and wraps', () {
      final format = descriptorFor('context_format');

      final toJsonl = logHoundAdvanceSetting(format, const LogHoundSettings());
      final backToMarkdown = logHoundAdvanceSetting(format, toJsonl);

      expect(toJsonl.contextFormat, 'jsonl');
      expect(backToMarkdown.contextFormat, 'markdown');
    });

    test('falls to the first option for an out-of-range value', () {
      final language = descriptorFor('language');

      final result = logHoundAdvanceSetting(
        language,
        const LogHoundSettings(language: 'fr'),
      );

      expect(result.language, 'en');
    });

    test('toggles bool settings', () {
      final responseBody = descriptorFor('capture_http_response_body');

      final enabled = logHoundAdvanceSetting(
        responseBody,
        const LogHoundSettings(),
      );
      final disabled = logHoundAdvanceSetting(responseBody, enabled);

      expect(enabled.captureHttpResponseBody, isTrue);
      expect(disabled.captureHttpResponseBody, isFalse);
    });
  });
}
