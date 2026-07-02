/// Startup banner for the `loghound` CLI.
///
/// A braille rendering of the loghound mascot (beagle + magnifying glass) from
/// `loghound-icon.png`, with a `loghound` figlet wordmark directly beneath the
/// collar tag. Kept free of `dart:io` so it stays pure and easy to test; the
/// CLI decides on color.
///
/// Alignment notes: the mascot block is built entirely from braille glyphs —
/// including its blank cells (U+2800) rather than ASCII spaces — so every cell
/// has the same advance width even on terminals that render braille double-width.
/// Both blocks are centered as a whole (one shared offset per block), never line
/// by line, so the art does not shear diagonally.
library;

const String _logHoundBannerArt = r'''⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣠⣴⠶⠶⠶⣤⣄
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣠⠞⠉⠀⠀⠀⠀⠀⠀⠀⠉⢶⣀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡞⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⢷
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡟⠀⣰⠁⣤⠚⠳⡄⠀⠀⠀⣴⠚⠲⣄⠹⠀⠀⢷
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡟⠀⠀⡏⠀⣠⢦⠀⢹⠀⠀⠀⠁⣠⢦⠀⠀⣷⠀⠀⢷
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡟⠀⠀⠀⡇⠀⢿⣿⠇⣾⠀⠀⠀⡆⢿⣿⠇⠀⣿⠀⠀⠀⣧
⠀⠀⠀⠀⠀⠀⠀⠀⠀⡾⠀⠀⠀⠀⡇⠀⠀⠀⣰⠁⠀⠀⠀⠹⠀⠀⠀⠀⣿⠀⠀⠀⠈⣆
⠀⠀⠀⠀⠀⠀⠀⠀⣾⠀⠀⠀⠀⠀⣿⠀⠀⣰⠁⠀⠀⠀⠀⠀⠹⠀⠀⠀⡇⢀⣤⠶⠶⣾⣄
⠀⠀⠀⠀⠀⠀⠀⣸⠁⠀⠀⠀⠀⠀⠘⠀⢠⠃⠀⡞⠉⠉⠙⣦⠀⢻⠀⣸⡾⣡⠞⠛⠛⠛⣦⠻⣄
⠀⠀⠀⠀⠀⠀⠀⣿⠀⠀⠀⠀⠀⠀⠀⡇⣾⠀⠀⢷⠟⡆⢷⠏⠀⠘⠀⡿⣾⠀⠀⠀⠀⠀⠀⢻⠹
⠀⠀⠀⠀⠀⠀⠀⢿⠀⠀⠀⠀⢀⣶⣿⣿⣿⠀⠀⠀⠉⡏⠁⠀⠀⢠⡟⠃⡇⠀⠀⠀⠀⠀⠀⠀⡇⡇
⠀⠀⠀⠀⠀⠀⠀⠀⢷⠀⠀⠀⠀⠿⠿⡿⢿⠷⢤⣴⣿⣿⣷⣤⠴⣿⠷⣆⣧⠀⠀⠀⠀⠀⠀⣰⢁⠇
⠀⠀⠀⠀⠀⠀⠀⠀⠀⣧⠀⠀⠀⠀⠀⡇⠀⠙⢶⠀⠉⠉⠁⣰⠶⠁⠀⡟⣌⢷⣀⠀⠀⢀⣴⢋⡟
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⣆⠀⠀⠀⣸⢷⣤⠀⠀⠈⠛⠛⠋⠀⠀⣀⣴⢿⠈⠳⣤⣍⣉⣥⠾⠉
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⢦⣤⣴⠋⠀⠉⠻⢿⣷⣾⣹⣶⣿⠿⠋⠀⠀⠷⣤⣤⠞
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡞⠙⠾⠉⡆
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡇⣀⡆⡇⡇
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠳⠶⠶⠶⠃
 _             _                           _
| | ___   __ _| |__   ___  _   _ _ __   __| |
| |/ _ \ / _` | '_ \ / _ \| | | | '_ \ / _` |
| | (_) | (_| | | | | (_) | |_| | | | | (_| |
|_|\___/ \__, |_| |_|\___/ \__,_|_| |_|\__,_|
         |___/''';

/// The startup banner.
///
/// When [color] is false the plain art is returned. When true, the braille
/// mascot lines are tinted warm tan and the figlet wordmark bold cyan, with each
/// line individually reset so wrapping a non-ANSI sink stays harmless.
String logHoundBanner({bool color = false}) {
  if (!color) {
    return _logHoundBannerArt;
  }

  const reset = '\x1b[0m';
  const mascotColor = '\x1b[38;5;179m'; // warm tan
  const wordmarkColor = '\x1b[1;36m'; // bold cyan

  final lines = _logHoundBannerArt.split('\n');
  final buffer = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    if (i > 0) {
      buffer.write('\n');
    }
    final line = lines[i];
    if (line.trim().isEmpty) {
      buffer.write(line);
      continue;
    }
    final isMascot = line.runes.any((rune) => rune >= 0x2800 && rune <= 0x28ff);
    buffer.write(isMascot ? mascotColor : wordmarkColor);
    buffer.write(line);
    buffer.write(reset);
  }
  return buffer.toString();
}

/// Whether the banner should be colorized for the current stdout.
///
/// Pure decision so it can be unit tested without a real terminal: colorize only
/// on an ANSI-capable terminal when the `NO_COLOR` convention is not opted into.
bool logHoundShouldColor({
  required bool hasTerminal,
  required bool supportsAnsi,
  required Map<String, String> environment,
}) {
  if (!hasTerminal || !supportsAnsi) {
    return false;
  }
  if (environment.containsKey('NO_COLOR')) {
    return false;
  }
  return true;
}
