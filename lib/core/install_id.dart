import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// A name this installation calls itself when it reports how a connection went.
///
/// Random, made once, and kept on the phone. Not derived from the IMEI, the
/// Android ID, the advertising id or anything else that would survive a
/// reinstall or identify the device to anyone else -- two phones cannot be
/// told apart by it, and it says nothing about this one.
///
/// Why it exists at all: the server's other identifier is a hash of the
/// connecting IP under a salt that changes every day. That was the right
/// choice for server measurements and it makes four questions unanswerable --
/// how many people actually use this, how long a session lasts, whether
/// someone came back tomorrow, whether the ones who fail are the same ones
/// every time. Those are the questions the next release depends on.
///
/// The user can replace it from Settings, which makes everything recorded
/// before that unlinkable from everything after.
class InstallId {
  const InstallId._();

  static const String _key = 'install_id_v1';

  static String? _cached;

  /// The id, made on first use.
  static Future<String> get() async {
    final cached = _cached;
    if (cached != null) return cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      if (saved != null && saved.length == 36) {
        _cached = saved;
        return saved;
      }
      final made = _uuid4();
      await prefs.setString(_key, made);
      _cached = made;
      return made;
    } catch (_) {
      // Storage is unavailable; use a per-run id rather than failing. It makes
      // this run look like a new install, which is the harmless direction.
      return _cached ??= _uuid4();
    }
  }

  /// Forgets the old id and makes a new one. Everything already sent stays
  /// where it is, attached to an identifier this phone no longer uses.
  static Future<String> reset() async {
    _cached = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {
      // Then `get` will make one anyway.
    }
    return get();
  }

  /// A version 4 UUID from the platform's secure random.
  ///
  /// Written out rather than pulled from a package: it is sixteen bytes and
  /// two bit twiddles, and the app has enough dependencies.
  static String _uuid4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
    String hex(int start, int end) => [
          for (var i = start; i < end; i++)
            bytes[i].toRadixString(16).padLeft(2, '0'),
        ].join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }
}
