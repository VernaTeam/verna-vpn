// Converts real share URIs into a sing-box config and prints it.
//
// Exists so the converter can be checked by the thing that will actually run
// it: `sing-box check` on the server, against configs pulled from the live
// inventory. Reading the JSON and deciding it looks right is not the same test.
//
//   dart run tool/dump_singbox_config.dart <uris.json> > config.json
//
// The input is the API's own `/configs/text` response.
import 'dart:convert';
import 'dart:io';

import 'package:verna_vpn/features/configs/domain/vpn_config.dart';
import 'package:verna_vpn/features/tunnel/data/singbox_outbound.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dump_singbox_config.dart <api-response.json>');
    exit(2);
  }

  final raw = jsonDecode(File(args.first).readAsStringSync());
  final rows = (raw['configs'] as List).cast<Map<String, dynamic>>();

  final outbounds = <Map<String, dynamic>>[];
  final skipped = <String>[];

  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    final config = VpnConfig(
      id: '${row['id']}',
      type: VpnConfigType.fromString('${row['type']}'),
      kind: VpnConfigKind.text,
      content: '${row['content']}',
      country: '${row['country'] ?? ''}',
      flag: '${row['flag'] ?? ''}',
      countryCode: '${row['code'] ?? ''}',
    );
    final outbound = SingboxOutbound.fromConfig(config, 'probe_$i');
    if (outbound == null) {
      skipped.add('${row['type']} #${row['id']}');
      continue;
    }
    outbounds.add(outbound);
  }

  stderr.writeln('converted ${outbounds.length}, skipped ${skipped.length}');
  for (final s in skipped.take(10)) {
    stderr.writeln('  skipped: $s');
  }

  final config = {
    'log': {'level': 'error'},
    'inbounds': [
      {
        'type': 'socks',
        'tag': 'in',
        'listen': '127.0.0.1',
        'listen_port': 21080,
      }
    ],
    'outbounds': [
      {
        'type': 'selector',
        'tag': 'proxy',
        'outbounds': [for (final o in outbounds) o['tag'] as String],
      },
      ...outbounds,
      {'type': 'direct', 'tag': 'direct'},
    ],
  };

  stdout.write(const JsonEncoder.withIndent('  ').convert(config));
}
