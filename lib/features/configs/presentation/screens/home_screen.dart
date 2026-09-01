import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../diagnostics/data/app_log.dart';
import '../../domain/vpn_config.dart';
import '../providers/configs_provider.dart';
import '../providers/local_test_provider.dart';
import '../../../tunnel/presentation/providers/tunnel_provider.dart';
import '../widgets/config_card.dart';
import '../widgets/filter_bottom_sheet.dart';
import 'config_detail_screen.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/palette.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Test the list from this device as soon as it opens.
    //
    // The server's verification says a config is alive where the server is;
    // measured on 2026-08-21, only one in eight of those actually carried
    // traffic from this phone. Showing the server's list unfiltered means most
    // rows are things the user cannot use, so the phone checks for itself and
    // the list is rebuilt from what it finds.
    //
    // Deferred to after the first frame: the list has to exist before there is
    // anything to test, and the screen should appear immediately rather than
    // waiting on a network sweep.
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoTest());
  }

  /// Guards against starting the same automatic run twice: the post-frame
  /// call and the "configs arrived" listener both lead here.
  bool _autoTestStarted = false;

  /// Starts a run unless one is already going, or a tunnel is up.
  ///
  /// Probing restarts the core, so testing while connected would drop the
  /// user's tunnel to answer a question about a list.
  void _autoTest() {
    // Unconditional: the point is to find out which gate stops the run, and a
    // log that only fires past the gates cannot tell us that.
    AppLog.instance.info('Auto-test check', detail: [
      'mounted=$mounted',
      'started=$_autoTestStarted',
      'connected=${ref.read(tunnelSnapshotProvider).isConnected}',
      'running=${ref.read(localTestProgressProvider).running}',
      'rows=${ref.read(filteredConfigsProvider).length}',
    ].join(' '));
    if (!mounted || _autoTestStarted) return;
    if (ref.read(tunnelSnapshotProvider).isConnected) {
      AppLog.instance.info('Auto-test skipped', detail: 'a tunnel is up');
      return;
    }
    if (ref.read(localTestProgressProvider).running) return;
    final configs = ref.read(filteredConfigsProvider);
    // Nothing to test yet -- the list is still loading. The listener in build
    // calls back once it arrives.
    if (configs.isEmpty) return;
    _autoTestStarted = true;
    AppLog.instance
        .info('Auto-test starting', detail: '${configs.length} rows');
    ref.read(localTestResultsProvider.notifier).run(configs);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(configsProvider);
    // Listen to the filtered list itself, not to the fetch that feeds it.
    //
    // Watching `configsProvider` looked equivalent and was not: the run was
    // evaluated three times while the fetch was still in flight, each time
    // finding an empty list, and the change that finally carried the configs
    // never reached it. Listening to the thing the decision actually depends on
    // removes the guesswork -- the moment there are rows, there is a run.
    ref.listen<List<VpnConfig>>(
      filteredConfigsProvider,
      (_, next) {
        if (next.isNotEmpty) _autoTest();
      },
    );

    // `ref.listen` only reports changes, so a list that was already loaded when
    // this screen opened would never trigger one. Cover that case directly.
    final current = ref.read(filteredConfigsProvider);
    if (current.isNotEmpty && !_autoTestStarted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoTest());
    }

    final filtered = ref.watch(visibleConfigsProvider);
    final filter = ref.watch(filterProvider);
    final s = ref.watch(stringsProvider);
    final c = context.verna;
    final cs = Theme.of(context).colorScheme;

    final hasActiveFilter =
        filter.typeFilter.isNotEmpty || filter.countryFilter.isNotEmpty;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        foregroundColor: c.textPrimary,
        elevation: 0,
        // Tight on width: the back arrow plus three actions leave little room,
        // and the name overflowed here twice -- once past the refresh button,
        // once truncated to "Ver...". Flexible with an ellipsis keeps it honest
        // at any text scale, and dropping the theme toggle (it lives in
        // Settings) bought back the space the logo needs.
        titleSpacing: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.vpn_lock_rounded, size: 18, color: cs.primary),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                s.appName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
            ),
          ],
        ),
        actions: [
          // Test the visible servers from this device.
          //
          // Disabled while a tunnel is up: probing restarts the core, which
          // would drop the user's connection to answer a question about a list.
          Consumer(builder: (context, ref, _) {
            final progress = ref.watch(localTestProgressProvider);
            final connected = ref.watch(tunnelSnapshotProvider).isConnected;
            return IconButton(
              icon: progress.running
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.speed_rounded),
              tooltip: connected ? s.testWhileConnected : s.testServers,
              onPressed: progress.running || connected
                  ? null
                  : () => ref
                      .read(localTestResultsProvider.notifier)
                      .run(ref.read(filteredConfigsProvider)),
            );
          }),
          // Refresh button with spinning indicator while loading
          IconButton(
            icon: state.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            tooltip: s.retry,
            onPressed: state.isLoading
                ? null
                : () => ref.read(configsProvider.notifier).refresh(),
          ),
          Stack(
            alignment: Alignment.topRight,
            children: [
              IconButton(
                icon: const Icon(Icons.tune_rounded),
                tooltip: s.filter,
                onPressed: () => FilterBottomSheet.show(context),
              ),
              if (hasActiveFilter)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: cs.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          const _TestStatusBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: c.textPrimary),
              decoration: InputDecoration(
                hintText: s.search,
                hintStyle: TextStyle(color: c.textMuted),
                filled: true,
                fillColor: c.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                prefixIcon: Icon(Icons.search_rounded,
                    size: 20, color: c.textMuted),
                suffixIcon: filter.query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(filterProvider.notifier).setQuery('');
                        },
                      )
                    : null,
              ),
              onChanged: (v) =>
                  ref.read(filterProvider.notifier).setQuery(v),
            ),
          ),
          if (hasActiveFilter)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: _ActiveFilterChips(),
            ),
          Expanded(child: _buildBody(state, filtered, s)),
        ],
      ),
    );
  }

  Widget _buildBody(ConfigsState state, List configs, S s) {
    if (state.isLoading && configs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && configs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded,
                size: 64, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text(s.error, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => ref.read(configsProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(s.retry),
            ),
          ],
        ),
      );
    }
    if (configs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded,
                size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(s.noConfigs),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                ref.read(filterProvider.notifier).reset();
                _searchController.clear();
              },
              child: Text(s.clearFilter),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => ref.read(configsProvider.notifier).refresh(),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: configs.length,
        itemBuilder: (context, index) {
          final cfg = configs[index];
          return ConfigCard(
            config: cfg,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ConfigDetailScreen(config: cfg),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// What this device has found so far, in one line.
///
/// Replaces a bar that read "10333 configs - 9405 text - 928 file". Those are
/// the inventory's numbers, and two thirds of them counted things the app no
/// longer shows; none of them told the user the thing that decides whether
/// this screen is useful, which is how many of these servers work from here.
class _TestStatusBar extends ConsumerWidget {
  const _TestStatusBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(localTestProgressProvider);
    final s = ref.watch(stringsProvider);
    final c = context.verna;

    // Counted from the results themselves, not from the rows on screen. The
    // visible list also carries Telegram proxies and rows the run never
    // reached, so counting it claimed 93 working right after a run that found
    // 33 -- a number that flattered the app and told the user nothing.
    final results = ref.watch(localTestResultsProvider);
    final working = results.values.where((r) => r.works).length;

    final running = progress.running;
    final label = running
        ? '${s.testingNow}  ${progress.done}/${progress.total}'
        : progress.total > 0
            ? '$working ${s.workingServers}  ·  ${s.testedHere}'
            : s.testedHere;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      color: c.surface,
      child: Row(
        children: [
          if (running)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: c.accent),
            )
          else
            Icon(Icons.verified_rounded, size: 15, color: c.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: c.textSecondary, fontSize: 12.5),
            ),
          ),
          if (running && progress.total > 0)
            SizedBox(
              width: 60,
              child: LinearProgressIndicator(
                value: progress.done / progress.total,
                minHeight: 3,
                backgroundColor: c.border,
                color: c.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActiveFilterChips extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(filterProvider);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // One chip per selection, each removable on its own -- the filters
          // are sets now, so a single "clear" chip could not undo just one.
          for (final type in filter.typeFilter)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Chip(
                label: Text(type.label),
                onDeleted: () =>
                    ref.read(filterProvider.notifier).toggleType(type),
                deleteIcon: const Icon(Icons.close_rounded, size: 16),
              ),
            ),
          for (final code in filter.countryFilter)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Chip(
                label: Text(code),
                onDeleted: () =>
                    ref.read(filterProvider.notifier).toggleCountry(code),
                deleteIcon: const Icon(Icons.close_rounded, size: 16),
              ),
            ),
        ],
      ),
    );
  }
}
