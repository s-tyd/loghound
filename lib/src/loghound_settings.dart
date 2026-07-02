import 'dart:convert';
import 'dart:io';

/// Persistent loghound CLI settings stored under a loghound root.
class LogHoundSettings {
  /// Creates immutable CLI settings.
  const LogHoundSettings({
    this.language = 'en',
    this.contextFormat = 'markdown',
    this.captureHttpRequestBody = false,
    this.captureHttpResponseBody = false,
  });

  /// Language for the interactive settings screen (`en` or `ja`).
  final String language;

  /// Default `loghound context` output format (`markdown` or `jsonl`).
  final String contextFormat;

  /// Whether app-side HTTP instrumentation is expected to capture request
  /// bodies.
  final bool captureHttpRequestBody;

  /// Whether app-side HTTP instrumentation is expected to capture response
  /// bodies.
  final bool captureHttpResponseBody;

  /// Returns a copy with selected values changed.
  LogHoundSettings copyWith({
    String? language,
    String? contextFormat,
    bool? captureHttpRequestBody,
    bool? captureHttpResponseBody,
  }) {
    return LogHoundSettings(
      language: language ?? this.language,
      contextFormat: contextFormat ?? this.contextFormat,
      captureHttpRequestBody:
          captureHttpRequestBody ?? this.captureHttpRequestBody,
      captureHttpResponseBody:
          captureHttpResponseBody ?? this.captureHttpResponseBody,
    );
  }

  /// Converts settings to JSON.
  Map<String, Object?> toJson() => {
    'language': language,
    'context_format': contextFormat,
    'capture_http_request_body': captureHttpRequestBody,
    'capture_http_response_body': captureHttpResponseBody,
  };

  /// Parses settings from JSON, using defaults for missing or invalid values.
  factory LogHoundSettings.fromJson(Map<String, Object?> json) {
    final language = json['language'];
    final contextFormat = json['context_format'];
    final captureHttpRequestBody = json['capture_http_request_body'];
    final captureHttpResponseBody = json['capture_http_response_body'];
    return LogHoundSettings(
      language: language == 'ja' ? 'ja' : 'en',
      contextFormat: contextFormat == 'jsonl' ? 'jsonl' : 'markdown',
      captureHttpRequestBody: captureHttpRequestBody == true,
      captureHttpResponseBody: captureHttpResponseBody == true,
    );
  }

  /// Returns one structured record per known setting, merging registry
  /// metadata from [logHoundSettingDescriptors] with this instance's
  /// current values. Labels and descriptions are localized to [language]
  /// (English fallback); all other fields are language-independent.
  List<Map<String, Object?>> toSettingRecords({String language = 'en'}) {
    return [
      for (final descriptor in logHoundSettingDescriptors)
        {
          'key': descriptor.key,
          'label': descriptor.localizedLabel(language),
          'description': descriptor.localizedDescription(language),
          'type': descriptor.type,
          'value': descriptor.valueOf(this),
          'default': descriptor.defaultValue,
          'command': descriptor.command,
          if (descriptor.options != null) 'options': descriptor.options,
        },
    ];
  }
}

/// Describes a single loghound setting for list/UI presentation.
class LogHoundSettingDescriptor {
  /// Creates an immutable setting descriptor.
  const LogHoundSettingDescriptor({
    required this.key,
    required this.label,
    required this.description,
    required this.type,
    required this.defaultValue,
    required this.command,
    required this.valueOf,
    required this.applyValue,
    this.options,
    this.labelByLanguage = const {},
    this.descriptionByLanguage = const {},
  });

  /// Machine-readable setting name, e.g. `context_format`.
  final String key;

  /// Short human-readable name (English canonical), e.g. `Device mode`.
  final String label;

  /// One-line explanation (English canonical).
  final String description;

  /// Value type: `bool` or `enum`.
  final String type;

  /// Value used when the setting has never been written.
  final Object? defaultValue;

  /// CLI command(s) or gesture used to change this setting.
  final String command;

  /// Reads this setting's current value out of [settings].
  final Object? Function(LogHoundSettings settings) valueOf;

  /// Returns settings updated so this setting's value becomes [value].
  final LogHoundSettings Function(LogHoundSettings settings, Object? value)
  applyValue;

  /// Allowed values for an enum setting, or null for a bool setting.
  final List<String>? options;

  /// Localized labels keyed by language code (English fallback via [label]).
  final Map<String, String> labelByLanguage;

  /// Localized descriptions keyed by language code (fallback via
  /// [description]).
  final Map<String, String> descriptionByLanguage;

  /// Returns the label for [language], falling back to the English [label].
  String localizedLabel(String language) => labelByLanguage[language] ?? label;

  /// Returns the description for [language], falling back to English.
  String localizedDescription(String language) =>
      descriptionByLanguage[language] ?? description;
}

