import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../domain/vpn_config.dart';

/// Servers shipped inside the app, for when nothing else can be reached.
///
/// The API is the app's control channel, and the control channel is subject to
/// exactly the blocking the app exists to get around. Measured on 2026-09-01:
/// `vernaservice.ir` resolved to 188.114.98.0, which timed out, while eight
/// other Cloudflare edges served the identical API in about a second. The
/// server had been healthy the whole time. [EdgeRouter] answers that case -- but
/// only once it has run and found a road. A first launch that loses both the
/// direct route and the fallback has no list at all, and an app whose purpose is
/// reaching blocked things instead reports that it cannot find any servers.
///
/// So the build carries a floor: a sample of the pool, spread across protocols
/// so a single filter cannot empty it, taken at build time from the live API.
///
/// These go stale -- free configs die within days -- which is the reason this
/// sits last rather than first. The order is live list, then the on-device
/// cache of a previous success, then this. And every entry is re-tested on the
/// device before it is offered, so a dead one costs a few seconds of probing
/// rather than becoming a promise the app cannot keep.
class SeedConfigs {
  const SeedConfigs._();

  static const String _asset = 'assets/seed_configs.json';

  /// Parsed once and kept. The file is ~47 KB of JSON; decoding it on every
  /// failed fetch would add work to the exact moment the app is already
  /// struggling.
  static List<VpnConfig>? _cache;

  /// Every bundled server, or an empty list if the asset is missing or broken.
  ///
  /// Never throws. This is the last thing tried before showing the user an
  /// error, so a fault here must not replace one failure with a worse one.
  static Future<List<VpnConfig>> all() async {
    final cached = _cache;
    if (cached != null) return cached;
    try {
      final raw = await rootBundle.loadString(_asset);
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final rows = (decoded['configs'] as List?) ?? const [];
      final parsed = <VpnConfig>[
        for (final row in rows)
          if (row is Map<String, dynamic>) ...[
            if (_parse(row) case final VpnConfig config) config,
          ],
      ];
      _cache = parsed;
      return parsed;
    } catch (_) {
      // A malformed bundle behaves like no bundle: the caller falls through to
      // the error it would have shown anyway.
      _cache = const [];
      return const [];
    }
  }

  /// The bundled servers of one protocol, as a page the repository can return
  /// in place of a fetch.
  ///
  /// `type` follows the API's vocabulary, and `'all'` means no filter, so the
  /// same string the caller would have sent over the network works here.
  static Future<ConfigsPage?> page({String type = 'all', int limit = 400}) async {
    final servers = await all();
    if (servers.isEmpty) return null;
    // Only what this app can actually run. The bundle is written from an API
    // response that still carries protocols the tunnel does not speak, and a
    // fallback list is the worst place to hand back a row that cannot connect.
    final usable = servers.where((c) => usableTypes.contains(c.type));
    final wanted = type == 'all'
        ? usable.toList()
        : usable.where((c) => c.type.name == type).toList();
    if (wanted.isEmpty) return null;
    final taken = wanted.take(limit).toList();
    return ConfigsPage(total: taken.length, configs: taken);
  }

  /// One row, in the same shape the API's text pages use.
  ///
  /// The bundle is written straight from an API response, so the field names
  /// are the API's rather than this app's. Anything unparseable is dropped
  /// rather than defaulted -- a config with no content cannot be connected to,
  /// and listing it would only waste a probe.
  static VpnConfig? _parse(Map<String, dynamic> m) {
    final id = m['id'];
    final content = m['content'];
    if (id is! String || content is! String || content.isEmpty) return null;
    final type = m['type'];
    if (type is! String) return null;
    return VpnConfig(
      id: id,
      type: VpnConfigType.fromString(type),
      kind: VpnConfigKind.text,
      content: content,
      country: (m['country'] as String?) ?? '',
      flag: (m['flag'] as String?) ?? '',
      countryCode: (m['code'] as String?) ?? '',
      // Deliberately no ping: whatever the server measured was from the
      // server's network at build time, and showing it as this device's
      // latency would be a number the app made up. The on-device test fills
      // it in with something true.
      quality: (m['quality'] as int?) ?? 0,
    );
  }
}
