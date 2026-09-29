import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/public_ip.dart';
import '../../domain/tunnel_snapshot.dart';
import 'tunnel_provider.dart';

/// What this phone looks like from outside when nothing is tunnelling it: the
/// address, and the country it is in.
typedef OwnEgress = ({String ip, String? country});

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

  @override
  Future<OwnEgress?> build() async {
    final phase = ref.watch(tunnelSnapshotProvider.select((s) => s.phase));
    if (phase != TunnelPhase.idle && phase != TunnelPhase.failed) return _last;
    final reading = await PublicIp.read();
    // A failed reading keeps the previous one rather than blanking the card:
    // the address has not changed just because a probe timed out.
    if (reading != null) _last = reading;
    return _last;
  }

  /// For a manual retry; the automatic path is the phase change above.
  Future<void> refresh() async {
    state = const AsyncLoading<OwnEgress?>().copyWithPrevious(state);
    final reading = await PublicIp.read();
    if (reading != null) _last = reading;
    state = AsyncData<OwnEgress?>(_last);
  }
}
