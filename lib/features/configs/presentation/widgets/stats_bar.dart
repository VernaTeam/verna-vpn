import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/vpn_config.dart';
import '../../../../core/l10n/app_strings.dart';

class StatsBar extends ConsumerWidget {
  final ConfigStats stats;
  const StatsBar({super.key, required this.stats});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final s = ref.watch(stringsProvider);
    final lastUpdated = stats.lastUpdated;

    final String timeLabel;
    if (lastUpdated == null) {
      timeLabel = '—';
    } else {
      final diff = DateTime.now().difference(lastUpdated);
      if (diff.inMinutes < 1) {
        timeLabel = s.justNow;
      } else if (diff.inMinutes < 60) {
        timeLabel = s.minutesAgo(diff.inMinutes);
      } else if (diff.inHours < 24) {
        timeLabel = s.hoursAgo(diff.inHours);
      } else {
        timeLabel = s.daysAgo(diff.inDays);
      }
    }

    return Container(
      color: cs.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.circle, size: 8, color: Colors.green.shade400),
          const SizedBox(width: 6),
          Text(
            '${stats.total} ${s.configsLabel}',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          Text(
            ' · ${stats.totalText} ${s.textLabel} · ${stats.totalFile} ${s.fileLabel}',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
          const Spacer(),
          Icon(Icons.update_rounded, size: 13, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            timeLabel,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
