import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../diagnostics/data/app_log.dart';
import 'network_status.dart';

/// The address this phone shows the internet when nothing is tunnelling it,
/// and the country that address is in.
///
/// The connect screen used to name an address only while connected, so the
/// card read "Germany" with nothing under it beforehand and the user had no
/// way to see what the tunnel actually changed. Meysam, 2026-09-30: show the
/// user's own IP before, the VPN's after -- and then: it shows the address
/// but not the place.
class PublicIp {
  const PublicIp._();

  /// Every probe at once, and the first answer that carries a country wins.
  ///
  /// In order of what they give, not of what is fastest, because the ones
  /// that answer are not the same from every network. From an Iranian mobile
  /// connection `ip-api.com` is blocked and so is `1.1.1.1` -- which is why
  /// the tunnel's own reader keeps three and why this keeps five. If only the
  /// address-only probe answers, the card shows an address with no flag,
  /// which is still better than the nothing it showed before.
  static const List<String> _probes = [
    // Address + country.
    'http://ip-api.com/json',
    'https://api.country.is/',
    'https://ipwho.is/',
    'https://ipinfo.io/json',
    // Address alone. Kept last, and kept: it is the one that answers from
    // here when nothing else does.
    'https://api.ipify.org?format=json',
  ];

  /// Reads the address and, where something answers with one, the country.
  /// Null if nothing answered at all.
  ///
  /// Refuses to read while a VPN network is up -- including the one Android
  /// keeps alive for seconds after a tunnel stops. A reading taken then is
  /// the *old exit*, which would be labelled as the user's own address: the
  /// same mistake that once filed an Iranian SIM as OVH France (§40), except
  /// this one would be on screen.
  static Future<({String ip, String? country})?> read({
    Duration timeout = const Duration(seconds: 8),
    Duration settle = const Duration(seconds: 6),
  }) async {
    if (!await _noVpn(settle)) return null;

    // Raced, not tried in turn. Sequentially, five probes behind a blocked
    // one cost their whole timeout each, and the card would have sat empty
    // for the better part of a minute.
    final answer = Completer<({String ip, String? country})?>();
    final clients = <Dio>[];
    ({String ip, String? country})? partial;
    String? winner;
    var pending = _probes.length;

    void settleOne() {
      pending--;
      if (pending == 0 && !answer.isCompleted) answer.complete(partial);
    }

    for (final url in _probes) {
      final dio = Dio(BaseOptions(
        connectTimeout: timeout,
        receiveTimeout: timeout,
        responseType: ResponseType.plain,
      ));
      clients.add(dio);
      dio.get<String>(url).then<void>((res) {
        final reading = _parse(res.data ?? '');
        if (reading == null) return;
        if (reading.country != null) {
          winner ??= url;
          if (!answer.isCompleted) answer.complete(reading);
        } else {
          partial ??= reading;
          winner ??= url;
        }
      }, onError: (Object _) {
        // Blocked, or simply slower than the one that won.
      }).whenComplete(settleOne);
    }

    try {
      final reading = await answer.future.timeout(
        timeout + const Duration(seconds: 2),
        onTimeout: () => partial,
      );
      // Logged because which probes answer is a property of the network the
      // user is on, and the next "why is there no flag" is answered by this
      // line rather than by guessing.
      AppLog.instance.info(
        'Own IP read',
        detail: reading == null
            ? 'nothing answered'
            : '${reading.country ?? 'country unknown'} · via ${_hostOf(winner ?? '?')}',
      );
      return reading;
    } finally {
      for (final dio in clients) {
        dio.close(force: true);
      }
    }
  }

  static Future<bool> _noVpn(Duration limit) async {
    final deadline = DateTime.now().add(limit);
    while (true) {
      if (await NetworkStatus.vpnActive() != true) return true;
      if (!DateTime.now().isBefore(deadline)) {
        AppLog.instance.info('Own IP not read',
            detail: 'a VPN network is still up; it would show that exit');
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  }

  static String _hostOf(String url) => Uri.tryParse(url)?.host ?? url;

  static ({String ip, String? country})? _parse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final ip = (decoded['ip'] ?? decoded['query']) as String?;
        if (ip == null || ip.isEmpty) return null;
        // Four services, three spellings: ipinfo and country.is say
        // `country`, ip-api says `countryCode`, ipwho.is says `country_code`.
        final country = (decoded['country_code'] ??
            decoded['countryCode'] ??
            decoded['country']) as String?;
        return (
          ip: ip,
          country: country != null && country.length == 2
              ? country.toUpperCase()
              : null,
        );
      }
    } catch (_) {
      // Not JSON.
    }
    return null;
  }
}
