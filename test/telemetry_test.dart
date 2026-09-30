
import 'package:flutter_test/flutter_test.dart';
import 'package:verna_vpn/features/telemetry/domain/telemetry_records.dart';

void main() {
  /// A session with every field filled, including ones that would be the
  /// obvious place for something private to leak in.
  SessionRecord fullSession() => SessionRecord(
        uid: newUid(),
        startedAt: DateTime.utc(2026, 10, 1, 9, 30, 15),
        picked: PickedBy.manual,
        askedCountry: 'DE',
        connectMs: 4200,
        attemptsBefore: 3,
        probeMs: 90,
        tunnelMs: 143,
        configId: 9911,
        protocol: 'vmess',
        exitCountry: 'DE',
        transport: 'cellular',
        operator: '43235',
        asn: 'AS44244',
        country: 'IR',
        appVersion: '1.0.3/r03',
      )
        ..durationS = 1800
        ..speedKbps = 3100
        ..bytesDown = 52428800
        ..bytesUp = 2097152
        ..peakKbps = 4800
        ..endedBy = EndedBy.user;

  /// Key names that must never appear, whatever a future field is called.
  /// Exact names, not substrings: `servers_live` legitimately contains
  /// "server", and a test that cannot tell those apart gets deleted the first
  /// time it cries wolf.
  const bannedKeys = {
    'server', 'servers', 'host', 'hostname', 'address', 'ip', 'exit_ip',
    'sni', 'password', 'pass', 'uuid', 'token', 'secret', 'key', 'link',
    'url', 'subscription', 'sub', 'remark', 'city', 'lat', 'lon',
    'latitude', 'longitude',
  };

  /// Anything that looks like a link, a login or an address, wherever it sits.
  void expectNoSecrets(Map<String, dynamic> row) {
    for (final key in row.keys) {
      expect(bannedKeys.contains(key), isFalse,
          reason: 'the field "$key" has no business in telemetry');
    }
    for (final entry in row.entries) {
      final value = entry.value;
      if (value is! String) continue;
      expect(value.contains('://'), isFalse, reason: '${entry.key} holds a link');
      expect(value.contains('@'), isFalse, reason: '${entry.key} holds a login');
      expect(RegExp(r'\d+\.\d+\.\d+\.\d+').hasMatch(value), isFalse,
          reason: '${entry.key} holds an address');
      // Long opaque strings are how a credential arrives by accident.
      expect(value.length <= 40, isTrue,
          reason: '${entry.key} is suspiciously long: $value');
    }
  }

  group('the privacy boundary', () {
    // The point of this group: the promise in the design document is worth
    // nothing after the next refactor, and a field added carelessly to a
    // record class would ship silently. These tests fail instead.
    test('a session carries no address, host, link or credential', () {
      expectNoSecrets(fullSession().toJson());
    });

    test('a failure carries no address, host, link or credential', () {
      expectNoSecrets(FailureRecord(
        uid: newUid(),
        at: DateTime.utc(2026, 10, 1, 9, 40),
        reason: FailReason.noneReachable,
        picked: PickedBy.auto,
        candidatesTried: 4,
        serversLive: 1,
        gaveUpAfterS: 38,
        askedCountry: 'NL',
        transport: 'cellular',
        operator: '43211',
        asn: 'AS197207',
        country: 'IR',
        appVersion: '1.0.3/r03',
      ).toJson());
    });

    test('the open-session file on disk is held to the same rule', () {
      // It is written where another app cannot read it, but it is still the
      // same data and it outlives the session.
      expectNoSecrets(fullSession().toOpenJson());
    });

    test('geography stops at country, operator and network', () {
      final keys = fullSession().toJson().keys.toSet();
      expect(keys, containsAll(['country', 'operator', 'asn']));
      expect(keys.contains('config_id'), isTrue,
          reason: 'the server is named by its id, never by its address');
    });
  });

  group('the wire format', () {
    test('timestamps are UTC seconds the server will accept', () {
      final json = fullSession().toJson();
      expect(json['started_at'], '2026-10-01T09:30:15');
      expect(
        RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$')
            .hasMatch(json['started_at'] as String),
        isTrue,
      );
    });

    test('every reason has a wire name the server knows', () {
      // The server rejects a reason it does not recognise, and a rejected row
      // is a silently missing one. These are the names in _FAIL_REASONS.
      const known = {
        'no_internet', 'permission_denied', 'no_candidates', 'none_reachable',
        'no_traffic', 'cancelled', 'core_failed', 'unknown',
      };
      for (final reason in FailReason.values) {
        expect(known.contains(reason.wire), isTrue,
            reason: '${reason.name} sends "${reason.wire}"');
      }
    });

    test('every ending has a wire name the server knows', () {
      const known = {'user', 'network', 'core_died', 'app_killed', 'error'};
      for (final ending in EndedBy.values) {
        expect(known.contains(ending.wire), isTrue,
            reason: '${ending.name} sends "${ending.wire}"');
      }
    });

    test('a session that has not ended sends no ending', () {
      final open = SessionRecord(
        uid: newUid(),
        startedAt: DateTime.utc(2026, 10, 1),
        picked: PickedBy.auto,
      );
      final json = open.toJson();
      expect(json.containsKey('ended_by'), isFalse);
      expect(json.containsKey('duration_s'), isFalse);
    });

    test('an abandoned session survives the round trip through disk', () {
      final session = fullSession();
      final recovered = SessionRecord.fromOpenJson(session.toOpenJson());
      expect(recovered, isNotNull);
      expect(recovered!.uid, session.uid);
      expect(recovered.startedAt.toUtc(), session.startedAt.toUtc());
      expect(recovered.picked, session.picked);
      expect(recovered.protocol, session.protocol);
      expect(recovered.operator, session.operator);
    });

    test('uids are unique', () {
      expect({for (var i = 0; i < 500; i++) newUid()}.length, 500);
    });
  });
}
