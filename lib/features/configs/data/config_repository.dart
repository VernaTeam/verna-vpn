import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/vpn_config.dart';
import 'config_api_client.dart';
import 'seed_configs.dart';

const _kTextCacheKey = 'cache_text_configs';
const _kFileCacheKey = 'cache_file_configs';
const _kCacheTimeKey = 'cache_time';
const _kCacheTtlMinutes = 15;

/// The last verified page that arrived, kept for when the API cannot be
/// reached at all. Never used while the network works.
const _kVerifiedCacheKey = 'cache_verified_configs';

class ConfigRepository {
  final ConfigApiClient _api;

  ConfigRepository(this._api);

  Future<ConfigsPage> getTextConfigs({
    String type = 'all',
    int limit = 50,
    int offset = 0,
    bool forceRefresh = false,
  }) async {
    try {
      final page = await _api.getTextConfigs(
        type: type,
        limit: limit,
        offset: offset,
      );
      if (offset == 0) await _cacheConfigs(_kTextCacheKey, page);
      return page;
    } catch (e) {
      if (offset == 0 && !forceRefresh) {
        final cached = await _loadCached(_kTextCacheKey);
        if (cached != null) return cached;
        final seeded = await SeedConfigs.page(type: type, limit: limit);
        if (seeded != null) return seeded;
      }
      rethrow;
    }
  }

  Future<ConfigsPage> getFileConfigs({
    String type = 'all',
    int limit = 50,
    int offset = 0,
    bool forceRefresh = false,
  }) async {
    try {
      final page = await _api.getFileConfigs(
        type: type,
        limit: limit,
        offset: offset,
      );
      if (offset == 0) await _cacheConfigs(_kFileCacheKey, page);
      return page;
    } catch (e) {
      if (offset == 0 && !forceRefresh) {
        final cached = await _loadCached(_kFileCacheKey);
        if (cached != null) return cached;
      }
      rethrow;
    }
  }

  /// Server-verified configs, with a cache that only exists for the case
  /// where the API cannot be reached.
  ///
  /// The freshness of this list is the whole point of the endpoint, so the
  /// cache is never preferred and never merged in -- it is what the app falls
  /// back to when the alternative is an empty screen. Measured on a J7 whose
  /// connection could not resolve vernaservice.ir while this machine could:
  /// without the fallback the app showed nothing, said nothing, and waited.
  ///
  /// Staleness is affordable here in a way it would not be elsewhere, because
  /// every row is re-tested on the device before a ping is shown.
  Future<ConfigsPage> getVerifiedConfigs({
    String type = 'all',
    String? country,
    int maxAgeHours = 24,
    int limit = 50,
  }) async {
    try {
      final page = await _api.getVerifiedConfigs(
        type: type,
        country: country,
        maxAgeHours: maxAgeHours,
        limit: limit,
      );
      // Only the unfiltered call is worth keeping: a cache of "vless in
      // Germany" would answer a question nobody asks twice.
      if (country == null && page.configs.isNotEmpty) {
        await _cacheAppend(_kVerifiedCacheKey, type, page);
      }
      return page;
    } catch (_) {
      final cached = await _loadVerifiedCache(type);
      if (cached != null) return cached;
      // Nothing cached either: a first launch on a network that blocks the
      // API. Fall through to what shipped with the build rather than telling
      // the user there are no servers, which was never true -- the server was
      // up the whole time, behind an address this connection cannot use.
      final seeded = await SeedConfigs.page(type: type, limit: limit);
      if (seeded != null) return seeded;
      rethrow;
    }
  }

  /// Keeps one page per protocol, so a fallback covers the same spread the
  /// live sample does rather than 300 rows of whichever protocol asked last.
  Future<void> _cacheAppend(String key, String type, ConfigsPage page) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      final Map<String, dynamic> byType =
          raw == null ? {} : (jsonDecode(raw) as Map).cast<String, dynamic>();
      byType[type] = {
        'total': page.total,
        'configs': page.configs.map(_configToMap).toList(),
      };
      await prefs.setString(key, jsonEncode(byType));
    } catch (_) {
      // A cache that cannot be written is not a reason to fail a fetch.
    }
  }

  Future<ConfigsPage?> _loadVerifiedCache(String type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kVerifiedCacheKey);
      if (raw == null) return null;
      final byType = (jsonDecode(raw) as Map).cast<String, dynamic>();
      final entry = byType[type];
      if (entry is! Map) return null;
      final list = (entry['configs'] as List?) ?? const [];
      if (list.isEmpty) return null;
      return ConfigsPage(
        total: (entry['total'] as int?) ?? list.length,
        configs: [
          for (final item in list)
            if (item is Map<String, dynamic>) _configFromMap(item),
        ],
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<VerifiedCountry>> getVerifiedCountries({int maxAgeHours = 24}) =>
      _api.getVerifiedCountries(maxAgeHours: maxAgeHours);

  Future<ConfigStats> getStats() => _api.getStats();

  // ---------------------------------------------------------------------------
  // Cache helpers
  // ---------------------------------------------------------------------------

  Future<void> _cacheConfigs(String key, ConfigsPage page) async {
    final prefs = await SharedPreferences.getInstance();
    final data = {
      'total': page.total,
      'configs': page.configs.map(_configToMap).toList(),
    };
    await prefs.setString(key, jsonEncode(data));
    await prefs.setString(_kCacheTimeKey, DateTime.now().toIso8601String());
  }

  Future<ConfigsPage?> _loadCached(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;

    final timeRaw = prefs.getString(_kCacheTimeKey);
    if (timeRaw != null) {
      final cached = DateTime.tryParse(timeRaw);
      if (cached != null) {
        final age = DateTime.now().difference(cached);
        if (age.inMinutes > _kCacheTtlMinutes) return null;
      }
    }

    try {
      final d = jsonDecode(raw) as Map<String, dynamic>;
      final configs = (d['configs'] as List)
          .map((e) => _configFromMap(e as Map<String, dynamic>))
          .toList();
      return ConfigsPage(total: d['total'] as int, configs: configs);
    } catch (_) {
      return null;
    }
  }

  // The row's own JSON, same keys as before plus what was added since -- the
  // built-in subscription id among them, without which a switched-off list's
  // servers would come back through the fallback cache.
  Map<String, dynamic> _configToMap(VpnConfig c) => c.toJson();

  VpnConfig _configFromMap(Map<String, dynamic> m) => VpnConfig.fromJson(m);
}
