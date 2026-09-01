import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../tunnel/domain/tunnel_snapshot.dart';
import '../../tunnel/presentation/providers/tunnel_provider.dart';

/// How much this device has actually moved through the tunnel, day by day.
///
/// The design's usage screen shows a quota, a renewal date and a device count.
/// This app has no accounts, no quota and no idea what else the user owns, so
/// those three numbers could only ever be invented. What it does have is the
/// core's own byte counters, and the honest version of that screen is what they
/// say: this session, today, and the fortnight behind it.
///
/// Kept on the device and nowhere else. Nothing here is reported anywhere --
/// the app has no telemetry, and a VPN that quietly measured its users would be
/// a strange thing to build.
class UsageStore {
  const UsageStore._();

  static const String _key = 'usage_daily_v1';

  /// How much history the chart shows, and therefore how much is worth keeping.
  /// Older days are dropped on write rather than accumulating forever.
  static const int days = 14;

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
      // Trimmed on the way out: sorted keys are ISO dates, so the newest are
      // simply the last ones.
      final keys = byDay.keys.toList()..sort();
      final keep = keys.length <= days
          ? keys
          : keys.sublist(keys.length - days);
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

/// One day's total, ready for the chart.
class UsageDay {
  const UsageDay(this.date, this.bytes);

  final DateTime date;
  final int bytes;
}

/// What the usage screen reads.
class UsageSummary {
  const UsageSummary({
    this.sessionBytes = 0,
    this.todayBytes = 0,
    this.totalBytes = 0,
    this.history = const [],
  });

  /// Moved since the current tunnel came up. Zero when nothing is connected.
  final int sessionBytes;

  /// Everything moved today, this session included.
  final int todayBytes;

  /// The whole retained window.
  final int totalBytes;

  /// Oldest first, exactly [UsageStore.days] entries, zeros included -- a chart
  /// with gaps closed up would misrepresent a quiet week as a busy one.
  final List<UsageDay> history;

  int get busiestDayBytes =>
      history.fold<int>(0, (best, day) => day.bytes > best ? day.bytes : best);
}

final usageProvider =
    NotifierProvider<UsageController, UsageSummary>(UsageController.new);

/// Turns the core's running totals into a daily history.
///
/// The counters the core reports are per-session and cumulative: they climb
/// while a tunnel is up and reset when the next one starts. So this records
/// *differences*, and treats any drop as a new session rather than as negative
/// traffic -- otherwise reconnecting would subtract the previous session from
/// today.
class UsageController extends Notifier<UsageSummary> {
  int _lastSeenTotal = 0;
  Map<String, int> _byDay = {};
  bool _loaded = false;

  @override
  UsageSummary build() {
    ref.listen<TunnelSnapshot>(tunnelSnapshotProvider, (_, next) {
      _record(next);
    });
    _load();
    return const UsageSummary();
  }

  Future<void> _load() async {
    _byDay = await UsageStore.read();
    _loaded = true;
    _publish(0);
  }

  void _record(TunnelSnapshot snapshot) {
    if (!_loaded) return;
    final total = snapshot.uploadTotal + snapshot.downloadTotal;

    // A drop means the core started counting again, so the new reading is the
    // whole of the new session rather than a delta against the old one.
    final delta = total >= _lastSeenTotal ? total - _lastSeenTotal : total;
    _lastSeenTotal = total;

    if (delta > 0) {
      final key = UsageStore.dayKey(DateTime.now());
      _byDay[key] = (_byDay[key] ?? 0) + delta;
      // Written on every update rather than at teardown: a VPN process can be
      // killed by the system at any moment, and a history that only survives a
      // graceful exit is a history of the quiet days.
      UsageStore.write(_byDay);
    }

    _publish(snapshot.isConnected ? total : 0);
  }

  void _publish(int sessionBytes) {
    final today = DateTime.now();
    final history = <UsageDay>[];
    for (var i = UsageStore.days - 1; i >= 0; i--) {
      final date = DateTime(today.year, today.month, today.day)
          .subtract(Duration(days: i));
      history.add(UsageDay(date, _byDay[UsageStore.dayKey(date)] ?? 0));
    }
    state = UsageSummary(
      sessionBytes: sessionBytes,
      todayBytes: _byDay[UsageStore.dayKey(today)] ?? 0,
      totalBytes: _byDay.values.fold<int>(0, (sum, v) => sum + v),
      history: history,
    );
  }

  /// Forgets everything. Offered in Settings beside the cache, because a usage
  /// history is the one thing here that is about the user rather than the app.
  Future<void> reset() async {
    _byDay = {};
    _lastSeenTotal = 0;
    await UsageStore.clear();
    _publish(0);
  }
}
