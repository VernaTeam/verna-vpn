import 'package:shared_preferences/shared_preferences.dart';

/// The exit country the user chose, kept across launches.
///
/// It used to live only in a provider, so closing the app put the picker back
/// to Automatic -- someone who deliberately chose Germany got a fresh search
/// of the whole world the next morning. A choice the user made by hand is the
/// kind of thing an app is expected to remember.
class PreferredCountryStore {
  const PreferredCountryStore._();

  static const String _key = 'preferred_country_v1';

  /// The saved code, or null for automatic.
  static Future<String?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_key);
      return code == null || code.isEmpty ? null : code;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String? code) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (code == null || code.isEmpty) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, code);
      }
    } catch (_) {
      // Losing the preference costs one tap, never a connection.
    }
  }
}
