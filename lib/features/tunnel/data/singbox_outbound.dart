import 'dart:convert';

import '../../configs/domain/vpn_config.dart';

/// Turns a share URI into a sing-box outbound.
///
/// The old core took share links directly -- `FlutterV2ray.parseFromURL` did
/// this job -- but sing-box speaks only its own JSON, so the translation moves
/// into the app. Field names follow the shapes already proven against
/// sing-box 1.13 on the server (`validator/singbox_tester.py`), not guesses
/// from documentation.
///
/// Returns null for anything it cannot express. A null here means the config is
/// skipped, never that it is broken, so being conservative costs a row and
/// being wrong costs a user a connection that silently carries nothing.
class SingboxOutbound {
  const SingboxOutbound._();

  /// Builds the outbound object for [config], tagged [tag].
  static Map<String, dynamic>? fromConfig(VpnConfig config, String tag) {
    final content = config.content?.trim();
    if (content == null || content.isEmpty) return null;
    try {
      return switch (config.type) {
        VpnConfigType.vless => _vless(content, tag),
        VpnConfigType.vmess => _vmess(content, tag),
        VpnConfigType.trojan => _trojan(content, tag),
        VpnConfigType.ss => _shadowsocks(content, tag),
        VpnConfigType.hysteria => _hysteria2(content, tag),
        _ => null,
      };
    } catch (_) {
      // A malformed share link is common in this inventory; it is not an error
      // worth surfacing, just a row that cannot be used.
      return null;
    }
  }

  // -- vless ---------------------------------------------------------------

  static Map<String, dynamic>? _vless(String raw, String tag) {
    final uri = Uri.parse(raw);
    final host = uri.host;
    final port = uri.port;
    if (host.isEmpty || port == 0) return null;
    final uuid = Uri.decodeComponent(uri.userInfo);
    if (uuid.isEmpty) return null;
    final q = uri.queryParameters;

    final outbound = <String, dynamic>{
      'type': 'vless',
      'tag': tag,
      'server': host,
      'server_port': port,
      'uuid': uuid,
    };

    // `flow` only belongs on a reality/tls outbound; sending it bare makes the
    // core reject the whole config.
    final flow = q['flow'];
    final security = q['security'] ?? 'none';
    if (flow != null && flow.isNotEmpty && security != 'none') {
      outbound['flow'] = flow;
    }

    final tls = _tls(q, host);
    if (tls != null) outbound['tls'] = tls;

    final transport = _transport(q);
    if (transport != null) outbound['transport'] = transport;

    return outbound;
  }

  // -- vmess ---------------------------------------------------------------

  /// vmess:// carries a base64 JSON blob rather than URI fields.
  static Map<String, dynamic>? _vmess(String raw, String tag) {
    final blob = raw.substring('vmess://'.length).split('#').first;
    final decoded = utf8.decode(base64.decode(_pad(blob)), allowMalformed: true);
    final json = jsonDecode(decoded);
    if (json is! Map) return null;

    final host = '${json['add'] ?? ''}';
    final port = int.tryParse('${json['port'] ?? ''}') ?? 0;
    final uuid = '${json['id'] ?? ''}';
    if (host.isEmpty || port == 0 || uuid.isEmpty) return null;

    final outbound = <String, dynamic>{
      'type': 'vmess',
      'tag': tag,
      'server': host,
      'server_port': port,
      'uuid': uuid,
      'security': 'auto',
      'alter_id': int.tryParse('${json['aid'] ?? 0}') ?? 0,
    };

    if ('${json['tls'] ?? ''}' == 'tls') {
      final sni = '${json['sni'] ?? json['host'] ?? ''}';
      outbound['tls'] = {
        'enabled': true,
        'insecure': true,
        if (sni.isNotEmpty) 'server_name': sni,
      };
    }

    final network = '${json['net'] ?? 'tcp'}';
    if (network == 'ws') {
      final path = '${json['path'] ?? '/'}';
      final wsHost = '${json['host'] ?? ''}';
      outbound['transport'] = {
        'type': 'ws',
        'path': path.isEmpty ? '/' : path,
        if (wsHost.isNotEmpty) 'headers': {'Host': wsHost},
      };
    } else if (network == 'grpc') {
      outbound['transport'] = {
        'type': 'grpc',
        'service_name': '${json['path'] ?? ''}',
      };
    }

    return outbound;
  }

