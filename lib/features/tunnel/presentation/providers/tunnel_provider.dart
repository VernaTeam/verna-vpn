import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../configs/data/config_repository.dart';
import '../../../configs/domain/vpn_config.dart';
import '../../../configs/presentation/providers/configs_provider.dart';
import '../../../configs/presentation/providers/local_test_provider.dart';
import '../../data/candidate_selector.dart';
import '../../data/preferred_country_store.dart';
import '../../data/tunnel_service.dart';
import '../../data/network_status.dart';
import '../../../reports/data/report_queue.dart';
import '../../../subscriptions/presentation/builtin_subscriptions_provider.dart';
import '../../../subscriptions/presentation/user_subscriptions_provider.dart';
import '../../domain/local_test.dart';
import '../../domain/tunnel_snapshot.dart';

final tunnelServiceProvider = Provider<TunnelService>((ref) {
  final service = TunnelService();
  // A real connection is the strongest evidence the app has about a server,
  // so its outcome is reported like the list's own test (see ReportSink).
  service.onTunnelResult =
      (config, stage, outcome, ms, asn) => ref.read(reportSinkProvider).submit(
            results: [(config: config, outcome: outcome, ms: ms)],
            stage: stage,
            asn: asn,
          );
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
    // A restored tunnel that stopped carrying traffic is replaced the way it
    // was made: the hand-picked server again, or a fresh automatic search.
    service.onRestoredTunnelDead =
        (saved) => saved.userChose ? connectTo(saved.config) : connect();
    ref.onDispose(() => service.onRestoredTunnelDead = null);
    // The tunnel can already be up from a previous run of this screen -- or of
    // this process. Ask, rather than assuming a fresh start means disconnected.
    Future.microtask(() async {
      // The country the user picked last time, before anything tries to
      // connect: a restored preference that arrives after the first connect
      // would be a preference the app ignored once and then obeyed.
      final saved = await PreferredCountryStore.load();
      if (saved != null && ref.read(preferredCountryProvider) == null) {
        ref.read(preferredCountryProvider.notifier).state = saved;
      }
      await service.restore();
      // Reports queued in an earlier session go out now if no tunnel is
      // up -- on the phone's own network (see ReportSink.flush).
      await ref.read(reportSinkProvider).flush();
    });
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
    // The automatic path, so it clears any earlier hand-picked server rather
    // than silently keeping it. The home screen's button and "Try again" go
    // through [retry], which only comes here when nothing was picked.
    ref.read(chosenServerProvider.notifier).state = null;
    final service = ref.read(tunnelServiceProvider);
    final repository = ref.read(repositoryProvider);
    final country = ref.read(preferredCountryProvider);

    state = state.copyWith(phase: TunnelPhase.preparing);

    // Before the server list is fetched: offline, that fetch is what took
    // two minutes, working through retries and eight Cloudflare edges to
    // reach an API over a network that was not there.
    if (!await NetworkStatus.hasInternet()) {
      state = state.copyWith(
        phase: TunnelPhase.failed,
        failure: TunnelFailure.noInternet,
      );
      return;
    }

    try {
      // Whatever this device has already proved goes first.
      //
      // Without this the connect button threw away the answer the app had
      // just spent thirty seconds measuring: the list showed thirteen servers
      // confirmed working from this phone, Connect started a fresh search of
      // its own, and reported "none of the 21 servers responded". Two
      // measurements of the same pool minutes apart, and the app believed the
      // one that had not been taken yet.
      // The user's own subscriptions go first: someone who added a link of
      // their own wants it used. And they do not depend on Verna's API -- if
      // the pool cannot be fetched, the user's servers are still worth trying
      // rather than reporting that the list is unreachable.
      final mine = _userCandidates(country);
      final proven = _provenCandidates(country);
      List<VpnConfig> configs;
      try {
        configs = await _fetchCandidates(repository, country);
      } catch (_) {
        if (mine.isEmpty) rethrow;
        configs = const [];
      }
      // The verified list is not filtered by source on the server; a list the
      // user switched off stays off here too.
      final off = ref.read(builtInSubscriptionsProvider).disabled;
      final searched = const CandidateSelector().select(
        [
          for (final c in configs)
            if (c.builtInSubId == null || !off.contains(c.builtInSubId)) c,
        ],
        limit: _attempts,
        preferredCountry: country,
      );

      // The searched list still follows, because a proven server can have
      // died since it was measured and the fallback is what makes that
      // survivable.
      final seen = <String>{};
      final candidates = [
        for (final config in [...mine, ...proven, ...searched])
          if (seen.add(config.id)) config,
      ];
      // The country goes to the service too, not just into the candidate
      // list: the service consults its own memory of what worked on this
      // network first, and that memory has no idea what the user just asked
      // for unless it is told.
      await service.connect(candidates, preferredCountry: country);
      unawaited(ref.read(reportSinkProvider).flush());
    } catch (e) {
      state = state.copyWith(
        phase: TunnelPhase.failed,
        failure: TunnelFailure.fetchFailed,
      );
    }
  }

  /// The user's own servers: those this device found working, fastest
  /// first, then those not tested yet. Tested and broken ones are left out.
  List<VpnConfig> _userCandidates(String? country) {
    final mine = ref.read(userConfigsProvider);
    if (mine.isEmpty) return const [];
    final results = ref.read(localTestResultsProvider);
    final working = <({VpnConfig config, int ms})>[];
    final untested = <VpnConfig>[];
    for (final config in mine) {
      if (country != null &&
          country.isNotEmpty &&
          config.countryCode != country) {
        continue;
      }
      final result = results[config.id];
      if (result == null) {
        untested.add(config);
      } else if (result.works) {
        working.add((config: config, ms: result.milliseconds ?? 1 << 30));
      }
    }
    working.sort((a, b) => a.ms.compareTo(b.ms));
    return [
      for (final entry in working) entry.config,
      ...untested,
    ].take(_attempts).toList();
  }

  /// Configs this device measured as working, fastest first.
  ///
  /// Read from the local test results rather than re-measured: they were taken
  /// on this phone, on this network, which is a stronger claim than anything
  /// the server can make about the same config.
  List<VpnConfig> _provenCandidates(String? country) {
    final results = ref.read(localTestResultsProvider);
    if (results.isEmpty) return const [];

    final pool = ref.read(vernaTextConfigsProvider);
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
    working.sort((a, b) {
      // Measured dropping concurrent flows: after the rest, however fast.
      final weak = a.config.weakUnderLoad == b.config.weakUnderLoad
          ? 0
          : a.config.weakUnderLoad
              ? 1
              : -1;
      return weak != 0 ? weak : a.ms.compareTo(b.ms);
    });
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
    final service = ref.read(tunnelServiceProvider);
    await service.connect([config], userChose: true);
    unawaited(ref.read(reportSinkProvider).flush());

    // A server picked from the list because it tested green, and then carried
    // nothing, must not stay green. Measured on a J7 on 2026-09-13: rows
    // tested minutes earlier failed when chosen -- one had stopped accepting
    // connections, one was too slow to answer in time, and a family of
    // Trojan-REALITY servers passed the probe but carried nothing in the
    // tunnel -- and the list went on inviting a second tap at each of them.
    // Only a failure that is the server's: no internet or a refused VPN
    // permission says nothing about it.
    final after = service.snapshot;
    if (after.phase == TunnelPhase.failed &&
        after.failure == TunnelFailure.noneAnswered) {
      ref
          .read(localTestResultsProvider.notifier)
          .record(config.id, const LocalTest.noTraffic());
    }
  }

  /// Tries again the way the last attempt was made.
  ///
  /// "Try again" and the connect button both called [connect], which clears
  /// the hand-picked server first: a user whose chosen server failed pressed
  /// Try again and got an automatic search instead of a second attempt at the
  /// server they had chosen. The card under the button names the server that
  /// will be used, so the button now uses that one.
  Future<void> retry() {
    final chosen = ref.read(chosenServerProvider);
    return chosen != null ? connectTo(chosen) : connect();
  }

  Future<void> disconnect() async {
    await ref.read(tunnelServiceProvider).disconnect();
    // Reports gathered while connected waited for this.
    unawaited(ref.read(reportSinkProvider).flush());
  }
}
