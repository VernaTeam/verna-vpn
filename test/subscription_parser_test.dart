import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:verna_vpn/features/configs/domain/vpn_config.dart';
import 'package:verna_vpn/features/subscriptions/data/builtin_subscription.dart';
import 'package:verna_vpn/features/subscriptions/data/subscription_parser.dart';
import 'package:verna_vpn/features/subscriptions/data/user_subscription.dart';

void main() {
  final vmessJson = jsonEncode({
    'v': '2',
    'ps': '🇳🇱 | @SomeChannel | Home server',
    'add': 'nl.example.com',
    'port': '443',
    'id': '11111111-2222-3333-4444-555555555555',
  });
  final vmess = 'vmess://${base64.encode(utf8.encode(vmessJson))}';

  final lines = [
    'vless://uuid@de.example.com:443?security=reality#%F0%9F%87%A9%F0%9F%87%AA%20%7C%20%40WhiteDNS%20%7C%20DE147',
    vmess,
    'trojan://pass@fr.example.com:443#France%201',
    'ss://YWVzLTI1Ni1nY206cGFzcw@us.example.com:8388#US',
    'hy2://pass@fi.example.com:443#Finland',
    'anytls://pass@de.example.com:443#DE%20AnyTLS',
    'tuic://uuid:pass@de.example.com:443#TUIC',
    '',
    '# a comment line',
    'vless://uuid@de.example.com:443?security=reality#%F0%9F%87%A9%F0%9F%87%AA%20%7C%20%40WhiteDNS%20%7C%20DE147',
  ];
  final plain = lines.join('\n');

  group('SubscriptionParser.parse', () {
    test('plain text: keeps what runs, counts what does not, drops dupes', () {
      final parsed = SubscriptionParser.parse(plain);
      expect(parsed.uris.length, 5, reason: 'vless, vmess, trojan, ss, hy2');
      expect(parsed.unsupported, 2, reason: 'anytls and tuic');
    });

    test('standard base64 gives the same result as plain text', () {
      final parsed = SubscriptionParser.parse(base64.encode(utf8.encode(plain)));
      expect(parsed.uris, SubscriptionParser.parse(plain).uris);
      expect(parsed.unsupported, 2);
    });

    test('URL-safe base64 without padding, wrapped over lines', () {
      final encoded = base64Url.encode(utf8.encode(plain)).replaceAll('=', '');
      final wrapped = [
        for (var i = 0; i < encoded.length; i += 76)
          encoded.substring(i, i + 76 > encoded.length ? encoded.length : i + 76),
      ].join('\n');
      expect(SubscriptionParser.parse(wrapped).uris.length, 5);
    });

    test('respects the per-subscription limit', () {
      final many = [
        for (var i = 0; i < 50; i++) 'vless://u@h$i.example.com:443#n$i',
      ].join('\n');
      expect(SubscriptionParser.parse(many, limit: 10).uris.length, 10);
    });

    test('a body with nothing in it', () {
      final parsed = SubscriptionParser.parse('<html>not found</html>');
      expect(parsed.uris, isEmpty);
      expect(parsed.unsupported, 0);
    });
  });

  group('remarks and flags', () {
    test('vmess remark comes from the ps field', () {
      expect(SubscriptionParser.remarkOf(vmess),
          '🇳🇱 | @SomeChannel | Home server');
    });

    test('a flag spells its own country code', () {
      final flag = SubscriptionParser.flagOf('🇩🇪 | @WhiteDNS | DE147');
      expect(flag.flag, '🇩🇪');
      expect(flag.code, 'DE');
      expect(SubscriptionParser.flagOf('no flag here').code, '');
    });

    test('rebrand replaces the fragment and keeps the server', () {
      const link = 'trojan://pass@fr.example.com:443?sni=x#%40SomeChannel';
      final out = SubscriptionParser.rebrand(link, code: 'FR', flag: '🇫🇷');
      expect(out.startsWith('trojan://pass@fr.example.com:443?sni=x#'), isTrue);
      expect(SubscriptionParser.remarkOf(out), '@Verna_VPN 🔐 | FR 🇫🇷');
      expect(out.contains('SomeChannel'), isFalse);
    });

    test('rebrand gives a link without a remark one', () {
      final out = SubscriptionParser.rebrand('ss://abc@us.example.com:8388',
          code: '', flag: '');
      expect(SubscriptionParser.remarkOf(out), '@Verna_VPN 🔐');
    });

    test('rebrand rewrites vmess inside its JSON, nothing else in it', () {
      final out = SubscriptionParser.rebrand(vmess, code: 'NL', flag: '🇳🇱');
      expect(SubscriptionParser.remarkOf(out), '@Verna_VPN 🔐 | NL 🇳🇱');
      final decoded = jsonDecode(utf8.decode(base64.decode(out.substring(8))))
          as Map<String, dynamic>;
      expect(decoded['add'], 'nl.example.com');
      expect(decoded['id'], '11111111-2222-3333-4444-555555555555');
    });
  });

  group('rows', () {
    final parsed = SubscriptionParser.parse(plain);
    final rows = [
      for (final uri in parsed.uris)
        SubscriptionParser.toConfig(uri,
            subscriptionId: 'abc', subscriptionName: 'Mine'),
    ];

    test('types', () {
      expect(rows.map((r) => r.type).toList(), [
        VpnConfigType.vless,
        VpnConfigType.vmess,
        VpnConfigType.trojan,
        VpnConfigType.ss,
        VpnConfigType.hysteria,
      ]);
    });

    test('named after the country, never after the remark', () {
      expect(rows.first.countryCode, 'DE');
      expect(rows.first.country, 'Germany');
      expect(rows[1].country, 'Netherlands');
      // No flag, no country -- not the remark, and not the subscription name.
      expect(rows[2].country, '');
      for (final row in rows) {
        expect(row.content!.contains('WhiteDNS'), isFalse);
        expect(row.content!.contains('SomeChannel'), isFalse);
      }
    });

    test('ids come from the link as served, so they survive a refresh', () {
      expect(rows.every((r) => r.id.startsWith('sub:abc:')), isTrue);
      final again = SubscriptionParser.toConfig(parsed.uris.first,
          subscriptionId: 'abc', subscriptionName: 'Mine');
      expect(again.id, rows.first.id);
      expect(rows.every((r) => r.subscriptionName == 'Mine'), isTrue);
    });
  });

  group('UserSubscription.storedName', () {
    const github =
        'https://raw.githubusercontent.com/someone/some-sub/refs/heads/main/base64.txt';

    test('a name the app invented from the link is dropped', () {
      expect(UserSubscription.storedName('raw.githubusercontent.com', github), '');
      expect(UserSubscription.storedName('someone/some-sub', github), '');
    });

    test("the user's own name is kept", () {
      expect(UserSubscription.storedName('  Work  ', github), 'Work');
      expect(UserSubscription.storedName('', github), '');
    });
  });

  group('BuiltInSubscription', () {
    test('reads what the API sends and nothing it does not', () {
      final sub = BuiltInSubscription.fromJson({
        'id': 1,
        'kind': 'vless',
        'number': 1,
        'total': 1115,
        'healthy': 666,
        'updated_at': '2026-09-13 13:52:04',
      });
      expect(sub.id, 1);
      expect(sub.kind, 'vless');
      expect(sub.healthy, 666);
      expect(sub.updatedAt, DateTime(2026, 9, 13, 13, 52, 4));
      final back = BuiltInSubscription.fromJson(sub.toJson());
      expect(back.total, 1115);
    });

    test('a row keeps its subscription id through the cache', () {
      const row = VpnConfig(
        id: '159055',
        type: VpnConfigType.vless,
        kind: VpnConfigKind.text,
        content: 'vless://x@1.2.3.4:443#%40Verna_VPN',
        country: 'France',
        flag: '🇫🇷',
        countryCode: 'FR',
        builtInSubId: 1,
      );
      final back = VpnConfig.fromJson(row.toJson());
      expect(back.builtInSubId, 1);
      expect(back.type, VpnConfigType.vless);
    });

    test('hysteria2 as the API spells it is a runnable row', () {
      expect(VpnConfigType.fromString('hysteria2'), VpnConfigType.hysteria);
      expect(tunnelableTypes.contains(VpnConfigType.fromString('hysteria2')),
          isTrue);
    });
  });
}
