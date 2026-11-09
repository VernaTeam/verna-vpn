import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/palette.dart';
import '../../../tunnel/presentation/providers/tunnel_provider.dart';
import '../../data/app_preferences.dart';
import '../../data/installed_apps.dart';

/// Which apps skip the tunnel.
///
/// Ticked apps go straight to the internet. The usual case in Iran is the
/// reverse of the usual VPN case: a banking or government app that refuses a
/// foreign address, while everything else should stay protected.
class SplitTunnelScreen extends ConsumerStatefulWidget {
  const SplitTunnelScreen({super.key});

  @override
  ConsumerState<SplitTunnelScreen> createState() => _SplitTunnelScreenState();
}

class _SplitTunnelScreenState extends ConsumerState<SplitTunnelScreen> {
  List<InstalledApp>? _apps;
  String _query = '';

  /// What the tunnel was started with, so the screen can say when a change
  /// is still waiting for the next connect.
  late final Set<String> _atOpen;

  @override
  void initState() {
    super.initState();
    _atOpen = {
      ...?ref.read(appPreferencesProvider).valueOrNull?.bypassApps,
    };
    _load();
  }

  Future<void> _load() async {
    final apps = await InstalledApps.load();
    if (!mounted) return;
    setState(() => _apps = apps);
  }

  void _toggle(String package, bool skip) {
    final current = {
      ...?ref.read(appPreferencesProvider).valueOrNull?.bypassApps,
    };
    skip ? current.add(package) : current.remove(package);
    ref
        .read(appPreferencesProvider.notifier)
        .setBypassApps(current.toList()..sort());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    final s = ref.watch(stringsProvider);
    final chosen = {
      ...?ref.watch(appPreferencesProvider).valueOrNull?.bypassApps,
    };
    final connected =
        ref.watch(tunnelSnapshotProvider.select((t) => t.isConnected));
    final changed = chosen.length != _atOpen.length ||
        !chosen.containsAll(_atOpen);

    final apps = _apps;
    final query = _query.trim().toLowerCase();
    final shown = apps == null
        ? const <InstalledApp>[]
        : [
            // Chosen first, so what is already outside the tunnel is the
            // first thing seen rather than a scroll away.
            for (final app in apps)
              if (chosen.contains(app.package) && _matches(app, query)) app,
            for (final app in apps)
              if (!chosen.contains(app.package) && _matches(app, query)) app,
          ];

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        foregroundColor: c.textPrimary,
        elevation: 0,
        title: Text(s.splitTunneling),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Text(
              s.splitIntro,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 13,
                height: 1.6,
              ),
            ),
          ),
          if (connected && changed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: c.warnSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  s.appliesNextConnect,
                  style: TextStyle(color: c.textPrimary, fontSize: 12.5),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              style: TextStyle(color: c.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: s.searchApps,
                hintStyle: TextStyle(color: c.textFaint),
                prefixIcon:
                    Icon(Icons.search_rounded, color: c.textMuted, size: 20),
                filled: true,
                fillColor: c.surface,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: c.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: c.border),
                ),
              ),
            ),
          ),
          Expanded(
            child: apps == null
                ? Center(
                    child: CircularProgressIndicator(color: c.accent),
                  )
                : shown.isEmpty
                    ? Center(
                        child: Text(s.noAppsFound,
                            style: TextStyle(color: c.textMuted)),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                        itemCount: shown.length,
                        itemBuilder: (context, i) {
                          final app = shown[i];
                          final skip = chosen.contains(app.package);
                          return _AppRow(
                            app: app,
                            skip: skip,
                            onChanged: (value) => _toggle(app.package, value),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  static bool _matches(InstalledApp app, String query) =>
      query.isEmpty ||
      app.label.toLowerCase().contains(query) ||
      app.package.toLowerCase().contains(query);
}

class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.app,
    required this.skip,
    required this.onChanged,
  });

  final InstalledApp app;
  final bool skip;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    final icon = app.icon;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onChanged(!skip),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: icon == null
                  ? Icon(Icons.android_rounded, color: c.textMuted)
                  : Image.memory(icon, gaplessPlayback: true),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                app.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.textPrimary, fontSize: 14),
              ),
            ),
            Checkbox(
              value: skip,
              activeColor: c.accent,
              onChanged: (value) => onChanged(value ?? false),
            ),
          ],
        ),
      ),
    );
  }
}
