import 'package:flutter_test/flutter_test.dart';
import 'package:verna_vpn/features/telemetry/domain/telemetry_records.dart';
import 'package:verna_vpn/features/tunnel/data/outside_stop.dart';

void main() {
  Future<void> noWait(Duration _) async {}

  group('why a tunnel stopped from outside', () {
    test('a VPN still up after the wait is another app', () async {
      expect(
        await classifyOutsideStop(
          vpnActive: () async => true,
          superseded: () => false,
          wait: noWait,
        ),
        EndedBy.revoked,
      );
    });

    test('no VPN after the wait stays core_died', () async {
      expect(
        await classifyOutsideStop(
          vpnActive: () async => false,
          superseded: () => false,
          wait: noWait,
        ),
        EndedBy.coreDied,
      );
    });

    test('no reading is not a finding', () async {
      expect(
        await classifyOutsideStop(
          vpnActive: () async => null,
          superseded: () => false,
          wait: noWait,
        ),
        EndedBy.coreDied,
      );
    });

    test('a VPN of our own new connect is not another app', () async {
      expect(
        await classifyOutsideStop(
          vpnActive: () async => true,
          superseded: () => true,
          wait: noWait,
        ),
        EndedBy.coreDied,
      );
    });

    test('our own lingering network does not count: it reads after the wait',
        () async {
      // The ghost is up until the wait is over, and gone when it is.
      var ghost = true;
      Duration? waited;
      final ended = await classifyOutsideStop(
        vpnActive: () async => ghost,
        superseded: () => false,
        wait: (duration) async {
          waited = duration;
          ghost = false;
        },
      );
      expect(ended, EndedBy.coreDied);
      expect(waited, greaterThan(const Duration(seconds: 10)));
    });
  });
}
