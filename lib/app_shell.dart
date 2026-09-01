import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/l10n/app_strings.dart';
import 'core/theme/palette.dart';
import 'core/widgets/verna_icons.dart';
import 'features/configs/presentation/screens/home_screen.dart';
import 'features/configs/presentation/screens/settings_screen.dart';
import 'features/settings/presentation/screens/plan_screen.dart';
import 'features/stats/presentation/screens/usage_screen.dart';
import 'features/tunnel/presentation/screens/vpn_home_screen.dart';

/// The app's frame: five tabs over one persistent state.
///
/// Replaces the previous arrangement, where every destination was an icon in
/// the home screen's app bar and each opened a fresh route. That worked but hid
/// the app's shape -- the server list and the settings looked like detours from
/// the connect button rather than places of their own.
///
/// [IndexedStack] rather than swapping the body: the config list runs a device
/// test when it opens, and rebuilding it on every tab change would restart that
/// test and throw away results the user is reading.

/// The tab the shell is showing.
///
/// Held here rather than in the widget's own state so a screen inside the
/// shell can move to a sibling tab. The home screen's "server list" button
/// used to push /configs, which stacked a second copy of the list on top of
/// the tab that already held one -- with its own back arrow and its own device
/// test starting from scratch.
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
  /// Which tabs have ever been opened.
  ///
  /// A tab is a placeholder until it is first visited, so the app does not pay
  /// for five screens on launch -- the server list in particular starts a
  /// device-wide probe the moment it builds.
  final Set<int> _visited = {0};

  static const List<Widget> _pages = [
    VpnHomeScreen(),
    HomeScreen(),
    UsageScreen(),
    PlanScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    final c = context.verna;
    final index = ref.watch(shellTabProvider);
    _visited.add(index);

    return Scaffold(
      backgroundColor: c.background,
      body: IndexedStack(
        index: index,
        children: [
          for (var i = 0; i < _pages.length; i++)
            if (_visited.contains(i)) _pages[i] else const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: _NavBar(
        index: index,
        onSelect: (value) => ref.read(shellTabProvider.notifier).select(value),
        labels: [
          strings.tabConnect,
          strings.tabServers,
          strings.tabUsage,
          strings.tabPlan,
          strings.settings,
        ],
      ),
    );
  }
}

/// The bar from the design, drawn rather than configured.
///
/// Material's [NavigationBar] was here and could not be made to match: it
/// insists on a pill indicator behind the active icon, sets its own 64px
/// height and label spacing, and takes Material icons. The design asks for a
/// hairline top rule, no indicator, and its own five line glyphs -- so this is
/// five columns and a border, which is all the bar ever was.
class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.index,
    required this.onSelect,
    required this.labels,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final List<String> labels;

  static const List<VernaIcon> _icons = [
    VernaIcon.connect,
    VernaIcon.servers,
    VernaIcon.usage,
    VernaIcon.plan,
    VernaIcon.settings,
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    return Container(
      decoration: BoxDecoration(
        color: c.background,
        border: Border(top: BorderSide(color: c.borderFaint)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 9, bottom: 12),
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

  final VernaIcon icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    final colour = selected ? c.accent : c.navInactive;

    return InkWell(
      onTap: onTap,
      // No ripple rectangle across the whole column: the design has no
      // indicator here, and a splash the width of a fifth of the screen reads
      // as a bug rather than as feedback.
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        // Keeps the target at the 44px minimum the design asks for, even
        // though the icon and label together are shorter than that.
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            VernaIconView(icon, size: 20, color: colour),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colour,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
