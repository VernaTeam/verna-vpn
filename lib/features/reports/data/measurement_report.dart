import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../../core/app_version.dart';
import '../../configs/domain/vpn_config.dart';

/// Which test a report describes.
///
/// Both are kept because they disagree about exactly the servers worth
/// knowing about: a Trojan family answered the one-request probe and carried
/// nothing in a full tunnel, which opens many flows at once.
enum ReportStage { probe, tunnel }

/// What a test found.
///
/// Three outcomes, not a pass/fail, because they point at different causes:
/// a server that refuses connections is blocked or gone; one that accepts them
/// and carries nothing is the signature of an oversubscribed account.
enum ReportOutcome { alive, noTraffic, unreachable }

/// Where a `tunnel`-stage attempt died.
///
/// `stage: tunnel` has never meant "the VPN was up". A candidate is checked
/// through a **local proxy port first**, deliberately, and no VPN interface
/// is requested until that passes -- it costs no TUN, no route and no key in
/// the status bar to find out a server is dead. Both halves reported
/// `no_traffic`, so one label covered two different events.
///
/// The config bot found this the expensive way (2026-10-22): its demotion
/// rule counts every non-`alive` tunnel row as a dead tunnel, so a server
/// that merely failed a proxy check -- possibly on an app-side timeout -- was
/// demoted as though its tunnel had carried nothing. 232 configs were
/// demoted, 38 of them with at least one `alive` report.
///
/// Null on anything that is not a `no_traffic` tunnel row.
enum FailStage {
  /// Failed the local proxy check. **No VPN was ever created.** Weaker
  /// evidence: the server may be dead, or the request may have timed out.
  proxy,

  /// The VPN interface was up and the route carried nothing back. This is the
  /// strong negative: a real tunnel that did not work.
  tunnel,
}

/// One measurement from this phone, as verna-api accepts it.
///
/// The shape is agreed with the config bot, which reads these rows and
/// aggregates them per server and per credential (2026-09-14). Nothing here
/// identifies the phone: no IP (the API derives a daily-salted hash from the
/// connection and keeps only that), no device id, no SIM identity -- on mobile
/// data only, the network's MCC+MNC (see [mobileOperator]). Rows from a user's
/// own subscriptions are never built, see [forConfig].
class MeasurementReport {
  const MeasurementReport({
    required this.uid,
    required this.configId,
    required this.server,
    required this.credHash,
    required this.protocol,
    required this.stage,
    required this.outcome,
    required this.transport,
    this.ms,
    this.asn,
    this.mobileOperator,
    this.source,
    this.failStage,
    this.appVersion = currentAppVersion,
  });

  /// Generated when the measurement is taken and kept through every retry,
  /// so the API can drop a batch it has already stored.
  final String uid;

  /// Verna's database id. A breadcrumb only -- rows are deleted as servers
  /// die, so the bot aggregates on [server] and [credHash].
  final int? configId;

  /// `host:port`, host lowercased.
  final String server;
  final String credHash;

  /// Spelled as the bot's `config_type`: `hysteria`, not `hysteria2`.
  final String protocol;
  final ReportStage stage;
  final ReportOutcome outcome;

  /// Only for [ReportOutcome.alive].
  final int? ms;

  /// "AS44244" and the like: the operator on mobile data, the ISP on Wi-Fi.
  final String? asn;

  /// `wifi`, `cellular` or `unknown`.
  final String transport;

  /// MCC+MNC of the mobile network ("43235" Irancell, "43211" MCI), only when
  /// [transport] is `cellular`. Meysam's decision (2026-09-14): which operator
  /// a server works best on. ASN usually comes back empty from Iranian
  /// networks, so this is the operator's only reliable source on mobile data.
  /// Never on Wi-Fi, where the SIM's operator did not carry the measurement.
  final String? mobileOperator;

  /// Which harvesting source this server came from, as the API's `sub` id.
  ///
  /// The bot collects from many channels and lists and already records which
  /// one each config arrived on (`source_channel`); the API hands that back
  /// to the app as `sub`. It never came back, so the only thing the bot could
  /// rank from real phones was individual servers -- and free servers die
  /// daily, which makes that ranking stale by the time it is useful. A source
  /// does not die daily. Carrying the id back lets "which lists are worth
  /// collecting from, measured from Iranian phones rather than from a VPS in
  /// Germany" finally be answered.
  ///
  /// Null when Verna supplied the row without a source, and never set for a
  /// user's own subscription -- those never become reports at all, see
  /// [forConfig].
  final int? source;

