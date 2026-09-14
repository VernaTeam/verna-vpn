import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'edge_router.dart';
import '../domain/vpn_config.dart';
import '../../subscriptions/data/builtin_subscription.dart';

/// Toggle to true to develop without a backend.
const bool _useMock = false;
const String apiBaseUrl = 'https://vernaservice.ir';
const String _apiV1 = '$apiBaseUrl/api/v1';

/// Country names arrive in their formal form -- "The Netherlands", "The United
/// States" -- while every other surface in the app uses the short name. Trim
/// the article so the list, the card and the notification agree.
String _tidyCountry(String? raw) =>
    (raw ?? '').replaceFirst(RegExp(r'^The '), '');

class ConfigApiClient {
  late final Dio _dio;

  ConfigApiClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: _apiV1,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        headers: {'Accept': 'application/json'},
      ),
    );
    _dio.interceptors.add(_RetryOnFlakyNetwork(this));
  }

  /// Points the client at a particular Cloudflare edge, or back at DNS.
  ///
  /// Only the socket's destination changes: the request URI, and therefore
  /// the TLS server name and the Host header, stay the real domain, so the
  /// certificate is validated exactly as before.
  void _routeVia(String? ip) {
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: ip == null
          ? null
          : () => EdgeRouter.clientVia(ip),
    );
  }

  Future<ConfigsPage> getTextConfigs({
    String type = 'all',
    int limit = 50,
    int offset = 0,
  }) async {
    if (_useMock) return _mockTextConfigs(limit: limit, offset: offset);
    final res = await _dio.get(
      '/configs/text',
      queryParameters: {'type': type, 'limit': limit, 'offset': offset},
    );
    return _parseTextPage(res.data as Map<String, dynamic>);
  }

  Future<ConfigsPage> getFileConfigs({
    String type = 'all',
    int limit = 50,
    int offset = 0,
  }) async {
    if (_useMock) return _mockFileConfigs(limit: limit, offset: offset);
    final res = await _dio.get(
      '/configs/files',
      queryParameters: {'type': type, 'limit': limit, 'offset': offset},
    );
    return _parseFilePage(res.data as Map<String, dynamic>);
  }

  /// Configs the server has seen carrying traffic recently.
  ///
  /// Prefer this over [getTextConfigs] for connecting. The plain listing is the
  /// whole inventory, most of which is dead at any moment, so the app ends up
  /// testing dozens of servers on the user's phone. This list was verified on
  /// the server by building a real tunnel through each one, so the phone can
  /// usually take the first entry and be done.
  ///
  /// [maxAgeHours] trades freshness for choice: 2h is a short, very live list,
  /// 24h is long but staler. The country filter is the *measured* exit country.
  Future<ConfigsPage> getVerifiedConfigs({
    String type = 'all',
    String? country,
    int maxAgeHours = 24,
    int limit = 50,
    int offset = 0,
  }) async {
    if (_useMock) return _mockTextConfigs(limit: limit, offset: offset);
    final res = await _dio.get(
      '/configs/verified',
      queryParameters: {
        'type': type,
        'max_age_hours': maxAgeHours,
        'limit': limit,
        'offset': offset,
        if (country != null && country.isNotEmpty) 'country': country,
      },
    );
    return _parseTextPage(res.data as Map<String, dynamic>);
  }

  /// Exit countries that currently have verified configs, most first.
  Future<List<VerifiedCountry>> getVerifiedCountries({
    int maxAgeHours = 24,
  }) async {
    final res = await _dio.get(
      '/configs/countries',
      queryParameters: {'max_age_hours': maxAgeHours},
    );
    final data = res.data as Map<String, dynamic>;
    return (data['countries'] as List)
        .cast<Map<String, dynamic>>()
        .map(VerifiedCountry.fromJson)
        .toList();
  }

  /// The config bot's own subscription lists, offered in the app by default.
  ///
  /// Names never arrive: a list is a kind and a number, and its servers carry
  /// Verna's remark rather than their publisher's.
  Future<List<BuiltInSubscription>> getSubscriptions({
    int maxAgeHours = 24,
  }) async {
    final res = await _dio.get(
      '/subscriptions',
      queryParameters: {'max_age_hours': maxAgeHours},
    );
    final data = res.data as Map<String, dynamic>;
    return [
      for (final item in (data['subscriptions'] as List? ?? const []))
        if (item is Map<String, dynamic>) BuiltInSubscription.fromJson(item),
    ];
  }

  /// One built-in subscription's servers that recently carried traffic,
  /// freshest first.
  Future<ConfigsPage> getSubscriptionConfigs(
    int id, {
    int limit = 30,
    int maxAgeHours = 24,
  }) async {
    final res = await _dio.get(
      '/subscriptions/$id/configs',
      queryParameters: {'limit': limit, 'max_age_hours': maxAgeHours},
    );
    return _parseTextPage(res.data as Map<String, dynamic>);
  }

  /// Measurements from this phone. Every report carries its own uid, so
  /// sending a batch twice after a timeout stores it once.
  Future<void> postReports(List<Map<String, dynamic>> reports) async {
    await _dio.post('/reports', data: {'reports': reports});
  }

  Future<ConfigStats> getStats() async {
    if (_useMock) return _mockStats();
    final res = await _dio.get('/configs/stats');
    final d = res.data as Map<String, dynamic>;
    return ConfigStats(
      totalText: d['total_text'] as int,
      totalFile: d['total_file'] as int,
      byType: Map<String, int>.from(d['by_type'] as Map),
      lastUpdated: d['last_updated'] != null
          ? DateTime.tryParse(d['last_updated'] as String)
          : null,
    );
  }

  // ---------------------------------------------------------------------------
  // Parsers
  // ---------------------------------------------------------------------------

  ConfigsPage _parseTextPage(Map<String, dynamic> d) {
    final list = (d['configs'] as List).map((e) {
      final m = e as Map<String, dynamic>;
      return VpnConfig(
        id: m['id'] as String,
        type: VpnConfigType.fromString(m['type'] as String),
        kind: VpnConfigKind.text,
        content: m['content'] as String?,
        country: _tidyCountry(m['country'] as String?),
        flag: m['flag'] as String? ?? '',
        countryCode: m['code'] as String? ?? '',
        pingMs: m['ping'] as int?,
        quality: (m['quality'] as int?) ?? 0,
        // SQLite hands back "2026-08-21 12:05:14"; DateTime.parse wants the T.
        verifiedAt: m['verified_at'] != null
            ? DateTime.tryParse(
                (m['verified_at'] as String).replaceFirst(' ', 'T'))
            : null,
        builtInSubId: m['sub'] as int?,
        concurrency: (m['concurrency'] as num?)?.toDouble(),
      );
    }).toList();
    return ConfigsPage(total: d['total'] as int, configs: list);
  }

  ConfigsPage _parseFilePage(Map<String, dynamic> d) {
    final list = (d['configs'] as List).map((e) {
      final m = e as Map<String, dynamic>;
      return VpnConfig(
        id: m['id'] as String,
        type: VpnConfigType.fromString(m['type'] as String),
        kind: VpnConfigKind.file,
        downloadUrl: m['download_url'] as String?,
        fileExtension: m['extension'] as String?,
        country: _tidyCountry(m['country'] as String?),
        flag: m['flag'] as String? ?? '',
        countryCode: m['code'] as String? ?? '',
        pingMs: m['ping'] as int?,
        quality: (m['quality'] as int?) ?? 0,
      );
    }).toList();
    return ConfigsPage(total: d['total'] as int, configs: list);
  }

  // ---------------------------------------------------------------------------
  // Mock data (used only when _useMock = true)
  // ---------------------------------------------------------------------------

  ConfigsPage _mockTextConfigs({required int limit, required int offset}) {
    final all = [
      _mkText('t001', 'vless', 'vless://mock@1.2.3.4:443#Verna-DE-1', 'Germany', '🇩🇪', 'DE', 23, 90),
      _mkText('t002', 'vmess', 'vmess://eyJhZGQiOiIxLjIuMy40In0=', 'Netherlands', '🇳🇱', 'NL', 41, 75),
    ];
    final paged = all.skip(offset).take(limit).toList();
    return ConfigsPage(total: all.length, configs: paged);
  }

  ConfigsPage _mockFileConfigs({required int limit, required int offset}) {
    final all = [
      _mkFile('f001', 'openvpn', '.ovpn', 'Germany', '🇩🇪', 'DE', 35, 80),
    ];
    final paged = all.skip(offset).take(limit).toList();
    return ConfigsPage(total: all.length, configs: paged);
  }

  ConfigStats _mockStats() => ConfigStats(
        totalText: 2,
        totalFile: 1,
        byType: {'vless': 1, 'vmess': 1, 'openvpn': 1},
        lastUpdated: DateTime.now().subtract(const Duration(minutes: 5)),
      );

  VpnConfig _mkText(String id, String type, String content, String country,
          String flag, String code, int ping, int quality) =>
      VpnConfig(
        id: id,
        type: VpnConfigType.fromString(type),
        kind: VpnConfigKind.text,
        content: content,
        country: country,
        flag: flag,
        countryCode: code,
        pingMs: ping,
        quality: quality,
      );

  VpnConfig _mkFile(String id, String type, String ext, String country,
          String flag, String code, int ping, int quality) =>
      VpnConfig(
        id: id,
        type: VpnConfigType.fromString(type),
        kind: VpnConfigKind.file,
        downloadUrl: '$_apiV1/configs/file/$id',
        fileExtension: ext,
        country: country,
        flag: flag,
        countryCode: code,
        pingMs: ping,
        quality: quality,
      );
}


