import 'package:flutter_test/flutter_test.dart';
import 'package:verna_vpn/features/configs/domain/vpn_config.dart';
import 'package:verna_vpn/features/tunnel/data/tunnel_service.dart';

VpnConfig at(String id, String country) => VpnConfig(
      id: id,
      type: VpnConfigType.vless,
      kind: VpnConfigKind.text,
      content: 'vless://u@h$id:443',
      country: country,
      flag: '',
      countryCode: country,
    );

void main() {
  group('a test run reaches every country in its first round', () {
    test('a grouped list is interleaved', () {
      // How the pool actually arrives: all of one country, then all of the
      // next. With batches of twenty, that is one country per batch.
      final grouped = [
        for (var i = 0; i < 25; i++) at('de$i', 'DE'),
        for (var i = 0; i < 25; i++) at('jp$i', 'JP'),
        for (var i = 0; i < 25; i++) at('nl$i', 'NL'),
      ];

      final spread = TunnelService.spreadByCountryForTest(grouped);

      expect(spread.length, grouped.length, reason: 'nothing may be dropped');
      expect({for (final c in spread) c.id}, {for (final c in grouped) c.id},
          reason: 'and nothing may be invented');
      // The point of the whole change: the first three rows cover all three
      // countries, so one probe round lights up the list.
      expect(spread.take(3).map((c) => c.countryCode).toSet(),
          {'DE', 'JP', 'NL'});
    });

    test('an uneven split keeps drawing from whoever has servers left', () {
      final uneven = [
        at('de1', 'DE'),
        at('de2', 'DE'),
        at('de3', 'DE'),
        at('jp1', 'JP'),
      ];
      final spread = TunnelService.spreadByCountryForTest(uneven);
      expect(spread.map((c) => c.id), ['de1', 'jp1', 'de2', 'de3']);
    });

    test('one country is left exactly as it was', () {
      final single = [at('de1', 'DE'), at('de2', 'DE')];
      expect(TunnelService.spreadByCountryForTest(single).map((c) => c.id),
          ['de1', 'de2']);
    });

    test('an empty list is not a special case anywhere', () {
      expect(TunnelService.spreadByCountryForTest(const []), isEmpty);
    });

    test('unknown countries share one bucket', () {
      // Otherwise every unlabelled row would be its own "country" and take
      // the whole first round, which is the opposite of the intent.
      final mixed = [
        at('x1', ''),
        at('x2', ''),
        at('x3', ''),
        at('jp1', 'JP'),
      ];
      final spread = TunnelService.spreadByCountryForTest(mixed);
      expect(spread.take(2).map((c) => c.id), ['x1', 'jp1']);
    });
  });
}
