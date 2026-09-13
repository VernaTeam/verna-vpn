import 'package:flutter/services.dart';

/// Whether the phone has a network to connect over at all.
///
/// Asked before a connection starts, because without one the search has
/// nothing to find: measured on a J7 with Wi-Fi and mobile data both off, the
/// app spent 135 seconds -- ten minutes, before the connect fixes -- trying to
/// reach an API and servers over a network that did not exist, and then
/// reported that no server answered. True, and useless.
///
/// Fails open. A platform that cannot answer is treated as online, so the
/// worst this check can do is nothing.
class NetworkStatus {
  const NetworkStatus._();

  static const MethodChannel _channel =
      MethodChannel('ir.vernaservice.vpn/permissions');

  static Future<bool> hasInternet() async {
    try {
      return await _channel.invokeMethod<bool>('hasInternet') ?? true;
    } on PlatformException {
      return true;
    } on MissingPluginException {
      return true;
    }
  }
}
