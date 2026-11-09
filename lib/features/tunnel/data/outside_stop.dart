import '../../telemetry/domain/telemetry_records.dart';

/// How long after a stop a VPN network can only be someone else's.
///
/// This app's own network lingers after its service has stopped: [justStopped]
/// allows ten seconds for that ghost. Two more so the reading falls clear of it.
const Duration outsideStopSettle = Duration(seconds: 12);

/// Why a tunnel ended that this app did not end.
///
/// Android gives the app one signal for all of these: the service stopped. A
/// server dying is the bot's business and another VPN app taking over is not,
/// and `core_died` mixed them -- one install was 31 of the 115 byte-less rows
/// without any way to say which it was.
///
/// So look once the dust has settled: a VPN network up after [outsideStopSettle]
/// belongs to another app, and that app is what ended this tunnel. Not asked
/// through `VpnService.prepare()`, which reads like the direct question but can
/// take the VPN away from the other app just by being called.
///
/// [EndedBy.coreDied] is the "cannot say" answer as well as the "nothing else
/// there" one: no reading, or a connect of this app's own started during the
/// wait and any VPN seen could be that one. It still covers the notification's
/// stop button, a crash, and a revoke from Settings with no other VPN behind it.
/// An app slower than the wait to bring its tunnel up is counted there too, so
/// `revoked` is a floor.
Future<EndedBy> classifyOutsideStop({
  required Future<bool?> Function() vpnActive,
  required bool Function() superseded,
  Future<void> Function(Duration) wait = _delay,
}) async {
  await wait(outsideStopSettle);
  if (superseded()) return EndedBy.coreDied;
  return await vpnActive() == true ? EndedBy.revoked : EndedBy.coreDied;
}

Future<void> _delay(Duration duration) =>
    Future<void>.delayed(duration);
