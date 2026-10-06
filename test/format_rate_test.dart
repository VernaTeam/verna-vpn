import 'package:flutter_test/flutter_test.dart';
import 'package:verna_vpn/features/tunnel/presentation/format_rate.dart';

void main() {
  group('a rate is shown in the unit that keeps it short', () {
    test('nothing moving reads as zero bytes, not an empty card', () {
      expect(formatRate(0), (value: '0', unit: 'B/s'));
      expect(formatRate(-5), (value: '0', unit: 'B/s'));
    });

    test('under a kilobyte it is bytes', () {
      expect(formatRate(1), (value: '1', unit: 'B/s'));
      expect(formatRate(999), (value: '999', unit: 'B/s'));
      // The last byte before the step up.
      expect(formatRate(1023), (value: '1023', unit: 'B/s'));
    });

    test('exactly a kilobyte steps up, and keeps one decimal while small', () {
      expect(formatRate(1024), (value: '1.0', unit: 'KB/s'));
      expect(formatRate(1536), (value: '1.5', unit: 'KB/s'));
      expect(formatRate(9 * 1024), (value: '9.0', unit: 'KB/s'));
    });

    test('past ten kilobytes the decimal is noise and goes', () {
      expect(formatRate(10 * 1024), (value: '10', unit: 'KB/s'));
      expect(formatRate(847 * 1024), (value: '847', unit: 'KB/s'));
    });

    test('the last kilobyte before a megabyte is still kilobytes', () {
      expect(formatRate(1024 * 1024 - 1).unit, 'KB/s');
    });

    test('a megabyte is 1.2 MB/s, never 1200 KB/s', () {
      expect(formatRate(1024 * 1024), (value: '1.0', unit: 'MB/s'));
      // The case Meysam named: 1200 KB/s should read as 1.2 MB/s.
      expect(formatRate(1200 * 1024), (value: '1.2', unit: 'MB/s'));
      expect(formatRate(9 * 1024 * 1024), (value: '9.0', unit: 'MB/s'));
    });

    test('past ten megabytes the decimal goes too', () {
      expect(formatRate(12 * 1024 * 1024), (value: '12', unit: 'MB/s'));
      expect(formatRate(150 * 1024 * 1024), (value: '150', unit: 'MB/s'));
    });

    test('the number stays short at every scale', () {
      // Four characters is the budget the card was laid out for.
      for (final bps in [0, 1, 1023, 1024, 99999, 1048576, 52428800]) {
        expect(formatRate(bps).value.length, lessThanOrEqualTo(4),
            reason: '$bps rendered as ${formatRate(bps)}');
      }
    });
  });
}
