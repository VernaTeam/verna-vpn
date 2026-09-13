import 'dart:convert';

import '../../../core/geo/country_names.dart';
import '../../configs/domain/vpn_config.dart';

/// What one subscription body turned into.
class ParsedSubscription {
  const ParsedSubscription({required this.uris, required this.unsupported});

  /// Share links this app can run, deduplicated, in the order they appeared.
  final List<String> uris;

  /// Share links it cannot -- AnyTLS, TUIC, SOCKS, WireGuard and the like.
  /// Counted rather than dropped silently, so the screen can say that a link
  /// was read and some of it was set aside, instead of looking half-broken.
  final int unsupported;
}

/// Reads a subscription link's body the way the config bot does.
///
/// A subscription is, in practice, one of two things: one base64 blob that
/// decodes to a share link per line, or those lines in plain text. The bot's
/// `scraper/sub_fetcher.py` accepts exactly these two and nothing else, and it
/// has read twenty real links without needing more, so this matches it rather
/// than guessing at Clash or sing-box JSON formats nobody has handed it yet.
///
/// Pure: no network, no storage, so every rule here can be tested directly.
class SubscriptionParser {
  const SubscriptionParser._();

  /// Schemes the embedded sing-box can run, and what the app calls them.
  ///
  /// `hy2` is the short form of `hysteria2`; the outbound converter already
  /// accepts both, and subscriptions use both.
  static const Map<String, VpnConfigType> _schemes = {
    'vless': VpnConfigType.vless,
    'vmess': VpnConfigType.vmess,
    'trojan': VpnConfigType.trojan,
    'ss': VpnConfigType.ss,
    'hysteria2': VpnConfigType.hysteria,
    'hy2': VpnConfigType.hysteria,
  };

  /// How many servers one subscription may contribute.
  ///
  /// Public aggregator links run to five thousand lines. Every line kept here
  /// is a row in the list and a candidate for the on-device test, so an
  /// unbounded link would turn one paste into minutes of probing -- and a
  /// personal subscription, which is what this feature is for, is a few dozen.
  static const int defaultLimit = 200;

