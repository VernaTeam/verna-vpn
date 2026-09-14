import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../configs/data/config_api_client.dart';
import '../../configs/domain/vpn_config.dart';
import '../../configs/presentation/providers/configs_provider.dart';
import '../../diagnostics/data/app_log.dart';
import '../../settings/data/app_preferences.dart';
import '../../tunnel/data/network_status.dart';
import '../../tunnel/presentation/providers/tunnel_provider.dart';
import 'measurement_report.dart';

/// Reports waiting to be sent, kept on disk so none are lost to a flaky
/// connection or a closed app.
///
/// Every report carries its own uid and the API ignores one it has already
/// stored, so sending a batch twice after a timeout is harmless.
class ReportQueue {
  ReportQueue(this._api);

  final ConfigApiClient _api;

  static const String _key = 'pending_reports_v1';

  /// Oldest are dropped past this. A phone that has been offline for days
  /// has more current things to say than its backlog.
  static const int _maxQueued = 1000;

  /// The API's own cap per request.
  static const int _batchSize = 200;

  bool _flushing = false;

  Future<void> addAll(List<MeasurementReport> reports) async {
    if (reports.isEmpty) return;
    final queued = await _load();
    queued.addAll(reports);
    final overflow = queued.length - _maxQueued;
    if (overflow > 0) queued.removeRange(0, overflow);
    await _save(queued);
  }

  /// Sends what is queued, a batch at a time, stopping at the first failure.
  Future<void> flush({Future<bool> Function()? mayUpload}) async {
    if (_flushing) return;
    if (mayUpload != null && !await mayUpload()) return;
    _flushing = true;
    var sent = 0;
    try {
      var queued = await _load();
      while (queued.isNotEmpty) {
        final batch = queued.take(_batchSize).toList();
        await _api.postReports([for (final r in batch) r.toJson()]);
        sent += batch.length;
        queued = queued.sublist(batch.length);
        await _save(queued);
      }
    } catch (e) {
      // Kept for the next flush. Not an error the user needs to see.
      AppLog.instance.info('Reports kept for later', detail: '$e');
    } finally {
      _flushing = false;
    }
    if (sent > 0) AppLog.instance.info('Reports sent', detail: '$sent');
  }

  Future<List<MeasurementReport>> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return [];
      return [
        for (final item in jsonDecode(raw) as List)
          if (item is Map<String, dynamic>)
            if (MeasurementReport.fromJson(item) case final MeasurementReport r)
              r,
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<MeasurementReport> reports) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _key, jsonEncode([for (final r in reports) r.toJson()]));
    } catch (_) {
      // Lost reports cost a little evidence, never a feature.
    }
  }
}

final reportQueueProvider =
    Provider<ReportQueue>((ref) => ReportQueue(ref.read(apiClientProvider)));

final reportSinkProvider = Provider<ReportSink>(ReportSink.new);

/// Where measurements go: queued and sent when the user allows it, dropped
/// on the spot when they do not.
class ReportSink {
  ReportSink(this._ref);

  final Ref _ref;

  /// Sends what is queued, but only while no tunnel carries this app's own
  /// traffic.
  ///
  /// The first real reports from a J7 (2026-09-14) came from three different
  /// "reporters" for one phone: they were sent through three candidate
  /// tunnels, so the API saw three VPN servers' exits instead of the user's
  /// network. Held until the tunnel is down, the address is the phone's own.
  Future<void> flush() => _ref.read(reportQueueProvider).flush(
        mayUpload: () async {
          if (!_ref.read(tunnelServiceProvider).noTunnel) return false;
          return await NetworkStatus.vpnActive() != true;
        },
      );

  Future<void> submit({
    required List<({VpnConfig config, ReportOutcome outcome, int? ms})> results,
    required ReportStage stage,
    String? asn,
  }) async {
    if (results.isEmpty) return;
    try {
      // Read from disk, not from whatever the provider holds at this instant:
      // a user who switched sharing off must never have one report slip out
      // because the setting had not loaded yet.
      final prefs = await _ref.read(appPreferencesProvider.future);
      if (!prefs.shareResults) return;
      // Whether another app's VPN carried a measurement is decided by the
      // caller, before measuring. Asked here it races this app's own tunnel,
      // which a connect starts right after its TCP sweep.
      final transport = await NetworkStatus.transport();
      final operator =
          transport == 'cellular' ? await NetworkStatus.mobileOperator() : null;
      final reports = [
        for (final r in results)
          if (MeasurementReport.forConfig(
            r.config,
            stage: stage,
            outcome: r.outcome,
            ms: r.ms,
            asn: asn,
            transport: transport,
            mobileOperator: operator,
          )
              case final MeasurementReport report)
            report,
      ];
      if (reports.isEmpty) return;
      final queue = _ref.read(reportQueueProvider);
      await queue.addAll(reports);
      unawaited(flush());
    } catch (e) {
      AppLog.instance.info('Reports not queued', detail: '$e');
    }
  }
}
