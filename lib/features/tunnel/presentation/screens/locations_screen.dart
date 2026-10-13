import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app_shell.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/palette.dart';
import '../../../configs/domain/vpn_config.dart';
import '../../../configs/presentation/providers/configs_provider.dart';
import '../../../configs/presentation/providers/local_test_provider.dart';
import '../../../configs/presentation/screens/config_detail_screen.dart';
import '../../../configs/presentation/screens/home_screen.dart';
import '../../../configs/presentation/widgets/config_card.dart';
import '../../data/preferred_country_store.dart';
import '../../domain/local_test.dart';
import '../providers/tunnel_provider.dart';

/// Where the user picks where to come out.
///
/// A country, not a server. The inventory is thousands of disposable free
/// configs, most of them dead at any moment, so a flat list of servers is
/// mostly a list of things that will not work. What the app can honestly
/// offer is a country -- and, for anyone who wants it, that country's servers
/// one tap deeper.
///
/// The numbers on each row are this phone's own: the ping is what the device
/// measured through that server, not what a server in Germany measured. Two
/// measurements of the same config disagree often, and only one of them is
/// about the network the user is actually on.
class LocationsScreen extends ConsumerStatefulWidget {
  const LocationsScreen({super.key});

  @override
  ConsumerState<LocationsScreen> createState() => _LocationsScreenState();
}

