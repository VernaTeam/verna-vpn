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
enum PickedBy {
  /// The user tapped a country or a server.
  manual,

  /// The app searched.
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
  });

  final String uid;
  final DateTime startedAt;
  final PickedBy picked;
  final String? askedCountry;

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
      picked: json['picked'] == 'manual' ? PickedBy.manual : PickedBy.auto,
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

  Map<String, dynamic> toJson() => {
        'failure_uid': uid,
        'at': stamp(at),
        'reason': reason.wire,
        'picked': picked.wire,
        if (candidatesTried != null) 'candidates_tried': candidatesTried,
        if (serversLive != null) 'servers_live': serversLive,
        if (gaveUpAfterS != null) 'gave_up_after_s': gaveUpAfterS,
        if (askedCountry != null) 'asked_country': askedCountry,
        'transport': transport,
        if (operator != null) 'operator': operator,
        if (asn != null) 'asn': asn,
        if (country != null) 'country': country,
        if (appVersion != null) 'app_version': appVersion,
      };
}
