import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/palette.dart';
import '../../../settings/data/app_preferences.dart';
import '../../../stats/data/usage_store.dart';
import '../../data/config_actions.dart';

/// Settings, to the design's layout.
///
/// It used to run on Material's stock dark theme -- near-black with a purple
/// accent -- which made the last tab look like a screen borrowed from another
/// app the moment you arrived from the connect screen.
///
/// The design's four switches are not four switches here. Auto-connect is
/// built, so it is a switch; kill switch, split tunneling and local network
/// access are not, so they say so. A toggle that flips and changes nothing is
/// worse than a missing feature -- and on a kill switch, which exists to
/// promise that traffic stops when the tunnel does, it is the one place a
/// decorative control could actually get someone hurt.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final c = context.verna;
    final lang = ref.watch(langProvider).valueOrNull ?? AppLang.fa;
    final themeMode =
        ref.watch(themeModeProvider).valueOrNull ?? ThemeMode.system;
    final prefs =
        ref.watch(appPreferencesProvider).valueOrNull ?? const AppPreferences();

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            Text(
              s.settings,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 18),

            // Language and appearance as segmented pills, the way the design
            // has them: two choices side by side beat two rows with a tick,
            // because the alternative is visible instead of implied.
            _Row(
              title: s.language,
              trailing: _Segmented(
                options: const ['EN', 'فارسی'],
                index: lang == AppLang.en ? 0 : 1,
                onSelect: (i) => ref
                    .read(langProvider.notifier)
                    .setLang(i == 0 ? AppLang.en : AppLang.fa),
              ),
            ),
            const SizedBox(height: 10),
            _Row(
              title: s.appearance,
              // Three, not the design's two: it drops System, and a phone-wide
              // dark schedule is a setting people actually use. Losing a
              // working feature is a worse mismatch than an extra segment.
              trailing: _Segmented(
                options: [s.themeSystem, s.themeLight, s.themeDark],
                index: switch (themeMode) {
                  ThemeMode.system => 0,
                  ThemeMode.light => 1,
                  ThemeMode.dark => 2,
                },
                onSelect: (i) =>
                    ref.read(themeModeProvider.notifier).setMode(switch (i) {
                          0 => ThemeMode.system,
                          1 => ThemeMode.light,
                          _ => ThemeMode.dark,
                        }),
              ),
            ),

            const SizedBox(height: 20),
            _SectionLabel(s.connection),
            const SizedBox(height: 8),

            _Row(
              title: s.autoConnect,
              subtitle: s.autoConnectHint,
              trailing: _Switch(
                value: prefs.autoConnect,
                onChanged: (value) => ref
                    .read(appPreferencesProvider.notifier)
                    .setAutoConnect(value),
              ),
            ),
            const SizedBox(height: 10),
            _Row(
              title: s.killSwitch,
              subtitle: s.killSwitchHint,
              trailing: _SoonBadge(label: s.notBuiltYet),
            ),
            const SizedBox(height: 10),
            _Row(
              title: s.splitTunneling,
              subtitle: s.splitTunnelingHint,
              trailing: _SoonBadge(label: s.notBuiltYet),
            ),
            const SizedBox(height: 10),
            _Row(
              title: s.lanAccess,
              subtitle: s.lanAccessHint,
              trailing: _SoonBadge(label: s.notBuiltYet),
            ),
            const SizedBox(height: 10),
            // Read-only, because they are facts about how the tunnel is built
            // rather than choices: the server is picked by the device's own
            // ping test, and DNS is resolved over HTTPS inside the tunnel.
            // Showing them as pickers would offer control that does not exist.
            _Row(
              title: s.selectionLabel,
              subtitle: s.selectionHint,
              trailing: const _MonoValue('AUTO'),
            ),
            const SizedBox(height: 10),
            _Row(
              title: s.dnsLabel,
              subtitle: s.dnsHint,
              trailing: const _MonoValue('1.1.1.1'),
            ),

            const SizedBox(height: 20),
            _SectionLabel(s.maintenance),
            const SizedBox(height: 8),

            _Row(
              title: s.telegramChannel,
              subtitle: '@Verna_VPN',
              leading: Icon(Icons.telegram_rounded, size: 20, color: c.accent),
              trailing: Icon(Icons.open_in_new_rounded,
                  size: 16, color: c.textMuted),
              onTap: () => ConfigActions.openTelegram('Verna_VPN'),
            ),
            const SizedBox(height: 10),
            _Row(
              title: s.diagnostics,
              leading: Icon(Icons.monitor_heart_outlined,
                  size: 20, color: c.textSecondary),
              trailing:
                  Icon(Icons.chevron_right_rounded, size: 20, color: c.textMuted),
              onTap: () => Navigator.pushNamed(context, '/diagnostics'),
            ),
            const SizedBox(height: 10),
            _Row(
              title: s.clearCache,
              leading: Icon(Icons.delete_outline_rounded,
                  size: 20, color: c.textSecondary),
              trailing:
                  Icon(Icons.chevron_right_rounded, size: 20, color: c.textMuted),
              onTap: () => _clearCache(context, s),
            ),
            const SizedBox(height: 10),
            _Row(
              title: s.resetUsage,
              subtitle: s.resetUsageHint,
              leading: Icon(Icons.insights_outlined,
                  size: 20, color: c.textSecondary),
              trailing:
                  Icon(Icons.chevron_right_rounded, size: 20, color: c.textMuted),
              onTap: () async {
                await ref.read(usageProvider.notifier).reset();
                if (context.mounted) _toast(context, s.cacheCleared);
              },
            ),

            const SizedBox(height: 26),
            Center(
              child: Text(
                'VERNA 1.0.0',
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  color: c.textFaint,
                  fontSize: 10.5,
                  letterSpacing: 0.6,
                  fontFamily: VernaType.mono,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clearCache(BuildContext context, S s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cache_text_configs');
    await prefs.remove('cache_file_configs');
    await prefs.remove('cache_time');
    await prefs.remove('cache_verified_configs');
    if (!context.mounted) return;
    _toast(context, s.cacheCleared);
  }

  static void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: context.verna.surfaceSunken,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

/// One settings row: its own card, as the design has them, rather than grouped
/// rows behind a single border.
class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: c.textMuted,
                          fontSize: 11,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A pill of mutually exclusive choices.
class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.options,
    required this.index,
    required this.onSelect,
  });

  final List<String> options;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < options.length; i++)
            GestureDetector(
              onTap: () => onSelect(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: i == index ? c.accent : null,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  options[i],
                  style: TextStyle(
                    color: i == index ? c.onAccent : c.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The design's 44x26 switch, rather than Material's.
class _Switch extends StatelessWidget {
  const _Switch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 26,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value ? c.selectedSurface : c.surfaceSunken,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: value ? c.selectedBorder : c.border),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: value ? c.accent : c.navInactive,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// What an unbuilt setting shows instead of a control.
class _SoonBadge extends StatelessWidget {
  const _SoonBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.chip,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: c.textFaint,
          fontSize: 10.5,
          fontFamily: VernaType.mono,
        ),
      ),
    );
  }
}

class _MonoValue extends StatelessWidget {
  const _MonoValue(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        textDirection: TextDirection.ltr,
        style: TextStyle(
          color: context.verna.accent,
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
          fontFamily: VernaType.mono,
        ),
      );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          color: context.verna.textFaint,
          fontSize: 10,
          letterSpacing: 0.12,
          fontFamily: VernaType.mono,
        ),
      );
}
