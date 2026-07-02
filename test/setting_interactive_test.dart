import 'package:loghound/src/setting_interactive.dart';
import 'package:test/test.dart';

SettingInteractiveState _state({
  int selectedIndex = 0,
  Set<String>? expanded,
  String language = 'en',
}) {
  return SettingInteractiveState(
    records: [
      {
        'key': 'language',
        'label': language == 'ja' ? '言語' : 'Language',
        'description': 'Language for the interactive settings screen',
        'type': 'enum',
        'value': language,
        'default': 'en',
        'command': 'loghound setting (space toggles en/ja)',
        'options': ['en', 'ja'],
      },
      {
        'key': 'context_format',
        'label': language == 'ja' ? 'Context 形式' : 'Context format',
        'description': 'Default output format for loghound context',
        'type': 'enum',
        'value': 'markdown',
        'default': 'markdown',
        'command': 'loghound context --format markdown|jsonl',
        'options': ['markdown', 'jsonl'],
      },
    ],
    selectedIndex: selectedIndex,
    expandedKeys: expanded ?? <String>{},
    language: language,
  );
}

/// Terminal display width, counting East Asian wide runes as two columns.
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

void main() {
  group('decodeSettingInteractiveKey', () {
    test('decodes arrow keys, enter, space, and quit', () {
      expect(
        decodeSettingInteractiveKey([0x1b, 0x5b, 0x41]),
        SettingInteractiveKey.up,
      );
      expect(
        decodeSettingInteractiveKey([0x1b, 0x5b, 0x42]),
        SettingInteractiveKey.down,
      );
      expect(
        decodeSettingInteractiveKey([0x1b, 0x5b, 0x43]),
        SettingInteractiveKey.right,
      );
      expect(decodeSettingInteractiveKey([0x0d]), SettingInteractiveKey.enter);
      expect(decodeSettingInteractiveKey([0x0a]), SettingInteractiveKey.enter);
      expect(decodeSettingInteractiveKey([0x20]), SettingInteractiveKey.space);
      expect(decodeSettingInteractiveKey([0x71]), SettingInteractiveKey.quit);
      expect(decodeSettingInteractiveKey([0x1b]), SettingInteractiveKey.quit);
      expect(
        decodeSettingInteractiveKey([0x7a]),
        SettingInteractiveKey.unknown,
      );
      expect(decodeSettingInteractiveKey([]), SettingInteractiveKey.unknown);
    });
  });

  group('handleSettingInteractiveKey', () {
    test('down moves selection and up clamps at the top', () {
      final down = handleSettingInteractiveKey(
        _state(),
        SettingInteractiveKey.down,
      );
      expect(down.state.selectedIndex, 1);
      expect(down.quit, isFalse);
      expect(down.advanceKey, isNull);

      final up = handleSettingInteractiveKey(
        _state(selectedIndex: 0),
        SettingInteractiveKey.up,
      );
      expect(up.state.selectedIndex, 0);
    });

    test('down clamps at the bottom', () {
      final result = handleSettingInteractiveKey(
        _state(selectedIndex: 1),
        SettingInteractiveKey.down,
      );
      expect(result.state.selectedIndex, 1);
    });

    test('space requests advancing the selected key', () {
      final result = handleSettingInteractiveKey(
        _state(selectedIndex: 1),
        SettingInteractiveKey.space,
      );
      expect(result.advanceKey, 'context_format');
      expect(result.quit, isFalse);
      expect(result.state.selectedIndex, 1);
    });

    test('right and enter toggle description expansion', () {
      final expanded = handleSettingInteractiveKey(
        _state(),
        SettingInteractiveKey.right,
      );
      expect(expanded.state.expandedKeys, contains('language'));

      final collapsed = handleSettingInteractiveKey(
        expanded.state,
        SettingInteractiveKey.enter,
      );
      expect(collapsed.state.expandedKeys, isNot(contains('language')));
    });

    test('navigation preserves the language', () {
      final result = handleSettingInteractiveKey(
        _state(language: 'ja'),
        SettingInteractiveKey.down,
      );
      expect(result.state.language, 'ja');
    });

    test('quit sets the quit flag', () {
      final result = handleSettingInteractiveKey(
        _state(),
        SettingInteractiveKey.quit,
      );
      expect(result.quit, isTrue);
    });

    test('unknown is a no-op', () {
      final result = handleSettingInteractiveKey(
        _state(selectedIndex: 1),
        SettingInteractiveKey.unknown,
      );
      expect(result.state.selectedIndex, 1);
      expect(result.advanceKey, isNull);
      expect(result.quit, isFalse);
    });
  });

  group('renderSettingInteractiveList', () {
    test('marks the selected row and shows values', () {
      final text = renderSettingInteractiveList(_state(selectedIndex: 1));
      final lines = text.split('\n');
      expect(
        lines.any((l) => l.startsWith('❯ ') && l.contains('Context format')),
        isTrue,
      );
      expect(
        lines.any((l) => l.startsWith('  ') && l.contains('Language')),
        isTrue,
      );
      expect(text, contains('en'));
      expect(text, contains('markdown'));
    });

    test('uses the localized title for ja', () {
      expect(
        renderSettingInteractiveList(_state()),
        contains('loghound settings'),
      );
      expect(
        renderSettingInteractiveList(_state(language: 'ja')),
        contains('loghound 設定'),
      );
    });

    test('shows description and enum options only when expanded', () {
      final collapsed = renderSettingInteractiveList(_state(selectedIndex: 1));
      expect(collapsed, isNot(contains('options:')));

      final expanded = renderSettingInteractiveList(
        _state(selectedIndex: 1, expanded: {'context_format'}),
      );
      expect(expanded, contains('Default output format'));
      expect(expanded, contains('options: markdown, jsonl'));
    });

    test('emits ANSI only when color is enabled', () {
      expect(renderSettingInteractiveList(_state()), isNot(contains('\x1b[')));
      expect(
        renderSettingInteractiveList(_state(), color: true),
        contains('\x1b['),
      );
    });

    test('aligns the value column across wide (CJK) labels', () {
      final lines = renderSettingInteractiveList(
        _state(language: 'ja'),
      ).split('\n');
      final languageLine = lines.firstWhere((line) => line.contains('言語'));
      final contextLine = lines.firstWhere(
        (line) => line.contains('Context 形式'),
      );

      int valueColumn(String line, String value) =>
          _displayWidth(line.substring(0, line.indexOf(value)));

      expect(
        valueColumn(languageLine, 'ja'),
        valueColumn(contextLine, 'markdown'),
      );
    });
  });
}
