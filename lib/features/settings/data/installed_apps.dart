import 'package:flutter/services.dart';

/// An app the user can open, for the split-tunneling list.
class InstalledApp {
  const InstalledApp({
    required this.package,
    required this.label,
    this.icon,
  });

  final String package;
  final String label;

  /// PNG bytes, or null when Android would not draw it.
  final Uint8List? icon;
}

/// The phone's launchable apps, read once per visit to the list.
///
/// Launchable rather than installed: a list of every package is hundreds of
/// system components nobody recognises, and Android 11 only lets an app see
/// what its manifest declares it needs to -- here, launcher entries.
class InstalledApps {
  const InstalledApps._();

  static const MethodChannel _channel =
      MethodChannel('ir.vernaservice.vpn/permissions');

  static Future<List<InstalledApp>> load() async {
    try {
      final raw = await _channel.invokeListMethod<Map>('launchableApps') ??
          const [];
      final apps = [
        for (final item in raw)
          InstalledApp(
            package: item['package'] as String,
            label: (item['label'] as String?)?.trim().isNotEmpty == true
                ? item['label'] as String
                : item['package'] as String,
            icon: item['icon'] as Uint8List?,
          ),
      ];
      apps.sort(
          (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
      return apps;
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }
}
