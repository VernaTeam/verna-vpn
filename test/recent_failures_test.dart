import 'package:flutter_test/flutter_test.dart';
import 'package:verna_vpn/features/tunnel/presentation/providers/recent_failures_provider.dart';

void main() {
  group('the rapid-retry notice appears only where the odds actually fall', () {
    test('a first failure says nothing: one retry is reasonable', () {
      expect(const RecentFailureState(count: 1).isRapidRetry, isFalse);
    });

    test('a second failure hard on the first is the case it exists for', () {
      // 4.9% inside this window against 38.9% outside it, measured over four
      // days of 1.0.5.
      expect(
        RecentFailureState(count: 2, at: DateTime.now(), gapS: 20).isRapidRetry,
        isTrue,
      );
    });

    test('a second failure after a real wait says nothing', () {
      expect(
        RecentFailureState(count: 2, at: DateTime.now(), gapS: 600).isRapidRetry,
        isFalse,
      );
    });

    test('the boundary is two minutes, not approximately two minutes', () {
      expect(RecentFailureState(count: 2, gapS: 119).isRapidRetry, isTrue);
      expect(RecentFailureState(count: 2, gapS: 120).isRapidRetry, isFalse);
    });

    test('an unknown gap is not treated as a fast one', () {
      // Null means the previous failure is not known -- a fresh install, or
      // storage that could not be read. Guessing "fast" there would show the
      // notice to someone on their first ever attempt.
      expect(const RecentFailureState(count: 3).isRapidRetry, isFalse);
    });

    test('nothing has failed yet', () {
      expect(const RecentFailureState().isRapidRetry, isFalse);
      expect(const RecentFailureState().count, 0);
    });
  });
}
