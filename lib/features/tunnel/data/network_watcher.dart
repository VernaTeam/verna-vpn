import 'dart:async';

import 'package:flutter/services.dart';

/// Tells the tunnel when the connection underneath it has changed.
///
/// A VPN tunnel is built on whatever network the phone had when it started.
/// Walking out of Wi-Fi onto mobile data does not politely tear the tunnel
/// down: the service keeps running, the notification keeps showing a country,
/// and nothing works. The app reported Connected the whole time, because
/// nothing was watching the ground it stood on.
///
/// Fed by an EventChannel over Android's ConnectivityManager rather than a
/// package: `connectivity_plus` wants AGP 8.12.1 and this project is on AGP 9,
/// which stopped the whole build resolving.
///
/// Reports *changes*, not state. Whether the phone is on Wi-Fi or mobile is not
/// interesting; that it swapped one for the other, or lost the network and got
/// one back, is what invalidates a running tunnel.
class NetworkWatcher {
  NetworkWatcher();

  static const EventChannel _channel =
      EventChannel('ir.vernaservice.vpn/network');

  final StreamController<NetworkChange> _controller =
      StreamController<NetworkChange>.broadcast();
  StreamSubscription<dynamic>? _sub;
  Timer? _debounce;

  String? _current;

  Stream<NetworkChange> get changes => _controller.stream;

  void start() {
    _sub ??= _channel.receiveBroadcastStream().listen(
          _onTransport,
          // A platform that cannot report this is not a reason to fail; the
          // tunnel simply will not notice a handover.
          onError: (Object _) {},
        );
  }

  void _onTransport(dynamic event) {
    final transport = event is String ? event : 'other';

    // The app's own tunnel is a network too. Treating it as a transport change
    // would have the tunnel tear itself down the instant it came up.
    if (transport == 'vpn') return;

    final previous = _current;
    _current = transport;
    if (previous == null || previous == transport) return;

    // Android reports a handover as several events in quick succession -- lost
    // Wi-Fi, nothing, mobile -- and reacting to each would rebuild the tunnel
    // two or three times for one walk out of the door. Waiting for the dust to
    // settle costs a second and asks the question once.
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () {
      if (_controller.isClosed) return;
      final now = _current ?? transport;
      _controller.add(NetworkChange(
        from: previous,
        to: now,
      ));
    });
  }

  void dispose() {
    _debounce?.cancel();
    _sub?.cancel();
    _controller.close();
  }
}

/// What happened to the network underneath the tunnel.
class NetworkChange {
  const NetworkChange({required this.from, required this.to});

  final String from;
  final String to;

  bool get offline => to == 'none';

  /// A network exists again after there was none.
  bool get cameBack => from == 'none' && to != 'none';

  /// One network replaced another.
  bool get swapped => from != 'none' && to != 'none';

  /// Whether a running tunnel should be re-examined because of this.
  bool get invalidatesTunnel => cameBack || swapped;

  @override
  String toString() => '$from -> $to';
}
