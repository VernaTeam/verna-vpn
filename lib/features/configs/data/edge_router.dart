import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// Reaches the API when the address DNS hands out is unreachable.
///
/// The API sits behind Cloudflare, which is anycast: every edge address serves
/// the site, provided the TLS handshake carries the right SNI and the request
/// the right Host. From an Iranian connection some of those addresses answer
/// and some do not, and which is which changes through the day.
///
/// Measured from Rasht on 2026-09-01, one address at a time, same request:
///
///     OK    575ms  104.21.29.197   (what DNS returned)
///     OK    528ms  104.18.0.1
///     fail 6014ms  104.19.0.1      TimeoutError
///     fail 6002ms  104.22.0.1      TimeoutError
///     OK    558ms  188.114.96.1
///     ...  10 of 17 reachable
///
/// So the app was not failing because the server was down -- it was up the
/// whole time, answering in 53ms on its own loopback -- but because DNS had
/// handed it one of the blocked edges and there was nothing else to try. For
/// a tool whose whole purpose is getting around blocking, losing its own
/// control channel to exactly that is not a detail.
///
/// The fix is to stop treating DNS as the only answer: keep a list of edges,
/// connect straight to one, and let TLS still see the real hostname so the
/// certificate validates normally. Nothing here weakens verification.
class EdgeRouter {
  const EdgeRouter._();

  static const String _key = 'api_edge_ip_v1';

  /// Cloudflare edges to fall back through, in the order they are tried.
  ///
  /// Spread across ranges on purpose: blocking tends to take whole prefixes,
  /// so five addresses in 104.21 would be five ways to fail together. These
  /// are anycast addresses owned by Cloudflare, not this project's servers --
  /// any of them will serve the site.
  static const List<String> edges = [
    '104.18.0.1',
    '104.16.0.1',
    '188.114.96.1',
    '172.66.0.1',
    '104.26.0.1',
    '104.24.0.1',
    '104.17.0.1',
    '104.21.0.1',
  ];

  /// The edge that worked last time, if any.
  ///
  /// Remembered so a user on a network where the default route is blocked does
  /// not pay the timeout again on every launch. Cleared as soon as it stops
  /// working, because the blocking moves.
  static Future<String?> pinned() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_key);
    } catch (_) {
      return null;
    }
  }

  static Future<void> pin(String ip) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, ip);
    } catch (_) {
      // A preference that will not save is not worth failing a request over.
    }
  }

  static Future<void> unpin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {
      // Same.
    }
  }

  /// The order to try: what worked last time first, then the rest.
  static Future<List<String>> order() async {
    final first = await pinned();
    if (first == null) return edges;
    return [first, ...edges.where((e) => e != first)];
  }

  /// An HTTP client that connects to [ip] while still speaking to the real
  /// hostname.
  ///
  /// `connectionFactory` only changes where the socket goes. The URI is
  /// untouched, so SNI and the Host header remain the domain and the
  /// certificate is checked against it exactly as before -- this reaches the
  /// site by another road, it does not lower the gate.
  static HttpClient clientVia(String ip) {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 15);
    client.connectionFactory = (uri, proxyHost, proxyPort) =>
        Socket.startConnect(ip, uri.port);
    return client;
  }
}
