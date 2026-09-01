import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../../configs/data/config_actions.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final s = ref.watch(stringsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(s.about)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(Icons.vpn_lock_rounded, size: 50, color: cs.primary),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              s.appName,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              s.appTagline,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.6,
                  ),
            ),
          ),
          const SizedBox(height: 32),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.telegram_rounded),
            title: Text(s.telegramChannel),
            subtitle: const Text('@Verna_VPN'),
            trailing: const Icon(Icons.open_in_new_rounded, size: 18),
            onTap: () => ConfigActions.openTelegram('Verna_VPN'),
          ),
          ListTile(
            leading: const Icon(Icons.tag_rounded),
            title: Text(s.version),
            subtitle: const Text('1.0.0'),
          ),
        ],
      ),
    );
  }
}
