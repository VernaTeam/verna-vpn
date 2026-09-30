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
}

/// What the tunnel layer knows about a connect that produced nothing.
class TunnelFailedFacts {
  const TunnelFailedFacts({
    required this.reason,
    required this.picked,
    required this.candidatesTried,
    required this.gaveUpAfterS,
    this.askedCountry,
  });

  final FailReason reason;
  final PickedBy picked;
  final int candidatesTried;
  final int gaveUpAfterS;
  final String? askedCountry;
}
