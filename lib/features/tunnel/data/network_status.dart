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

  /// `wifi`, `cellular` or `unknown`: the network under the tunnel, never
  /// the tunnel itself.
  static Future<String> transport() async {
    try {
      final value = await _channel.invokeMethod<String>('transport');
      return value == 'wifi' || value == 'cellular' ? value! : 'unknown';
    } on PlatformException {
      return 'unknown';
    } on MissingPluginException {
      return 'unknown';
    }
  }

  /// MCC+MNC of the mobile network ("43235"), or null. Meant for mobile
  /// data only; see MeasurementReport.mobileOperator.
  static Future<String?> mobileOperator() async {
    try {
      final value = await _channel.invokeMethod<String>('mobileOperator');
      return value != null && RegExp(r'^[0-9]{5,6}$').hasMatch(value)
          ? value
          : null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Whether Android shows any VPN up, or null when it cannot say.
  /// Diagnostics only: it cannot tell this app's tunnel from another's.
  static Future<bool?> vpnActive() async {
    try {
      return await _channel.invokeMethod<bool>('vpnActive');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Whether one of this app's core services is alive, or null when Android
  /// cannot say. Asked of Android, not of the plugin, whose "stopped" also
  /// means "lost its connection to a core that is still running" -- see
  /// `CoreServices.kt`. [vpnOnly] leaves out the device test's proxy core.
  static Future<bool?> coreRunning({bool vpnOnly = false}) async {
    try {
      return await _channel
          .invokeMethod<bool>('coreRunning', {'vpnOnly': vpnOnly});
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Whether Android would start this app's VPN without asking, or null
  /// when it cannot say. Asking does not change anything.
  static Future<bool?> vpnPrepared() async {
    try {
      return await _channel.invokeMethod<bool>('vpnPrepared');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

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
