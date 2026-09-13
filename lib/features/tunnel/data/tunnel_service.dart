import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_singbox_client/flutter_singbox_client.dart';

import '../../configs/domain/vpn_config.dart';
import '../../diagnostics/data/app_log.dart';
import '../domain/local_test.dart';
import '../domain/tunnel_snapshot.dart';
import 'candidate_selector.dart';
import 'known_good_store.dart';
import 'network_status.dart';
import 'network_watcher.dart';
import 'notification_permission.dart';
import 'singbox_outbound.dart';

/// Owns the tunnel: picks a config that actually works, brings it up, and
/// reports what it is doing.
///
/// The rule this service exists to enforce: **a tunnel is not working until
/// traffic has been observed leaving through it.** Measured on a Galaxy A54 on
/// 2026-08-20, a config passed a latency probe at 2090ms, the service reported
/// CONNECTED, Android showed the VPN key icon -- and not one byte moved. Every
/// signal short of a completed request through the tunnel can say yes to a
/// tunnel that carries nothing, so every connection here ends with a request.
///
/// Runs on sing-box. The previous core (flutter_v2ray/Xray) was abandoned
/// eighteen months ago, shipped 4 KB-aligned libraries that Google Play
/// rejects, could not run hysteria2, and needed three separate workarounds for
/// its own bugs -- a descriptor race that killed the process, a connection mode
/// that only ever switched one way, and a notification that outlived its
/// service. All three are gone with it: the code below asks the core for its
/// state, its notification, and its latency tests instead of reproducing them.
class TunnelService {
  TunnelService();

  final SingboxClient _client = SingboxClient();
  final StreamController<TunnelSnapshot> _controller =
      StreamController<TunnelSnapshot>.broadcast();
  final AppLog _log = AppLog.instance;

  // Attached in _ensureInitialized, not in the constructor: every member of
  // SingboxClient -- streams included -- reads a platform instance that only
  // exists after initialize() has run, so touching one earlier throws
  // "SingboxPlatformInterface not initialized" and takes the first frame with
  // it.
  StreamSubscription<ServiceState>? _serviceStateSub;
  StreamSubscription<TrafficStats>? _trafficSub;
  StreamSubscription<List<OutboundGroup>>? _groupSub;
  StreamSubscription<String>? _faultSub;
  StreamSubscription<List<LogEntry>>? _coreLogSub;

  TunnelSnapshot _snapshot = const TunnelSnapshot();
  ServiceState _state = ServiceState.stopped;
  bool _initialized = false;
  bool _cancelled = false;
  bool _testing = false;
  bool _testCancelled = false;
  DateTime? _connectedAt;

  /// When the core last reported itself stopped, from any path -- a probe
  /// ending, a tunnel torn down, the notification's stop button.
  DateTime? _stoppedAt;

  final NetworkWatcher _network = NetworkWatcher();
  StreamSubscription<NetworkChange>? _networkSub;

  /// What the last connect() was asked to choose from.
  ///
  /// Kept so a tunnel that dies with the network can be rebuilt from the same
  /// intent -- including whether the user had picked a server by hand, which
  /// must survive a reconnection or the app would quietly move them somewhere
  /// else while their back was turned.
  List<VpnConfig> _lastCandidates = const [];
  bool _lastUserChose = false;
  bool _recovering = false;

  /// Latest urltest results, keyed by outbound tag. Only delays above zero:
  /// the core reports 0 for an outbound it could not reach.
  final Map<String, int> _delays = {};

  /// Every tag the core has finished testing, reachable or not.
  ///
  /// Separate from [_delays] because "tested and dead" and "not tested yet"
  /// have to be told apart -- treating them alike is what made a whole batch
  /// look broken the moment the first result landed.
  final Set<String> _tested = {};

  Stream<TunnelSnapshot> get updates => _controller.stream;
  TunnelSnapshot get snapshot => _snapshot;

  /// Where to ask "what is my exit IP", once traffic is flowing.
  ///
  /// A list because each can fail for its own reason: 1.1.1.1 is blocked from
  /// Iran outright, and hostname probes stop resolving if DNS does not survive
  /// the tunnel. Whichever answers first is used.
  static const List<String> _egressProbes = [
    // Country first, address second. ipify was first and answers with the
    // address alone, so every verification logged "(?)" for the country and
    // fell back to comparing addresses -- which is what let an Iranian exit
    // pass as a working tunnel. The check is only as good as what it is given.
    'http://ip-api.com/json',
    'https://1.1.1.1/cdn-cgi/trace',
    'https://api.ipify.org?format=json',
  ];

  /// Tag of the group the core measures latency across.
  static const String _groupTag = 'auto';

  /// Local port the proxy-mode session listens on while testing.
  static const int _probePort = 21080;

  /// Candidates in one measured group.
  ///
  /// The core tests these itself, in parallel, on one service start, so a
  /// larger batch finishes a long list in fewer core starts. It is not free
  /// though: every member of the group races for the same radio at the same
  /// moment, and on a Galaxy J7 sixty-four simultaneous handshakes made
  /// working servers look slow and slow servers look dead.
  ///
  /// Twenty is the compromise -- few enough that the measurement is of the
  /// server rather than of the queue behind it, large enough that a 200-row
  /// list is ten core starts and not thirty.
  static const int _batchSize = 20;

  /// How many candidates one connection attempt will consider.
  ///
  /// Deliberately not [_batchSize]: that bounds a single measurement, this
  /// bounds the search. They were the same number once, so narrowing the
  /// measurement narrowed the search with it -- a connect attempt on Irancell
  /// tried twenty servers, failed all twenty, and reported no tunnel on a
  /// network where the list finds dozens that work.
  ///
  /// The shortlist is probed in batches regardless, so a longer one costs
  /// probing time rather than memory or sockets.
  static const int _shortlistSize = 80;

  /// How many candidates to try without a probe result behind them.
  ///
  /// The probe can be wrong -- a one-member group reports nothing at all -- so
  /// a few are still tried when it comes back empty. It is not wrong forty
  /// times in a row: on RighTel the app tried all forty, fourteen seconds
  /// each, and spent ten minutes reaching the answer the probe gave in
  /// thirty-five seconds.
  static const int _blindAttempts = 4;

  /// Protocols that listen on UDP, which a TCP connect cannot test.
  ///
  /// Hysteria and TUIC ride on QUIC, so their port refuses a TCP handshake
  /// whether the server works or not. The reachability sweep used to drop
  /// them for exactly that reason; they now pass through to the core's probe,
  /// which speaks their protocol.
  static const Set<VpnConfigType> _udpTypes = {
    VpnConfigType.hysteria,
    VpnConfigType.tuic,
  };

