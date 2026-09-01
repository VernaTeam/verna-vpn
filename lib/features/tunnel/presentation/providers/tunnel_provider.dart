import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../configs/data/config_repository.dart';
import '../../../configs/domain/vpn_config.dart';
import '../../../configs/presentation/providers/configs_provider.dart';
import '../../../configs/presentation/providers/local_test_provider.dart';
import '../../data/candidate_selector.dart';
import '../../data/tunnel_service.dart';
import '../../domain/tunnel_snapshot.dart';

final tunnelServiceProvider = Provider<TunnelService>((ref) {
  final service = TunnelService();
  ref.onDispose(service.dispose);
  return service;
});

/// Exit countries that currently have configs verified through a real tunnel,
/// most-populated first.
///
/// autoDispose so reopening the picker asks again: the counts describe a moving
/// window, and a list cached from an hour ago would offer countries that no
/// longer have anything alive behind them.
final verifiedCountriesProvider =
    FutureProvider.autoDispose<List<VerifiedCountry>>((ref) {
  return ref.read(repositoryProvider).getVerifiedCountries();
});

/// The country the user asked to exit from, or null for "anywhere".
///
/// A preference, not a filter: a connection in the wrong country still beats
/// no connection, so the selector falls back rather than returning nothing.
final preferredCountryProvider = StateProvider<String?>((_) => null);

/// The server the user picked by hand, or null for automatic.
///
/// Kept beside the snapshot rather than inside it because it outlives a
/// connection: the home screen has to name the chosen server while preparing,
/// while connected, and after a failure. Without it the card read "Automatic"
/// however deliberately a row had been tapped.
final chosenServerProvider = StateProvider<VpnConfig?>((_) => null);

final tunnelSnapshotProvider =
    NotifierProvider<TunnelController, TunnelSnapshot>(TunnelController.new);

class TunnelController extends Notifier<TunnelSnapshot> {
  static const int _poolSize = 200;

  /// Deliberately more than the tunnel will ever get through. The TCP sweep in
  /// TunnelService removes the unreachable ones in parallel for roughly the
  /// cost of a single timeout, so a bigger shortlist buys more live servers
  /// without costing the user more waiting.
  static const int _attempts = 40;

  @override
  TunnelSnapshot build() {
    final service = ref.watch(tunnelServiceProvider);
    final sub = service.updates.listen((snapshot) => state = snapshot);
    ref.onDispose(sub.cancel);
    // The tunnel can already be up from a previous run of this screen -- or of
    // this process. Ask, rather than assuming a fresh start means disconnected.
    Future.microtask(service.restore);
    return service.snapshot;
  }

  /// Windows to ask the server for, freshest first.
  ///
  /// A config verified in the last two hours is far likelier to still work than
  /// one verified yesterday, but the two-hour list is short. So try the tight
  /// window first and widen only if it comes back too thin to bother trying.
  static const List<int> _freshnessWindows = [2, 6, 24];

  /// Below this, a window is not worth connecting with -- widen instead.
  static const int _minUsable = 8;

  /// Fetch a pool, narrow it to what is worth trying, and hand it to the
  /// tunnel.
  Future<void> connect() async {
    // Pressing the button on the home screen is the automatic path, so it
    // clears any earlier hand-picked server rather than silently keeping it.
    ref.read(chosenServerProvider.notifier).state = null;
    final service = ref.read(tunnelServiceProvider);
    final repository = ref.read(repositoryProvider);
    final country = ref.read(preferredCountryProvider);

    state = state.copyWith(phase: TunnelPhase.preparing);

    try {
      // Whatever this device has already proved goes first.
      //
      // Without this the connect button threw away the answer the app had
      // just spent thirty seconds measuring: the list showed thirteen servers
      // confirmed working from this phone, Connect started a fresh search of
      // its own, and reported "none of the 21 servers responded". Two
      // measurements of the same pool minutes apart, and the app believed the
      // one that had not been taken yet.
      final proven = _provenCandidates(country);
      final configs = await _fetchCandidates(repository, country);
      final searched = const CandidateSelector().select(
        configs,
        limit: _attempts,
        preferredCountry: country,
      );

      // The searched list still follows, because a proven server can have
      // died since it was measured and the fallback is what makes that
      // survivable.
      final seen = <String>{};
      final candidates = [
        for (final config in [...proven, ...searched])
          if (seen.add(config.id)) config,
      ];
      await service.connect(candidates);
    } catch (e) {
      state = state.copyWith(
        phase: TunnelPhase.failed,
        failure: TunnelFailure.fetchFailed,
      );
    }
  }

  /// Configs this device measured as working, fastest first.
  ///
  /// Read from the local test results rather than re-measured: they were taken
  /// on this phone, on this network, which is a stronger claim than anything
  /// the server can make about the same config.
  List<VpnConfig> _provenCandidates(String? country) {
    final results = ref.read(localTestResultsProvider);
    if (results.isEmpty) return const [];

    final pool = ref.read(configsProvider).textConfigs;
    final working = <({VpnConfig config, int ms})>[];
    for (final config in pool) {
      final result = results[config.id];
      if (result == null || !result.works) continue;
      if (country != null &&
          country.isNotEmpty &&
          config.countryCode != country) {
        continue;
      }
      working.add((config: config, ms: result.milliseconds ?? 1 << 30));
    }
    working.sort((a, b) => a.ms.compareTo(b.ms));
    return [for (final entry in working.take(_attempts)) entry.config];
  }

  /// Prefers server-verified configs, widening the freshness window until the
  /// list is worth using, and falls back to the raw inventory only if the
  /// verified endpoint has nothing at all.
  ///
  /// The fallback matters: the verification data comes from the bot's intake
  /// pipeline, so a quiet period upstream can leave the recent windows empty.
  /// A blind list is a much worse experience, but it is better than refusing
  /// to connect.
  Future<List<VpnConfig>> _fetchCandidates(
    ConfigRepository repository,
    String? country,
  ) async {
    for (final hours in _freshnessWindows) {
      final page = await repository.getVerifiedConfigs(
        country: country,
        maxAgeHours: hours,
        limit: _poolSize,
      );
      if (page.configs.length >= _minUsable) return page.configs;
      if (hours == _freshnessWindows.last && page.configs.isNotEmpty) {
        return page.configs;
      }
    }
    final page = await repository.getTextConfigs(limit: _poolSize);
    return page.configs;
  }

  /// Connect to one config the user picked from the list.
  ///
  /// Same machinery as [connect], with a list of one: it still verifies that
  /// traffic actually leaves through the tunnel before reporting success. What
  /// it deliberately does not do is quietly move on to a different server --
  /// the user asked for this one, so a failure is reported as a failure.
  Future<void> connectTo(VpnConfig config) async {
    ref.read(chosenServerProvider.notifier).state = config;
    state = state.copyWith(phase: TunnelPhase.preparing);
    await ref
        .read(tunnelServiceProvider)
        .connect([config], userChose: true);
  }

  Future<void> disconnect() => ref.read(tunnelServiceProvider).disconnect();
}
