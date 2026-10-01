// Prints the exact payload the app would POST to /v1/telemetry.
//
// Not a toy: it builds the real record classes and encodes them the real way,
// so posting this output to the server proves the two sides agree on every
// field name and value shape. A hand-written sample proves only that the
// person who wrote it remembered the schema.
//
//   dart run tool/telemetry_sample.dart
import 'dart:convert';

import 'package:verna_vpn/features/telemetry/domain/telemetry_records.dart';

void main() {
  final session = SessionRecord(
    uid: newUid(),
    startedAt: DateTime.now().subtract(const Duration(minutes: 31)),
    picked: PickedBy.manual,
    askedCountry: 'DE',
    connectMs: 5100,
    attemptsBefore: 2,
    probeMs: 118,
    tunnelMs: 164,
    configId: 9911,
    protocol: 'vmess',
    exitCountry: 'DE',
    transport: 'cellular',
    operator: '43235',
    asn: 'AS44244',
    country: 'IR',
    appVersion: '1.0.3/r03',
  )
    ..durationS = 1860
    ..speedKbps = 2750
    ..bytesDown = 73400320
    ..bytesUp = 4194304
    ..peakKbps = 5120
    ..endedBy = EndedBy.user;

  final failure = FailureRecord(
    uid: newUid(),
    at: DateTime.now(),
    reason: FailReason.noneReachable,
    picked: PickedBy.auto,
    candidatesTried: 6,
    serversLive: 2,
    gaveUpAfterS: 44,
    transport: 'cellular',
    operator: '43211',
    asn: 'AS197207',
    country: 'IR',
    appVersion: '1.0.3/r03',
  );

  print(jsonEncode({
    'install_id': '7c9e6679-7425-40de-944b-e07fc1f90ae7',
    'sessions': [session.toJson()],
    'failures': [failure.toJson()],
  }));
}
