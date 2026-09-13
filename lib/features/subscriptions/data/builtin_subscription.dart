import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../configs/domain/vpn_config.dart';

/// A subscription the config bot reads, offered in the app without the user
/// having to add anything.
///
/// Named by what it carries, never by who publishes it: the server sends a
/// kind and a number and keeps the list's name and link to itself. Its
/// servers arrive already rebranded, so nothing here names a channel either.
class BuiltInSubscription {
  const BuiltInSubscription({
    required this.id,
    required this.kind,
    required this.number,
    required this.total,
    required this.healthy,
    this.updatedAt,
  });

  /// The bot's own id for the list. Stable, so a switched-off subscription
  /// stays off across refreshes even if its number or its place changes.
  final int id;

  /// `vless`, `vmess`, `ss`, `trojan`, `hysteria2` or `mixed`.
  final String kind;

  /// Its number within [kind] -- "VLESS 2" -- fixed on the server.
  final int number;

  /// Configs the bot holds from this list.
  final int total;

  /// Of those, how many the server saw carrying traffic in the last day.
  final int healthy;

  /// When the bot last fetched the list.
  final DateTime? updatedAt;

  factory BuiltInSubscription.fromJson(Map<String, dynamic> json) {
    final updated = json['updated_at'] as String?;
    return BuiltInSubscription(
      id: json['id'] as int,
      kind: json['kind'] as String? ?? 'mixed',
      number: json['number'] as int? ?? 1,
      total: json['total'] as int? ?? 0,
      healthy: json['healthy'] as int? ?? 0,
      // SQLite hands back "2026-09-13 13:52:04"; DateTime wants the T.
      updatedAt:
          updated == null ? null : DateTime.tryParse(updated.replaceFirst(' ', 'T')),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'number': number,
        'total': total,
        'healthy': healthy,
        'updated_at': updatedAt?.toIso8601String(),
      };
}

/// The last list and its servers, kept for launches where Verna's API cannot
/// be reached, and the user's switches, kept for good.
class BuiltInSubscriptionStore {
  const BuiltInSubscriptionStore._();

  static const String _cacheKey = 'builtin_subscriptions_v1';
  static const String _disabledKey = 'builtin_subscriptions_disabled_v1';

  static Future<
      ({
        List<BuiltInSubscription> items,
        Map<int, List<VpnConfig>> configs,
      })> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return (items: const <BuiltInSubscription>[], configs: const <int, List<VpnConfig>>{});
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final items = [
        for (final item in (data['items'] as List? ?? const []))
          if (item is Map<String, dynamic>) BuiltInSubscription.fromJson(item),
      ];
      final configs = <int, List<VpnConfig>>{};
      final byId = data['configs'] as Map<String, dynamic>? ?? const {};
      byId.forEach((id, list) {
        final key = int.tryParse(id);
        if (key == null || list is! List) return;
        configs[key] = [
          for (final item in list)
            if (item is Map<String, dynamic>) VpnConfig.fromJson(item),
        ];
      });
      return (items: items, configs: configs);
    } catch (_) {
      // A cache that cannot be read is a cache that is not there.
      return (items: const <BuiltInSubscription>[], configs: const <int, List<VpnConfig>>{});
    }
  }

  static Future<void> write(
    List<BuiltInSubscription> items,
    Map<int, List<VpnConfig>> configs,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode({
          'items': [for (final item in items) item.toJson()],
          'configs': {
            for (final entry in configs.entries)
              '${entry.key}': [for (final c in entry.value) c.toJson()],
          },
        }),
      );
    } catch (_) {
      // Not being able to cache is not a reason to fail a refresh.
    }
  }

  static Future<Set<int>> readDisabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        for (final id in prefs.getStringList(_disabledKey) ?? const <String>[])
          if (int.tryParse(id) case final int value) value,
      };
    } catch (_) {
      return const {};
    }
  }

  static Future<void> writeDisabled(Set<int> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_disabledKey, [for (final id in ids) '$id']);
    } catch (_) {
      // The switch still holds for this session.
    }
  }
}
