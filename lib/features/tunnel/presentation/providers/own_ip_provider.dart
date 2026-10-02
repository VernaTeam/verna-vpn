import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/public_ip.dart';
import '../../domain/tunnel_snapshot.dart';
import 'tunnel_provider.dart';

/// What this phone looks like from outside when nothing is tunnelling it: the
/// address, and the country it is in.
typedef OwnEgress = ({String ip, String? country, String? asn});

/// The phone's own public address, kept only while nothing is tunnelling.
///
/// Watches the tunnel's *phase*, not the whole snapshot: the snapshot changes
/// every second with the traffic counters, and rebuilding on that would put an
/// HTTP request on a one-second timer.
///
/// While connected or connecting it holds whatever it last read rather than
/// measuring: a reading taken through the tunnel would be the exit address,
/// labelled as the user's own.
final ownIpProvider = AsyncNotifierProvider<OwnIpNotifier, OwnEgress?>(
  OwnIpNotifier.new,
);

class OwnIpNotifier extends AsyncNotifier<OwnEgress?> {
  OwnEgress? _last;
  Timer? _retry;

  /// How many times to come back after a reading that could not be taken.
  ///
  /// The usual reason is a VPN network still up -- Verna's own, for the
  /// seconds Android keeps it alive after a stop, or another app's. Reading
  /// then would print that exit as the user's own address, so [PublicIp]
  /// refuses; without a retry the card simply stayed empty for the rest of
  /// the session, which is what it did on the A54 after a disconnect.
  static const int _attempts = 3;
  static const Duration _retryAfter = Duration(seconds: 12);

  @override
  Future<OwnEgress?> build() async {
    ref.onDispose(() => _retry?.cancel());
    _retry?.cancel();
    final phase = ref.watch(tunnelSnapshotProvider.select((s) => s.phase));
    if (phase != TunnelPhase.idle && phase != TunnelPhase.failed) return _last;
    final reading = await PublicIp.read();
    // A failed reading keeps the previous one rather than blanking the card:
    // the address has not changed just because a probe timed out.
    if (reading != null) {
      _last = reading;
    } else {
      _schedule(1);
    }
    return _last;
  }

  void _schedule(int attempt) {
    if (attempt > _attempts) return;
    _retry?.cancel();
    _retry = Timer(_retryAfter, () async {
      final reading = await PublicIp.read();
      if (reading == null) {
        _schedule(attempt + 1);
        return;
      }
      _last = reading;
      state = AsyncData<OwnEgress?>(_last);
    });
  }

  /// For a manual retry; the automatic path is the phase change above.
  Future<void> refresh() async {
    state = const AsyncLoading<OwnEgress?>().copyWithPrevious(state);
    final reading = await PublicIp.read();
    if (reading != null) _last = reading;
    state = AsyncData<OwnEgress?>(_last);
  }
}
