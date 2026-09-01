import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The switches on the settings screen that actually do something.
///
/// The design draws four: auto-connect, kill switch, split tunneling and local
/// network access. Only the first is built, so only the first is a switch --
/// the other three are shown as pending rather than as controls, because a
/// toggle that flips and changes nothing is worse than an absent feature. It
/// tells the user their traffic is protected in a way it is not, and a kill
/// switch is exactly the setting where that matters.
class AppPreferences {
  const AppPreferences({this.autoConnect = false});

  /// Connect as soon as the app opens, without waiting for a tap.
  final bool autoConnect;

  AppPreferences copyWith({bool? autoConnect}) =>
      AppPreferences(autoConnect: autoConnect ?? this.autoConnect);
}

const String _kAutoConnect = 'pref_auto_connect_v1';

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
      );
    } catch (_) {
      return const AppPreferences();
    }
  }

  Future<void> setAutoConnect(bool value) async {
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
}
