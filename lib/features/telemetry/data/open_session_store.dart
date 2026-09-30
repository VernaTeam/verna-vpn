import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/telemetry_records.dart';

/// The session currently running, written down in case the app does not get
/// to finish it.
///
/// Android kills backgrounded VPN apps, and those are exactly the sessions
/// worth having: the tunnel died, the phone ran out of memory, the user walked
/// away. If a row were only written at disconnect, every one of those would be
/// missing and the data would quietly describe a better app than the real one.
///
/// So the row is written when the tunnel comes up, refreshed every
/// [heartbeat], and closed by the next launch with `ended_by = app_killed` and
/// the duration up to the last refresh. The heartbeat is what makes that
/// duration honest: without it, a session killed after two hours would be
/// recovered as one second long.
class OpenSessionStore {
  const OpenSessionStore._();

  static const String _key = 'open_session_v1';

  /// Often enough that a recovered duration is roughly right, rarely enough
  /// that it is not a write every second.
  static const Duration heartbeat = Duration(seconds: 30);

  static Future<void> save(
    SessionRecord session, {
    required int lastSeenEpoch,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          ...session.toOpenJson(),
          'last_seen_epoch': lastSeenEpoch,
          if (session.bytesDown != null) 'bytes_down': session.bytesDown,
          if (session.bytesUp != null) 'bytes_up': session.bytesUp,
          if (session.peakKbps != null) 'peak_kbps': session.peakKbps,
        }),
      );
    } catch (_) {
      // A session that cannot be written down is still a session; it just
      // will not survive the process dying.
    }
  }

  /// The session left behind by a previous run, already closed as
  /// `app_killed`, or null if the last run ended properly.
  static Future<SessionRecord?> takeAbandoned() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      await prefs.remove(_key);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final session = SessionRecord.fromOpenJson(json);
      if (session == null) return null;
      final lastSeen = json['last_seen_epoch'];
      if (lastSeen is int) {
        final seconds = (lastSeen - session.startedAt.millisecondsSinceEpoch) ~/ 1000;
        session.durationS = seconds < 0 ? 0 : seconds;
      }
      session.bytesDown = json['bytes_down'] as int?;
      session.bytesUp = json['bytes_up'] as int?;
      session.peakKbps = json['peak_kbps'] as int?;
      session.endedBy = EndedBy.appKilled;
      return session;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {
      // Then the next launch recovers a session that did end cleanly, which
      // costs one duplicate row the server will store once.
    }
  }
}