  // -- trojan --------------------------------------------------------------

  static Map<String, dynamic>? _trojan(String raw, String tag) {
    final uri = Uri.parse(raw);
    final host = uri.host;
    final port = uri.port;
    final password = Uri.decodeComponent(uri.userInfo);
    if (host.isEmpty || port == 0 || password.isEmpty) return null;
    final q = uri.queryParameters;

    // Trojan is normally TLS, but not always: the CDN-fronted ones ride
    // websocket over plain port 80, and forcing TLS on those made sing-box
    // fail the connection outright. Honour `security` when it is stated, and
    // otherwise assume TLS except on the bare HTTP port.
    final stated = q['security'];
    final wantsTls = stated != null ? stated != 'none' : port != 80;
    final tls = wantsTls ? _tls(q, host, forceEnabled: true) : null;
    final transport = _transport(q);

    return <String, dynamic>{
      'type': 'trojan',
      'tag': tag,
      'server': host,
      'server_port': port,
      'password': password,
      if (tls != null) 'tls': tls,
      if (transport != null) 'transport': transport,
    };
  }

  // -- shadowsocks ---------------------------------------------------------

  /// Two forms in the wild: `ss://base64(method:pass)@host:port` and the fully
  /// base64-encoded `ss://base64(method:pass@host:port)`.
  static Map<String, dynamic>? _shadowsocks(String raw, String tag) {
    var body = raw.substring('ss://'.length).split('#').first.split('?').first;
    String method;
    String password;
    String host;
    int port;

    if (body.contains('@')) {
      final at = body.lastIndexOf('@');
      final userInfo = body.substring(0, at);
      final hostPort = body.substring(at + 1);
      final creds = _looksBase64(userInfo)
          ? utf8.decode(base64.decode(_pad(userInfo)), allowMalformed: true)
          : Uri.decodeComponent(userInfo);
      final colon = creds.indexOf(':');
      if (colon <= 0) return null;
      method = creds.substring(0, colon);
      password = creds.substring(colon + 1);
      final portSep = hostPort.lastIndexOf(':');
      if (portSep <= 0) return null;
      host = hostPort.substring(0, portSep).replaceAll(RegExp(r'[\[\]]'), '');
      port = int.tryParse(hostPort.substring(portSep + 1)) ?? 0;
    } else {
      final decoded =
          utf8.decode(base64.decode(_pad(body)), allowMalformed: true);
      final at = decoded.lastIndexOf('@');
      if (at <= 0) return null;
      final creds = decoded.substring(0, at);
      final hostPort = decoded.substring(at + 1);
      final colon = creds.indexOf(':');
      if (colon <= 0) return null;
      method = creds.substring(0, colon);
      password = creds.substring(colon + 1);
      final portSep = hostPort.lastIndexOf(':');
      if (portSep <= 0) return null;
      host = hostPort.substring(0, portSep).replaceAll(RegExp(r'[\[\]]'), '');
      port = int.tryParse(hostPort.substring(portSep + 1)) ?? 0;
    }

    if (host.isEmpty || port == 0 || method.isEmpty) return null;
    return <String, dynamic>{
      'type': 'shadowsocks',
      'tag': tag,
      'server': host,
      'server_port': port,
      'method': method,
      'password': password,
    };
  }

  // -- hysteria2 -----------------------------------------------------------

