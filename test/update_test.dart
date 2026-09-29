import 'package:flutter_test/flutter_test.dart';
import 'package:verna_vpn/features/update/data/update_checker.dart';

void main() {
  group('release tags', () {
    test('a v prefix is not part of the version', () {
      expect(UpdateChecker.normalise('v1.0.1'), '1.0.1');
      expect(UpdateChecker.normalise('1.0.1'), '1.0.1');
      expect(UpdateChecker.normalise('  v2.3.4 '), '2.3.4');
    });

    test('a suffix is dropped, the numbers are kept', () {
      expect(UpdateChecker.normalise('v1.0.0-beta'), '1.0.0');
      expect(UpdateChecker.normalise('v1.2.0-rc.2'), '1.2.0');
    });

    test('anything unrecognisable yields nothing to compare', () {
      expect(UpdateChecker.normalise(''), '');
      expect(UpdateChecker.normalise('nightly'), '');
    });
  });

  group('is it newer', () {
    test('field by field, not as text', () {
      // The one a string comparison gets backwards: "1.10" sorts before "1.9".
      expect(UpdateChecker.isNewer('1.10.0', '1.9.0'), isTrue);
      expect(UpdateChecker.isNewer('1.9.0', '1.10.0'), isFalse);
    });

    test('the same version is not an update', () {
      expect(UpdateChecker.isNewer('1.0.0', '1.0.0'), isFalse);
    });

    test('an older release never offers itself', () {
      expect(UpdateChecker.isNewer('0.9.9', '1.0.0'), isFalse);
      expect(UpdateChecker.isNewer('1.0.0', '1.0.1'), isFalse);
    });

    test('missing fields count as zero', () {
      expect(UpdateChecker.isNewer('1.0.1', '1.0'), isTrue);
      expect(UpdateChecker.isNewer('1.0', '1.0.0'), isFalse);
      expect(UpdateChecker.isNewer('2', '1.9.9'), isTrue);
    });
  });
}
