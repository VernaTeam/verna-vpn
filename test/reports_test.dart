import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:verna_vpn/features/configs/domain/vpn_config.dart';
import 'package:verna_vpn/features/reports/data/measurement_report.dart';
import 'package:verna_vpn/features/tunnel/data/candidate_selector.dart';

VpnConfig row(
  String id,
  VpnConfigType type,
  String content, {
  double? concurrency,
}) =>
    VpnConfig(
      id: id,
      type: type,
      kind: VpnConfigKind.text,
      content: content,
      country: 'Germany',
      flag: '',
      countryCode: 'DE',
      concurrency: concurrency,
    );

void main() {
  // The config bot computed these from the pinned rule, independently of this
  // code, with raw inputs chosen to exercise the steps where two
  // implementations drift apart silently: case, whitespace, percent-encoding.
  // If one fails here, a family would split in two in the aggregate.
  group('cred_hash matches the bot reference vectors', () {
    test('vless: uppercase uuid with trailing spaces is lowercased and trimmed',
        () {
      final id = ServerIdentity.of(row('1', VpnConfigType.vless,
          'vless://7595CD50-9326-48E4-A7BC-802E85E643EC%20%20@Example.com:443?security=reality#x'))!;
      expect(id.protocol, 'vless');
      expect(id.server, 'example.com:443');
      expect(id.credHash, '94e155e42791e1e9');
    });

    test('vmess: uuid from the JSON, lowercased', () {
      final json = jsonEncode({
        'add': 'VM.example.com',
        'port': '8443',
        'id': 'B1E4B7A2-0000-4C11-9D33-ABCDEFABCDEF',
      });
      final id = ServerIdentity.of(row('2', VpnConfigType.vmess,
          'vmess://${base64.encode(utf8.encode(json))}'))!;
      expect(id.server, 'vm.example.com:8443');
      expect(id.credHash, 'b05f3ec7d204336d');
    });

    test('trojan: password case is kept', () {
      final id = ServerIdentity.of(row('3', VpnConfigType.trojan,
          'trojan://BbNnpOgc1j9WOaWoslbSyeob1r47IRHV@5.75.171.12:1080?security=reality&sni=x#y'))!;
      expect(id.server, '5.75.171.12:1080');
      expect(id.credHash, 'a73f6da34a446867');
    });

    test('hysteria: percent-decoded, spelled as the bot spells it', () {
      final id = ServerIdentity.of(row('4', VpnConfigType.hysteria,
          'hy2://p%40ss%20word@fi.example.com:443?sni=x#y'))!;
      expect(id.protocol, 'hysteria');
      expect(id.credHash, '14022dbb6bd04a99');
    });

    test('ss: method lowercased, both link forms agree', () {
      final userInfo = base64Url
          .encode(utf8.encode('AES-256-GCM:secret-pass'))
          .replaceAll('=', '');
      final short = ServerIdentity.of(row('5', VpnConfigType.ss,
          'ss://$userInfo@SS.example.com:8388#x'))!;
      final full = ServerIdentity.of(row(
          '6',
          VpnConfigType.ss,
          'ss://${base64.encode(utf8.encode('AES-256-GCM:secret-pass@ss.example.com:8388'))}#x'))!;
      expect(short.credHash, 'f3c94ecb53114bfb');
      expect(full.credHash, short.credHash);
      expect(full.server, 'ss.example.com:8388');
    });

    test('tuic, by the formula alone (the app does not run tuic)', () {
      expect(
        ServerIdentity.hash('tuic', '7595cd50-9326-48e4-a7bc-802e85e643ec:pw'),
        'fb6a0ffb1f299f95',
      );
    });

    test('the protocol keeps equal passwords apart', () {
      expect(ServerIdentity.hash('trojan', 'secret'),
          isNot(ServerIdentity.hash('ss', 'secret')));
    });
  });

  group('reports', () {
    const trojan =
        'trojan://BbNnpOgc1j9WOaWoslbSyeob1r47IRHV@5.75.171.12:1080?security=reality#y';

    test("a user's own subscription row is never reported", () {
      expect(
        MeasurementReport.forConfig(
          row('sub:abc:1234abcd', VpnConfigType.trojan, trojan),
          stage: ReportStage.tunnel,
          outcome: ReportOutcome.alive,
          ms: 100,
          transport: 'wifi',
        ),
        isNull,
      );
    });

    test('the JSON is exactly the agreed contract', () {
      final report = MeasurementReport.forConfig(
        row('160176', VpnConfigType.trojan, trojan),
        stage: ReportStage.probe,
        outcome: ReportOutcome.noTraffic,
        ms: 999,
        asn: 'AS44244',
        transport: 'cellular',
      )!;
      final json = report.toJson();
      expect(json.keys.toSet(), {
        'report_uid', 'config_id', 'server', 'cred_hash', 'protocol', 'stage',
        'outcome', 'ms', 'asn', 'transport', 'app_version', 'mobile_operator',
      });
      expect(json['config_id'], 160176);
      expect(json['outcome'], 'no_traffic');
      expect(json['stage'], 'probe');
      expect(json['ms'], isNull, reason: 'ms only for alive');
      expect(json['protocol'], 'trojan');
      expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
          .hasMatch(json['report_uid'] as String), isTrue);
      final back = MeasurementReport.fromJson(json)!;
      expect(back.uid, report.uid);
      expect(back.outcome, ReportOutcome.noTraffic);
    });

    test('the operator travels only with mobile data', () {
      final cfg = row('160176', VpnConfigType.trojan, trojan);
      final cellular = MeasurementReport.forConfig(cfg,
          stage: ReportStage.tunnel,
          outcome: ReportOutcome.alive,
          ms: 120,
          transport: 'cellular',
          mobileOperator: '43235')!;
      final wifi = MeasurementReport.forConfig(cfg,
          stage: ReportStage.tunnel,
          outcome: ReportOutcome.alive,
          ms: 120,
          transport: 'wifi',
          mobileOperator: '43235')!;
      expect(cellular.toJson()['mobile_operator'], '43235');
      expect(wifi.toJson()['mobile_operator'], isNull);
      expect(MeasurementReport.fromJson(cellular.toJson())!.mobileOperator,
          '43235');
      expect(cellular.appVersion, '1.0.0/r03');
    });

    test('every measurement gets its own uid', () {
      final uids = {for (var i = 0; i < 200; i++) MeasurementReport.newUid()};
      expect(uids.length, 200);
    });
  });

  group('concurrency', () {
    test('only a measured shortfall counts as weak', () {
      expect(row('1', VpnConfigType.vless, 'vless://u@h:1').weakUnderLoad,
          isFalse);
      expect(
          row('1', VpnConfigType.vless, 'vless://u@h:1', concurrency: 0.8)
              .weakUnderLoad,
          isFalse);
      expect(
          row('1', VpnConfigType.vless, 'vless://u@h:1', concurrency: 0.7)
              .weakUnderLoad,
          isTrue);
    });

    test('the candidate list tries weak servers last, untested ones normally',
        () {
      final pool = [
        row('weak', VpnConfigType.vless, 'vless://u@a.example.com:443',
            concurrency: 0.4),
        row('untested', VpnConfigType.vless, 'vless://u@b.example.com:443'),
        row('perfect', VpnConfigType.vless, 'vless://u@c.example.com:443',
            concurrency: 1.0),
      ];
      for (var seed = 0; seed < 10; seed++) {
        final picked = CandidateSelector(random: Random(seed)).select(pool);
        expect(picked.last.id, 'weak');
        expect(picked.length, 3);
      }
    });

    test('the ratio survives the on-device cache', () {
      final back = VpnConfig.fromJson(
          row('9', VpnConfigType.ss, 'ss://x@h:1', concurrency: 0.67).toJson());
      expect(back.concurrency, 0.67);
    });
  });
}
