import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../diagnostics/data/app_log.dart';

/// The switches on the settings screen that actually do something.
///
/// The design draws four: auto-connect, kill switch, split tunneling and local
/// network access. Each is a control only once it is built -- a toggle that
/// flips and changes nothing is worse than an absent feature, and a kill
/// switch is exactly the setting where that matters.
class AppPreferences {
  const AppPreferences({
    this.autoConnect = false,
    this.shareResults = true,
    this.bypassApps = const [],
    this.lanDirect = false,
  });

  /// Connect as soon as the app opens, without waiting for a tap.
  final bool autoConnect;

  /// Send which of Verna's servers worked from this phone, anonymously, so the
  /// bot can push broken ones down for everyone. On by default -- decided by
  /// Meysam on 2026-09-14 -- because with few users, opt-in would collect
  /// almost nothing; the user can switch it off in Settings.
  final bool shareResults;

  /// Package names that go straight to the internet instead of through the
  /// tunnel. Excluded rather than included, because what people in Iran need
  /// is the reverse of most VPNs' default: a bank or a domestic app that
  /// refuses foreign addresses, while everything else stays protected.
  final List<String> bypassApps;

  /// Private addresses (home router, printer, a TV) reached directly.
  final bool lanDirect;

  AppPreferences copyWith({
    bool? autoConnect,
    bool? shareResults,
    List<String>? bypassApps,
    bool? lanDirect,
  }) =>
      AppPreferences(
        autoConnect: autoConnect ?? this.autoConnect,
        shareResults: shareResults ?? this.shareResults,
        bypassApps: bypassApps ?? this.bypassApps,
        lanDirect: lanDirect ?? this.lanDirect,
      );
}

const String _kAutoConnect = 'pref_auto_connect_v1';
const String _kShareResults = 'pref_share_results_v1';
const String _kBypassApps = 'pref_bypass_apps_v1';
const String _kLanDirect = 'pref_lan_direct_v1';

final appPreferencesProvider =
    AsyncNotifierProvider<AppPreferencesController, AppPreferences>(
        AppPreferencesController.new);

class AppPreferencesController extends AsyncNotifier<AppPreferences> {
  @override
  Future<AppPreferences> build() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return AppPreferences(
        autoConnect: prefs.getBool(_kAutoConnect) ?? false,
        shareResults: prefs.getBool(_kShareResults) ?? true,
        bypassApps: prefs.getStringList(_kBypassApps) ?? const [],
        lanDirect: prefs.getBool(_kLanDirect) ?? false,
      );
    } catch (_) {
      return const AppPreferences();
    }
  }

  Future<void> setAutoConnect(bool value) async {
    // Logged, because half of "it connects on its own" and "it never connects
    // on its own" is a switch nobody remembers touching.
    AppLog.instance.info('Setting changed',
        detail: 'auto-connect ${value ? 'on' : 'off'}');
    // Published before the write, so the switch moves under the finger rather
    // than after a round trip to disk.
    state = AsyncData((state.valueOrNull ?? const AppPreferences())
        .copyWith(autoConnect: value));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kAutoConnect, value);
    } catch (_) {
      // A preference that will not save is not worth an error dialog.
    }
  }

  Future<void> setShareResults(bool value) async {
    AppLog.instance.info('Setting changed',
        detail: 'share results ${value ? 'on' : 'off'}');
    state = AsyncData((state.valueOrNull ?? const AppPreferences())
        .copyWith(shareResults: value));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kShareResults, value);
    } catch (_) {
      // As above.
    }
  }

  Future<void> setBypassApps(List<String> packages) async {
    // A count, not the names: the log is shown to whoever opens Diagnostics,
    // and which bank someone uses is not the log's business.
    AppLog.instance.info('Setting changed',
        detail: 'apps outside the tunnel: ${packages.length}');
    state = AsyncData((state.valueOrNull ?? const AppPreferences())
        .copyWith(bypassApps: List.unmodifiable(packages)));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kBypassApps, packages);
    } catch (_) {
      // As above.
    }
  }

  Future<void> setLanDirect(bool value) async {
    AppLog.instance.info('Setting changed',
        detail: 'local network direct ${value ? 'on' : 'off'}');
    state = AsyncData((state.valueOrNull ?? const AppPreferences())
        .copyWith(lanDirect: value));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kLanDirect, value);
    } catch (_) {
      // As above.
    }
  }
}