  /// For a `no_traffic` tunnel row, which half of the attempt failed.
  /// Null everywhere else. See [FailStage].
  final FailStage? failStage;

  final String appVersion;

  /// The app version plus a zero-padded report-format revision.
  ///
  /// The version used to be frozen at 1.0.0 -- there had been no real
  /// release -- so the `/rNN` suffix was the only thing that could tell
  /// builds apart. It still is what the bot reads: rows before r02 were
  /// sent through whatever tunnel was up, so their reporter hash describes
  /// a VPN server, not a user. Zero-padded so r10 still sorts after r02
  /// when anyone compares these as strings. r03 adds [mobileOperator];
  /// reporter semantics are those of r02.
  ///
  /// The prefix now moves with [kAppVersion], so a row also says which
  /// release produced it. The bot keys on `/rNN` and ignores the prefix, so
  /// raising the version here is safe; raising **r** is not, and needs the
  /// bot session told first.
  ///
  /// r04 adds [source]; r05 adds [failStage]. Additive on both sides: the
  /// server takes one more nullable column each time, so rows from older
  /// builds store exactly as they did.
  static const String currentAppVersion = '$kAppVersion/r05';

  /// A report for [config], or null when it must not or cannot be sent.
  ///
  /// Only Verna's own rows carry a numeric database id; a row from the
  /// user's own subscription is `sub:<id>:<hash>` and never leaves the phone.
  static MeasurementReport? forConfig(
    VpnConfig config, {
    required ReportStage stage,
    required ReportOutcome outcome,
    required String transport,
    int? ms,
    String? asn,
    String? mobileOperator,
    FailStage? failStage,
  }) {
    final id = int.tryParse(config.id);
    if (id == null) return null;
    final identity = ServerIdentity.of(config);
    if (identity == null) return null;
    return MeasurementReport(
      uid: newUid(),
      configId: id,
      server: identity.server,
      credHash: identity.credHash,
      protocol: identity.protocol,
      stage: stage,
      outcome: outcome,
      ms: outcome == ReportOutcome.alive ? ms : null,
      asn: asn,
      transport: transport,
      mobileOperator: transport == 'cellular' ? mobileOperator : null,
      source: config.builtInSubId,
      // Only ever meaningful for the outcome it describes.
      failStage: outcome == ReportOutcome.noTraffic ? failStage : null,
    );
  }

  static String outcomeName(ReportOutcome outcome) => switch (outcome) {
        ReportOutcome.alive => 'alive',
        ReportOutcome.noTraffic => 'no_traffic',
        ReportOutcome.unreachable => 'unreachable',
      };

  Map<String, dynamic> toJson() => {
        'report_uid': uid,
        'config_id': configId,
        'server': server,
        'cred_hash': credHash,
        'protocol': protocol,
        'stage': stage.name,
        'outcome': outcomeName(outcome),
        'ms': ms,
        'asn': asn,
        'transport': transport,
        'app_version': appVersion,
        'mobile_operator': mobileOperator,
        'source': source,
        'fail_stage': failStage?.name,
      };

  static MeasurementReport? fromJson(Map<String, dynamic> json) {
    try {
      return MeasurementReport(
        uid: json['report_uid'] as String,
        configId: json['config_id'] as int?,
        server: json['server'] as String,
        credHash: json['cred_hash'] as String,
        protocol: json['protocol'] as String,
        stage: ReportStage.values.byName(json['stage'] as String),
        outcome: ReportOutcome.values.firstWhere(
            (o) => outcomeName(o) == json['outcome'] as String),
        ms: json['ms'] as int?,
        asn: json['asn'] as String?,
        transport: json['transport'] as String? ?? 'unknown',
        appVersion: json['app_version'] as String? ?? currentAppVersion,
        mobileOperator: json['mobile_operator'] as String?,
        source: json['source'] as int?,
        failStage: switch (json['fail_stage']) {
          'proxy' => FailStage.proxy,
          'tunnel' => FailStage.tunnel,
          _ => null,
        },
      );
    } catch (_) {
      return null;
    }
  }

  /// A random UUID v4.
  static String newUid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')]
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

/// The server a config dials and the account it logs in with, in the form
/// both the app and the bot hash identically.
///
/// Pinned with the config bot on 2026-09-14; a change on either side alone
/// silently splits every family in two, with no error anywhere:
///
///   cred_hash = sha256(utf8(protocol + ":" + credential)).hexdigest()[:16]
///   vless, vmess     credential = uuid, trimmed, lowercased
///   trojan, hysteria credential = password, percent-decoded, case kept
///   ss               credential = method lowercased + ":" + password, decoded
///   protocol spelled as the bot's config_type (hysteria, not hysteria2)
class ServerIdentity {
  const ServerIdentity({
    required this.server,
    required this.protocol,
    required this.credHash,
  });

