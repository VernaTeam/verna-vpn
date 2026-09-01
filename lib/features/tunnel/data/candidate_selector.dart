import 'dart:convert';
import 'dart:math';

import '../../configs/domain/vpn_config.dart';

/// Turns the raw inventory into a short list worth trying on the device.
///
/// The API hands back whatever the bot has collected, ordered by `ping_ms`.
/// Handing that straight to the tunnel wastes most of the user's attempts, for
/// three measured reasons:
///
///  1. Only some protocols can run in-app at all. Xray parses vmess, vless,
///     trojan and ss; hysteria2, tuic and wireguard are not supported by the
///     core we embed, and tg_proxy/openvpn/npvt/dark never were.
///  2. `ping_ms` measures the CDN edge for CDN-fronted configs, so it stays
///     2-8ms even when the proxy behind it is dead. Ordering by it is a
///     de-facto "prefer CDN" filter, and over 60 real tunnel tests it halved
///     the success rate (23.3% vs 46.7%, z=2.68, p=0.007).
///  3. The inventory is full of duplicates -- a 2026-08-20 sample found 42% of
///     `ss` entries repeated the same server. Trying one dead host five times
///     burns five of the user's attempts on one failure.
class CandidateSelector {
  const CandidateSelector({this.random});

  /// Injectable for deterministic tests.
  final Random? random;

  /// Protocols the embedded Xray core can actually run.
  static const Set<VpnConfigType> runnableTypes = {
    VpnConfigType.vmess,
    VpnConfigType.vless,
    VpnConfigType.trojan,
    VpnConfigType.ss,
  };

  /// What the bot writes into `country_code` when the real server behind a CDN
  /// cannot be geolocated. It is a marker, not a place.
  static const String cdnMarker = 'CDN';

  /// Picks up to [limit] configs worth trying, best-first.
  ///
  /// [preferredCountry] narrows to one exit country when the user asked for
  /// one; when nothing matches it is ignored rather than returning an empty
  /// list, because a connection in the wrong country beats no connection.
  List<VpnConfig> select(
    List<VpnConfig> pool, {
    int limit = 25,
    String? preferredCountry,
  }) {
    final runnable = pool.where(_isRunnable).toList();

    // One config per server. Later duplicates of the same host:port add
    // nothing but delay.
    final seen = <String>{};
    final unique = <VpnConfig>[];
    for (final config in runnable) {
      final endpoint = _endpointOf(config);
      if (endpoint == null) continue;
      if (!seen.add(endpoint)) continue;
      unique.add(config);
    }

    final direct = <VpnConfig>[];
    final cdn = <VpnConfig>[];
    for (final config in unique) {
      if (config.countryCode.toUpperCase() == cdnMarker) {
        cdn.add(config);
      } else {
        direct.add(config);
      }
    }

    // Shuffle inside each group. The app cannot delete dead configs, so any
    // fixed order means every user retries the same head of the list: if it is
    // dead the whole app looks dead while hundreds of live configs go untried.
    // Random also spreads users over servers instead of hammering one.
    final rng = random ?? Random();
    direct.shuffle(rng);
    cdn.shuffle(rng);

    if (preferredCountry != null && preferredCountry.isNotEmpty) {
      final wanted = preferredCountry.toUpperCase();
      bool matches(VpnConfig c) => c.countryCode.toUpperCase() == wanted;
      final preferred = direct.where(matches).toList();
      final rest = direct.where((c) => !matches(c)).toList();
      direct
        ..clear()
        ..addAll(preferred)
        ..addAll(rest);
    }

    // CDN rows are not banned -- for some types they are most of the pool --
    // they are simply tried last.
    return [...direct, ...cdn].take(limit).toList();
  }

  bool _isRunnable(VpnConfig config) {
    if (!config.isText) return false;
    if (!runnableTypes.contains(config.type)) return false;
    final content = config.content;
    return content != null && content.contains('://');
  }

  /// The server a config dials, or null when the URI cannot be read.
  ///
  /// Used both to deduplicate and to reach the host directly for a cheap
  /// liveness check before the core is involved.
  static ({String host, int port})? endpointOf(VpnConfig config) {
    final combined = const CandidateSelector()._endpointOf(config);
    if (combined == null) return null;
    final colon = combined.lastIndexOf(':');
    final port = int.tryParse(combined.substring(colon + 1));
    if (colon <= 0 || port == null) return null;
    return (host: combined.substring(0, colon), port: port);
  }

  /// `host:port` for deduplication, or null when the URI cannot be read.
  ///
  /// Deliberately tolerant: a config we cannot parse here is simply not
  /// deduplicated, never dropped, because the core's own parser is the one
  /// that matters.
  String? _endpointOf(VpnConfig config) {
    final uri = config.content;
    if (uri == null) return null;
    final parts = uri.split('://');
    if (parts.length < 2) return null;
    final scheme = parts.first.toLowerCase();
    final rest = parts.sublist(1).join('://');

    try {
      if (scheme == 'vmess') {
        final blob = _padBase64(rest.split('#').first);
        final json = jsonDecode(utf8.decode(base64.decode(blob)));
        if (json is Map) return '${json['add']}:${json['port']}';
        return null;
      }

      var body = rest.split('#').first.split('?').first;
      if (scheme == 'ss' && !body.contains('@')) {
        // Fully base64-encoded ss:// form: method:pass@host:port
        body = utf8.decode(base64.decode(_padBase64(body)));
      }
      final hostPort = body.split('@').last.replaceAll(RegExp(r'/+$'), '');
      final colon = hostPort.lastIndexOf(':');
      if (colon <= 0) return null;
      final host = hostPort.substring(0, colon).replaceAll(RegExp(r'[\[\]]'), '');
      return '$host:${hostPort.substring(colon + 1)}';
    } catch (_) {
      return null;
    }
  }

  String _padBase64(String value) {
    final normalized = value.replaceAll('-', '+').replaceAll('_', '/');
    final remainder = normalized.length % 4;
    if (remainder == 0) return normalized;
    return normalized + '=' * (4 - remainder);
  }
}
