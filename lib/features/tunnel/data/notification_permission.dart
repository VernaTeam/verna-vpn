import 'package:flutter/services.dart';

/// Asks for the runtime notification permission, once, before the first
/// connection.
///
/// Android 13 made the foreground-service notification conditional on
/// POST_NOTIFICATIONS, and nothing grants it implicitly. Without it the tunnel
/// runs perfectly and shows nothing: no country, no throughput, no stop button.
///
/// Asked at connect time rather than at launch, because the permission dialog
/// makes sense next to the VPN consent dialog and means nothing on a screen the
/// user has just opened for the first time.
class NotificationPermission {
  const NotificationPermission._();

  static const MethodChannel _channel =
      MethodChannel('ir.vernaservice.vpn/permissions');

  /// True when the notification will actually be shown -- including on every
  /// Android below 13, where the permission does not exist.
  static Future<bool> granted() async {
    try {
      return await _channel.invokeMethod<bool>('hasNotificationPermission') ??
          true;
    } on PlatformException {
      // An unimplemented channel means a platform without this restriction.
      return true;
    } on MissingPluginException {
      return true;
    }
  }

  /// Shows the system dialog if it has not been answered yet.
  ///
  /// Deliberately fire-and-forget: the answer arrives asynchronously and the
  /// connection must not wait on it. A refusal costs the notification, not the
  /// tunnel.
  static Future<void> request() async {
    try {
      await _channel.invokeMethod<void>('requestNotificationPermission');
    } on PlatformException {
      // Nothing to do: the tunnel works either way.
    } on MissingPluginException {
      // Same.
    }
  }
}
