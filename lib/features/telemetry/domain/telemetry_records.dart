/// What a connection was like, and why one failed.
///
/// Deliberately narrow. Everything here describes the *tunnel* -- how long it
/// lasted, how fast it was, which server carried it, which network it left
/// from -- and nothing describes what the user did inside it. There is no
/// field for a hostname, a domain, an app, a subscription link or a
/// credential, and `test/telemetry_test.dart` checks that the encoded JSON
/// contains none of those even by accident.
library;

import 'dart:math';

/// How the server was chosen.
///
/// Three, not two. It was manual-or-auto until an A54 on Irancell recorded a
/// session as `auto` while the user had chosen the Netherlands by hand
/// (2026-10-05): `manual` meant "tapped this exact server", and choosing a
/// country -- the common way people steer this app -- fell through to `auto`.
/// The question being asked is "does choosing help", so choosing a country has
/// to be its own answer.
enum PickedBy {
  /// This exact server, tapped in the list.
  server,

  /// A country, with the app free to pick a server inside it.
  country,

  /// The app chose everything.
  auto;

  String get wire => name;
}

/// How a session ended. The difference matters: a user who disconnects is
/// satisfied or finished, a tunnel that dies under a network change is not the
/// same event, and a session ended by Android killing the app is invisible
/// unless it is reconstructed on the next launch.
enum EndedBy {
  user,
  network,
  coreDied,
  appKilled,
  error;

  String get wire => switch (this) {
        EndedBy.user => 'user',
        EndedBy.network => 'network',
        EndedBy.coreDied => 'core_died',
        EndedBy.appKilled => 'app_killed',
        EndedBy.error => 'error',
      };
}

/// Why a connect attempt produced nothing. Taken from the app's own
/// [TunnelFailure], not invented for telemetry, so a reason in the database is
/// a reason the app actually distinguished.
enum FailReason {
  noInternet,
  permissionDenied,

  /// The app had no servers to offer at all -- the pool never arrived, or
  /// every row in it was of a kind the tunnel cannot run. A different problem
  /// from a pool that arrived and turned out to be blocked, and the two must
  /// not be one number: one is ours to fix, the other is the network's.
  noCandidates,
  noneReachable,
  noTraffic,
  cancelled,
  coreFailed,
  unknown;

  String get wire => switch (this) {
        FailReason.noInternet => 'no_internet',
        FailReason.permissionDenied => 'permission_denied',
        FailReason.noCandidates => 'no_candidates',
        FailReason.noneReachable => 'none_reachable',
        FailReason.noTraffic => 'no_traffic',
        FailReason.cancelled => 'cancelled',
        FailReason.coreFailed => 'core_failed',
        FailReason.unknown => 'unknown',
      };
}

String newUid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int start, int end) => [
        for (var i = start; i < end; i++)
          bytes[i].toRadixString(16).padLeft(2, '0'),
      ].join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

/// The UTC second, as the server's validator expects it.
String stamp(DateTime at) {
  final utc = at.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year}-${two(utc.month)}-${two(utc.day)}T'
      '${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}';
}

/// One connection, from the tap to the disconnect.
class SessionRecord {
  SessionRecord({
    required this.uid,
    required this.startedAt,
    required this.picked,
    this.askedCountry,
    this.connectMs,
    this.attemptsBefore,
    this.probeMs,
    this.tunnelMs,
    this.configId,
    this.protocol,
    this.exitCountry,
    this.transport = 'unknown',
    this.operator,
    this.asn,
    this.country,
    this.appVersion,
    this.durationS,
    this.speedKbps,
    this.bytesDown,
    this.bytesUp,
    this.peakKbps,
    this.endedBy,
    this.usedMemory,
    this.widened,
    this.sinceLastFailureS,
  });

  final String uid;
  final DateTime startedAt;
  final PickedBy picked;
  final String? askedCountry;

  /// The three fields a success needs so it can be compared with a failure on
  /// equal terms (r05): whether the phone's own memory led the attempt,
  /// whether the search went past a hand-picked server that failed, and how
  /// long since this install last failed.
  ///
  /// The last of those is the one that matters most. A retry inside two
  /// minutes of a failure succeeded 4.9% of the time over four days of 1.0.5,
  /// against 38.9% after a short wait -- and 64% of all attempts were in that
  /// window. Carrying the number on the row makes that a GROUP BY instead of
  /// a self-join on timestamps.
  final bool? usedMemory;
  final bool? widened;
  final int? sinceLastFailureS;

  /// From the tap to a verified tunnel, and how many servers were tried first.
  final int? connectMs;
  final int? attemptsBefore;

  /// What the device test predicted, and what the tunnel actually measured.
  /// Two columns rather than one, because the whole question is whether they
  /// agree -- a promise of 90 ms that delivers 400 is a bug in the ranking,
  /// not a slow server.
  final int? probeMs;
  final int? tunnelMs;

  final int? configId;
  final String? protocol;
  final String? exitCountry;
  final String transport;
  final String? operator;
  final String? asn;
  final String? country;
  final String? appVersion;

  // Filled in when the session ends.
  int? durationS;
  int? speedKbps;
  int? bytesDown;
  int? bytesUp;
  int? peakKbps;
  EndedBy? endedBy;