class _LocationsScreenState extends ConsumerState<LocationsScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Picks a country and goes back to the connect screen, as the design has
  /// it. A tunnel that is already up is rebuilt, because the user just asked
  /// to be somewhere else and leaving them where they were would ignore that.
  void _choose(String? code) {
    ref.read(preferredCountryProvider.notifier).state = code;
    ref.read(chosenServerProvider.notifier).state = null;
    // Remembered, so tomorrow's first connect goes where the user chose
    // today rather than back to Automatic.
    PreferredCountryStore.save(code);
    final tunnel = ref.read(tunnelSnapshotProvider);
    ref.read(shellTabProvider.notifier).select(0);
    if (tunnel.isConnected || tunnel.isBusy) {
      ref.read(tunnelSnapshotProvider.notifier).connect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    final s = ref.watch(stringsProvider);
    final selected = ref.watch(preferredCountryProvider);
    final countries = ref.watch(verifiedCountriesProvider);
    final measured = _measurements();
    // The fastest country this phone has actually reached, which is what the
    // colours are judged against. Fixed thresholds do not survive contact with
    // an Iranian mobile network: the design's 45/90 ms painted every row rose,
    // and 90/180 did the same on a bad evening. Relative bands always say the
    // useful thing -- which of these is fast *for you, now*.
    final best = measured.values
        .map((m) => m.ping)
        .whereType<int>()
        .fold<int?>(null, (a, b) => a == null || b < a ? b : a);

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    s.tabLocations,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                // It already refreshed both halves -- the country list from
                // the server and the pings from this phone -- but it said so
                // nowhere, and the test takes a minute. Meysam, 2026-10-13:
                // "that refresh button does nothing". It did; it just worked
                // in silence, which from the outside is the same thing.
                _TestButton(
                  onRun: () {
                    ref.invalidate(verifiedCountriesProvider);
                    ref
                        .read(localTestResultsProvider.notifier)
                        .run(ref.read(filteredConfigsProvider));
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: TextField(
              controller: _search,
              onChanged: (value) => setState(() => _query = value.trim()),
              style: TextStyle(color: c.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: s.searchCountry,
                hintStyle: TextStyle(color: c.textMuted, fontSize: 14),
                prefixIcon: Icon(Icons.search, size: 20, color: c.textMuted),
                filled: true,
                fillColor: c.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: c.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: c.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: c.selectedBorder),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: _FastestRow(
              strings: s,
              selected: selected == null,
              onTap: () => _choose(null),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            // `.lbl`, including its Persian override: mono, tracked and
            // uppercased in English; plain Vazirmatn at 11.5 in Persian, where
            // letter-spacing breaks the joins between letters and there is no
            // such thing as uppercase.
            child: Builder(
              builder: (context) {
                final persian = s.lang == AppLang.fa;
                return Text(
                  persian ? s.allLocations : s.allLocations.toUpperCase(),
                  style: TextStyle(
                    fontFamily: persian ? VernaType.sans : VernaType.mono,
                    color: c.textFaint,
                    fontSize: persian ? 11.5 : 9.5,
                    fontWeight: FontWeight.w500,
                    letterSpacing: persian ? 0 : 1.52,
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: countries.when(
              loading: () => const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (_, __) => _Message(
                icon: Icons.cloud_off_rounded,
                text: s.msgFetchFailed,
                action: s.retry,
                onAction: () => ref.invalidate(verifiedCountriesProvider),
              ),
              data: (all) {
                final list = _sorted(_filter(all, _query), measured);
                if (list.isEmpty) {
                  return _Message(
                    icon: Icons.public_off_rounded,
                    text: all.isEmpty
                        ? s.noVerifiedCountries
                        : s.noSearchResults,
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(verifiedCountriesProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                    // One extra row at the end: the full list, with its
                    // search, its filters and its subscriptions strip. Picking
                    // a country covers what most people want, but the app's
                    // own inventory should not become unreachable because the
                    // list moved one level down.
                    itemCount: list.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      if (i == list.length) {
                        return _AllServersRow(
                          strings: s,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const HomeScreen(),
                            ),
                          ),
                        );
                      }
                      final country = list[i];
                      final local = measured[country.code];
                      return _CountryRow(
                        country: country,
                        strings: s,
                        pingMs: local?.ping,
                        bestMs: best,
                        working: local?.working ?? 0,
                        selected: country.code == selected,
                        onTap: () => _choose(country.code),
                        onOpenServers: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CountryServersScreen(
                              code: country.code,
                              name: s.countryName(country.code),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// The best latency this phone has measured per country, and how many of
  /// that country's servers actually carried traffic here.
  Map<String, ({int? ping, int working})> _measurements() {
    final results = ref.watch(localTestResultsProvider);
    if (results.isEmpty) return const {};

    // Walk the results, not the pool. Walking the pool meant a row measured
    // inside a country screen -- which fetches that country's own servers --
    // was invisible out here, because it is not a pool row. The controller
    // keeps the country beside each result; the pool is only a fallback for
    // ids recorded before it did.
    final countryOf = ref.read(localTestResultsProvider.notifier).countryById;
    final fromPool = {
      for (final config in ref.watch(vernaTextConfigsProvider))
        config.id: config.countryCode,
    };
    final out = <String, ({int? ping, int working})>{};
    for (final entry in results.entries) {
      final code = countryOf[entry.key] ?? fromPool[entry.key] ?? '';
      if (code.isEmpty) continue;
      final result = entry.value;
      if (!result.works) continue;
      final previous = out[code];
      final ms = result.milliseconds;
      final bestSoFar = previous?.ping;
      // A config can carry traffic without having produced a latency, so the
      // best-known ping survives a row that has none.
      final best = ms == null
          ? bestSoFar
          : bestSoFar == null
              ? ms
              : (ms < bestSoFar ? ms : bestSoFar);
      out[code] = (ping: best, working: (previous?.working ?? 0) + 1);
    }
    return out;
  }

  /// Countries this phone has measured first, fastest first.
  ///
  /// There was no sort here at all. The list came back in the API's order,
  /// which is by how many servers it holds, and the pings this phone had
  /// measured were drawn onto rows without ever moving them. So a country
  /// with 633 ms sat above one with 125 ms, and countries with no ping at all
  /// sat above every measured one -- which is what Meysam kept reporting, and
  /// what I kept fixing on the wrong screen: the sort I added on 2026-10-13
  /// was the one *inside* a country, not this.
  ///
  /// Three bands, in order:
  ///   - measured and working, by the latency measured here. The number on
  ///     the row and the row's position now say the same thing.
  ///   - working but with no latency yet: a server carried traffic, the
  ///     figure has not landed. Better than unknown, worse than a number.
  ///   - everything else, left in the API's order, which is by server count.
  ///     Unknown is not the same as bad, so these keep a sensible order of
  ///     their own rather than being shuffled.
  List<VerifiedCountry> _sorted(
    List<VerifiedCountry> all,
    Map<String, ({int? ping, int working})> measured,
  ) {
    int band(VerifiedCountry country) {
      final m = measured[country.code];
      if (m == null || m.working == 0) return 2;
      return m.ping == null ? 1 : 0;
    }

    final indexed = [
      for (var i = 0; i < all.length; i++) (country: all[i], at: i),
    ]..sort((a, b) {
        final byBand = band(a.country).compareTo(band(b.country));
        if (byBand != 0) return byBand;
        final pa = measured[a.country.code]?.ping;
        final pb = measured[b.country.code]?.ping;
        if (pa != null && pb != null && pa != pb) return pa.compareTo(pb);
        // Stable: equal rows keep the order they arrived in.
        return a.at.compareTo(b.at);
      });
    return [for (final e in indexed) e.country];
  }

  /// Matches on both the name and the code, so "NL" and "Netherlands" both
  /// find the same row.
  List<VerifiedCountry> _filter(List<VerifiedCountry> all, String query) {
    if (query.isEmpty) return all;
    final needle = query.toLowerCase();
    return all
        .where((c) =>
            c.name.toLowerCase().contains(needle) ||
            c.code.toLowerCase().contains(needle))
        .toList();
  }
}

/// The design's "Fastest server" row: no country, let the app decide.
class _FastestRow extends StatelessWidget {
  const _FastestRow({
    required this.strings,
    required this.selected,
    required this.onTap,
  });

  final S strings;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? c.selectedSurface : c.surface,
          border: Border.all(color: selected ? c.accent : c.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: c.accentSoft,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(Icons.bolt_rounded, size: 20, color: c.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.fastestServer,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    strings.fastestServerSub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.textFaint, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The way into the whole inventory: search, filters, protocol tabs and the
/// subscriptions strip, exactly as they were when that list was a tab.
class _AllServersRow extends StatelessWidget {
  const _AllServersRow({required this.strings, required this.onTap});

  final S strings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: c.surfaceSunken,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(19),
          ),
          child: Row(
            children: [
              Icon(Icons.dns_outlined, size: 19, color: c.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  strings.allServers,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: c.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountryRow extends StatelessWidget {
  const _CountryRow({
    required this.country,
    required this.strings,
    required this.pingMs,
    required this.bestMs,
    required this.working,
    required this.selected,
    required this.onTap,
    required this.onOpenServers,
  });

  final VerifiedCountry country;
  final S strings;
  final int? pingMs;

  /// The fastest country measured on this phone right now, or null before any
  /// test has finished.
  final int? bestMs;
  final int working;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onOpenServers;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    // The app's own name, not the pool's: the API writes English, and an
    // English country name inside a Persian row is both wrong to read and the
    // thing most likely to reorder in an RTL line.
    final name = strings.countryName(country.code);

    return Semantics(
      selected: selected,
      child: GestureDetector(
      onTap: onTap,
      child: Container(
        // `.listrow`: 14px 15px, radius 20, and a cyan border when selected.
        padding: const EdgeInsetsDirectional.fromSTEB(15, 14, 6, 14),
        decoration: BoxDecoration(
          color: selected ? c.selectedSurface : c.surface,
          border: Border.all(color: selected ? c.accent : c.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 31,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.chip,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                country.flag.isEmpty ? '🏳️' : country.flag,
                style: const TextStyle(fontSize: 19),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    // What this phone found comes first when it has looked;
                    // the server's count is the fallback, and it is a weaker
                    // claim -- it was measured from somewhere else.
                    working > 0
                        ? strings.healthyHere(working)
                        : strings.serversAvailable(country.count),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.textFaint, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (pingMs != null) ...[
              _SignalBars(
                strength: _strength(pingMs!),
                colour: _quality(c, pingMs!),
              ),
              const SizedBox(width: 8),
              _PingTag(milliseconds: pingMs!, colour: _quality(c, pingMs!)),
            ],
            const SizedBox(width: 6),
            // The way into the individual servers, for anyone who wants to
            // pick one by hand. A chevron rather than a second full-width
            // tap target: the row's job is choosing a country.
            Semantics(
              button: true,
              label: strings.allServersIn(name),
              // 48x48, which is Android's minimum for a thing a finger is
              // meant to hit. It was 32x40 -- measured on the J7 as 84x105
              // physical pixels at 2.625x -- and Meysam reported exactly what
              // that predicts: hard to land on. The faint disc is there for
              // the same reason; a bare chevron at the edge of a tappable row
              // does not read as a separate button, so people aimed at the
              // row and got the country selected instead.
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onOpenServers,
                child: Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.selectedSurface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.chevron_right_rounded,
                      size: 22, color: c.textSecondary),
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  /// Three bands against the fastest country this phone found.
  ///
  /// The design used 45 and 90 ms, which are European numbers: from an Iranian
  /// mobile network every row came back rose, and a colour that is always the
  /// same colour is not information. Relative to the best, "green" means near
  /// the best available tonight, which is the comparison someone scanning this
  /// list is actually making.
  Color _quality(VernaColors c, int ms) {
    final best = bestMs;
    if (best == null || best <= 0) return c.textMuted;
    if (ms <= best * 1.5) return c.ok;
    if (ms <= best * 3) return c.warn;
    return c.danger;
  }

  /// Bars follow the same three bands.
  int _strength(int ms) {
    final best = bestMs;
    if (best == null || best <= 0) return 1;
    if (ms <= best * 1.5) return 3;
    if (ms <= best * 3) return 2;
    return 1;
  }
}

class _PingTag extends StatelessWidget {
  const _PingTag({required this.milliseconds, required this.colour});

  final int milliseconds;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Text(
          '$milliseconds ms',
          style: TextStyle(
            fontFamily: VernaType.mono,
            color: colour,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

/// Three bars, filled by how this country compares with the best one tonight.
class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.strength, required this.colour});

  /// 1, 2 or 3.
  final int strength;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    // `.bars`: 3.5 wide, 2.5 apart, 6 / 9 / 12 tall.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 1; i <= 3; i++) ...[
          if (i > 1) const SizedBox(width: 2.5),
          Container(
            width: 3.5,
            height: 3.0 + i * 3,
            decoration: BoxDecoration(
              color: i <= strength ? colour : c.track,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ],
    );
  }
}

// The selected tick used to live here, a 22px disc between the ping and the
// chevron. Removed 2026-10-13: both rows already turn their surface and their
// border to the accent colour when selected, so the tick repeated something
// the row had already said -- and it sat hard against the chevron, which is
// what Meysam noticed. The row's own colour is the indicator now.
//
// Screen readers are told through Semantics(selected:) on the row instead,
// which is what that flag is for; they never depended on the drawing.

/// Every server the app knows about in one country.
///
/// Reached from the chevron on a country row. Same cards as the old server
/// list, so a config opened here behaves exactly as it did there -- including
/// the tap guard that stops a row moving under a finger mid-test.
class CountryServersScreen extends ConsumerWidget {
  const CountryServersScreen({
    super.key,
    required this.code,
    required this.name,
  });

  final String code;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.verna;
    final s = ref.watch(stringsProvider);
    final results = ref.watch(localTestResultsProvider);
    // What the API has in this country, which is what the row's count
    // promised. The app's own pool is the fallback while that is in flight or
    // if it fails -- a short list beats an empty screen.
    final fetched = ref.watch(countryConfigsProvider(code));
    final pool = ref
        .watch(vernaTextConfigsProvider)
        .where((config) => config.countryCode == code)
        .toList();
    final loading = fetched.isLoading && pool.isEmpty;
    final seen = <String>{};
    final configs = [
      for (final config in [...?fetched.valueOrNull, ...pool])
        if (seen.add(config.id)) config,
    ]..sort((a, b) => _rank(results, a).compareTo(_rank(results, b)));

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        foregroundColor: c.textPrimary,
        elevation: 0,
        title: Text(name, style: const TextStyle(fontSize: 17)),
        // The same manual test as the locations list, scoped to this country.
        // Asked for by Meysam on 2026-10-13: open Germany, test it yourself,
        // take whichever answered. Re-measuring rows that already have a
        // number is the point -- a server that worked ten minutes ago is a
        // claim about ten minutes ago.
        actions: [
          _TestButton(
            onRun: () {
              ref.invalidate(countryConfigsProvider(code));
              ref.read(localTestResultsProvider.notifier).run(configs);
            },
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : configs.isEmpty
          ? _Message(icon: Icons.public_off_rounded, text: s.noSearchResults)
          : _CountryTestRunner(
              configs: configs,
              child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
              itemCount: configs.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ConfigCard(
                  key: ValueKey(configs[i].id),
                  config: configs[i],
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ConfigDetailScreen(config: configs[i]),
                    ),
                  ),
                ),
              ),
              ),
            ),
    );
  }

  /// Working servers first, fastest of those at the top, untested after them,
  /// and the ones this phone proved broken at the bottom.
  ///
  /// The untested middle used to be one flat band, so every row this phone
  /// had not reached yet sat in whatever order the API returned -- which is
  /// no order at all to a user looking at a country's list. They are now
  /// ordered among themselves by the server's **tunnel-verified** latency,
  /// which is a real measurement of a real connection, just not from here.
  /// It never outranks anything this phone measured itself, and a row with
  /// only a TCP ping is not treated as measured at all: a CDN edge answers
  /// that whether or not the proxy behind it is alive.
  int _rank(Map<String, LocalTest> results, VpnConfig config) {
    final result = results[config.id];
    if (result != null) {
      if (!result.works) return 1000000;
      return result.milliseconds ?? 90000;
    }
    if (config.hasMeasuredPing) return 100000 + config.pingMs!.clamp(0, 59999);
    return 200000;
  }
}

/// Measures one country's servers when the user opens that country.
///
/// The shell's [AutoTestRunner] sweeps the *filtered* list, which is the one
/// behind the Home screen, and it works through it in runs of four hundred
/// that any connect cancels. A country opened from Locations is therefore
/// usually a screen of rows that say "Not tested" -- which is exactly what
/// Meysam asked about on 2026-10-07: thousands of configs and a handful of
/// numbers.
///
/// This asks the same question for the rows actually on screen, which is a
/// far smaller set and finishes in seconds. The guards are the shell
/// runner's, for the same reasons: probing restarts the core, so it must
/// never run while a tunnel is up or a connect is in flight.
class _CountryTestRunner extends ConsumerStatefulWidget {
  const _CountryTestRunner({required this.configs, required this.child});

  final List<VpnConfig> configs;
  final Widget child;

  @override
  ConsumerState<_CountryTestRunner> createState() => _CountryTestRunnerState();
}

class _CountryTestRunnerState extends ConsumerState<_CountryTestRunner> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // After the first frame, so opening the country is instant and the
    // measuring happens behind the list the user is already reading.
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  void _run() {
    if (!mounted || _started) return;
    final tunnel = ref.read(tunnelSnapshotProvider);
    if (tunnel.isConnected || tunnel.isBusy) return;
    if (ref.read(localTestProgressProvider).running) return;

    final results = ref.read(localTestResultsProvider);
    final pending = [
      for (final config in widget.configs)
        if (!results.containsKey(config.id)) config,
    ];
    if (pending.isEmpty) return;

    _started = true;
    ref.read(localTestResultsProvider.notifier).run(pending);
  }

  @override
  Widget build(BuildContext context) {
    // A run already going when the screen opened has to finish first; this
    // country's rows are measured the moment it does.
    ref.listen<LocalTestProgress>(localTestProgressProvider, (previous, next) {
      if ((previous?.running ?? false) && !next.running) _run();
    });
    // And a tunnel coming down is the first chance to measure since it went
    // up, for a user who connected, disconnected and came back to the list.
    ref.listen(tunnelSnapshotProvider, (previous, next) {
      if ((previous?.isConnected ?? false) && !next.isConnected) _run();
    });
    return widget.child;
  }
}

/// Runs the on-device test, and shows that it is running.
///
/// The progress comes from [localTestProgressProvider], which the run already
/// published for the connect screen; this only puts it where the button is.
/// While a run is going the icon becomes a spinner with "Testing 42 of 150",
/// so the minute it takes reads as work rather than as a dead control.
///
/// Disabled while a tunnel is up, because probing restarts the core and would
/// drop the user's connection to answer a question about a list. It says why
/// rather than simply not responding.
class _TestButton extends ConsumerWidget {
  const _TestButton({required this.onRun});

  final VoidCallback onRun;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.verna;
    final s = ref.watch(stringsProvider);
    final progress = ref.watch(localTestProgressProvider);
    final tunnel = ref.watch(tunnelSnapshotProvider);
    final busy = tunnel.isConnected || tunnel.isBusy;

    if (progress.running) {
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
            ),
            const SizedBox(width: 8),
            Text(
              s.testingProgress(progress.done, progress.total),
              style: TextStyle(color: c.textSecondary, fontSize: 11),
            ),
          ],
        ),
      );
    }

    return IconButton(
      tooltip: busy ? s.testBlockedWhileConnected : s.testServers,
      icon: Icon(Icons.refresh_rounded,
          color: busy ? c.textFaint : c.textSecondary),
      onPressed: busy
          ? () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(s.testBlockedWhileConnected)),
              )
          : onRun,
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: c.border),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textMuted, height: 1.7),
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: onAction, child: Text(action!)),
          ],
        ],
      ),
    );
  }
}
