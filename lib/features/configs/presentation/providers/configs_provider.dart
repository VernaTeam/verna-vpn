import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../diagnostics/data/app_log.dart';
import '../../data/config_api_client.dart';
import '../../data/config_repository.dart';
import '../../domain/vpn_config.dart';

final apiClientProvider = Provider<ConfigApiClient>((_) => ConfigApiClient());

final repositoryProvider = Provider<ConfigRepository>(
  (ref) => ConfigRepository(ref.read(apiClientProvider)),
);

enum TabFilter { all, text, file }

class FilterState {
  final TabFilter tab;

  /// Selected protocols; empty means every protocol.
  ///
  /// Holds the enum rather than a name. It used to hold strings, and the two
  /// sides spelled them differently: the chips sent the API's `tg_proxy` while
  /// this compared against Dart's `tgProxy`. Every other protocol spells the
  /// same both ways, so the only symptom was a Telegram filter that matched
  /// nothing -- a mismatch a type cannot express.
  final Set<VpnConfigType> typeFilter;

  /// Selected exit countries; empty means every country.
  final Set<String> countryFilter;
  final String query;

  const FilterState({
    this.tab = TabFilter.all,
    this.typeFilter = const {},
    this.countryFilter = const {},
    this.query = '',
  });

  /// Empty means "all". Keeping it that way rather than carrying a separate
  /// `allTypes` flag means the two can never disagree -- "All" is simply the
  /// state of having selected nothing.
  bool get isAllTypes => typeFilter.isEmpty;
  bool get isAllCountries => countryFilter.isEmpty;

  FilterState copyWith({
    TabFilter? tab,
    Set<VpnConfigType>? typeFilter,
    Set<String>? countryFilter,
    String? query,
  }) =>
      FilterState(
        tab: tab ?? this.tab,
        typeFilter: typeFilter ?? this.typeFilter,
        countryFilter: countryFilter ?? this.countryFilter,
        query: query ?? this.query,
      );
}

class FilterNotifier extends Notifier<FilterState> {
  @override
  FilterState build() => const FilterState();

  void setTab(TabFilter tab) => state = state.copyWith(tab: tab);

  /// Adds or removes one protocol. Selecting anything specific implicitly
  /// turns "All" off, because "All" is the empty selection.
  void toggleType(VpnConfigType type) {
    final next = Set<VpnConfigType>.from(state.typeFilter);
    if (!next.remove(type)) next.add(type);
    state = state.copyWith(typeFilter: next);
  }

  void toggleCountry(String code) {
    final next = Set<String>.from(state.countryFilter);
    if (!next.remove(code)) next.add(code);
    state = state.copyWith(countryFilter: next);
  }

  void clearTypes() => state = state.copyWith(typeFilter: const {});
  void clearCountries() => state = state.copyWith(countryFilter: const {});
  void setQuery(String q) => state = state.copyWith(query: q);
  void reset() => state = const FilterState();
}

final filterProvider =
    NotifierProvider<FilterNotifier, FilterState>(FilterNotifier.new);

class ConfigsState {
  final List<VpnConfig> textConfigs;
  final List<VpnConfig> fileConfigs;
  final ConfigStats? stats;
  final bool isLoading;
  final String? error;

  const ConfigsState({
    this.textConfigs = const [],
    this.fileConfigs = const [],
    this.stats,
    this.isLoading = false,
    this.error,
  });

  ConfigsState copyWith({
    List<VpnConfig>? textConfigs,
    List<VpnConfig>? fileConfigs,
    ConfigStats? stats,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) =>
      ConfigsState(
        textConfigs: textConfigs ?? this.textConfigs,
        fileConfigs: fileConfigs ?? this.fileConfigs,
        stats: stats ?? this.stats,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : error ?? this.error,
      );

  // Combined list, best quality first.
  List<VpnConfig> get allConfigs => [...textConfigs, ...fileConfigs]
    ..sort((a, b) => b.quality.compareTo(a.quality));
}

class ConfigsNotifier extends Notifier<ConfigsState> {
  @override
  ConfigsState build() {
    Future.microtask(load);
    return const ConfigsState(isLoading: true);
  }

