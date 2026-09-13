import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../configs/domain/vpn_config.dart';
import '../../configs/presentation/providers/configs_provider.dart';
import '../../diagnostics/data/app_log.dart';
import '../data/builtin_subscription.dart';

class BuiltInSubscriptionsState {
  const BuiltInSubscriptionsState({
    this.items = const [],
    this.configs = const {},
    this.disabled = const {},
    this.loading = false,
    this.failed = false,
  });

  /// The lists worth offering, most healthy first.
  final List<BuiltInSubscription> items;

  /// A fresh sample of each list's servers, by subscription id.
  final Map<int, List<VpnConfig>> configs;

  /// Ids the user switched off. Everything else is on.
  final Set<int> disabled;

  final bool loading;

  /// The last refresh could not reach the API. What is on screen then came
  /// from the cache, or there is nothing.
  final bool failed;

  bool isEnabled(int id) => !disabled.contains(id);

  BuiltInSubscriptionsState copyWith({
    List<BuiltInSubscription>? items,
    Map<int, List<VpnConfig>>? configs,
    Set<int>? disabled,
    bool? loading,
    bool? failed,
  }) =>
      BuiltInSubscriptionsState(
        items: items ?? this.items,
        configs: configs ?? this.configs,
        disabled: disabled ?? this.disabled,
        loading: loading ?? this.loading,
        failed: failed ?? this.failed,
      );
}

final builtInSubscriptionsProvider =
    NotifierProvider<BuiltInSubscriptionsController, BuiltInSubscriptionsState>(
        BuiltInSubscriptionsController.new);

class BuiltInSubscriptionsController
    extends Notifier<BuiltInSubscriptionsState> {
  /// Servers asked for per list.
  ///
  /// The largest list holds hundreds of healthy configs, and every row taken
  /// is a row the phone then tests. Twelve lists at thirty each is about as
  /// many rows as Verna's own sample, which a Galaxy J7 gets through in a few
  /// minutes; the freshest-verified thirty of a list are also the ones most
  /// likely to still work.
  static const int perSubscription = 30;

  @override
  BuiltInSubscriptionsState build() {
    Future.microtask(_load);
    return const BuiltInSubscriptionsState(loading: true);
  }

  Future<void> _load() async {
    final cached = await BuiltInSubscriptionStore.read();
    final disabled = await BuiltInSubscriptionStore.readDisabled();
    state = state.copyWith(
      items: cached.items,
      configs: cached.configs,
      disabled: disabled,
    );
    await refresh();
  }

  Future<void> refresh() async {
    state = state.copyWith(loading: true);
    final api = ref.read(apiClientProvider);
    try {
      final items = await api.getSubscriptions();
      // One list failing keeps what it served last time rather than emptying
      // the others.
      final pages = await Future.wait([
        for (final sub in items)
          api
              .getSubscriptionConfigs(sub.id, limit: perSubscription)
              .then((page) => page.configs)
              .catchError(
                  (Object _) => state.configs[sub.id] ?? const <VpnConfig>[]),
      ]);
      final configs = {
        for (var i = 0; i < items.length; i++) items[i].id: pages[i],
      };
      state = state.copyWith(
        items: items,
        configs: configs,
        loading: false,
        failed: false,
      );
      await BuiltInSubscriptionStore.write(items, configs);
      AppLog.instance.info('Built-in subscriptions',
          detail: '${items.length} lists, '
              '${configs.values.fold<int>(0, (n, l) => n + l.length)} servers');
    } catch (e) {
      AppLog.instance.warn('Built-in subscriptions unavailable', detail: '$e');
      state = state.copyWith(loading: false, failed: true);
    }
  }

  Future<void> setEnabled(int id, bool enabled) async {
    final next = {...state.disabled};
    if (enabled) {
      next.remove(id);
    } else {
      next.add(id);
    }
    state = state.copyWith(disabled: next);
    await BuiltInSubscriptionStore.writeDisabled(next);
  }
}

/// The servers of every built-in subscription that is switched on.
///
/// Interleaved one list at a time rather than concatenated: until the phone
/// has tested them the list is shown in this order, and thirty rows of the
/// first list before anything from the second reads as the others missing.
final builtInConfigsProvider = Provider<List<VpnConfig>>((ref) {
  final state = ref.watch(builtInSubscriptionsProvider
      .select((s) => (items: s.items, configs: s.configs, off: s.disabled)));
  final lists = [
    for (final sub in state.items)
      if (!state.off.contains(sub.id)) state.configs[sub.id] ?? const <VpnConfig>[],
  ];
  final seen = <String>{};
  final result = <VpnConfig>[];
  for (var i = 0;; i++) {
    var any = false;
    for (final list in lists) {
      if (i >= list.length) continue;
      any = true;
      if (seen.add(list[i].id)) result.add(list[i]);
    }
    if (!any) break;
  }
  return result;
});
