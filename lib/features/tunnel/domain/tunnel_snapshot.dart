import '../../configs/domain/vpn_config.dart';

/// What the tunnel is doing right now.
///
/// [searching] is not a cosmetic in-between state. Most configs in the
/// inventory are dead at any moment, so connecting means trying several in a
/// row and can take from a few seconds to a minute. Hiding that behind a
/// spinner makes the app look frozen, so the phase carries real progress.
enum TunnelPhase {
  /// Nothing running.
  idle,

  /// Fetching candidates and asking for VPN permission.
  preparing,

  /// Trying candidates one by one, verifying each actually carries traffic.
  searching,

  /// A tunnel is up and was verified to move traffic.
  connected,

  /// Every candidate was tried and none worked.
  failed,
}

/// Why a connection attempt ended without a tunnel.
///
/// A value rather than a message: the service that detects these has no
/// business holding user-facing text, and the app ships in two languages.
enum TunnelFailure {
  none,

  /// The user declined Android's VPN consent dialog.
  permissionDenied,

  /// Android refused VPN permission without showing the dialog at all.
  ///
  /// Told apart from [permissionDenied] by time: the refusal came back in
  /// under a second, faster than anyone can read a system dialog and dismiss
  /// it. Over eight days of 1.0.8, 38 permission failures from 5 installs all
  /// had `gave_up_after_s = 0` -- people were not declining, Android was. The
  /// usual cause is another VPN app set to Always-on, which makes Android
  /// refuse every other app silently. "Permission denied" told those users
  /// nothing they could act on.
  permissionBlocked,

  /// The phone has no Wi-Fi and no mobile data, so there is nothing to
  /// search. Said at once rather than discovered after a full search.
  noInternet,

  /// The server list could not be fetched at all.
  fetchFailed,

  /// The list came back, but nothing in it was worth trying.
  noCandidates,

  /// Everything was tried and none of it carried traffic.
  noneAnswered,

  /// Candidates verified through the proxy, but the tunnel itself kept
  /// failing -- retrying the same ones will not help.
  unstable,

  /// Something threw. [TunnelSnapshot.errorDetail] carries the text.
  error,
}

/// An immutable view of the tunnel for the UI to render.
class TunnelSnapshot {
  const TunnelSnapshot({
    this.phase = TunnelPhase.idle,
    this.failure = TunnelFailure.none,
    this.errorDetail,
    this.attempt = 0,
    this.total = 0,
    this.checked = 0,
    this.uploadTotal = 0,
    this.downloadTotal = 0,
    this.active,
    this.exitIp,
    this.exitCountryCode,
    this.duration = '00:00:00',
    this.uploadSpeed = 0,
    this.downloadSpeed = 0,
    this.pingMs,
  });

  final TunnelPhase phase;

  /// Set when [phase] is [TunnelPhase.failed]. The UI turns it into words.
  final TunnelFailure failure;

  /// Raw exception text for [TunnelFailure.error]; never shown on its own.
  final String? errorDetail;

  /// Progress through the candidate list, 1-based. Zero when not searching.
  final int attempt;
  final int total;

  /// How many candidates have finished their probe.
  ///
  /// [attempt] only moves when a server is actually tried, and most of a
  /// search happens before that: the probe rounds, which on a slow network
  /// are the whole wait. So the counter read "0/132" for twenty seconds and
  /// the ring sat empty, and people gave up -- `cancelled` was the second
  /// failure reason on 1.0.8, 96 of 374, at 23 seconds, with only one server
  /// tried on average. This lets the screen show the work it is doing.
  final int checked;

  /// Bytes moved since this tunnel came up, as the core counts them.
  ///
  /// Separate from the speeds because they answer different questions: the
  /// speed says whether anything is happening now, the total says whether the
  /// session did anything at all.
  final int uploadTotal;
  final int downloadTotal;

  /// The config the tunnel is currently running on.
  final VpnConfig? active;

  /// Where traffic actually leaves, measured after connecting rather than
  /// taken from the config's metadata. The two disagree often: a config
  /// labelled Philippines was measured exiting in Turkey.
  final String? exitIp;
  final String? exitCountryCode;

  /// Live counters from the core.
  final String duration;
  final int uploadSpeed;
  final int downloadSpeed;

  /// Latency of the winning config, as measured during selection.
  final int? pingMs;

  bool get isConnected => phase == TunnelPhase.connected;
  bool get isBusy =>
      phase == TunnelPhase.preparing || phase == TunnelPhase.searching;

  /// Country to show. Prefers what was measured through the tunnel and falls
  /// back to the config's own label.
  String? get displayCountryCode => exitCountryCode ?? active?.countryCode;

  TunnelSnapshot copyWith({
    TunnelPhase? phase,
    TunnelFailure? failure,
    String? errorDetail,
    int? attempt,
    int? total,
    int? checked,
    int? uploadTotal,
    int? downloadTotal,
    VpnConfig? active,
    String? exitIp,
    String? exitCountryCode,
    String? duration,
    int? uploadSpeed,
    int? downloadSpeed,
    int? pingMs,
    bool clearActive = false,
    bool clearExit = false,
  }) {
    return TunnelSnapshot(
      phase: phase ?? this.phase,
      failure: failure ?? this.failure,
      errorDetail: errorDetail ?? this.errorDetail,
      attempt: attempt ?? this.attempt,
      total: total ?? this.total,
      checked: checked ?? this.checked,
      uploadTotal: uploadTotal ?? this.uploadTotal,
      downloadTotal: downloadTotal ?? this.downloadTotal,
      active: clearActive ? null : (active ?? this.active),
      exitIp: clearExit ? null : (exitIp ?? this.exitIp),
      exitCountryCode: clearExit ? null : (exitCountryCode ?? this.exitCountryCode),
      duration: duration ?? this.duration,
      uploadSpeed: uploadSpeed ?? this.uploadSpeed,
      downloadSpeed: downloadSpeed ?? this.downloadSpeed,
      pingMs: pingMs ?? this.pingMs,
    );
  }
}
