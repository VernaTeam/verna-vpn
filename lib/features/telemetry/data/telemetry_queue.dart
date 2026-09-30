import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/install_id.dart';
import '../../configs/data/config_api_client.dart';
import '../../diagnostics/data/app_log.dart';
import '../domain/telemetry_records.dart';

/// Rows waiting to be sent, kept on disk so none are lost to a flaky
/// connection or a closed app.
///
/// The same shape as [ReportQueue], for the same reasons: every row carries a
/// uid the server deduplicates on, so a batch retried after a timeout stores
/// once and a replayed one stores nothing.
class TelemetryQueue {
  TelemetryQueue(this._api);

  final ConfigApiClient _api;

  static const String _sessionsKey = 'pending_sessions_v1';
  static const String _failuresKey = 'pending_failures_v1';

  /// Oldest are dropped past this. A phone that has been offline for a week
  /// has more current things to say than its backlog -- and this is
  /// diagnostics, not accounting.
  static const int _maxQueued = 300;

  /// The server's own cap per request is 100 rows, for both kinds together.
  static const int _batchSize = 50;

  bool _flushing = false;

  Future<void> addSession(SessionRecord session) =>
      _append(_sessionsKey, session.toJson());

  Future<void> addFailure(FailureRecord failure) =>
      _append(_failuresKey, failure.toJson());

  Future<void> _append(String key, Map<String, dynamic> row) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queued = prefs.getStringList(key) ?? <String>[];
      queued.add(jsonEncode(row));
      final overflow = queued.length - _maxQueued;
      if (overflow > 0) queued.removeRange(0, overflow);
      await prefs.setStringList(key, queued);
    } catch (e) {
      AppLog.instance.info('Telemetry not queued', detail: '$e');
    }
  }

  /// Sends what is queued, a batch at a time, stopping at the first failure.
  ///
  /// [mayUpload] is asked first, so nothing is sent while a tunnel is being
  /// built -- measuring a connection must not compete with it for the radio.
  Future<void> flush({Future<bool> Function()? mayUpload}) async {
    if (_flushing) return;
    if (mayUpload != null && !await mayUpload()) return;
    _flushing = true;
    var sent = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      var sessions = prefs.getStringList(_sessionsKey) ?? <String>[];
      var failures = prefs.getStringList(_failuresKey) ?? <String>[];
      if (sessions.isEmpty && failures.isEmpty) return;

      final install = await InstallId.get();
      while (sessions.isNotEmpty || failures.isNotEmpty) {
        final sessionBatch = sessions.take(_batchSize).toList();
        final failureBatch =
            failures.take(_batchSize - (sessionBatch.length ~/ 2)).toList();
        await _api.postTelemetry(
          installId: install,
          sessions: [for (final s in sessionBatch) _decode(s)],
          failures: [for (final f in failureBatch) _decode(f)],
        );
        sent += sessionBatch.length + failureBatch.length;
        sessions = sessions.sublist(sessionBatch.length);
        failures = failures.sublist(failureBatch.length);
        await prefs.setStringList(_sessionsKey, sessions);
        await prefs.setStringList(_failuresKey, failures);
      }
    } catch (e) {
      // Kept for the next flush. Not an error the user needs to see.
      AppLog.instance.info('Telemetry kept for later', detail: '$e');
    } finally {
      _flushing = false;
    }
    if (sent > 0) AppLog.instance.info('Telemetry sent', detail: '$sent');
  }

  static Map<String, dynamic> _decode(String raw) =>
      jsonDecode(raw) as Map<String, dynamic>;

  /// Drops everything waiting. Used when the user resets their install id, so
  /// rows measured under the old one are not sent under the new one.
  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_sessionsKey);
      await prefs.remove(_failuresKey);
    } catch (_) {
      // Nothing to do about it, and nothing depends on it.
    }
  }
}