  /// Mirrors `_hysteria2_to_singbox` from the bot's validator, which is the
  /// version that has actually passed against a live core.
  static Map<String, dynamic>? _hysteria2(String raw, String tag) {
    final normalised =
        raw.startsWith('hy2://') ? raw.replaceFirst('hy2://', 'hysteria2://') : raw;
    final uri = Uri.parse(normalised);
    final host = uri.host;
    final port = uri.port;
    if (host.isEmpty || port == 0) return null;
    final q = uri.queryParameters;
    final password = Uri.decodeComponent(uri.userInfo);

    final outbound = <String, dynamic>{
      'type': 'hysteria2',
      'tag': tag,
      'server': host,
      'server_port': port,
      'password': password,
      'tls': {
        'enabled': true,
        'insecure': _isTrue(q['insecure']),
        if ((q['sni'] ?? '').isNotEmpty) 'server_name': q['sni'],
      },
    };

    final obfs = q['obfs'];
    final obfsPassword = q['obfs-password'];
    if (obfs != null &&
        obfs.isNotEmpty &&
        obfsPassword != null &&
        obfsPassword.isNotEmpty) {
      outbound['obfs'] = {'type': obfs, 'password': obfsPassword};
    }
    return outbound;
  }

  // -- shared pieces -------------------------------------------------------

  static Map<String, dynamic>? _tls(
    Map<String, String> q,
    String host, {
    bool forceEnabled = false,
  }) {
    final security = q['security'] ?? (forceEnabled ? 'tls' : 'none');
    if (security == 'none' && !forceEnabled) return null;

    final sni = q['sni'] ?? q['host'] ?? '';
    final tls = <String, dynamic>{
      'enabled': true,
      // These are other people's servers with whatever certificates they
      // happen to have; refusing a self-signed one would drop most of the
      // inventory for a guarantee the app never offered.
      'insecure': true,
      if (sni.isNotEmpty) 'server_name': sni,
    };

    final alpn = q['alpn'];
    if (alpn != null && alpn.isNotEmpty) {
      tls['alpn'] = alpn.split(',').where((a) => a.isNotEmpty).toList();
    }

    final fingerprint = q['fp'];
    if (fingerprint != null && fingerprint.isNotEmpty) {
      tls['utls'] = {'enabled': true, 'fingerprint': fingerprint};
    }

    if (security == 'reality') {
      final publicKey = q['pbk'] ?? '';
      if (publicKey.isEmpty) return null; // reality without a key cannot work
      tls['reality'] = {
        'enabled': true,
        'public_key': publicKey,
        if ((q['sid'] ?? '').isNotEmpty) 'short_id': q['sid'],
      };
      // Not optional: sing-box refuses to build the outbound at all --
      // "uTLS is required by reality client" -- and one such row took the whole
      // config down with it. Many share links omit `fp`, so a default is
      // needed rather than only honouring what was written.
      tls['utls'] ??= {'enabled': true, 'fingerprint': 'chrome'};
      // Reality validates the certificate by its own means.
      tls['insecure'] = false;
    }

    return tls;
  }

  static Map<String, dynamic>? _transport(Map<String, String> q) {
    switch (q['type']) {
      case 'ws':
        final path = q['path'] ?? '/';
        final host = q['host'] ?? '';
        return {
          'type': 'ws',
          'path': path.isEmpty ? '/' : Uri.decodeComponent(path),
          if (host.isNotEmpty) 'headers': {'Host': host},
        };
      case 'grpc':
        return {
          'type': 'grpc',
          'service_name': Uri.decodeComponent(q['serviceName'] ?? ''),
        };
      case 'httpupgrade':
        return {
          'type': 'httpupgrade',
          'path': Uri.decodeComponent(q['path'] ?? '/'),
          if ((q['host'] ?? '').isNotEmpty) 'host': q['host'],
        };
      default:
        // tcp and anything unrecognised: no transport block at all, which is
        // what sing-box expects for plain TCP.
        return null;
    }
  }

  static bool _isTrue(String? value) =>
      value == '1' || value?.toLowerCase() == 'true';

  static bool _looksBase64(String value) =>
      !value.contains(':') && RegExp(r'^[A-Za-z0-9+/=_-]+$').hasMatch(value);

  static String _pad(String value) {
    final normalised = value.replaceAll('-', '+').replaceAll('_', '/');
    final remainder = normalised.length % 4;
    return remainder == 0 ? normalised : normalised + '=' * (4 - remainder);
  }
}