  /// What the latency measurement fetches through the finished tunnel.
  ///
  /// Plain HTTP and an empty body, so the timing is one request and one
  /// response rather than a TLS handshake or a download.
  static const String _latencyProbe = 'http://cp.cloudflare.com/generate_204';

  /// How long a probe waits with no new result before calling it finished.
  static const Duration _settleWindow = Duration(seconds: 4);

  /// How long to let the core finish letting go of its port after a stop.
  ///
  /// Measured rather than picked: with no wait at all the next start failed
  /// with "address already in use" within the same second, and a second of
  /// grace was enough for every start that followed to succeed.
  static const Duration _teardownSettle = Duration(milliseconds: 900);

  /// The shortest a probe may take, however finished the core claims to be.
  ///
  /// The core stamps `urlTestTime` on the whole group at once, so counting
  /// stamped entries said "64 of 64 tested" about 1.1s after the request --
  /// before a single TLS handshake could have completed. Everything still
  /// being measured was then recorded as dead. A floor costs a few seconds per
  /// batch and is the difference between a measurement and a coin toss.
  ///
  /// It has to outlast the core's own probe window, or the run gives up on
  /// exactly the servers the floor exists to wait for.
  static const Duration _probeFloor = Duration(seconds: 8);

  /// How many times a group is measured before its members are believed.
  ///
  /// sing-box gives each outbound a fixed window to fetch the probe URL and
  /// exposes no setting for it, so the only way to be fairer to a slow server
  /// is to ask again. Measured on the J7 on 2026-09-01: of 313 servers, 191
  /// accepted a TCP connection -- the network was not refusing them -- and the
  /// app reported 7 carrying traffic. A single race, run by forty outbounds at
  /// once over one radio, is not a measurement of any of them.
  ///
  /// A second pass costs a few seconds and can only add: a delay is recorded
  /// when it arrives and never withdrawn, so a server that lost the first race
  /// gets counted on the second, and one that already answered is unaffected.
  static const int _probePasses = 2;

  /// Hard ceiling on one probe, however slowly results arrive.
  static const Duration _probeCeiling = Duration(seconds: 45);

  /// How long to let a freshly started tunnel settle before asking it to
  /// carry anything.
  ///
  /// The core reporting `started` means its service is running, not that the
  /// route is installed and the outbound has completed its handshake -- and
  /// the first request pays for both.
  static const Duration _tunnelSettle = Duration(milliseconds: 1200);

  /// How long the verification request may take through a new tunnel.
  ///
  /// Generous on purpose, and measured rather than picked: on Irancell the
  /// device test clocked working servers between 250ms and 3.5s for one small
  /// fetch through a warm session. A cold tunnel to the same server is slower
  /// still, so a five-second budget was rejecting servers for being ordinary.
  static const Duration _verifyBudget = Duration(seconds: 12);

  // -- lifecycle -----------------------------------------------------------

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _client.initialize();
    _initialized = true;
    _serviceStateSub = _client.serviceStateStream.listen(_onServiceState);
    _trafficSub = _client.trafficStatsStream.listen(_onTraffic);
    _groupSub = _client.outboundGroupStream.listen(_onGroups);
    // The core reports a failed start here and nowhere else: connect() returns
    // normally and the service simply never reaches started, so without this a
    // rejected config looks identical to a slow one.
    _faultSub = _client.faultStream.listen(
      (fault) => _log.error('Core fault', detail: fault),
    );

    _network.start();
    _networkSub ??= _network.changes.listen(_onNetworkChange);

