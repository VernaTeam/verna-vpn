import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../configs/domain/vpn_config.dart';

/// The tunnel that is up, as the screen showed it.
class ActiveSession {
  const ActiveSession({
    required this.config,
    required this.connectedAt,
    this.pingMs,
    this.exitIp,
    this.exitCountryCode,
    this.userChose = false,
  });

  final VpnConfig config;
  final DateTime connectedAt;
  final int? pingMs;
  final String? exitIp;
  final String? exitCountryCode;

  /// Whether the user picked this server by hand. A restored tunnel that has
  /// to be replaced is replaced the same way: the chosen server again, not a
  /// quiet move to whichever server an automatic search prefers.
  final bool userChose;

  Map<String, dynamic> toJson() => {
        'config': config.toJson(),
        'connectedAt': connectedAt.toIso8601String(),
        'pingMs': pingMs,
        'exitIp': exitIp,
        'exitCountryCode': exitCountryCode,
        'userChose': userChose,
      };

  static ActiveSession? fromJson(Map<String, dynamic> json) {
    final config = json['config'];
    final at = DateTime.tryParse(json['connectedAt'] as String? ?? '');
    if (config is! Map<String, dynamic> || at == null) return null;
    return ActiveSession(
      config: VpnConfig.fromJson(config),
      connectedAt: at,
      pingMs: json['pingMs'] as int?,
      exitIp: json['exitIp'] as String?,
      exitCountryCode: json['exitCountryCode'] as String?,
      userChose: json['userChose'] as bool? ?? false,
    );
  }
}

/// The live session, kept outside Dart's memory.
///
/// The VPN service outlives the screen, and everything the screen knew about
/// it did not. Measured on a J7 on 2026-09-14: after "Close all" the app came
/// back and said Connected -- the core was asked and answered -- but the
/// server read "Unknown", the session timer restarted at zero, and protocol
/// and ping were blank, because those lived only in the Flutter engine that
/// had just been destroyed.
///
/// Saved when a tunnel is verified, cleared when it ends by any path.
class ActiveSessionStore {
  const ActiveSessionStore._();

  static const String _key = 'active_session_v1';

  static Future<void> save(ActiveSession session) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(session.toJson()));
    } catch (_) {
      // Without it the tunnel still works; the screen just knows less later.
    }
  }

  static Future<ActiveSession?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      return ActiveSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {
      // Nothing to do.
    }
  }
}
