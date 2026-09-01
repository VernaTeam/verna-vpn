import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/palette.dart';
import '../../../tunnel/domain/tunnel_snapshot.dart';
import '../../../tunnel/presentation/providers/tunnel_provider.dart';

/// What this session has actually done.
///
/// Deliberately only the current session. The mockup had monthly usage charts,
/// which would need a store of history the app does not keep -- and inventing
/// one from nothing would be the same sin as the ping badges: a confident
/// number nobody measured. Duration and throughput come straight from the core.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    final c = context.verna;
    final snapshot = ref.watch(tunnelSnapshotProvider);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        foregroundColor: c.textPrimary,
        elevation: 0,
        title: Text(strings.tabStats),
      ),
      body: snapshot.phase != TunnelPhase.connected
          ? _Empty(strings: strings)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _Tile(
                  label: strings.sessionDuration,
                  value: snapshot.duration,
                  icon: Icons.schedule_rounded,
                ),
                _Tile(
                  label: strings.statDownload,
                  value: _speed(snapshot.downloadSpeed),
                  icon: Icons.south_rounded,
                ),
                _Tile(
                  label: strings.statUpload,
                  value: _speed(snapshot.uploadSpeed),
                  icon: Icons.north_rounded,
                ),
                _Tile(
                  label: strings.statPing,
                  value: snapshot.pingMs == null
                      ? '—'
                      : '${snapshot.pingMs} ms',
                  icon: Icons.speed_rounded,
                ),
                _Tile(
                  label: strings.exitAddress,
                  value: snapshot.exitIp ?? '—',
                  icon: Icons.public_rounded,
                ),
              ],
            ),
    );
  }

  String _speed(int bytesPerSecond) {
    if (bytesPerSecond <= 0) return '0 KB/s';
    if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).round()} KB/s';
    }
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.strings});

  final S strings;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insights_outlined, size: 56, color: c.border),
          const SizedBox(height: 12),
          Text(
            strings.statsWhenConnected,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textMuted),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        // A solid surface, not white at 5% opacity: that trick reads as a
        // faint card on near-black and as nothing at all on a light page.
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: c.textMuted, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label,
                style: TextStyle(color: c.textSecondary, fontSize: 14)),
          ),
          // Figures and units are one LTR token; an RTL layout would mirror
          // "12 KB/s" into "KB/s 12".
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              value,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
