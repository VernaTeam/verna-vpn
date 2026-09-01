import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/vpn_config.dart';
import '../../data/config_actions.dart';
import '../../../../core/l10n/app_strings.dart';
import '../widgets/qr_sheet.dart';

class ConfigDetailScreen extends ConsumerStatefulWidget {
  final VpnConfig config;
  const ConfigDetailScreen({super.key, required this.config});

  @override
  ConsumerState<ConfigDetailScreen> createState() =>
      _ConfigDetailScreenState();
}

class _ConfigDetailScreenState extends ConsumerState<ConfigDetailScreen> {
  bool _busy = false;
  double _progress = 0;

  VpnConfig get config => widget.config;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = ref.watch(stringsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('${config.flag} ${config.country}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_rounded),
            tooltip: s.showQr,
            onPressed: () => QrSheet.show(context, config, s),
          ),
          if (config.isText)
            IconButton(
              icon: const Icon(Icons.copy_rounded),
              tooltip: s.copy,
              onPressed: () => _copy(s),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _InfoCard(
            title: s.protocol,
            value: config.type.label,
            icon: Icons.vpn_lock_rounded,
          ),
          _InfoCard(
            title: s.country,
            value: '${config.flag} ${config.country} (${config.countryCode})',
            icon: Icons.public_rounded,
          ),
          // Latency, but only when it was measured through a real tunnel.
          //
          // `ping_ms` in the inventory is a mixture: for most rows it is a TCP
          // handshake with the host, which a CDN edge answers in 2-8ms whether
          // or not the proxy behind it is alive. Ordering by that number halved
          // the real success rate in testing, so showing it as fact would point
          // users at exactly the configs least likely to work. A row that has
          // been run in sing-box and answered through the tunnel carries
          // `verifiedAt`, and only then is the number worth printing.
          _InfoCard(
            title: s.ping,
            value: config.hasMeasuredPing ? '${config.pingMs} ms' : s.notTested,
            icon: Icons.speed_rounded,
            valueColor: _pingColor(),
          ),
          if (config.verifiedAt != null)
            _InfoCard(
              title: s.lastVerified,
              value: _ago(s, config.verifiedAt!),
              icon: Icons.verified_rounded,
              valueColor: Colors.green,
            ),
          _InfoCard(
            title: s.recommendedApp,
            value: config.type.recommendedApp,
            icon: Icons.apps_rounded,
          ),
          if (config.isFile)
            _InfoCard(
              title: s.fileType,
              value: config.fileExtension ?? '—',
              icon: Icons.file_present_rounded,
            ),
          const SizedBox(height: 16),
          if (config.isText && config.content != null) ...[
            Text(s.configContent,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                config.content!,
                textDirection: TextDirection.ltr,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      height: 1.5,
                    ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _copy(s),
                    icon: const Icon(Icons.copy_rounded),
                    label: Text(s.copy),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _openInApp(s),
                    icon: const Icon(Icons.bolt_rounded),
                    label: Text(s.connect),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => QrSheet.show(context, config, s),
              icon: const Icon(Icons.qr_code_rounded),
              label: Text(s.showQr),
            ),
          ],
          if (config.isFile) ...[
            if (_busy) ...[
              LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed: _busy ? null : () => _download(s),
              icon: _busy
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download_rounded),
              label: Text(_busy ? s.downloading : s.download),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => QrSheet.show(context, config, s),
              icon: const Icon(Icons.qr_code_rounded),
              label: Text(s.showQr),
            ),
          ],
        ],
      ),
    );
  }

  /// Colour bands for latency, so the number still reads at a glance. Grey
  /// whenever there is no measured number to colour.
  Color _pingColor() {
    if (!config.hasMeasuredPing) return Colors.grey;
    final ping = config.pingMs!;
    if (ping < 150) return Colors.green;
    if (ping < 500) return Colors.orange;
    return Colors.red;
  }

  /// How long ago the tunnel test happened, in the coarsest unit that still
  /// says something useful.
  String _ago(S s, DateTime when) {
    final minutes = DateTime.now().difference(when).inMinutes;
    if (minutes < 1) return s.justNow;
    if (minutes < 60) return s.minutesAgo(minutes);
    return s.hoursAgo(minutes ~/ 60);
  }


  Future<void> _copy(S s) async {
    if (config.content == null) return;
    await Clipboard.setData(ClipboardData(text: config.content!));
    _snack(s.copied);
  }

  Future<void> _openInApp(S s) async {
    setState(() => _busy = true);
    final result = await ConfigActions.openInApp(config);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result.status) {
      case ActionStatus.ok:
        break;
      case ActionStatus.noApp:
        _snack(s.noApp, isError: true);
      case ActionStatus.failed:
        _snack(s.error, isError: true);
    }
  }

  Future<void> _download(S s) async {
    setState(() {
      _busy = true;
      _progress = 0;
    });
    final result = await ConfigActions.downloadAndOpen(
      config,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result.status) {
      case ActionStatus.ok:
        _snack(s.downloaded);
      case ActionStatus.noApp:
        _snack(s.noApp, isError: true);
      case ActionStatus.failed:
        _snack(s.downloadFailed, isError: true);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            isError ? Theme.of(context).colorScheme.errorContainer : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color? valueColor;
  const _InfoCard({
    required this.title,
    required this.value,
    required this.icon,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon, color: cs.primary),
        title: Text(title,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: cs.onSurfaceVariant)),
        subtitle: Text(value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: valueColor,
                )),
      ),
    );
  }
}
