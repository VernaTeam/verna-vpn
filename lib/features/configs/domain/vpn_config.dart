/// Unified VPN config entity (text URI or downloadable file)
class VpnConfig {
  final String id;
  final VpnConfigType type;
  final VpnConfigKind kind;
  final String? content;
  final String? downloadUrl;
  final String? fileExtension;
  final String country;
  final String flag;
  final String countryCode;
  final int? pingMs;
  final int quality; // 0-100, server-side quality score
  final DateTime? foundAt;

  /// When the server last proved this config alive by running it in sing-box
  /// and reading the exit through the tunnel. Null means it has never had that
  /// test -- only a TCP ping, which a CDN edge answers whether or not the proxy
  /// behind it is alive.
  final DateTime? verifiedAt;

  const VpnConfig({
    required this.id,
    required this.type,
    required this.kind,
    this.content,
    this.downloadUrl,
    this.fileExtension,
    required this.country,
    required this.flag,
    required this.countryCode,
    this.pingMs,
    this.quality = 0,
    this.foundAt,
    this.verifiedAt,
  });

  /// Whether the latency figure came from a real tunnel rather than a TCP
  /// handshake. Only then is it worth showing as a number.
  bool get hasMeasuredPing =>
      verifiedAt != null && pingMs != null && pingMs! > 0;

  bool get isText => kind == VpnConfigKind.text;
  bool get isFile => kind == VpnConfigKind.file;

  /// Absolute download URL. The API returns a relative path; callers that need
  /// a full URL (QR, download) should use this with the configured base.
  String? absoluteDownloadUrl(String baseHost) {
    if (downloadUrl == null) return null;
    if (downloadUrl!.startsWith('http')) return downloadUrl;
    return '$baseHost$downloadUrl';
  }

  String get typeLabel => type.label;

  /// Quality bucket for color/label.
  QualityLevel get qualityLevel {
    if (quality <= 0) return QualityLevel.unknown;
    if (quality >= 70) return QualityLevel.high;
    if (quality >= 40) return QualityLevel.medium;
    return QualityLevel.low;
  }
}

enum QualityLevel { high, medium, low, unknown }

/// What the app can do something useful with.
///
/// Everything else -- .ovpn and .conf files, npvt, dark, the proprietary
/// app formats -- can only ever be copied out and opened somewhere else. Those
/// rows made the list longer without making it more useful, and they broke the
/// promise the list now makes: that what you see here was tested from this
/// phone. They live in the Telegram channel, which is the right place for them.
///
/// hysteria2, tuic, wireguard and warp are absent because the embedded Xray
/// core cannot run them. They come back when the core does.
const Set<VpnConfigType> tunnelableTypes = {
  VpnConfigType.vless,
  VpnConfigType.vmess,
  VpnConfigType.trojan,
  VpnConfigType.ss,
  // Listed on request, ahead of the core that can run it: Xray has no
  // hysteria, so these fail a device test until the sing-box migration.
  VpnConfigType.hysteria,
};

/// Handed to Telegram rather than run in the tunnel.
/// Protocols the app lists but hands to another app instead of running.
///
/// Empty on purpose. It held MTProto, which Telegram uses and this tunnel
/// cannot: those rows could never be tested, never carried the app's traffic,
/// and still occupied the list looking like servers -- so when every real
/// server failed, the screen was full of entries that had never been
/// candidates. The set stays because the handling around it is correct and a
/// future protocol may need it; nothing populates it today.
const Set<VpnConfigType> handoffTypes = <VpnConfigType>{};

/// Everything the app is willing to show.
final Set<VpnConfigType> usableTypes = {...tunnelableTypes, ...handoffTypes};

enum VpnConfigKind { text, file }

enum VpnConfigType {
  vmess,
  vless,
  trojan,
  ss,
  ssr,
  hysteria,
  tuic,
  warp,
  tgProxy,
  openvpn,
  wireguard,
  npvt,
  dark,
  unknown;

  static VpnConfigType fromString(String s) {
    return switch (s.toLowerCase()) {
      'vmess' => vmess,
      'vless' => vless,
      'trojan' => trojan,
      'ss' => ss,
      'ssr' => ssr,
      'hysteria' => hysteria,
      'tuic' => tuic,
      'warp' => warp,
      'tg_proxy' => tgProxy,
      'openvpn' => openvpn,
      'wireguard' => wireguard,
      'npvt' => npvt,
      'dark' => dark,
      _ => unknown,
    };
  }

  String get label => switch (this) {
        vmess => 'VMess',
        vless => 'VLESS',
        trojan => 'Trojan',
        ss => 'Shadowsocks',
        ssr => 'ShadowsocksR',
        hysteria => 'Hysteria2',
        tuic => 'TUIC',
        warp => 'WARP',
        tgProxy => 'MTProto',
        openvpn => 'OpenVPN',
        wireguard => 'WireGuard',
        npvt => 'NPV Tunnel',
        dark => 'Dark Tunnel',
        unknown => 'Unknown',
      };

  String get recommendedApp => switch (this) {
        vmess || vless || trojan || ss || hysteria || tuic => 'v2rayNG / Hiddify',
        ssr => 'v2rayNG',
        warp => '1.1.1.1',
        tgProxy => 'Telegram',
        openvpn => 'OpenVPN Connect',
        wireguard => 'WireGuard',
        npvt => 'NPV Tunnel',
        dark => 'Dark Tunnel',
        unknown => '—',
      };
}

class ConfigsPage {
  final int total;
  final List<VpnConfig> configs;
  const ConfigsPage({required this.total, required this.configs});
}

class ConfigStats {
  final int totalText;
  final int totalFile;
  final Map<String, int> byType;
  final DateTime? lastUpdated;

  const ConfigStats({
    required this.totalText,
    required this.totalFile,
    required this.byType,
    this.lastUpdated,
  });

  int get total => totalText + totalFile;
}

/// One row of the server-location list: an exit country and how many verified
/// configs currently leave from it.
class VerifiedCountry {
  const VerifiedCountry({
    required this.code,
    required this.name,
    required this.flag,
    required this.count,
  });

  final String code;
  final String name;
  final String flag;
  final int count;

  factory VerifiedCountry.fromJson(Map<String, dynamic> json) {
    return VerifiedCountry(
      code: json['code'] as String? ?? '',
      name: json['name'] as String? ?? '',
      flag: json['flag'] as String? ?? '',
      count: json['count'] as int? ?? 0,
    );
  }
}
