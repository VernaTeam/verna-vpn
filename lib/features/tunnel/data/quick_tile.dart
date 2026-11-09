import 'package:flutter/services.dart';

import '../domain/tunnel_snapshot.dart';

/// The Dart side of the Quick Settings tile (`VernaTileService`).
///
/// Fails quietly. The tile is a shortcut, and no platform answering here must
/// never get in the way of the tunnel it is a shortcut to.
class QuickTile {
  const QuickTile._();

  static const MethodChannel _channel = MethodChannel('ir.vernaservice.vpn/tile');

  static String? _lastPublished;

  static void attach({
    required Future<void> Function() onConnectRequested,
    required Future<void> Function() onDisconnectRequested,
  }) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'connectRequested':
          await onConnectRequested();
        case 'disconnectRequested':
          await onDisconnectRequested();
        default:
          throw MissingPluginException(call.method);
      }
    });
  }

  /// Forgets what was last sent, so the next [publish] goes through even if
  /// it says the same: the tile may have shown its own guess in between.
  static void forgetPublished() => _lastPublished = null;

  /// Tells the tile what the tunnel is doing. The snapshot stream ticks every
  /// second while connected, so only a change crosses the channel.
  static Future<void> publish(TunnelSnapshot snapshot,
      {required String busyLabel}) async {
    final state = snapshot.isBusy
        ? 'busy'
        : snapshot.isConnected
            ? 'on'
            : 'off';
    if (state == _lastPublished) return;
    _lastPublished = state;
    try {
      await _channel.invokeMethod<void>(
          'publish', {'state': state, 'busyLabel': busyLabel});
    } on PlatformException {
      // The tile reads the service itself when it has no word from here.
    } on MissingPluginException {
      // Same.
    }
  }

  /// A short message for someone who started a connect from the tile and is
  /// not looking at the app.
  static Future<void> toast(String text) async {
    try {
      await _channel.invokeMethod<void>('toast', {'text': text});
    } on PlatformException {
      // Then the tile going back to off is the only answer.
    } on MissingPluginException {
      // Same.
    }
  }

  /// Whether a tap on the tile is waiting for a connect. Reads once.
  static Future<bool> takeConnectRequest() => _take('takeConnectRequest');

  /// Whether the tile stopped the tunnel while no engine was running.
  static Future<bool> takeStoppedAway() => _take('takeStoppedAway');

  static Future<bool> _take(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