    // The core's own log, in debug builds only.
    //
    // Added while chasing a tunnel that carried bytes but resolved no names.
    // Every guess about the DNS block cost a build, an install and a
    // reconnection; the core had been explaining itself the whole time and
    // nobody was listening. Filtered to DNS and errors, because the full
    // stream is far too chatty to read.
    assert(() {
      _coreLogSub = _client.coreLogStream.listen((entries) {
        for (final entry in entries) {
          final line = entry.toString();
          final lower = line.toLowerCase();
          if (lower.contains('dns') ||
              lower.contains('error') ||
              lower.contains('fail')) {
            _log.info('core', detail: line);
          }
        }
      });
      return true;
    }());
  }

  void _emit(TunnelSnapshot next) {
    _snapshot = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  void _onServiceState(ServiceState state) {
    final previous = _state;
    _state = state;
    if (state == ServiceState.stopped) _stoppedAt = DateTime.now();

    // The tunnel can end without this app asking: the notification's stop
    // button, Android reclaiming the service, the core failing. Nothing else
    // watches for that, so a screen saying Connected could outlive the tunnel.
    if (state == ServiceState.stopped &&
        previous != ServiceState.stopped &&
        _snapshot.phase == TunnelPhase.connected) {
      _log.info('Tunnel ended', detail: 'stopped outside the app');
      _connectedAt = null;
      _emit(const TunnelSnapshot(phase: TunnelPhase.idle));
    }
  }

  void _onTraffic(TrafficStats stats) {
    if (_snapshot.phase != TunnelPhase.connected) return;
    _emit(_snapshot.copyWith(
      uploadSpeed: stats.uplinkBps,
      downloadSpeed: stats.downlinkBps,
      uploadTotal: stats.uplinkTotalBytes,
      downloadTotal: stats.downlinkTotalBytes,
      duration: _elapsed(),
    ));
  }

  void _onGroups(List<OutboundGroup> groups) {
    for (final group in groups) {
      for (final item in group.items) {
        // urlTestTime is stamped whether or not the outbound answered, so it
        // marks the test as done; the delay says whether it passed. A urltest
        // reports 0 for an outbound it could not reach, and keeping that as a
        // delay would sort dead servers to the top.
        if (item.urlTestTime != null) _tested.add(item.tag);
        if (item.urlTestDelayMs > 0) _delays[item.tag] = item.urlTestDelayMs;
      }
    }
  }

  /// Re-examines a running tunnel after the network underneath it changed.
  Future<void> _onNetworkChange(NetworkChange change) async {
    if (!change.invalidatesTunnel) return;
    if (_snapshot.phase != TunnelPhase.connected) return;
    if (_recovering || _testing) return;

    _recovering = true;
    try {
      _log.info('Network changed', detail: '$change');

      // The same question that qualified this tunnel in the first place: do
      // bytes come back? A handover the core absorbed leaves this answering
      // yes, and then there is nothing to do.
      final still = await _readEgress(timeout: const Duration(seconds: 8));
      if (still != null) {
        _log.good('Tunnel survived the change', detail: still.ip);
        _emit(_snapshot.copyWith(
          exitIp: still.ip,
          exitCountryCode: still.country,
        ));
        return;
      }

      if (_lastCandidates.isEmpty) {
        _log.warn('Tunnel lost with the network',
            detail: 'nothing to rebuild from');
        await _stop();
        _emit(const TunnelSnapshot(phase: TunnelPhase.idle));
        return;
      }

      _log.warn('Tunnel died with the network', detail: 'rebuilding');
    } finally {
      _recovering = false;
    }

    // Outside the guard: connect() is long, and holding _recovering across it
    // would block the next change from ever being noticed.
    await connect(_lastCandidates, userChose: _lastUserChose);
  }

  String _elapsed() {
    final since = _connectedAt;
    if (since == null) return '00:00:00';
    final d = DateTime.now().difference(since);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  // -- public API ----------------------------------------------------------

  Future<bool> requestPermission() async {
    await _ensureInitialized();
    return _client.requestVPNPermission();
  }

  /// Re-attach to a tunnel that is already running.
  ///
  /// The service outlives the UI: closing the app leaves it running while
  /// Android may destroy the Flutter engine, and the rebuilt Dart state would
  /// otherwise report "not connected" over a live tunnel. The core is asked
  /// rather than remembered, and the exit address is re-measured rather than
  /// restored, because a stored one could describe a tunnel that has since
  /// dropped.
  Future<void> restore() async {
    try {
      await _ensureInitialized();
      final state = await _client.getServiceState();
      if (!state.isRunning) return;
    } catch (_) {
      return;
    }

    _state = ServiceState.started;
    _connectedAt ??= DateTime.now();
    _emit(const TunnelSnapshot(phase: TunnelPhase.connected));

    final egress = await _readEgress(timeout: const Duration(seconds: 10));
    if (egress == null) return;
    _emit(_snapshot.copyWith(
      exitIp: egress.ip,
      exitCountryCode: egress.country,
    ));
  }

  /// Brings up the first candidate that demonstrably carries traffic.
  ///
  /// [userChose] marks a server picked by hand. It turns off the remembered
  /// shortlist, which otherwise runs first and wins: choosing a server in the
  /// United States connected to the Italian one that happened to work last
  /// time, every time, because memory was consulted before the request was.
  /// A deliberate choice is not a hint to be improved upon.
  Future<void> connect(
    List<VpnConfig> candidates, {
    bool userChose = false,
  }) async {
    if (_testing) {
      _testCancelled = true;
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    _cancelled = false;
    _lastCandidates = candidates;
    _lastUserChose = userChose;
    // Named in the log, because the row a finger lands on is not always the
    // row the eye picked -- and "it failed" is only a useful report once it
    // is certain which server failed.
    if (userChose && candidates.length == 1) {
      final chosen = candidates.single;
      _log.info('Connecting to chosen server',
          detail: '${chosen.type.label} ${chosen.countryCode} #${chosen.id}');
    }
    _emit(const TunnelSnapshot(phase: TunnelPhase.preparing));

    try {
      await _ensureInitialized();
      await _stop();

      // Also here, because a hand-picked server comes straight to the service
      // without the provider's fetch -- and would otherwise spend its egress
      // and reachability timeouts discovering the same thing.
      if (!await NetworkStatus.hasInternet()) {
        _emit(const TunnelSnapshot(
          phase: TunnelPhase.failed,
          failure: TunnelFailure.noInternet,
        ));
        return;
      }

      if (!await _client.requestVPNPermission()) {
        _emit(const TunnelSnapshot(
          phase: TunnelPhase.failed,
          failure: TunnelFailure.permissionDenied,
        ));
        return;
      }

      // Asked here, right after the VPN consent, because the two dialogs
      // belong to the same moment. Not awaited: a refusal costs the
      // notification, never the tunnel.
      if (!await NotificationPermission.granted()) {
        unawaited(NotificationPermission.request());
      }

      final usable =
          candidates.where((c) => tunnelableTypes.contains(c.type)).toList();
      if (usable.isEmpty) {
        _emit(const TunnelSnapshot(
          phase: TunnelPhase.failed,
          failure: TunnelFailure.noCandidates,
        ));
        return;
      }

      // The device's own exit, so a change of country means something -- and
      // the network it is on, so the right memories are consulted.
      final before = await _readEgress(timeout: const Duration(seconds: 6));
      final network = before?.network ?? 'unknown';

      // Servers this phone has already connected through on this network, in
      // front of everything. A connection used to begin by rediscovering the
      // world: fetch the pool, sweep it, probe it in batches, then try
      // candidates one by one. Ninety seconds, for a question that had been
      // answered ten minutes earlier and thrown away when the process ended.
      final remembered =
          userChose ? const <KnownGood>[] : await KnownGoodStore.forNetwork(network);
      final rememberedConfigs = [for (final e in remembered) e.toConfig()];

      // A plain TCP connect to each server, all at once. The core's own test
      // is better but costs a service start; this throws out hosts that are
      // not listening at all for the price of a single timeout.
      _emit(_snapshot.copyWith(
        phase: TunnelPhase.searching,
        attempt: 0,
        total: usable.length,
      ));
      final reachable = await _reachable(usable, fallbackToAll: false);
      if (_cancelled) return;

      // Nothing on the list accepts a connection from this network, and
      // nothing has worked here before. Every tunnel would fail for the same
      // reason, so say so now instead of proving it forty times.
      if (reachable.isEmpty && rememberedConfigs.isEmpty) {
        _log.warn('No server reachable',
            detail: '0 of ${usable.length} accepted a connection');
        _emit(TunnelSnapshot(
          phase: TunnelPhase.failed,
          failure: TunnelFailure.noneAnswered,
          total: usable.length,
        ));
        return;
      }

      // The remembered ones are not put through the reachability sweep or the
      // probe: they have carried real traffic from this phone, which is a
      // stronger claim than either test makes, and the egress check below is
      // still what decides.
      final seenIds = <String>{};
      final shortlist = [
        for (final config in [...rememberedConfigs, ...reachable])
          if (seenIds.add(config.id)) config,
      ].take(_shortlistSize).toList();
      _emit(_snapshot.copyWith(
        phase: TunnelPhase.searching,
        attempt: 0,
        total: shortlist.length,
      ));

      // Two passes, cheapest first.
      //
      // First, what has already carried traffic from this phone on this
      // network -- no probe, because a real connection already answered the
      // question the probe would ask. Then the rest a batch at a time: probe
      // twenty, try whatever answered, and only probe the next twenty if
      // none of those carried traffic. Ranking the whole list first spent
      // forty of fifty-six seconds on a J7 finding servers after the first
      // one had already been found.
      //
      // When the probe finds nobody answering, only [_blindAttempts] are
      // tried anyway. The queue used to fall back to the whole shortlist: on
      // RighTel that was forty tunnels at fourteen seconds each, ten minutes
      // to report a failure the probe had already reported.
      final remainder = [
        for (final config in shortlist)
          if (!rememberedConfigs.any((r) => r.id == config.id)) config,
      ];

      var attempt = 0;
      int total =
          rememberedConfigs.length + min<int>(remainder.length, _blindAttempts);

      for (final config in rememberedConfigs) {
        if (_cancelled) return;
        attempt++;
        if (await _tryCandidate(config, 0, before, network, attempt, total)) {
          return;
        }
      }

      // A one-member group reports nothing at all -- measured on an A54,
      // "1 outbounds -> 0 tested, 0 answered" -- so a single candidate is not
      // probed; it is simply tried.
      var anyAnswered = remainder.length <= 1;
      if (remainder.length == 1) {
        attempt++;
        total = attempt;
        if (await _tryCandidate(
            remainder.single, 0, before, network, attempt, total)) {
          return;
        }
      }

      for (var start = 0;
          remainder.length > 1 && start < remainder.length;
          start += _batchSize) {
        if (_cancelled) return;
        final batch =
            remainder.sublist(start, min(start + _batchSize, remainder.length));
        final ranked = await _rank(batch, retryOnlyIfSilent: true);
        if (_cancelled) return;
        if (ranked.isEmpty) continue;

        anyAnswered = true;
        total = attempt + ranked.length;
        for (final candidate in ranked) {
          if (_cancelled) return;
          attempt++;
          if (await _tryCandidate(candidate.config, candidate.milliseconds,
              before, network, attempt, total)) {
            return;
          }
        }
      }

      // Nobody answered a single probe. The probe can be wrong, so a few are
      // tried anyway -- a few, not the whole list.
      if (!anyAnswered) {
        final blind = remainder.take(_blindAttempts).toList();
        total = attempt + blind.length;
        for (final config in blind) {
          if (_cancelled) return;
          attempt++;
          if (await _tryCandidate(config, 0, before, network, attempt, total)) {
            return;
          }
        }
      }

      _emit(TunnelSnapshot(
        phase: TunnelPhase.failed,
        failure: TunnelFailure.noneAnswered,
        total: attempt,
      ));
    } catch (e) {
      await _stop();
      _emit(TunnelSnapshot(
        phase: TunnelPhase.failed,
        failure: TunnelFailure.error,
        errorDetail: '$e',
      ));
    }
  }

  /// Starts [config], proves traffic leaves through it, and publishes the
  /// connected state. False means move on to the next candidate.
  Future<bool> _tryCandidate(
    VpnConfig config,
    int probeMs,
    _Egress? before,
    String network,
    int attempt,
    int total,
  ) async {
    _emit(_snapshot.copyWith(
      phase: TunnelPhase.searching,
      attempt: attempt,
      total: total,
    ));

    if (!await _startTunnel(config)) {
      await _stop();
      return false;
    }
    _log.info('Tunnel up', detail: 'checking that traffic leaves through it');

    // Let the route settle before the first request, or the cost of
    // installing it is charged to the server.
    await Future<void>.delayed(_tunnelSettle);
    if (_cancelled) return false;

    // Each probe's own failure, kept for the log. "No answer through the
    // tunnel" was all a rejected server ever said, and it covers causes with
    // different fixes: names that will not resolve inside the tunnel, a route
    // that swallows connections, a TLS error.
    final failures = <String>[];
    final after =
        await _readEgress(timeout: _verifyBudget, failures: failures);
    final verdict = _verifyEgress(before, after, config);
    if (verdict != null || after == null) {
      // A hand-picked server gets one more question before it is given up
      // on, because its failure is the one a user asks about: does anything
      // pass when no name has to be resolved? That tells a server that is
      // dead in the tunnel from one that only cannot reach the resolver.
      final withoutDns =
          _lastUserChose && after == null ? await _probeWithoutDns() : null;
      _log.warn('Tunnel carried no traffic',
          detail: [
            verdict ?? 'no answer through the tunnel',
            if (after == null && failures.isNotEmpty) failures.join('; '),
            if (withoutDns != null) withoutDns,
          ].join(' -- '));
      // A remembered server that has stopped working must not keep being
      // tried first, or the shortcut becomes the slow path.
      await KnownGoodStore.forget(config.id, network);
      await _stop();
      return false;
    }

    final latency = await _measureLatency();
    final pingMs = latency ?? (probeMs > 0 ? probeMs : null);

    await KnownGoodStore.remember(config, network, milliseconds: pingMs);

    _connectedAt = DateTime.now();
    _emit(TunnelSnapshot(
      phase: TunnelPhase.connected,
      active: config,
      exitIp: after.ip,
      exitCountryCode: after.country,
      pingMs: pingMs,
      attempt: attempt,
      total: total,
    ));
    _log.good('Connected',
        detail: '${after.ip} (${after.country ?? '?'}), '
            '${pingMs == null ? 'latency unknown' : '$pingMs ms'}');
    return true;
  }

  /// Round trip through the finished tunnel, on a connection already open.
  ///
  /// What the screen called "ping" used to be either the core's urltest delay
  /// or the time the whole verification took. Both include setting up a
  /// connection -- the TCP handshake to the server, the proxy's own
  /// handshake, and for the verification a TLS handshake on top -- so a
  /// server 250ms away read as 546ms, 1900ms, 3291ms. That measures how long
  /// a new connection takes to open, not how far away the server is.
  ///
  /// So this opens one connection, discards the first request (it pays for
  /// the setup), and times the next two on the same socket. The faster of
  /// those is one request and one response through the tunnel, which is what
  /// a person means by ping.
  Future<int?> _measureLatency() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5)
      ..idleTimeout = const Duration(seconds: 10);
    try {
      int? best;
      for (var i = 0; i < 3; i++) {
        final stopwatch = Stopwatch()..start();
        final request = await client
            .getUrl(Uri.parse(_latencyProbe))
            .timeout(const Duration(seconds: 5));
        final response =
            await request.close().timeout(const Duration(seconds: 5));
        await response.drain<void>();
        stopwatch.stop();
        if (i == 0) continue;
        final ms = stopwatch.elapsedMilliseconds;
        if (best == null || ms < best) best = ms;
      }
      return best;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> disconnect() async {
    _cancelled = true;
    // Forget the request, so a network change after a deliberate disconnect
    // does not helpfully bring the tunnel back up.
    _lastCandidates = const [];
    await _stop();
    _connectedAt = null;
    _emit(const TunnelSnapshot(phase: TunnelPhase.idle));
  }

  void stopTesting() => _testCancelled = true;

  /// Tests configs from this phone and reports which carry traffic.
  ///
  /// The server can only prove a config is alive from where the server sits.
  /// This answers the question that decides whether the user can use it.
  Future<Map<String, LocalTest>> testCandidates(
    List<VpnConfig> configs, {
    void Function(int done, int total, int working)? onProgress,
    void Function(Map<String, LocalTest> partial)? onBatch,
  }) async {
    if (_state != ServiceState.stopped) {
      _log.warn('Server test skipped', detail: 'a tunnel is currently up');
      return const {};
    }
    final subject =
        configs.where((c) => tunnelableTypes.contains(c.type)).toList();
    if (subject.isEmpty) return const {};

    _testing = true;
    _testCancelled = false;
    _log.info('Testing servers from this device',
        detail: '${subject.length} configs');

    final results = <String, LocalTest>{};
    await _ensureInitialized();

    final reachable = (await _reachable(subject)).toSet();
    _log.info('Reachability filter',
        detail: '${reachable.length} of ${subject.length} accepted TCP');
    for (final config in subject) {
      if (!reachable.contains(config)) {
        results[config.id] = const LocalTest.unreachable();
      }
    }
    var done = subject.length - reachable.length;
    onProgress?.call(done, subject.length, 0);
    onBatch?.call(Map<String, LocalTest>.from(results));

    final ordered = reachable.toList();
    var working = 0;
    // No _enoughWorking shortcut here, unlike the connect sweep: stopping at
    // ten leaves the rest of the list saying "Not tested" next to rows that
    // have a ping, which reads as the test having failed.
    for (var start = 0; start < ordered.length; start += _batchSize) {
      if (_testCancelled) break;
      final batch =
          ordered.sublist(start, min(start + _batchSize, ordered.length));
      final ranked = await _rank(batch);

      final byId = {for (final r in ranked) r.config.id: r};
      final partial = <String, LocalTest>{};
      for (final config in batch) {
        final hit = byId[config.id];
        final result = hit == null
            ? const LocalTest.noTraffic()
            : LocalTest.alive(hit.milliseconds, null);
        results[config.id] = result;
        partial[config.id] = result;
        if (hit != null) working++;
      }
      done += batch.length;
      onBatch?.call(partial);
      onProgress?.call(done, subject.length, working);
    }

    _testing = false;
    _log.good('Server test finished',
        detail: '$working of ${subject.length} carried traffic from here');
    return results;
  }

  // -- core interaction ----------------------------------------------------

  /// Runs [candidates] in proxy mode and asks the core to time each one.
  ///
  /// Replaces a hand-written SOCKS5 client, manual batching and a halving
  /// retry: sing-box measures a urltest group itself, in parallel, and reports
  /// per-outbound delays. No TUN device is created, so nothing here can
  /// disturb a connection or leave a descriptor behind.
  Future<List<({VpnConfig config, int milliseconds})>> _rank(
    List<VpnConfig> candidates, {
    bool retryOnlyIfSilent = false,
  }) async {
    if (candidates.isEmpty) return const [];

    final tags = <String, VpnConfig>{};
    final outbounds = <Map<String, dynamic>>[];
    for (var i = 0; i < candidates.length; i++) {
      final tag = 'node_$i';
      final outbound = SingboxOutbound.fromConfig(candidates[i], tag);
      if (outbound == null) continue;
      tags[tag] = candidates[i];
      outbounds.add(outbound);
    }
    if (outbounds.isEmpty) {
      _log.warn('Probe skipped', detail: 'no candidate could be converted');
      return const [];
    }
    _log.info('Probe starting', detail: '${outbounds.length} outbounds');

    final config = _probeConfig(outbounds);
    try {
      // Validated before it is run: a single malformed outbound used to take
      // the whole batch down with it, and the core will say so up front.
      await _client.checkConfig(config);
    } catch (e) {
      _log.warn('Probe config rejected', detail: '$e');
      return const [];
    }

    _delays.clear();
    _tested.clear();
    await _awaitPortFree();
    try {
      await _client.connect(SessionOptions(
        config: config,
        networkMode: NetworkMode.proxy,
        notification: const NotificationConfig(
          title: 'Verna VPN',
          channelName: 'VPN service',
          showTrafficStats: false,
          showStopButton: false,
        ),
      ));
      if (!await _awaitState(ServiceState.started, seconds: 10)) {
        _log.warn('Probe skipped', detail: 'core never reached started');
        return const [];
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));
      for (var pass = 1; pass <= _probePasses; pass++) {
        await _client.urlTest(_groupTag);
        await _awaitGroupTested(outbounds.length);
        // Everyone answered, so a second race would only cost time.
        if (_delays.length >= outbounds.length) break;
        // A connection needs one server that works, not a complete ranking:
        // if anyone answered, try them before spending another pass.
        if (retryOnlyIfSilent && _delays.isNotEmpty) break;
        if (pass < _probePasses) {
          _log.info('Probe retrying',
              detail: '${_delays.length} of ${outbounds.length} answered');
        }
      }
      _log.info('Probe finished',
          detail: '${_tested.length} tested, ${_delays.length} answered');
    } catch (e) {
      _log.warn('Probe failed', detail: '$e');
      return const [];
    } finally {
      await _stop();
    }

    final ranked = <({VpnConfig config, int milliseconds})>[];
    _delays.forEach((tag, delay) {
      final config = tags[tag];
      if (config != null) ranked.add((config: config, milliseconds: delay));
    });
    ranked.sort((a, b) => a.milliseconds.compareTo(b.milliseconds));
    return ranked;
  }

  /// Decides whether traffic is really leaving through the tunnel.
  ///
  /// Returns null when the tunnel is carrying traffic, or a short reason when
  /// it is not.
  ///
  /// This used to be `after.ip != before.ip`, and that comparison is not the
  /// question. A phone moving from mobile data to Wi-Fi changes its address;
  /// so does carrier NAT, on its own schedule. On an A54 on 2026-08-27 the app
  /// announced "Connected -- 31.171.101.93" -- the handset's own Iranian
  /// address -- and Chrome could not load a page, because the only thing the
  /// check had established was that two readings differed.
  ///
  /// Country is the honest test. It survives NAT rotation, it survives a
  /// change of network, and it is what the user is actually buying: an exit
  /// somewhere else. Where the server's own country is known, the exit has to
  /// match it; where it is not, the exit merely has to be somewhere other than
  /// where the phone started.
  String? _verifyEgress(_Egress? before, _Egress? after, VpnConfig config) {
    if (after == null) return 'no answer through the tunnel';

    final exit = after.country?.toUpperCase();
    final expected = config.countryCode.toUpperCase();
    final origin = before?.country?.toUpperCase();

    if (exit != null && expected.length == 2) {
      // The server says where it is; the tunnel has to agree.
      return exit == expected ? null : 'exit in $exit, server claims $expected';
    }

    if (exit != null && origin != null) {
      return exit == origin ? 'exit still in $exit' : null;
    }

    // No country from either reading -- fall back to the address, which is
    // weak but better than accepting anything.
    if (before?.ip != null && after.ip == before!.ip) return 'address unchanged';
    return null;
  }

  /// Waits for the core to finish testing all [expected] outbounds.
  ///
  /// urlTest returns the moment the core accepts the request -- the results
  /// then trickle in over several seconds. Returning on the first one, as this
  /// did, meant every server still being measured was recorded as dead: one
  /// row showed a ping and the rest of the list vanished.
  ///
  /// Ends on whichever comes first: every outbound tested, no new result for
  /// [_settleWindow] (the stragglers are servers that will not answer at all),
  /// or the hard ceiling.
  Future<void> _awaitGroupTested(int expected) async {
    final start = DateTime.now();
    final floor = start.add(_probeFloor);
    final deadline = start.add(_probeCeiling);
    var seen = -1;
    var lastChange = start;

    while (DateTime.now().isBefore(deadline)) {
      if (_testCancelled || _cancelled) return;

      // Counted on answers, not on the core's own "tested" stamp: a server
      // that will never answer looks identical to one still being tried, and
      // only the passage of time tells them apart.
      if (_delays.length != seen) {
        seen = _delays.length;
        lastChange = DateTime.now();
      }

      final past = DateTime.now().isAfter(floor);
      if (past && _delays.length >= expected) return;
      if (past && DateTime.now().difference(lastChange) > _settleWindow) return;

      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  Future<bool> _startTunnel(VpnConfig config) async {
    final outbound = SingboxOutbound.fromConfig(config, 'proxy');
    if (outbound == null) return false;
    final json = _tunnelConfig(outbound, config);
    try {
      await _awaitPortFree();
      await _client.checkConfig(json);
      await _client.connect(SessionOptions(
        config: json,
        networkMode: NetworkMode.vpn,
        notification: NotificationConfig(
          // Reads left to right even on a Persian system: without the mark the
          // shell reorders the pieces around the pipe.
          title: '‎Verna VPN | ${_label(config)}',
          channelName: 'VPN service',
          showTrafficStats: true,
          showStopButton: true,
          stopButtonLabel: 'Disconnect',
        ),
      ));
      return _awaitState(ServiceState.started, seconds: 15);
    } catch (e) {
      _log.warn('Tunnel start failed', detail: '$e');
      return false;
    }
  }

  String _label(VpnConfig config) {
    final name = config.country.isNotEmpty ? config.country : config.countryCode;
    if (name.isEmpty) return 'Verna';
    final code = config.countryCode;
    return code.length == 2 ? '$name ${_flag(code)}' : name;
  }

  String _flag(String code) {
    const base = 0x1F1E6;
    final upper = code.toUpperCase();
    return String.fromCharCodes(
        [base + upper.codeUnitAt(0) - 0x41, base + upper.codeUnitAt(1) - 0x41]);
  }

  /// Stops the service and waits until the core has actually let go.
  ///
  /// "Stopped" arrives on the state stream before the core has released its
  /// command port, and starting the next candidate into that gap fails --
  ///
  ///   Start failed: listen command server: listen tcp 127.0.0.1:10086:
  ///   bind: address already in use
  ///
  /// -- and then keeps failing, because each attempt leaves another listener
  /// half-closed behind it. Every start after that times out at fifteen
  /// seconds. This is what turns "the first server did not work" into "connect
  /// and disconnect a few times and eventually it works": a search that should
  /// move on after one failure instead poisons every attempt that follows.
  ///
  /// The settle is short and unconditional. Skipping it when the state says
  /// stopped is exactly the mistake -- the state is what was wrong.
  /// Blocks until the core has had [_teardownSettle] since it last stopped.
  ///
  /// The settle used to live at the end of _stop(), which looked right and was
  /// not: _stop() returns immediately when the state already says stopped, so
  /// a start that followed a *probe* -- the device test stops the core dozens
  /// of times -- skipped the wait entirely and hit
  ///
  ///   listen tcp 127.0.0.1:10086: bind: address already in use
  ///
  /// The guard belongs at the start, where every path passes, rather than at
  /// the end of one of them.
  Future<void> _awaitPortFree() async {
    final stopped = _stoppedAt;
    if (stopped == null) return;
    final elapsed = DateTime.now().difference(stopped);
    if (elapsed >= _teardownSettle) return;
    await Future<void>.delayed(_teardownSettle - elapsed);
  }

  Future<void> _stop() async {
    if (_state == ServiceState.stopped) return;
    try {
      await _client.disconnect();
    } catch (_) {
      // Already gone.
    }
    await _awaitState(ServiceState.stopped, seconds: 8);
  }

  Future<bool> _awaitState(ServiceState want, {int seconds = 10}) async {
    final deadline = DateTime.now().add(Duration(seconds: seconds));
    while (DateTime.now().isBefore(deadline)) {
      if (_state == want) return true;
      if (_cancelled && want == ServiceState.started) return false;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return _state == want;
  }

  // -- configs -------------------------------------------------------------

  /// A proxy-mode config whose outbounds sit in one urltest group.
  String _probeConfig(List<Map<String, dynamic>> outbounds) {
    return jsonEncode({
      'log': {'level': 'error'},
      'inbounds': [
        {
          'type': 'socks',
          'tag': 'in',
          'listen': '127.0.0.1',
          'listen_port': _probePort,
        }
      ],
      'outbounds': [
        {
          'type': 'urltest',
          'tag': _groupTag,
          'outbounds': [for (final o in outbounds) o['tag'] as String],
          // Plain HTTP on purpose: a TLS handshake failing tells us about the
          // certificate, not about whether the proxy passes bytes.
          'url': 'http://cp.cloudflare.com/generate_204',
          'interval': '10m',
        },
        ...outbounds,
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': {
        'rules': [
          {'inbound': 'in', 'outbound': _groupTag}
        ]
      },
    });
  }

  /// A VPN-mode config for one chosen server.
  String _tunnelConfig(Map<String, dynamic> outbound, VpnConfig config) {
    return jsonEncode({
      // Warnings too, not only errors: a DNS exchange failing inside the
      // tunnel is not always logged at error level, and the core's own account
      // of it is what tells a resolver problem apart from a dead server.
      'log': {'level': 'warn'},
      'dns': {
        // The 1.12 server format, not the `address:` one every share-config
        // tutorial still shows: sing-box 1.14 removed the legacy shape and
        // refuses the whole config over it, which surfaced here as a tunnel
        // that reported "the server didn't respond" without contacting one.
        'servers': [
          // DNS over HTTPS, on port 443.
          //
          // Two wrong answers came before this one. UDP needs the outbound to
          // relay UDP, and most free configs here are TCP-only, so every
          // query vanished. DoT fixed that but asks for port 853, and the
          // core's log showed those connections timing out at 5 and 10
          // seconds -- these proxies carry 443 and little else.
          //
          // DoH is the shape that matches what a censored network already
          // permits: it is a TCP connection to port 443 carrying what looks
          // like ordinary web traffic, which is precisely what the proxy
          // exists to move.
          {
            'tag': 'remote',
            'type': 'https',
            'server': '1.1.1.1',
            'detour': 'proxy',
          },
          // No detour: naming the direct outbound explicitly is rejected by
          // 1.14 ("detour to an empty direct outbound makes no sense"), and
          // direct is what a server without one does anyway.
          {'tag': 'local', 'type': 'udp', 'server': '8.8.8.8'},
          // The phone's own resolver, for one job only: finding the proxy
          // server itself. See default_domain_resolver below.
          {'tag': 'system', 'type': 'local'},
        ],
        // Resolved through the tunnel, so name lookups cannot leak to a
        // resolver that is being tampered with locally.
        'final': 'remote',
        'strategy': 'ipv4_only',
      },
      'inbounds': [
        {
          'type': 'tun',
          'tag': 'tun-in',
          'address': ['172.19.0.1/30'],
          // 1500 leaves no headroom for the tunnel's own framing: the TCP
          // handshake gets through and larger packets are dropped, which reads
          // as a connection that opens and then stalls.
          'mtu': 1400,
          'auto_route': true,
          'strict_route': false,
          'stack': 'mixed',
        }
      ],
      'outbounds': [
        outbound,
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': {
        'auto_detect_interface': true,
        // How the core finds a server published under a name, not an address.
        //
        // Unset, it asked dns.final -- DNS over HTTPS *through the proxy*,
        // which cannot be reached before the proxy's address is known. Every
        // such server was dead in the tunnel while passing the device test,
        // whose config has no dns block and so uses the system resolver.
        // Measured on a J7 on 2026-09-13: a Trojan server under a .ir name
        // tested green at 226 ms, then "Tunnel carried no traffic -- 1.1.1.1:
        // connection reset; ip-api.com, api.ipify.org: connect timed out".
        // About one verified server in ten has a name for an address, and six
        // Trojan servers in ten do.
        //
        // The system resolver is what the device test already relies on, and
        // it leaks nothing a connection to that server would not show anyway.
        // Every other lookup still goes through the tunnel.
        'default_domain_resolver': 'system',
        'rules': [
          // Sniffing first, so the router can tell what a connection carries.
          {'action': 'sniff'},

          // Hijacked by port, not by protocol.
          //
          // `{'protocol': 'dns', 'action': 'hijack-dns'}` reads better and did
          // nothing: protocol matching depends on sniffing having identified
          // the payload, and a DNS query is one UDP packet that the router
          // never got to inspect. The core said so plainly once its own log
          // was being read --
          //
          //   inbound/tun[tun-in]: inbound packet connection to 172.19.0.2:53
          //   outbound/shadowsocks[proxy]: outbound packet connection to
          //                                172.19.0.2:53
          //
          // -- every query was being posted to the tunnel's own peer address
          // and then forwarded abroad as ordinary traffic, where nothing was
          // ever going to answer it. Port 53 is the one thing about a DNS
          // query that needs no interpretation.
          {'port': 53, 'action': 'hijack-dns'},

          // Kept as well: it costs nothing and catches DNS on odd ports once
          // sniffing has had its say.
          //
          // Routing DNS to an outbound forwards the raw UDP packet and hopes
          // something answers it; the dns block above is then never consulted,
          // so nothing resolves. Measured on a Galaxy J7 on 2026-08-27 with a
          // working Dutch exit: a raw address (208.95.112.1) returned a full
          // page through the tunnel, while api.ipify.org hung forever. Every
          // app had working connectivity and no names -- which is exactly what
          // "connected but nothing loads" looks like from the inside.
          //
          // The action hands the query to sing-box's own resolver instead,
          // which is what the dns block was written for.
          {'protocol': 'dns', 'action': 'hijack-dns'},
        ],
      },
    });
  }

  // -- measurement ---------------------------------------------------------

  /// Drops candidates whose server will not accept a TCP connection, ordered
  /// by how quickly it did.
  Future<List<VpnConfig>> _reachable(
    List<VpnConfig> candidates, {
    bool fallbackToAll = true,
  }) async {
    final checks = candidates.map((config) async {
      // Kept, untested, and sorted after everything that answered: see
      // [_udpTypes]. The core's probe decides whether they work.
      if (_udpTypes.contains(config.type)) {
        return (config: config, micros: 1 << 29);
      }
      final endpoint = CandidateSelector.endpointOf(config);
      if (endpoint == null) return (config: config, micros: 1 << 30);
      final stopwatch = Stopwatch()..start();
      try {
        final socket = await Socket.connect(endpoint.host, endpoint.port,
            timeout: const Duration(seconds: 4));
        stopwatch.stop();
        socket.destroy();
        return (config: config, micros: stopwatch.elapsedMicroseconds);
      } catch (_) {
        return null;
      }
    });

    final results = (await Future.wait(checks)).nonNulls.toList()
      ..sort((a, b) => a.micros.compareTo(b.micros));
    final live = results.map((r) => r.config).toList();
    // With [fallbackToAll], nothing reachable is read as "probably offline"
    // and the whole list comes back, which suits the server list. The connect
    // path turns it off: there, nothing reachable is an answer, and treating
    // it as "try everything" was the longest route to the same failure.
    if (live.isEmpty && fallbackToAll) return candidates;
    return live;
  }

  /// Asks, through the tunnel, where traffic is coming out.
  ///
  /// All probes at once, and the first useful answer wins.
  ///
  /// They used to be tried in turn, each with a twelve second budget for
  /// connecting and another twelve for reading. When a tunnel carried nothing
  /// -- the common case while searching -- every probe ran to its timeout
  /// before the next was tried, and rejecting one dead server took the best
  /// part of forty seconds. Measured on a J7: four candidates, thirty-seven
  /// seconds apart, which is most of why connecting felt like minutes.
  ///
  /// Racing them costs nothing extra: they are three small requests, and a
  /// tunnel that cannot answer any of them in [timeout] is not one worth
  /// waiting longer for.
  Future<_Egress?> _readEgress({
    required Duration timeout,
    List<String>? failures,
  }) async {
    // The comment above always described this; the code did not. It used
    // Future.wait, which returns when the *last* probe finishes -- and one
    // probe is 1.1.1.1, blocked from Iran, so outside the tunnel every reading
    // ran to its full timeout however fast ip-api answered. A Completer
    // returns on the first reading that carries a country.
    final answer = Completer<_Egress?>();
    final clients = <Dio>[];
    _Egress? partial;
    var pending = _egressProbes.length;

    void settle() {
      pending--;
      if (pending == 0 && !answer.isCompleted) answer.complete(partial);
    }

    for (final url in _egressProbes) {
      final dio = Dio(BaseOptions(
        connectTimeout: timeout,
        receiveTimeout: timeout,
        responseType: ResponseType.plain,
      ));
      clients.add(dio);
      dio.get<String>(url).then<void>((res) {
        final reading = _parseEgress(res.data ?? '');
        if (reading == null) {
          failures?.add('${_hostOf(url)}: unreadable reply');
          return;
        }
        // A reading with a country settles the question at once; one without
        // only half answers it and is kept in case nothing better arrives.
        if (reading.country != null) {
          if (!answer.isCompleted) answer.complete(reading);
        } else {
          partial ??= reading;
        }
      }, onError: (Object e) {
        failures?.add('${_hostOf(url)}: ${_whyFailed(e)}');
      }).whenComplete(settle);
    }

    try {
      return await answer.future.timeout(
        timeout + const Duration(seconds: 2),
        onTimeout: () => partial,
      );
    } finally {
      // The losers are cut off rather than left to run out their timeouts in
      // the background, still holding sockets through a tunnel that may be
      // about to be torn down.
      for (final dio in clients) {
        dio.close(force: true);
      }
    }
  }

  /// Asked through a tunnel that just failed its egress check, by address, so
  /// no name has to resolve. Never used to pass a tunnel -- a tunnel whose
  /// names do not resolve is useless however well it carries bytes -- only to
  /// say why one failed.
  static const List<String> _dnsFreeProbes = [
    // ip-api.com by its address: not Cloudflare, no DNS. Answers means the
    // tunnel carries traffic and the failure is the resolver.
    'http://208.95.112.1/json',
    // Google's DNS-over-HTTPS, by address. Answers means a resolver other
    // than 1.1.1.1 would have worked through this server.
    'https://8.8.8.8/resolve?name=example.com&type=A',
  ];

  Future<String> _probeWithoutDns() async {
    final answers = await Future.wait([
      for (final url in _dnsFreeProbes) _probeOnce(url),
    ]);
    return 'without DNS: ${answers.join('; ')}';
  }

  Future<String> _probeOnce(String url) async {
    const timeout = Duration(seconds: 6);
    final dio = Dio(BaseOptions(
      connectTimeout: timeout,
      receiveTimeout: timeout,
      responseType: ResponseType.plain,
    ));
    try {
      final res = await dio.get<String>(url);
      return '${_hostOf(url)}: answered ${res.statusCode}';
    } catch (e) {
      return '${_hostOf(url)}: ${_whyFailed(e)}';
    } finally {
      dio.close(force: true);
    }
  }

  static String _hostOf(String url) => Uri.tryParse(url)?.host ?? url;

  /// A probe's failure in the fewest words that still separate the causes: a
  /// name that would not resolve points at DNS inside the tunnel, a timeout at
  /// a route that swallows the connection, a handshake error at something
  /// rewriting it.
  static String _whyFailed(Object error) {
    if (error is DioException) {
      final inner = error.error;
      if (inner is SocketException) {
        if (inner.message.toLowerCase().contains('host lookup')) {
          return 'name did not resolve';
        }
        return 'socket: ${inner.osError?.message ?? inner.message}';
      }
      if (inner is HandshakeException) return 'TLS handshake failed';
      return switch (error.type) {
        DioExceptionType.connectionTimeout => 'connect timed out',
        DioExceptionType.receiveTimeout => 'no reply in time',
        DioExceptionType.sendTimeout => 'send timed out',
        DioExceptionType.badResponse =>
          'HTTP ${error.response?.statusCode ?? '?'}',
        DioExceptionType.cancel => 'cut off',
        _ => error.type.name,
      };
    }
    return error.runtimeType.toString();
  }

  _Egress? _parseEgress(String body) {
    if (body.contains('ip=')) {
      String? ip;
      String? loc;
      for (final line in body.split('\n')) {
        if (line.startsWith('ip=')) ip = line.substring(3).trim();
        if (line.startsWith('loc=')) loc = line.substring(4).trim();
      }
      if (ip != null) return _Egress(ip, loc);
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final ip = (decoded['query'] ?? decoded['ip']) as String?;
        final country = decoded['countryCode'] as String?;
        // "AS44244 Iran Cell Service and Communication Company" -- the number
        // is the stable part; the name changes spelling between lookups.
        final asn = (decoded['as'] as String?)?.split(' ').first;
        if (ip != null) return _Egress(ip, country, asn);
      }
    } catch (_) {
      // Not JSON.
    }
    return null;
  }

  void dispose() {
    _cancelled = true;
    _serviceStateSub?.cancel();
    _trafficSub?.cancel();
    _groupSub?.cancel();
    _faultSub?.cancel();
    _coreLogSub?.cancel();
    _networkSub?.cancel();
    _network.dispose();
    _controller.close();
    _client.dispose();
  }
}

class _Egress {
  const _Egress(this.ip, this.country, [this.network]);
  final String ip;
  final String? country;

  /// The autonomous system the reading came from -- "AS44244" for Irancell,
  /// "AS29049" for a Delta Telecom home line, and so on.
  ///
  /// Free, because ip-api.com returns it in the same response the egress check
  /// already asks for. It is what makes a remembered server meaningful: the
  /// question is never "did this config work" but "did it work here".
  final String? network;
}
