/// A decoded keypress in the interactive `loghound setting` list.
enum SettingInteractiveKey {
  /// Move the selection up.
  up,

  /// Move the selection down.
  down,

  /// Expand or collapse the selected row's description.
  right,

  /// Expand or collapse the selected row's description.
  enter,

  /// Advance the selected setting's value.
  space,

  /// Leave the interactive list.
  quit,

  /// An input that maps to no action.
  unknown,
}

/// Decodes raw stdin bytes (read from a terminal in raw mode) into a
/// [SettingInteractiveKey]. Unrecognized input maps to
/// [SettingInteractiveKey.unknown].
SettingInteractiveKey decodeSettingInteractiveKey(List<int> bytes) {
  if (bytes.length == 1) {
    switch (bytes.first) {
      case 0x0d:
      case 0x0a:
        return SettingInteractiveKey.enter;
      case 0x20:
        return SettingInteractiveKey.space;
      case 0x71: // 'q'
      case 0x1b: // bare ESC
        return SettingInteractiveKey.quit;
    }
    return SettingInteractiveKey.unknown;
  }
  if (bytes.length == 3 && bytes[0] == 0x1b && bytes[1] == 0x5b) {
    switch (bytes[2]) {
      case 0x41:
        return SettingInteractiveKey.up;
      case 0x42:
        return SettingInteractiveKey.down;
      case 0x43:
        return SettingInteractiveKey.right;
    }
  }
  return SettingInteractiveKey.unknown;
}

/// Immutable UI state of the interactive setting list.
class SettingInteractiveState {
  /// Creates the interactive list state.
  const SettingInteractiveState({
    required this.records,
    required this.selectedIndex,
    required this.expandedKeys,
    required this.language,
  });

  /// Setting records, already localized, shaped like
  /// `LogHoundSettings.toSettingRecords()`.
  final List<Map<String, Object?>> records;

  /// Index of the currently highlighted row.
  final int selectedIndex;

  /// Setting keys whose description is currently expanded.
  final Set<String> expandedKeys;

  /// Language code driving the screen chrome (`en` or `ja`).
  final String language;

  /// Returns a copy with selected values replaced.
  SettingInteractiveState copyWith({
    List<Map<String, Object?>>? records,
    int? selectedIndex,
    Set<String>? expandedKeys,
    String? language,
  }) {
    return SettingInteractiveState(
      records: records ?? this.records,
      selectedIndex: selectedIndex ?? this.selectedIndex,
      expandedKeys: expandedKeys ?? this.expandedKeys,
      language: language ?? this.language,
    );
  }
}

/// Outcome of applying one keypress to a [SettingInteractiveState].
class SettingInteractiveResult {
  /// Creates a key-handling result.
  const SettingInteractiveResult({
    required this.state,
    this.advanceKey,
    this.quit = false,
  });

  /// The next UI state.
  final SettingInteractiveState state;

  /// Setting key the caller should advance and persist, if any.
  final String? advanceKey;

  /// Whether the interactive loop should exit.
  final bool quit;
}

/// Pure state transition for one decoded [key]. Selection is clamped and
/// does not wrap. Space returns the selected key in
/// [SettingInteractiveResult.advanceKey] for the caller to advance and
/// persist; it does not mutate the value itself.
SettingInteractiveResult handleSettingInteractiveKey(
  SettingInteractiveState state,
  SettingInteractiveKey key,
) {
  switch (key) {
    case SettingInteractiveKey.up:
      final index = state.selectedIndex <= 0 ? 0 : state.selectedIndex - 1;
      return SettingInteractiveResult(
        state: state.copyWith(selectedIndex: index),
      );
    case SettingInteractiveKey.down:
      final last = state.records.isEmpty ? 0 : state.records.length - 1;
      final index = state.selectedIndex >= last
          ? last
          : state.selectedIndex + 1;
      return SettingInteractiveResult(
        state: state.copyWith(selectedIndex: index),
      );
    case SettingInteractiveKey.right:
    case SettingInteractiveKey.enter:
      final selected = _selectedKey(state);
      if (selected == null) {
        return SettingInteractiveResult(state: state);
      }
      final expanded = Set<String>.of(state.expandedKeys);
      if (!expanded.remove(selected)) {
        expanded.add(selected);
      }
      return SettingInteractiveResult(
        state: state.copyWith(expandedKeys: expanded),
      );
    case SettingInteractiveKey.space:
      return SettingInteractiveResult(
        state: state,
        advanceKey: _selectedKey(state),
      );
    case SettingInteractiveKey.quit:
      return SettingInteractiveResult(state: state, quit: true);
    case SettingInteractiveKey.unknown:
      return SettingInteractiveResult(state: state);
  }
}