/// All known loghound settings, in display order.
const logHoundSettingDescriptors = <LogHoundSettingDescriptor>[
  LogHoundSettingDescriptor(
    key: 'language',
    label: 'Language',
    description:
        'Language for the interactive settings screen (NDJSON stays English)',
    type: 'enum',
    defaultValue: 'en',
    command: 'loghound setting (space toggles en/ja)',
    options: ['en', 'ja'],
    valueOf: _languageValue,
    applyValue: _languageApply,
    labelByLanguage: {'ja': '言語'},
    descriptionByLanguage: {'ja': '設定画面の表示言語（NDJSON 出力は英語のまま）'},
  ),
  LogHoundSettingDescriptor(
    key: 'context_format',
    label: 'Context format',
    description:
        'Default output format for loghound context when --format is not given',
    type: 'enum',
    defaultValue: 'markdown',
    command:
        'loghound context --format markdown|jsonl (space sets the default)',
    options: ['markdown', 'jsonl'],
    valueOf: _contextFormatValue,
    applyValue: _contextFormatApply,
    labelByLanguage: {'ja': 'Context 形式'},
    descriptionByLanguage: {'ja': 'loghound context の既定出力形式（--format 未指定時）'},
  ),
  LogHoundSettingDescriptor(
    key: 'capture_http_request_body',
    label: 'Record HTTP request body',
    description:
        'Expected app-side Dio/body capture setting for AI HTTP investigation',
    type: 'bool',
    defaultValue: false,
    command:
        'loghound setting toggles policy; pass --dart-define=LOGHOUND_CAPTURE_HTTP_REQUEST_BODY=true to the app',
    valueOf: _captureHttpRequestBodyValue,
    applyValue: _captureHttpRequestBodyApply,
    labelByLanguage: {'ja': 'HTTP送信内容を記録'},
    descriptionByLanguage: {
      'ja': 'AI の HTTP 調査用にアプリ側 Dio/body capture で request body を保存する想定',
    },
  ),
  LogHoundSettingDescriptor(
    key: 'capture_http_response_body',
    label: 'Record HTTP response body',
    description:
        'Expected app-side Dio/body capture setting for AI HTTP investigation',
    type: 'bool',
    defaultValue: false,
    command:
        'loghound setting toggles policy; pass --dart-define=LOGHOUND_CAPTURE_HTTP_RESPONSE_BODY=true to the app',
    valueOf: _captureHttpResponseBodyValue,
    applyValue: _captureHttpResponseBodyApply,
    labelByLanguage: {'ja': 'HTTP応答内容を記録'},
    descriptionByLanguage: {
      'ja': 'AI の HTTP 調査用にアプリ側 Dio/body capture で response body を保存する想定',
    },
  ),
];

Object? _languageValue(LogHoundSettings settings) => settings.language;

LogHoundSettings _languageApply(LogHoundSettings settings, Object? value) {
  return settings.copyWith(language: value as String);
}

Object? _contextFormatValue(LogHoundSettings settings) =>
    settings.contextFormat;

LogHoundSettings _contextFormatApply(LogHoundSettings settings, Object? value) {
  return settings.copyWith(contextFormat: value as String);
}

Object? _captureHttpRequestBodyValue(LogHoundSettings settings) =>
    settings.captureHttpRequestBody;

LogHoundSettings _captureHttpRequestBodyApply(
  LogHoundSettings settings,
  Object? value,
) {
  return settings.copyWith(captureHttpRequestBody: value == true);
}

Object? _captureHttpResponseBodyValue(LogHoundSettings settings) =>
    settings.captureHttpResponseBody;

LogHoundSettings _captureHttpResponseBodyApply(
  LogHoundSettings settings,
  Object? value,
) {
  return settings.copyWith(captureHttpResponseBody: value == true);
}

/// Returns settings with [descriptor]'s value advanced to the next state:
/// a bool flips, an enum cycles through its options (wrapping), and an
/// out-of-range enum value resets to the first option.
LogHoundSettings logHoundAdvanceSetting(
  LogHoundSettingDescriptor descriptor,
  LogHoundSettings settings,
) {
  final current = descriptor.valueOf(settings);
  final options = descriptor.options;
  if (options == null) {
    return descriptor.applyValue(settings, current != true);
  }
  final index = options.indexOf(current?.toString() ?? '');
  final next = index < 0
      ? options.first
      : options[(index + 1) % options.length];
  return descriptor.applyValue(settings, next);
}

/// Reads and writes loghound settings from `<root>/settings.json`.
class LogHoundSettingsStore {
  /// Creates a settings store under [root].
  LogHoundSettingsStore(this.root);

  /// Root directory for logs and settings.
  final Directory root;

  /// File that stores settings.
  File get file => File('${root.path}${Platform.pathSeparator}settings.json');

  /// Reads settings, returning defaults when the file does not exist.
  Future<LogHoundSettings> read() async {
    if (!await file.exists()) {
      return const LogHoundSettings();
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        return LogHoundSettings.fromJson(Map<String, Object?>.from(decoded));
      }
    } on FormatException {
      return const LogHoundSettings();
    }
    return const LogHoundSettings();
  }

  /// Writes settings.
  Future<void> write(LogHoundSettings settings) async {
    await file.parent.create(recursive: true);
    await file.writeAsString('${jsonEncode(settings.toJson())}\n');
  }
}
