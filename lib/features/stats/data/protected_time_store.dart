import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../tunnel/domain/tunnel_snapshot.dart';
import '../../tunnel/presentation/providers/tunnel_provider.dart';

/// How long this device has actually spent behind a tunnel, day by day.
///
/// The design's connect screen has a "Time protected · 6h this week" card with
/// seven bars. Nothing in the app knew that number: [UsageStore] counts bytes,
/// and a tunnel can be up for an hour without moving any. So this counts
/// seconds the same way that one counts bytes -- on the device, kept nowhere
/// else, reported to nobody.
///
/// Measured from the wall clock rather than from the session timer, because a
/// session that spans midnight belongs to two days and the timer only knows
/// about one of them.
class ProtectedTimeStore {
  const ProtectedTimeStore._();

  static const String _key = 'protected_seconds_v1';

  /// A week of bars on the card, plus the day they sit on.
  static const int days = 7;

  static String dayKey(DateTime when) =>
      '${when.year.toString().padLeft(4, '0')}-'
      '${when.month.toString().padLeft(2, '0')}-'
      '${when.day.toString().padLeft(2, '0')}';

  static Future<Map<String, int>> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return {};
      final decoded = (jsonDecode(raw) as Map).cast<String, dynamic>();
      return {
        for (final entry in decoded.entries)
          if (entry.value is num) entry.key: (entry.value as num).toInt(),
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> write(Map<String, int> byDay) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = byDay.keys.toList()..sort();
      final keep =
          keys.length <= days ? keys : keys.sublist(keys.length - days);
      await prefs.setString(
        _key,
        jsonEncode({for (final k in keep) k: byDay[k]}),
      );
    } catch (_) {
      // A history that will not save is not worth failing a tunnel over.
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {
      // Same.
    }
  }
}

/// One day's protected time, ready for the card's bars.
class ProtectedDay {
  const ProtectedDay(this.date, this.seconds);

  final DateTime date;
  final int seconds;
}

class ProtectedTime {
  const ProtectedTime({this.history = const [], this.weekSeconds = 0});

  /// Oldest first, exactly [ProtectedTimeStore.days] entries, zeros included.
  final List<ProtectedDay> history;

  /// The sum of that window -- what the card's headline says.
  final int weekSeconds;

  int get busiestDaySeconds =>
      history.fold<int>(0, (best, d) => d.seconds > best ? d.seconds : best);
}

final protectedTimeProvider =
    NotifierProvider<ProtectedTimeController, ProtectedTime>(
        ProtectedTimeController.new);

class ProtectedTimeController extends Notifier<ProtectedTime> {
  Map<String, int> _byDay = {};
  bool _loaded = false;
  DateTime? _since;

  @override
  ProtectedTime build() {
    ref.listen<TunnelSnapshot>(tunnelSnapshotProvider, (previous, next) {
      _record(next.isConnected);
    });
    _load();
    return const ProtectedTime();
  }

  Future<void> _load() async {
    _byDay = await ProtectedTimeStore.read();
    _loaded = true;
    // A tunnel restored from a previous run of the app is already up when this
    // provider builds, so start the clock rather than waiting for a change.
    _record(ref.read(tunnelSnapshotProvider).isConnected);
  }

  void _record(bool connected) {
    if (!_loaded) return;
    final now = DateTime.now();
    final since = _since;

    if (since != null) {
      final elapsed = now.difference(since).inSeconds;
      // Clamped: a phone that slept for nine hours with the tunnel up did not
      // spend nine hours protecting anything the user was doing, and the
      // clock can also jump backwards over a timezone change.
      if (elapsed > 0 && elapsed < 3600) {
        final key = ProtectedTimeStore.dayKey(now);
        _byDay[key] = (_byDay[key] ?? 0) + elapsed;
        ProtectedTimeStore.write(_byDay);
      }
    }

    _since = connected ? now : null;
    _publish();
  }

  void _publish() {
    final today = DateTime.now();
    final history = <ProtectedDay>[];
    var week = 0;
    for (var i = ProtectedTimeStore.days - 1; i >= 0; i--) {
      final date = DateTime(today.year, today.month, today.day)
          .subtract(Duration(days: i));
      final seconds = _byDay[ProtectedTimeStore.dayKey(date)] ?? 0;
      history.add(ProtectedDay(date, seconds));
      week += seconds;
    }
    state = ProtectedTime(history: history, weekSeconds: week);
  }

  /// Forgotten alongside the usage history, from the same place in Settings.
  Future<void> reset() async {
    _byDay = {};
    _since = null;
    await ProtectedTimeStore.clear();
    _publish();
  }
}