const String _reset = '\x1b[0m';
const String _bold = '\x1b[1m';
const String _dim = '\x1b[2m';
const String _boldCyan = '\x1b[1;36m';
const String _green = '\x1b[32m';
const String _yellow = '\x1b[33m';

/// Spaces between the label column and its value.
const String _valueGap = '      ';

/// Renders [state] as terminal text (one `\n`-terminated line each). The
/// chrome is localized by `state.language`; when [color] is true the output
/// is wrapped in ANSI escapes. The caller adds cursor movement for redraws.
String renderSettingInteractiveList(
  SettingInteractiveState state, {
  bool color = false,
}) {
  final ja = state.language == 'ja';
  final title = ja ? 'loghound 設定' : 'loghound settings';
  final hint = ja
      ? '↑↓ 移動 · space 変更 · →/enter 詳細 · q 終了'
      : '↑↓ move · space change · →/enter details · q quit';
  final optionsLabel = ja ? '選択肢: ' : 'options: ';

  final buffer = StringBuffer()
    ..writeln(_wrap(title, _bold, color))
    ..writeln(_wrap(hint, _dim, color))
    ..writeln();

  var labelWidth = 0;
  for (final record in state.records) {
    final width = _displayWidth(record['label'] as String? ?? '');
    if (width > labelWidth) {
      labelWidth = width;
    }
  }

  for (var i = 0; i < state.records.length; i++) {
    final record = state.records[i];
    final selected = i == state.selectedIndex;
    final marker = selected ? '❯ ' : '  ';
    final label = record['label'] as String? ?? '';
    final padding = ' ' * (labelWidth - _displayWidth(label));
    final head = '$marker$label$padding';
    final headText = color && selected ? '$_boldCyan$head$_reset' : head;
    final value = _renderValue(record['value']);
    final valueText = color
        ? '${_valueColor(record['value'])}$value$_reset'
        : value;
    buffer.writeln('$headText$_valueGap$valueText');

    final key = record['key'] as String?;
    if (key != null && state.expandedKeys.contains(key)) {
      final description = '  ${record['description'] as String? ?? ''}';
      buffer.writeln(_wrap(description, _dim, color));
      final options = record['options'];
      if (options is List && options.isNotEmpty) {
        final line = '  $optionsLabel${options.join(', ')}';
        buffer.writeln(_wrap(line, _dim, color));
      }
    }
  }
  return buffer.toString();
}

String _wrap(String text, String code, bool color) =>
    color ? '$code$text$_reset' : text;

String _valueColor(Object? value) {
  if (value is bool) {
    return value ? _green : _dim;
  }
  return _yellow;
}

String? _selectedKey(SettingInteractiveState state) {
  if (state.selectedIndex < 0 || state.selectedIndex >= state.records.length) {
    return null;
  }
  return state.records[state.selectedIndex]['key'] as String?;
}

String _renderValue(Object? value) {
  if (value is bool) {
    return value ? 'true' : 'false';
  }
  return value?.toString() ?? '';
}

/// Terminal display width of [text], counting East Asian wide runes (CJK,
/// kana, fullwidth forms) as two columns so mixed-script labels align.
int _displayWidth(String text) {
  var width = 0;
  for (final rune in text.runes) {
    width += _isWideRune(rune) ? 2 : 1;
  }
  return width;
}

bool _isWideRune(int rune) {
  return (rune >= 0x1100 && rune <= 0x115F) ||
      (rune >= 0x2E80 && rune <= 0x303E) ||
      (rune >= 0x3041 && rune <= 0x33FF) ||
      (rune >= 0x3400 && rune <= 0x4DBF) ||
      (rune >= 0x4E00 && rune <= 0x9FFF) ||
      (rune >= 0xA000 && rune <= 0xA4CF) ||
      (rune >= 0xAC00 && rune <= 0xD7A3) ||
      (rune >= 0xF900 && rune <= 0xFAFF) ||
      (rune >= 0xFE30 && rune <= 0xFE4F) ||
      (rune >= 0xFF00 && rune <= 0xFF60) ||
      (rune >= 0xFFE0 && rune <= 0xFFE6);
}