/// Tries a failed request again before giving up.
///
/// One attempt per request is the right design on a healthy network and the
/// wrong one here. Measured on a J7 on a home connection in Gilan: `ping
/// vernaservice.ir` returned 50% packet loss, and the app -- which asks once
/// and reports failure -- showed "Could not fetch the server list" and stopped.
/// Nothing was broken except the assumption that a request either arrives or
/// the network is down.
///
/// Only idempotent reads are retried, and only for the failures that a second
/// attempt can plausibly fix: timeouts and connection errors. A 404 or a 500 is
/// an answer, and asking again is just noise.
class _RetryOnFlakyNetwork extends Interceptor {
  _RetryOnFlakyNetwork(this._client);

  final ConfigApiClient _client;

  Dio get _dio => _client._dio;

  void _routeVia(String? ip) => _client._routeVia(ip);

  /// Three attempts total. A fourth costs more waiting than it buys.
  static const int _maxAttempts = 3;

  /// Short, and growing: a network dropping half its packets usually needs a
  /// moment, not a minute.
  static const List<Duration> _backoff = [
    Duration(milliseconds: 400),
    Duration(milliseconds: 1200),
  ];

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (!_worthRetrying(err)) {
      handler.next(err);
      return;
    }

    final options = err.requestOptions;
    final attempt = (options.extra['verna_attempt'] as int?) ?? 1;

