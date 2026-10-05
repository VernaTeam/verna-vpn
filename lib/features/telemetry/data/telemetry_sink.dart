import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_version.dart';
import '../../configs/data/config_api_client.dart';
import '../../configs/presentation/providers/local_test_provider.dart';
import '../../diagnostics/data/app_log.dart';
import '../../settings/data/app_preferences.dart';
import '../../tunnel/data/network_status.dart';
import '../../tunnel/domain/tunnel_snapshot.dart';
import '../../tunnel/presentation/providers/own_ip_provider.dart';
import '../../tunnel/presentation/providers/tunnel_provider.dart';
import '../domain/telemetry_records.dart';
import '../domain/tunnel_facts.dart';
import 'open_session_store.dart';
import 'speed_probe.dart';
import 'telemetry_queue.dart';

final telemetryQueueProvider =
    Provider<TelemetryQueue>((ref) => TelemetryQueue(ConfigApiClient()));

final telemetrySinkProvider = Provider<TelemetrySink>(TelemetrySink.new);

/// Turns what the tunnel did into rows, and sends them.
///
/// The tunnel service reports facts about the tunnel; everything else a row
/// needs -- which transport carried it, which SIM was in the phone, which
/// country the phone was in, how many servers were alive at the time, and
/// whether the user agreed to any of this being sent -- is known here and not
/// there.
class TelemetrySink {
  TelemetrySink(this._ref);

  final Ref _ref;

  SessionRecord? _open;
  Timer? _heartbeat;
  Timer? _retry;
  int _lastSeenEpoch = 0;

  /// Whether this row may leave the phone at all.
  ///
  /// Read from disk each time rather than from whatever the provider holds at
  /// this instant: a user who has just switched sharing off must not have one
  /// last session slip out because the setting had not loaded yet.
  Future<bool> _allowed() async {
    try {
      final prefs = await _ref.read(appPreferencesProvider.future);
      return prefs.shareResults;
    } catch (_) {
      return false;
    }
  }

  /// A tunnel came up. Opens a session, starts its clock, and takes one speed
  /// sample through it.
  Future<void> tunnelUp(TunnelUpFacts facts) async {
    if (!await _allowed()) return;
    final transport = await NetworkStatus.transport();
    final operator =
        transport == 'cellular' ? await NetworkStatus.mobileOperator() : null;

    final session = SessionRecord(
      uid: newUid(),
      startedAt: DateTime.now(),
      picked: facts.picked,
      askedCountry: facts.askedCountry,
      connectMs: facts.connectMs,
      attemptsBefore: facts.attemptsBefore,
      probeMs: facts.probeMs,
      tunnelMs: facts.tunnelMs,
      // Only Verna's own rows carry a numeric id; a server from the user's
      // own subscription has none, and none is sent for it.
      configId: int.tryParse(facts.config.id),
      protocol: facts.config.type.name,
      exitCountry: facts.exitCountry,
      transport: transport,
      operator: operator,
      // The own-IP reading first: the tunnel service's lastAsn comes from the
      // pre-connect ip-api lookup, which is blocked from Iran and therefore
      // null for most of the users this is for.
      asn: _ref.read(ownIpProvider).valueOrNull?.asn ??
          _ref.read(tunnelServiceProvider).lastAsn,
      country: _ref.read(ownIpProvider).valueOrNull?.country,
      appVersion: kAppVersion,
    );
    _open = session;
    _lastSeenEpoch = DateTime.now().millisecondsSinceEpoch;
    await OpenSessionStore.save(session, lastSeenEpoch: _lastSeenEpoch);

    // Refreshed while the session runs, so a session Android kills is
    // recovered with roughly the right length rather than as one second.
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(OpenSessionStore.heartbeat, (_) {
      final current = _open;
      if (current == null) return;
      _lastSeenEpoch = DateTime.now().millisecondsSinceEpoch;
      unawaited(
          OpenSessionStore.save(current, lastSeenEpoch: _lastSeenEpoch));
    });

    // After a moment: the first seconds of a tunnel are the route settling,
    // and a sample taken then measures that rather than the server. Tried
    // twice, because the first attempt lands while the route is still new and
    // a slow mobile tunnel can miss it entirely.
    unawaited(_sampleSpeed(session, delay: const Duration(seconds: 5)));
  }

  /// One speed sample, and one retry a while later if it did not land.
  Future<void> _sampleSpeed(
    SessionRecord session, {
    required Duration delay,
    bool retry = true,
  }) async {
    await Future<void>.delayed(delay);
    // Still the same session? A sample that arrives after the user has
    // reconnected belongs to a tunnel that no longer exists.
    if (_open?.uid != session.uid) return;
    final kbps = await SpeedProbe.measure();
    if (_open?.uid != session.uid) return;
    if (kbps != null) {
      session.speedKbps = kbps;
      AppLog.instance.info('Speed sample', detail: '$kbps KB/s');
      return;
    }
    if (retry) {
      AppLog.instance.info('Speed sample missed', detail: 'trying once more');
      await _sampleSpeed(session,
          delay: const Duration(seconds: 45), retry: false);
    }
  }

