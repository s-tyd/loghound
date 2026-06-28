import 'package:loghound/src/banner.dart';
import 'package:test/test.dart';

void main() {
  group('logHoundBanner', () {
    test('plain banner has the art but no ANSI escapes', () {
      final banner = logHoundBanner();
      expect(banner, contains('⣿')); // braille mascot pixel
      expect(banner, contains('___')); // figlet wordmark
      expect(banner.split('\n').length, greaterThan(10));
      expect(banner, isNot(contains('\x1b[')));
    });

    test('colored banner wraps lines in ANSI and resets them', () {
      final banner = logHoundBanner(color: true);
      expect(banner, contains('\x1b['));
      expect(banner, contains('\x1b[0m'));
      expect(banner, contains('⣿')); // art is still present
    });
  });

  group('logHoundShouldColor', () {
    test('true on an ANSI terminal without NO_COLOR', () {
      expect(
        logHoundShouldColor(
          hasTerminal: true,
          supportsAnsi: true,
          environment: const {},
        ),
        isTrue,
      );
    });

    test('false when NO_COLOR is set', () {
      expect(
        logHoundShouldColor(
          hasTerminal: true,
          supportsAnsi: true,
          environment: const {'NO_COLOR': '1'},
        ),
        isFalse,
      );
    });

    test('false without a terminal', () {
      expect(
        logHoundShouldColor(
          hasTerminal: false,
          supportsAnsi: true,
          environment: const {},
        ),
        isFalse,
      );
    });

    test('false when ANSI is unsupported', () {
      expect(
        logHoundShouldColor(
          hasTerminal: true,
          supportsAnsi: false,
          environment: const {},
        ),
        isFalse,
      );
    });
  });
}
