import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../domain/vpn_config.dart';
import '../../data/config_api_client.dart';
import '../../../../core/l10n/app_strings.dart';

/// Reusable QR bottom sheet for a config. Scroll-safe and sized to the
/// viewport so it never overflows on small screens.
class QrSheet {
  QrSheet._();

  static void show(BuildContext context, VpnConfig config, S s) {
    final data = config.isText
        ? config.content
        : config.absoluteDownloadUrl(apiBaseUrl);

    if (data == null || data.isEmpty) return;

    final hint = config.isText ? s.qrHintText : s.qrHintFile;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        // QR size adapts to the smaller of width/height, capped, with margins
        // reserved for text so nothing overflows.
        final media = MediaQuery.of(ctx);
        final maxQr = (media.size.width - 96).clamp(160.0, 280.0);

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${config.flag} ${config.country}',
                    style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(s.qrTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        )),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: QrImageView(
                    data: data,
                    version: QrVersions.auto,
                    size: maxQr,
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.L,
                    errorStateBuilder: (c, err) => SizedBox(
                      width: maxQr,
                      height: maxQr,
                      child: const Center(
                        child: Text('QR generation failed',
                            textAlign: TextAlign.center),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(hint,
                    textAlign: TextAlign.center,
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        )),
              ],
            ),
          ),
        );
      },
    );
  }
}
