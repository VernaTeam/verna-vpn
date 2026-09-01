/// The result of testing one config from this phone, on this network.
///
/// Distinct from anything the server reports. The server proves a config is
/// alive by running it from a datacentre with an unrestricted connection;
/// measured on 2026-08-21, twenty configs it had just verified were all alive
/// there, all TCP-reachable from Iran, and only one in eight actually carried
/// traffic from the phone. Liveness and usability are different questions, and
/// only the device can answer the second.
class LocalTest {
  const LocalTest.alive(this.milliseconds, this.exitIp)
      : reachable = true,
        carriedTraffic = true;

  const LocalTest.noTraffic()
      : milliseconds = null,
        exitIp = null,
        reachable = true,
        carriedTraffic = false;

  const LocalTest.unreachable()
      : milliseconds = null,
        exitIp = null,
        reachable = false,
        carriedTraffic = false;

  /// Round trip through the proxy, measured here. Null unless it worked.
  final int? milliseconds;

  /// Where traffic came out, as seen from this phone.
  final String? exitIp;

  /// Whether the server accepted a TCP connection from this network.
  final bool reachable;

  /// Whether a request actually completed through it.
  final bool carriedTraffic;

  bool get works => carriedTraffic;
}

/// Progress of a run over the list.
class LocalTestProgress {
  const LocalTestProgress({
    this.running = false,
    this.done = 0,
    this.total = 0,
    this.working = 0,
  });

  final bool running;
  final int done;
  final int total;
  final int working;

  bool get idle => !running && total == 0;
}
