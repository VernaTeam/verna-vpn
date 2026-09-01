import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../configs/domain/vpn_config.dart';

/// Servers this device has actually connected through, remembered across runs.
///
/// Nothing was persisted before, so every connection rediscovered the whole
/// pool from scratch: fetch 300 configs, sweep them for reachability, run the
/// core's latency probe in batches, then try candidates one at a time with an
/// egress check on each. Measured on a J7, that is 90 seconds when it goes
/// well and minutes when it does not -- for a question the app had already
/// answered minutes earlier and thrown away.
///
/// A server that carried traffic ten minutes ago is overwhelmingly the best
/// thing to try first, and trying it costs about three seconds.
///
/// **Kept per network.** A config that works on a home connection can be dead
/// on Irancell, and offering it first there would trade one wasted minute for
/// another. The key is the network the phone was on when the server worked --
/// which the pre-connect egress reading already reports, at no extra cost.
class KnownGoodStore {
  const KnownGoodStore._();

  static const String _key = 'known_good_servers_v1';

  /// How many to keep per network. Small on purpose: these are tried in order
  /// before the search begins, and a long stale list is just a slow start.
  static const int _perNetwork = 6;

  /// Older than this and it is not evidence any more -- free servers die and
  /// blocks arrive within hours.
  static const Duration _maxAge = Duration(hours: 12);

  /// Everything remembered for [network], freshest first.
  static Future<List<KnownGood>> forNetwork(String network) async {
    final all = await _load();
    final now = DateTime.now();
    final mine = all
        .where((e) => e.network == network && now.difference(e.at) < _maxAge)
        .toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    return mine;
  }

  /// Records a server that carried traffic, and forgets the oldest.
  static Future<void> remember(
    VpnConfig config,
    String network, {
    int? milliseconds,
  }) async {
    final content = config.content;
    if (content == null || content.isEmpty) return;

    final all = await _load();
    // One entry per config per network: reconnecting to the same server
    // repeatedly should refresh its timestamp, not fill the list with copies.
    all.removeWhere((e) => e.configId == config.id && e.network == network);
    all.add(KnownGood(
      configId: config.id,
      content: content,
      typeName: config.type.name,
      country: config.country,
      countryCode: config.countryCode,
      flag: config.flag,
      milliseconds: milliseconds,
      at: DateTime.now(),
      network: network,
    ));

    final trimmed = <KnownGood>[];
    final counts = <String, int>{};
    all.sort((a, b) => b.at.compareTo(a.at));
    for (final entry in all) {
      final n = counts[entry.network] ?? 0;
      if (n >= _perNetwork) continue;
      counts[entry.network] = n + 1;
      trimmed.add(entry);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final e in trimmed) e.toJson()]),
    );
  }

  /// Drops a server that has stopped working, so it is not offered first again.
  static Future<void> forget(String configId, String network) async {
    final all = await _load();
    final before = all.length;
    all.removeWhere((e) => e.configId == configId && e.network == network);
    if (all.length == before) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode([for (final e in all) e.toJson()]));
  }

  static Future<List<KnownGood>> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return [
        for (final item in decoded)
          if (item is Map<String, dynamic>) KnownGood.fromJson(item),
      ];
    } catch (_) {
      // A store that cannot be read is a store that is empty. Never a reason
      // to fail a connection.
      return [];
    }
  }
}

/// One remembered server.
class KnownGood {
  const KnownGood({
    required this.configId,
    required this.content,
    required this.typeName,
    required this.country,
    required this.countryCode,
    required this.flag,
    required this.milliseconds,
    required this.at,
    required this.network,
  });

  final String configId;

  /// The share URI itself, not just the id.
  ///
  /// The inventory turns over: the row that worked yesterday may not be in
  /// today's page at all, and an id alone would then point at nothing. Keeping
  /// the URI means the server can be tried whether or not the API still lists
  /// it.
  final String content;

  final String typeName;
  final String country;
  final String countryCode;
  final String flag;
  final int? milliseconds;
  final DateTime at;

  /// Which network this was measured on -- an ASN where one is known.
  final String network;

  VpnConfig toConfig() => VpnConfig(
        id: configId,
        type: VpnConfigType.fromString(typeName),
        kind: VpnConfigKind.text,
        content: content,
        country: country,
        countryCode: countryCode,
        flag: flag,
      );

  Map<String, dynamic> toJson() => {
        'id': configId,
        'content': content,
        'type': typeName,
        'country': country,
        'code': countryCode,
        'flag': flag,
        'ms': milliseconds,
        'at': at.toIso8601String(),
        'net': network,
      };

  factory KnownGood.fromJson(Map<String, dynamic> json) => KnownGood(
        configId: '${json['id']}',
        content: '${json['content']}',
        typeName: '${json['type']}',
        country: '${json['country'] ?? ''}',
        countryCode: '${json['code'] ?? ''}',
        flag: '${json['flag'] ?? ''}',
        milliseconds: json['ms'] as int?,
        at: DateTime.tryParse('${json['at']}') ?? DateTime(2000),
        network: '${json['net'] ?? 'unknown'}',
      );
}