  static ParsedSubscription parse(String body, {int limit = defaultLimit}) {
    final text = _decodeBody(body);
    final seen = <String>{};
    final uris = <String>[];
    var unsupported = 0;

    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final marker = line.indexOf('://');
      // Not a share link at all -- a header, a comment, a stray word.
      if (marker <= 0) continue;
      final scheme = line.substring(0, marker).toLowerCase();
      if (!_schemes.containsKey(scheme)) {
        unsupported++;
        continue;
      }
      if (!seen.add(line)) continue;
      if (uris.length < limit) uris.add(line);
    }
    return ParsedSubscription(uris: uris, unsupported: unsupported);
  }

  /// The body as lines of share links, whichever form it arrived in.
  ///
  /// Plain text is recognised by containing `://`, which no base64 alphabet
  /// can produce. Anything else is tried as base64, including the URL-safe
  /// alphabet and missing padding, both of which real subscriptions use.
  static String _decodeBody(String body) {
    final trimmed = body.trim();
    if (trimmed.contains('://')) return trimmed;
    final decoded = _base64Text(trimmed.replaceAll(RegExp(r'\s+'), ''));
    if (decoded != null && decoded.contains('://')) return decoded;
    return trimmed;
  }

  static String? _base64Text(String input) {
    var s = input.replaceAll('-', '+').replaceAll('_', '/');
    // A length of 4n+1 cannot be valid base64; the bot drops the stray
    // character, and so does this.
    if (s.length % 4 == 1) s = s.substring(0, s.length - 1);
    final mod = s.length % 4;
    if (mod != 0) s = s.padRight(s.length + 4 - mod, '=');
    try {
      return utf8.decode(base64.decode(s), allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  static VpnConfigType typeOf(String uri) {
    final marker = uri.indexOf('://');
    if (marker <= 0) return VpnConfigType.unknown;
    return _schemes[uri.substring(0, marker).toLowerCase()] ??
        VpnConfigType.unknown;
  }

  /// The server's name as its publisher wrote it.
  ///
  /// The fragment after `#` for most schemes; for VMess, whose whole payload
  /// is base64 JSON, the `ps` field inside it.
  static String remarkOf(String uri) {
    if (uri.toLowerCase().startsWith('vmess://')) {
      final blob = uri.substring(8).split('#').first.trim();
      final json = _base64Text(blob);
      if (json != null) {
        try {
          final decoded = jsonDecode(json);
          if (decoded is Map && decoded['ps'] is String) {
            return (decoded['ps'] as String).trim();
          }
        } catch (_) {
          // Not JSON after all; fall back to the fragment below.
        }
      }
    }
    final hash = uri.indexOf('#');
    if (hash < 0) return '';
    final fragment = uri.substring(hash + 1);
    try {
      return Uri.decodeComponent(fragment).trim();
    } catch (_) {
      return fragment.trim();
    }
  }

  static bool _isRegional(int rune) => rune >= 0x1F1E6 && rune <= 0x1F1FF;

  /// The first flag emoji in [text], and the country code it spells.
  ///
  /// A flag is two regional-indicator symbols, each one letter of the ISO code
  /// shifted into that block -- so the code falls straight out of it, with no
  /// lookup table. That is what lets the country filter work on a user's own
  /// servers, which arrive with no geo data of any kind.
  static ({String flag, String code}) flagOf(String text) {
    final runes = text.runes.toList();
    for (var i = 0; i + 1 < runes.length; i++) {
      final first = runes[i];
      final second = runes[i + 1];
      if (_isRegional(first) && _isRegional(second)) {
        return (
          flag: String.fromCharCodes([first, second]),
          code: String.fromCharCodes(
              [first - 0x1F1E6 + 0x41, second - 0x1F1E6 + 0x41]),
        );
      }
    }
    return (flag: '', code: '');
  }

  /// The remark Verna puts on a link, in the form the config bot writes for
  /// the pool: `@Verna_VPN 🔐 | DE 🇩🇪`.
  static String brandFor(String code, String flag) =>
      code.isEmpty ? '@Verna_VPN 🔐' : '@Verna_VPN 🔐 | $code $flag';

  /// [uri] with its publisher's remark replaced by Verna's.
  ///
  /// The remark is where a share link names whoever published it -- usually a
  /// Telegram channel -- and a copied link or a QR code carries it into every
  /// app it is pasted into. Only the name changes; the server is untouched.
  static String rebrand(String uri, {required String code, required String flag}) {
    final label = brandFor(code, flag);
    if (uri.toLowerCase().startsWith('vmess://')) {
      final blob = uri.substring(8).split('#').first.trim();
      final json = _base64Text(blob);
      if (json != null) {
        try {
          final decoded = jsonDecode(json);
          if (decoded is Map) {
            decoded['ps'] = label;
            return 'vmess://${base64.encode(utf8.encode(jsonEncode(decoded)))}';
          }
        } catch (_) {
          // Not JSON after all; treat it like any other link below.
        }
      }
    }
    final hash = uri.indexOf('#');
    final bare = hash < 0 ? uri : uri.substring(0, hash);
    return '$bare#${Uri.encodeComponent(label)}';
  }

  /// One share link as a row the rest of the app already knows how to show,
  /// test and connect to.
  ///
  /// The row is named after its country, never after its remark: remarks are
  /// where publishers put their channel names, and the row used to print
  /// "@WhiteDNS | GB97 | 6.1MB/s" as the server's title.
  ///
  /// The id is derived from the link as the subscription served it, so it
  /// survives a refresh: a server tested yesterday keeps its result when the
  /// subscription is fetched again and still lists it.
  static VpnConfig toConfig(
    String uri, {
    required String subscriptionId,
    required String subscriptionName,
  }) {
    final flag = flagOf(remarkOf(uri));
    return VpnConfig(
      id: 'sub:$subscriptionId:${_hash(uri)}',
      type: typeOf(uri),
      kind: VpnConfigKind.text,
      content: rebrand(uri, code: flag.code, flag: flag.flag),
      country: flag.code.isEmpty ? '' : CountryNames.of(flag.code),
      flag: flag.flag,
      countryCode: flag.code,
      subscriptionName: subscriptionName,
    );
  }

  /// FNV-1a, 32-bit. Stable across runs and platforms, which Object.hashCode
  /// is not, and plenty for telling a few hundred links apart.
  static String _hash(String text) {
    var hash = 0x811c9dc5;
    for (final unit in text.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
