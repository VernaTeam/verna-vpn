import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/diagnostics/data/app_log.dart';
import '../../../configs/domain/vpn_config.dart';
import '../../../tunnel/domain/local_test.dart';
import '../../../tunnel/presentation/providers/tunnel_provider.dart';
import '../providers/configs_provider.dart';
import '../providers/local_test_provider.dart';

/// Keeps the device's own measurements up to date, wherever the user is.
///
/// This used to live in the server-list screen, which was fine while that
/// screen was a tab: the list was where the numbers were shown. Aurora shows
/// them on the connect screen (healthy count, protocol, ping) and on every
/// country row in Locations, so the run can no longer depend on which tab
/// somebody opened. It sits in the shell instead and feeds all of them.
///
/// Renders nothing: it is state, wrapped in a widget so it lives and dies with
/// the shell.
class AutoTestRunner extends ConsumerStatefulWidget {
  const AutoTestRunner({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AutoTestRunner> createState() => _AutoTestRunnerState();
}

class _AutoTestRunnerState extends ConsumerState<AutoTestRunner> {
  /// Whether a run has ever started.
  ///
  /// Not a "never again" latch: rows arrive in waves -- a user's own
  /// subscriptions are in memory immediately, Verna's pool a moment later from
  /// the API -- and the first wave used to consume the only run there was.
  bool _started = false;

  /// How many untested rows have to appear before a second run is worth it.
  /// One or two late arrivals are not; three hundred are.
  static const int _minNewRows = 10;

  @override
  void initState() {
    super.initState();
    // After the first frame: the list has to exist before there is anything to
    // test, and the app should appear immediately rather than waiting on a
    // sweep of the whole inventory.
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  /// Starts a run unless one is already going, or a tunnel is up.
  ///
  /// Probing restarts the core, so testing while connected would drop the
  /// user's tunnel to answer a question about a list.
  void _run() {
    if (!mounted) return;
    final tunnel = ref.read(tunnelSnapshotProvider);
    // Busy as well as connected: a connect in progress has the core to
    // itself, and a test squeezed into the gap between two candidates ends by
    // stopping it.
    if (tunnel.isConnected || tunnel.isBusy) return;
    if (ref.read(localTestProgressProvider).running) return;

    final configs = ref.read(filteredConfigsProvider);
    if (configs.isEmpty) return;

    // Only what has no answer yet. Re-testing rows this device has already
    // measured would cost minutes and change nothing.
    final results = ref.read(localTestResultsProvider);
    final pending = configs.where((c) => !results.containsKey(c.id)).toList();
    if (pending.isEmpty) return;
    if (_started && pending.length < _minNewRows) return;

    _started = true;
    AppLog.instance.info('Auto-test starting',
        detail: '${pending.length} of ${configs.length} rows untested');
    ref.read(localTestResultsProvider.notifier).run(pending);
  }

  @override
  Widget build(BuildContext context) {
    // The moment there are rows, there is a run.
    ref.listen<List<VpnConfig>>(filteredConfigsProvider, (_, next) {
      if (next.isNotEmpty) _run();
    });

    // And again when a run ends: rows arrive in waves, and a run in progress
    // makes _run() return, so the late wave would otherwise sit untested until
    // somebody pressed the button.
    ref.listen<LocalTestProgress>(localTestProgressProvider, (previous, next) {
      if ((previous?.running ?? false) && !next.running) _run();
    });

    // A tunnel that goes down is the first chance to measure since it came up.
    ref.listen(tunnelSnapshotProvider, (previous, next) {
      if ((previous?.isConnected ?? false) && !next.isConnected) _run();
    });

    // `ref.listen` only reports changes, so a list that was already loaded
    // when the shell built would never trigger one. Cover that case directly.
    if (!_started && ref.read(filteredConfigsProvider).isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _run());
    }

    return widget.child;
  }
}
