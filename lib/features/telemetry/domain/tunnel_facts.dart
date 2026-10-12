import '../../configs/domain/vpn_config.dart';
import 'telemetry_records.dart';

/// What the tunnel layer knows about a connection it just made.
///
/// The service reports facts; the sink turns them into a row, because only the
/// sink knows the things that are not the tunnel's business -- which transport
/// carried it, which SIM was in the phone, and whether the user agreed to
/// share any of it.
class TunnelUpFacts {
  const TunnelUpFacts({
    required this.config,
    required this.picked,
    required this.connectMs,
    required this.attemptsBefore,
    this.probeMs,
    this.tunnelMs,
    this.exitCountry,
    this.askedCountry,
    this.usedMemory,
    this.widened,
  });

  final VpnConfig config;
  final PickedBy picked;

  /// From the tap to a tunnel that had been verified to carry traffic.
  final int connectMs;

  /// How many servers were tried and rejected before this one.
  final int attemptsBefore;

  /// The device test's prediction and the tunnel's own measurement.
  final int? probeMs;
  final int? tunnelMs;

  final String? exitCountry;
  final String? askedCountry;

  /// Whether a server this phone had already carried traffic through led the
  /// attempt. The same field is on a failure, so the memory's worth is a
  /// comparison rather than a guess.
  final bool? usedMemory;

  /// Whether the attempt went past a hand-picked server that failed. On a
  /// session this is the measure of the fallback added in 1.0.6: a widened
  /// success is a connection the old code would have reported as a failure.
  final bool? widened;
}

/// What the tunnel layer knows about a connect that produced nothing.
class TunnelFailedFacts {
  const TunnelFailedFacts({
    required this.reason,
    required this.picked,
    required this.candidatesTried,
    required this.gaveUpAfterS,
    this.askedCountry,
    this.shortlistSize,
    this.probeAnswered,
    this.usedMemory,
    this.widened,
    this.protocol,
  });

  final FailReason reason;
  final PickedBy picked;
  final int candidatesTried;
  final int gaveUpAfterS;
  final String? askedCountry;

  /// How many servers the attempt had to work with once the unreachable ones
  /// were dropped.
  ///
  /// Added after the 1.0.5 review (2026-10-13), which could not explain its
  /// own central number: failures averaged 2.1 candidates tried. Whether that
  /// is "the shortlist held two" or "the shortlist held eighty and only two
  /// answered a probe" are opposite problems with opposite fixes, and nothing
  /// stored could tell them apart.
  final int? shortlistSize;

  /// Of those, how many answered the core's own latency probe. The pair with
  /// [shortlistSize] is the whole funnel: reachable -> answered -> tried.
  final int? probeAnswered;

  /// Whether a server this phone had previously carried traffic through led
  /// the attempt.
  ///
  /// 1.0.5 changed how that memory is filed -- per operator rather than per
  /// ASN -- and shipped with no way to measure whether it helps. This is that
  /// way.
  final bool? usedMemory;

  /// Whether the attempt went past what the user picked by hand because the
  /// picked server failed. Measures the fallback added in 1.0.6; without it
  /// the fallback's effect is invisible, since a widened attempt that
  /// succeeds just looks like an ordinary success.
  final bool? widened;

  /// The protocol of the last server tried. Sessions have always carried one
  /// and failures never did, so "which protocols fail here" could only ever
  /// be answered for the ones that worked.
  final String? protocol;
}