  Future<void> load({bool forceRefresh = false}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    final repo = ref.read(repositoryProvider);
    try {
      // Show configs the server has seen carrying traffic, not the whole
      // inventory. The raw listing is mostly dead at any moment, so tapping
      // Connect on a random row usually failed -- which made the list look
      // broken when it was only being honest about a dead server.
      //
      // Falls back to the raw listing when nothing has been verified recently,
      // because an old list still beats an empty screen.
      final verified = await _verifiedSample(repo);
      final text = verified.isNotEmpty
          ? verified
          : (await repo.getTextConfigs(limit: 200, forceRefresh: forceRefresh))
              .configs;

      // No Telegram proxies. They are handed to Telegram rather than run
      // here, so they can never be tested, never carry the app's traffic, and
      // sat in the list as rows that looked like servers and were not. And no
      // file configs either -- .ovpn and friends, which this app cannot run.
      //
      // The inventory counter is fetched separately and allowed to fail. It
      // is a number in the diagnostics screen; letting it take the server list
      // down with it turned a working fallback into "Failed to load data" on
      // exactly the blocked networks the fallback exists for.
      final stats = await repo
          .getStats()
          .then<ConfigStats?>((value) => value)
          .catchError((Object _) => null);

      state = state.copyWith(
        textConfigs: text,
        stats: stats ?? state.stats,
        isLoading: false,
      );
    } catch (e) {
      // Logged, because the symptom on screen is an empty list and the cause
      // is invisible: the auto-test simply reports rows=0 forever and the app
      // looks broken rather than blocked.
      AppLog.instance.error('Config fetch failed', detail: '$e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> refresh() => load(forceRefresh: true);

  /// How many verified rows to ask for, per protocol.
  ///
  /// One undifferentiated page of 200 came back as 139 shadowsocks, 37 vless
  /// and 24 vmess -- the API's own ordering, not a shortage: the server held
  /// 708 verified vless at that moment. The device test then dropped whatever
  /// does not work from here, and a single vless row survived the whole
  /// journey, which read as the app barely having any. Asking per protocol
  /// makes the sample describe the inventory instead of its ordering.
  ///
  /// Roughly proportional to what the server actually verifies, with a floor
  /// so a scarce protocol still gets a hearing.
  static const Map<String, int> _quotas = {
    'vless': 120,
    'ss': 90,
    'vmess': 60,
    'hysteria': 40,
    'trojan': 30,
  };

  Future<List<VpnConfig>> _verifiedSample(ConfigRepository repo) async {
    final pages = await Future.wait(
      _quotas.entries.map(
        (e) => repo
            .getVerifiedConfigs(type: e.key, limit: e.value)
            .then((page) => page.configs)
            // One protocol failing must not empty the screen.
            .catchError((Object _) => const <VpnConfig>[]),
      ),
    );

    // Interleaved rather than concatenated: the list is sorted by measured
    // ping once the device test finishes, but until then it is shown in this
    // order, and 120 vless rows before the first shadowsocks reads as the
    // other protocols being missing again.
    final result = <VpnConfig>[];
    final seen = <String>{};
    for (var i = 0;; i++) {
      var added = false;
      for (final page in pages) {
        if (i >= page.length) continue;
        added = true;
        if (seen.add(page[i].id)) result.add(page[i]);
      }
      if (!added) break;
    }
    return result;
  }
}

final configsProvider =
    NotifierProvider<ConfigsNotifier, ConfigsState>(ConfigsNotifier.new);

final filteredConfigsProvider = Provider<List<VpnConfig>>((ref) {
  final state = ref.watch(configsProvider);
  final filter = ref.watch(filterProvider);

  List<VpnConfig> base = switch (filter.tab) {
    TabFilter.text => state.textConfigs,
    TabFilter.file => state.fileConfigs,
    TabFilter.all => state.allConfigs,
  };

  // Only what the app can act on. See `usableTypes`.
  base = base.where((c) => usableTypes.contains(c.type)).toList();

  if (filter.typeFilter.isNotEmpty) {
    base = base.where((c) => filter.typeFilter.contains(c.type)).toList();
  }
  if (filter.countryFilter.isNotEmpty) {
    base =
        base.where((c) => filter.countryFilter.contains(c.countryCode)).toList();
  }
  if (filter.query.isNotEmpty) {
    final q = filter.query.toLowerCase();
    base = base
        .where((c) =>
            c.country.toLowerCase().contains(q) ||
            c.type.label.toLowerCase().contains(q) ||
            c.countryCode.toLowerCase().contains(q))
        .toList();
  }
  return base;
});

final availableCountriesProvider =
    Provider<List<({String code, String name, String flag})>>((ref) {
  final state = ref.watch(configsProvider);
  final seen = <String>{};
  final result = <({String code, String name, String flag})>[];
  for (final c in [...state.textConfigs, ...state.fileConfigs]) {
    if (c.countryCode.isNotEmpty && seen.add(c.countryCode)) {
      result.add((code: c.countryCode, name: c.country, flag: c.flag));
    }
  }
  result.sort((a, b) => a.name.compareTo(b.name));
  return result;
});
