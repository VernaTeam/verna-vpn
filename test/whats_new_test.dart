import 'package:flutter_test/flutter_test.dart';
import 'package:verna_vpn/features/update/data/update_checker.dart';

void main() {
  const notes = '''
Faster to connect, and honest about where you are.

## Download

| File | For |
|---|---|
| `verna-vpn-1.0.4-arm64-v8a.apk` | Most phones |

<!-- whatsnew
- Faster connecting.
- Bug fixes and performance improvements.
-->

<!-- whatsnew-fa
- اتصال سریع‌تر.
- رفع اشکال و بهبود عملکرد.
-->

## Not built yet
Kill switch.
''';

  group("what's new", () {
    test('comes out of the hidden block, not the page', () {
      final lines = UpdateChecker.whatsNew(notes);
      expect(lines, ['Faster connecting.', 'Bug fixes and performance improvements.']);
      // Nothing from the page itself: no headings, no table, no file names.
      for (final line in lines) {
        expect(line.contains('##'), isFalse);
        expect(line.contains('|'), isFalse);
        expect(line.contains('.apk'), isFalse);
      }
    });

    test('the Persian block is used when the app is Persian', () {
      final lines = UpdateChecker.whatsNew(notes, persian: true);
      expect(lines.first, 'اتصال سریع‌تر.');
      expect(lines.length, 2);
    });

    test('falls back to the other language rather than showing nothing', () {
      const english = '<!-- whatsnew\nOnly English here.\n-->';
      expect(UpdateChecker.whatsNew(english, persian: true), ['Only English here.']);
    });

    test('a release with no block yields nothing, so the app can say so', () {
      // The caller shows "bug fixes and performance improvements" for this.
      expect(UpdateChecker.whatsNew('Just a normal release page.'), isEmpty);
      expect(UpdateChecker.whatsNew(null), isEmpty);
      expect(UpdateChecker.whatsNew(''), isEmpty);
    });

    test('an empty block counts as no block', () {
      expect(UpdateChecker.whatsNew('<!-- whatsnew\n\n-->'), isEmpty);
    });

    test('bullets are stripped however they were typed', () {
      const mixed = '<!-- whatsnew\n- dash\n* star\n• bullet\nplain\n-->';
      expect(UpdateChecker.whatsNew(mixed),
          ['dash', 'star', 'bullet', 'plain']);
    });

    test('a changelog is not a dialog: at most four lines', () {
      final many = '<!-- whatsnew\n${List.filled(9, '- a line').join('\n')}\n-->';
      expect(UpdateChecker.whatsNew(many).length, 4);
    });

    test('a paragraph is clipped rather than allowed to fill the screen', () {
      final long = '<!-- whatsnew\n${'x' * 300}\n-->';
      final line = UpdateChecker.whatsNew(long).single;
      expect(line.length, lessThanOrEqualTo(120));
      expect(line, endsWith('...'));
    });
  });
}
