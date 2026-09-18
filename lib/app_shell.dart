import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/l10n/app_strings.dart';
import 'core/theme/palette.dart';
import 'features/configs/presentation/screens/settings_screen.dart';
import 'features/configs/presentation/widgets/auto_test_runner.dart';
import 'features/stats/presentation/screens/usage_screen.dart';
import 'features/subscriptions/presentation/subscriptions_screen.dart';
import 'features/tunnel/presentation/screens/locations_screen.dart';
import 'features/tunnel/presentation/screens/vpn_home_screen.dart';

/// The app's frame: five tabs over one persistent state.
///
/// [IndexedStack] rather than swapping the body: a screen keeps its scroll
/// position and its controllers when the user comes back to it, and the map on
/// the connect screen keeps the country it had flown to.
///
/// The fifth tab is Subscriptions, where the Aurora handoff has Plan. This app
/// is free -- no account, no quota, no renewal date -- so a plan screen could
/// only ever show invented numbers, while the subscriptions behind the server
/// list are real and were buried two levels deep in Settings.

/// The tab the shell is showing.
///
/// Held here rather than in the widget's own state so a screen inside the
/// shell can move to a sibling tab: the connect screen's location card opens
/// Locations, and choosing a country there comes back to Connect.
class ShellTab extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) => state = index;
}

final shellTabProvider = NotifierProvider<ShellTab, int>(ShellTab.new);

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  /// Which tabs have ever been opened, so the app does not build five screens
  /// on launch.
  final Set<int> _visited = {0};

  static const List<Widget> _pages = [
    VpnHomeScreen(),
    LocationsScreen(),
    UsageScreen(),
    SubscriptionsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    final c = context.verna;
    final index = ref.watch(shellTabProvider);
    _visited.add(index);

    return AutoTestRunner(
      child: Scaffold(
        backgroundColor: c.background,
        // The design floats the bar over the content, with every scroll area
        // padded by 92 to clear it. Here the bar takes its own space instead:
        // the usage, subscriptions and settings screens were written against a
        // bar that occupies layout, and a floating one would hide their last
        // row until each of them is re-padded. The card look is the same.
        body: IndexedStack(
          index: index,
          children: [
            for (var i = 0; i < _pages.length; i++)
              if (_visited.contains(i)) _pages[i] else const SizedBox.shrink(),
          ],
        ),
        bottomNavigationBar: _NavBar(
          index: index,
          onSelect: (value) =>
              ref.read(shellTabProvider.notifier).select(value),
          labels: [
            strings.tabConnect,
            strings.tabLocations,
            strings.tabUsage,
            strings.tabSubscriptions,
            strings.settings,
          ],
        ),
      ),
    );
  }
}

/// The floating bar from the design: a card pinned to the bottom with the
/// active item sitting in a wash of the accent.
class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.index,
    required this.onSelect,
    required this.labels,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final List<String> labels;

  static const List<IconData> _icons = [
    Icons.power_settings_new_rounded,
    Icons.public_rounded,
    Icons.bar_chart_rounded,
    Icons.layers_rounded,
    Icons.tune_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: c.shadow.withValues(alpha: 0.35),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: [
            for (var i = 0; i < _icons.length; i++)
              Expanded(
                child: _NavItem(
                  icon: _icons[i],
                  label: labels[i],
                  selected: i == index,
                  onTap: () => onSelect(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    final colour = selected ? c.accent : c.navInactive;

    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          // 44 tall including the padding: the minimum tap target, which the
          // icon and label together do not reach on their own.
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: selected ? c.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 21, color: colour),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colour,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