  Map<String, dynamic> toJson() => {
        'session_uid': uid,
        'started_at': stamp(startedAt),
        'picked': picked.wire,
        if (askedCountry != null) 'asked_country': askedCountry,
        if (connectMs != null) 'connect_ms': connectMs,
        if (attemptsBefore != null) 'attempts_before': attemptsBefore,
        if (probeMs != null) 'probe_ms': probeMs,
        if (tunnelMs != null) 'tunnel_ms': tunnelMs,
        if (configId != null) 'config_id': configId,
        if (protocol != null) 'protocol': protocol,
        if (exitCountry != null) 'exit_country': exitCountry,
        'transport': transport,
        if (operator != null) 'operator': operator,
        if (asn != null) 'asn': asn,
        if (country != null) 'country': country,
        if (appVersion != null) 'app_version': appVersion,
        if (durationS != null) 'duration_s': durationS,
        if (speedKbps != null) 'speed_kbps': speedKbps,
        if (bytesDown != null) 'bytes_down': bytesDown,
        if (bytesUp != null) 'bytes_up': bytesUp,
        if (peakKbps != null) 'peak_kbps': peakKbps,
        if (endedBy != null) 'ended_by': endedBy!.wire,
        if (usedMemory != null) 'used_memory': usedMemory! ? 1 : 0,
        if (widened != null) 'widened': widened! ? 1 : 0,
        if (sinceLastFailureS != null)
          'since_last_failure_s': sinceLastFailureS,
      };

  /// For the open-session file: everything, including what is not set yet.
  Map<String, dynamic> toOpenJson() => {
        ...toJson(),
        'started_epoch': startedAt.millisecondsSinceEpoch,
      };

  static SessionRecord? fromOpenJson(Map<String, dynamic> json) {
    final uid = json['session_uid'];
    final epoch = json['started_epoch'];
    if (uid is! String || epoch is! int) return null;
    return SessionRecord(
      uid: uid,
      startedAt: DateTime.fromMillisecondsSinceEpoch(epoch),
      picked: PickedBy.values.firstWhere(
        (p) => p.wire == json['picked'],
        // A row written by an older build says "manual"; it meant a
        // hand-picked server.
        orElse: () => json['picked'] == 'manual' ? PickedBy.server : PickedBy.auto,
      ),
      askedCountry: json['asked_country'] as String?,
      connectMs: json['connect_ms'] as int?,
      attemptsBefore: json['attempts_before'] as int?,
      probeMs: json['probe_ms'] as int?,
      tunnelMs: json['tunnel_ms'] as int?,
      configId: json['config_id'] as int?,
      protocol: json['protocol'] as String?,
      exitCountry: json['exit_country'] as String?,
      transport: json['transport'] as String? ?? 'unknown',
      operator: json['operator'] as String?,
      asn: json['asn'] as String?,
      country: json['country'] as String?,
      appVersion: json['app_version'] as String?,
      speedKbps: json['speed_kbps'] as int?,
    );
  }
}

/// One connect that ended with no tunnel.
class FailureRecord {
  FailureRecord({
    required this.uid,
    required this.at,
    required this.reason,
    required this.picked,
    this.candidatesTried,
    this.serversLive,
    this.gaveUpAfterS,
    this.askedCountry,
    this.transport = 'unknown',
    this.operator,
    this.asn,
    this.country,
    this.appVersion,
    this.shortlistSize,
    this.probeAnswered,
    this.usedMemory,
    this.widened,
    this.protocol,
    this.sinceLastFailureS,
    this.consecutiveFailures,
  });

  final String uid;
  final DateTime at;
  final FailReason reason;
  final PickedBy picked;
  final int? candidatesTried;

  /// How many servers had passed this phone's own probe when the attempt
  /// began. The column that separates "the app is broken" from "this network
  /// blocks everything".
  final int? serversLive;

  final int? gaveUpAfterS;
  final String? askedCountry;
  final String transport;
  final String? operator;
  final String? asn;
  final String? country;
  final String? appVersion;

  /// The funnel, added for r05: how many servers were reachable, how many of
  /// those answered the core's probe, and (in [candidatesTried]) how many were
  /// actually tried. The 1.0.5 review could read only the last of the three
  /// and so could not say whether 2.1 tried meant a short list or a silent
  /// one.
  final int? shortlistSize;
  final int? probeAnswered;

  /// Whether the phone's own memory of working servers led the attempt.
  final bool? usedMemory;

  /// Whether a hand-picked server failed and the search carried on past it.
  final bool? widened;

  /// The protocol of the last server tried. Only sessions carried one before,
  /// so protocol failure rates could only be computed from successes.
  final String? protocol;

  /// Seconds since this install's previous failure, and how many failures it
  /// has had in a row.
  ///
  /// Both are reconstructible by joining rows on timestamps -- that is how the
  /// 2026-10-13 review found that a retry inside two minutes succeeds 4.9% of
  /// the time against 38.9% after a short wait. Reconstructing it was slow,
  /// fragile across clock skew, and impossible to put in front of the user.
  /// The phone knows both for certain.
  final int? sinceLastFailureS;
  final int? consecutiveFailures;

  Map<String, dynamic> toJson() => {
        'failure_uid': uid,
        'at': stamp(at),
        'reason': reason.wire,
        'picked': picked.wire,
        if (candidatesTried != null) 'candidates_tried': candidatesTried,
        if (serversLive != null) 'servers_live': serversLive,
        if (gaveUpAfterS != null) 'gave_up_after_s': gaveUpAfterS,
        if (askedCountry != null) 'asked_country': askedCountry,
        if (shortlistSize != null) 'shortlist_size': shortlistSize,
        if (probeAnswered != null) 'probe_answered': probeAnswered,
        if (usedMemory != null) 'used_memory': usedMemory! ? 1 : 0,
        if (widened != null) 'widened': widened! ? 1 : 0,
        if (protocol != null) 'protocol': protocol,
        if (sinceLastFailureS != null) 'since_last_failure_s': sinceLastFailureS,
        if (consecutiveFailures != null)
          'consecutive_failures': consecutiveFailures,
        'transport': transport,
        if (operator != null) 'operator': operator,
        if (asn != null) 'asn': asn,
        if (country != null) 'country': country,
        if (appVersion != null) 'app_version': appVersion,
      };
}