  final String server;
  final String protocol;
  final String credHash;

  static String hash(String protocol, String credential) => sha256
      .convert(utf8.encode('$protocol:$credential'))
      .toString()
      .substring(0, 16);

  static ServerIdentity? of(VpnConfig config) {
    final raw = config.content?.trim();
    if (raw == null || raw.isEmpty) return null;
    try {
      return switch (config.type) {
        VpnConfigType.vless => _fromUserInfo(raw, 'vless', uuid: true),
        VpnConfigType.trojan => _fromUserInfo(raw, 'trojan', uuid: false),
        VpnConfigType.hysteria => _fromUserInfo(
            raw.replaceFirst(RegExp('^hy2://', caseSensitive: false),
                'hysteria2://'),
            'hysteria',
            uuid: false),
        VpnConfigType.vmess => _vmess(raw),
        VpnConfigType.ss => _shadowsocks(raw),
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }

  static ServerIdentity? _fromUserInfo(
    String raw,
    String protocol, {
    required bool uuid,
  }) {
    final uri = Uri.parse(raw);
    final host = uri.host.toLowerCase();
    if (host.isEmpty || uri.port == 0) return null;
    var credential = Uri.decodeComponent(uri.userInfo);
    if (uuid) credential = credential.trim().toLowerCase();
    if (credential.isEmpty) return null;
    return ServerIdentity(
      server: '$host:${uri.port}',
      protocol: protocol,
      credHash: hash(protocol, credential),
    );
  }

  static ServerIdentity? _vmess(String raw) {
    final blob = raw.substring('vmess://'.length).split('#').first.trim();
    final json =
        jsonDecode(utf8.decode(base64.decode(_pad(blob)), allowMalformed: true));
    if (json is! Map) return null;
    final host = '${json['add'] ?? ''}'
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\[\]]'), '');
    final port = int.tryParse('${json['port'] ?? ''}') ?? 0;
    final uuid = '${json['id'] ?? ''}'.trim().toLowerCase();
    if (host.isEmpty || port == 0 || uuid.isEmpty) return null;
    return ServerIdentity(
      server: '$host:$port',
      protocol: 'vmess',
      credHash: hash('vmess', uuid),
    );
  }

  /// Both forms: `ss://base64(method:pass)@host:port` and the fully encoded
  /// `ss://base64(method:pass@host:port)`.
  static ServerIdentity? _shadowsocks(String raw) {
    final body =
        raw.substring('ss://'.length).split('#').first.split('?').first;
    String creds;
    String hostPort;
    if (body.contains('@')) {
      final at = body.lastIndexOf('@');
      final userInfo = body.substring(0, at);
      hostPort = body.substring(at + 1);
      creds = _looksBase64(userInfo)
          ? utf8.decode(base64.decode(_pad(userInfo)), allowMalformed: true)
          : Uri.decodeComponent(userInfo);
    } else {
      final decoded =
          utf8.decode(base64.decode(_pad(body)), allowMalformed: true);
      final at = decoded.lastIndexOf('@');
      if (at <= 0) return null;
      creds = decoded.substring(0, at);
      hostPort = decoded.substring(at + 1);
    }
    final colon = creds.indexOf(':');
    if (colon <= 0) return null;
    final method = creds.substring(0, colon).toLowerCase();
    final password = creds.substring(colon + 1);

    hostPort = hostPort.replaceAll(RegExp(r'/+$'), '');
    final portSep = hostPort.lastIndexOf(':');
    if (portSep <= 0) return null;
    final host = hostPort
        .substring(0, portSep)
        .replaceAll(RegExp(r'[\[\]]'), '')
        .toLowerCase();
    final port = int.tryParse(hostPort.substring(portSep + 1)) ?? 0;
    if (host.isEmpty || port == 0) return null;
    return ServerIdentity(
      server: '$host:$port',
      protocol: 'ss',
      credHash: hash('ss', '$method:$password'),
    );
  }

  static bool _looksBase64(String value) =>
      !value.contains(':') && RegExp(r'^[A-Za-z0-9+/=_-]+$').hasMatch(value);

  static String _pad(String value) {
    final normalised = value.replaceAll('-', '+').replaceAll('_', '/');
    final remainder = normalised.length % 4;
    return remainder == 0 ? normalised : normalised + '=' * (4 - remainder);
  }
}