  /// Traffic counters from the snapshot stream, for totals and the peak.
  void observe(TunnelSnapshot snapshot) {
    final session = _open;
    if (session == null || !snapshot.isConnected) return;
    if (snapshot.downloadTotal > 0) session.bytesDown = snapshot.downloadTotal;
    if (snapshot.uploadTotal > 0) session.bytesUp = snapshot.uploadTotal;
    final kbps = (snapshot.downloadSpeed / 1024).round();
    if (kbps > (session.peakKbps ?? 0)) session.peakKbps = kbps;
  }

  /// The tunnel is down. Closes the row and queues it.
  Future<void> tunnelDown(EndedBy cause) async {
    final session = _open;
    _open = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    await OpenSessionStore.clear();
    if (session == null) return;
    session.durationS =
        DateTime.now().difference(session.startedAt).inSeconds;
    session.endedBy = cause;
    await _ref.read(telemetryQueueProvider).addSession(session);
    unawaited(flush());
  }

  /// A connect that ended with nothing.
  Future<void> connectFailed(TunnelFailedFacts facts) async {
    if (!await _allowed()) return;
    final transport = await NetworkStatus.transport();
    final operator =
        transport == 'cellular' ? await NetworkStatus.mobileOperator() : null;
    // How many servers this phone had found alive when the attempt began.
    // Without it, "could not connect" cannot be told apart from "this network
    // blocks everything", which is the difference between an app bug and a
    // fact about the user's ISP.
    final live = _ref
        .read(localTestResultsProvider)
        .values
        .where((r) => r.works)
        .length;

    final failure = FailureRecord(
      uid: newUid(),
      at: DateTime.now(),
      reason: facts.reason,
      picked: facts.picked,
      candidatesTried: facts.candidatesTried,
      serversLive: live,
      gaveUpAfterS: facts.gaveUpAfterS,
      askedCountry: facts.askedCountry,
      transport: transport,
      operator: operator,
      asn: _ref.read(ownIpProvider).valueOrNull?.asn ??
          _ref.read(tunnelServiceProvider).lastAsn,
      country: _ref.read(ownIpProvider).valueOrNull?.country,
      appVersion: kAppVersion,
    );
    await _ref.read(telemetryQueueProvider).addFailure(failure);
    unawaited(flush());
  }

  /// Closes a session the last run of the app never got to finish.
  Future<void> recoverAbandoned() async {
    final session = await OpenSessionStore.takeAbandoned();
    if (session == null) return;
    if (!await _allowed()) return;
    AppLog.instance.info('Recovered an unfinished session',
        detail: '${session.durationS ?? 0}s, ended by app_killed');
    await _ref.read(telemetryQueueProvider).addSession(session);
    unawaited(flush());
  }

  /// Sends what is queued, but only while no tunnel is up.
  ///
  /// The same rule the reports use: sent through a tunnel, the server would
  /// see a VPN exit instead of the phone's own network. Here it also keeps the
  /// upload from competing with the connection being measured.
  ///
  /// And it comes back if the moment was wrong. Measured on a J7 on
  /// 2026-10-02: a session was recorded, the speed sample ran, the disconnect
  /// queued the row -- and the one flush it got was the second after the
  /// disconnect, while Android still held the old VPN network up. The guard
  /// refused, correctly, and nothing ever asked again, so the row sat on the
  /// phone. Reports never showed this because the device test flushes them
  /// again a minute later; telemetry has no such second caller, so it needs
  /// its own.
  Future<void> flush() async {
    _retry?.cancel();
    final sent = await _ref.read(telemetryQueueProvider).flush(
          mayUpload: () async {
            if (!_ref.read(tunnelServiceProvider).noTunnel) return false;
            return await NetworkStatus.vpnActive() != true;
          },
        );
    if (!sent) _scheduleRetry(1);
  }

  /// The ghost VPN clears in seconds; a network that is simply down can take
  /// longer. Five tries over about four minutes covers both, and anything
  /// still waiting goes out on the next launch.
  static const int _retries = 5;
  static const Duration _retryAfter = Duration(seconds: 45);

  void _scheduleRetry(int attempt) {
    if (attempt > _retries) return;
    _retry?.cancel();
    _retry = Timer(_retryAfter, () async {
      final sent = await _ref.read(telemetryQueueProvider).flush(
            mayUpload: () async {
              if (!_ref.read(tunnelServiceProvider).noTunnel) return false;
              return await NetworkStatus.vpnActive() != true;
            },
          );
      if (!sent) _scheduleRetry(attempt + 1);
    });
  }
}
