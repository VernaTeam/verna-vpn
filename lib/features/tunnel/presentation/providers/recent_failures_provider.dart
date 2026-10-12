import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/tunnel_snapshot.dart';
import 'tunnel_provider.dart';

/// How many connects have failed in a row, and how long the gap was between
/// the last two.
///
/// Exists for one measured fact. Over four days of 1.0.5, a connect attempted
/// within two minutes of a failure succeeded **4.9%** of the time; after a
/// short wait, **38.9%**. And 64% of every attempt made was inside that
/// window -- 469 of 728. People press the button again immediately, which is
/// the natural thing to do and almost never works, because what failed was
/// the minute, not the server.
///
/// The app cannot fix the minute. It can stop pretending the next tap is as
/// good as the last one.
class RecentFailures extends Notifier<RecentFailureState> {
  @override
  RecentFailureState build() {
    ref.listen<TunnelSnapshot>(tunnelSnapshotProvider, (previous, next) {
      final wasFailed = previous?.phase == TunnelPhase.failed;
      if (next.phase == TunnelPhase.failed && !wasFailed) {
        final now = DateTime.now();
        final last = state.at;
        state = RecentFailureState(
          count: state.count + 1,
          at: now,
          gapS: last == null ? null : now.difference(last).inSeconds,
        );
      } else if (next.isConnected) {
        // A connection ends the streak. Not a disconnect: hanging up on a
        // working tunnel is not a failure and must not read as one.
        state = const RecentFailureState();
      }
    });
    return const RecentFailureState();
  }
}

class RecentFailureState {
  const RecentFailureState({this.count = 0, this.at, this.gapS});

  final int count;
  final DateTime? at;

  /// Seconds between the previous failure and this one, null for the first.
  final int? gapS;

  /// Whether this failure followed hard on another one.
  ///
  /// Two minutes is where the measured cliff is, not a round number picked to
  /// look tidy: inside it, 4.9%; outside, 38.9%.
  bool get isRapidRetry => count >= 2 && gapS != null && gapS! < 120;
}

final recentFailuresProvider =
    NotifierProvider<RecentFailures, RecentFailureState>(RecentFailures.new);
