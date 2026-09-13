import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diagnostics/data/app_log.dart';
import '../../../tunnel/domain/local_test.dart';
import '../../../tunnel/presentation/providers/tunnel_provider.dart';
import '../../domain/vpn_config.dart';
import 'configs_provider.dart';

/// Results of testing list entries from this device, keyed by config id.
///
/// Kept separate from the configs themselves: the config is what the server
/// said, this is what the phone found, and merging them would lose track of
/// which claim came from where.
final localTestResultsProvider =
    NotifierProvider<LocalTestController, Map<String, LocalTest>>(
        LocalTestController.new);

final localTestProgressProvider =
    NotifierProvider<LocalTestProgressController, LocalTestProgress>(
        LocalTestProgressController.new);

class LocalTestProgressController extends Notifier<LocalTestProgress> {
  @override
  LocalTestProgress build() => const LocalTestProgress();

  void set(LocalTestProgress next) => state = next;
}

class LocalTestController extends Notifier<Map<String, LocalTest>> {
  /// Upper bound on one run.
  ///
  /// Was 48, from when each batch of eight meant its own core start. sing-box
  /// measures a whole group in parallel -- 13 outbounds took 1.4s on the
  /// Galaxy J7 -- so the cap now only exists to bound a pathologically large
  /// inventory. It matters because every row the run does not reach shows
  /// "Not tested" beside rows that have a ping, which reads as a broken test:
  /// with 260 rows in the list, 212 of them said exactly that.
  static const int _limit = 400;

  @override
  Map<String, LocalTest> build() => const {};

  Future<void> run(List<VpnConfig> configs) async {
    final service = ref.read(tunnelServiceProvider);
    final progress = ref.read(localTestProgressProvider.notifier);
    // Only what the tunnel could actually carry. An MTProto proxy is handed to
    // Telegram, never run here, so testing one would mark it broken and the
    // filtered view below would then hide the very rows the Telegram filter
    // exists to show.
    final subject = configs
        .where((c) => tunnelableTypes.contains(c.type))
        .take(_limit)
        .toList();
    if (subject.isEmpty) return;
    AppLog.instance.info('Test run requested', detail: '${subject.length} rows');

    progress.set(LocalTestProgress(running: true, total: subject.length));
    final results = await service.testCandidates(
      subject,
      onProgress: (done, total, working) => progress.set(
        LocalTestProgress(
            running: true, done: done, total: total, working: working),
      ),
      // Published as each batch lands so the list reorders while the run is
      // still going. Waiting for the end meant staring at a stale order for
      // minutes and then watching it jump.
      onBatch: (partial) => state = {...state, ...partial},
    );

    // Merge rather than replace: a row tested in an earlier run keeps its
    // result until it is tested again.
    state = {...state, ...results};
    progress.set(LocalTestProgress(
      done: subject.length,
      total: subject.length,
      working: results.values.where((r) => r.works).length,
    ));
  }

  /// Replaces one row's result with what a real connection just found.
  ///
  /// A connection is a stronger test than the list's probe, and a newer one.
  void record(String id, LocalTest result) => state = {...state, id: result};

  void clear() {
    state = const {};
    ref.read(localTestProgressProvider.notifier).set(const LocalTestProgress());
  }
}

/// The list as the user should see it once the phone has had its say.
///
/// Three rules, in order:
///   - anything this device tested and found broken is dropped. Showing a row
///     with a 24ms badge that cannot pass a byte is worse than showing nothing,
///     and the whole point of testing here was to stop doing that.
///   - what works is sorted by the latency measured here, fastest first.
///   - rows the run never reached keep their place underneath. They are
///     unknown, not condemned.
final visibleConfigsProvider = Provider<List<VpnConfig>>((ref) {
  final configs = ref.watch(filteredConfigsProvider);
  // Re-sorted as each batch lands, which moves rows under a finger. The list
  // screen guards taps against that (see ConfigCard.tapGuard) rather than
  // freezing the order: frozen, a first run after launch kept the servers
  // that had just failed at the top for minutes, and the working ones
  // scattered below them.
  final results = ref.watch(localTestResultsProvider);
  if (results.isEmpty) return configs;

  // Two groups, each ordered the same way: the user's own subscriptions
  // first, then Verna's pool. Sorting them together would scatter a user's
  // servers through a list of hundreds and hide the ones they added on purpose.
  final mineWorking = <VpnConfig>[];
  final mineUntested = <VpnConfig>[];
  final working = <VpnConfig>[];
  final untested = <VpnConfig>[];
  for (final config in configs) {
    final mine = config.isFromUserSubscription;
    // Handoff rows are never tested and never hidden: whether Telegram can use
    // a proxy is Telegram's business, and this device cannot find out.
    if (handoffTypes.contains(config.type)) {
      (mine ? mineUntested : untested).add(config);
      continue;
    }
    final result = results[config.id];
    if (result == null) {
      (mine ? mineUntested : untested).add(config);
    } else if (result.works) {
      (mine ? mineWorking : working).add(config);
    }
    // Tested and broken: deliberately dropped.
  }

  int byLatency(VpnConfig a, VpnConfig b) {
    final left = results[a.id]?.milliseconds ?? 1 << 30;
    final right = results[b.id]?.milliseconds ?? 1 << 30;
    return left.compareTo(right);
  }

  mineWorking.sort(byLatency);
  working.sort(byLatency);

  return [...mineWorking, ...mineUntested, ...working, ...untested];
});