    if (attempt < _maxAttempts) {
      await Future<void>.delayed(_backoff[attempt - 1]);
      options.extra = {...options.extra, 'verna_attempt': attempt + 1};
      try {
        handler.resolve(await _dio.fetch<dynamic>(options));
        return;
      } on DioException catch (e) {
        // Falls through to the edges below rather than giving up: the retries
        // above only help a lossy link, and a blocked edge stays blocked
        // however many times it is asked.
        err = e;
      }
    }

    // Every ordinary attempt failed. The address DNS gave us may simply be
    // one of the Cloudflare edges that this network drops -- measured from
    // Rasht, seven of seventeen were unreachable while the site was up -- so
    // try the others before reporting failure.
    if (options.extra['verna_edge'] == null) {
      for (final ip in await EdgeRouter.order()) {
        _routeVia(ip);
        final retry = options.copyWith()
          ..extra = {...options.extra, 'verna_edge': ip, 'verna_attempt': 1};
        try {
          final response = await _dio.fetch<dynamic>(retry);
          await EdgeRouter.pin(ip);
          handler.resolve(response);
          return;
        } on DioException {
          // Next edge.
        }
      }
      // None of them worked either: this is not a routing problem, so stop
      // pinning one and let the next request start from DNS again.
      _routeVia(null);
      await EdgeRouter.unpin();
    }

    handler.next(err);
  }

  static bool _worthRetrying(DioException err) => switch (err.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.connectionError =>
          true,
        // A response arrived. Whatever it says, asking again will not change
        // it.
        _ => false,
      };
}
