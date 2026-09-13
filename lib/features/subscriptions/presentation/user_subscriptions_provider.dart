import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../configs/domain/vpn_config.dart';
import '../../diagnostics/data/app_log.dart';
import '../data/subscription_parser.dart';
import '../data/user_subscription.dart';

class UserSubscriptionsState {
  const UserSubscriptionsState({
    this.items = const [],
    this.refreshing = const {},
    this.loaded = false,
  });

  final List<UserSubscription> items;

  /// Ids being fetched right now, so each row can show its own spinner.
  final Set<String> refreshing;
  final bool loaded;

  UserSubscriptionsState copyWith({
    List<UserSubscription>? items,
    Set<String>? refreshing,
    bool? loaded,
  }) =>
      UserSubscriptionsState(
        items: items ?? this.items,
        refreshing: refreshing ?? this.refreshing,
        loaded: loaded ?? this.loaded,
      );
}

final userSubscriptionsProvider =
    NotifierProvider<UserSubscriptionsController, UserSubscriptionsState>(
        UserSubscriptionsController.new);

class UserSubscriptionsController extends Notifier<UserSubscriptionsState> {
  @override
  UserSubscriptionsState build() {
    Future.microtask(_load);
    return const UserSubscriptionsState();
  }

  Future<void> _load() async {
    final items = await UserSubscriptionStore.read();
    state = state.copyWith(items: items, loaded: true);
    // Stale lists are refreshed in the background, one after another. The
    // stored servers are usable meanwhile, so launch never waits on this.
    for (final sub in items.where((s) => s.isStale)) {
      await refresh(sub.id);
    }
  }

  /// Fetches [url] and keeps it if it lists anything this app can run.
  ///
  /// Refused rather than saved half-working: a subscription added with an
  /// error would sit in the list contributing nothing, and the user would
  /// reasonably assume it was fine. Returns the new id, or the reason.
  Future<({String? id, SubscriptionProblem? problem})> add({
    required String name,
    required String url,
  }) async {
    final link = url.trim();
    final parsed = Uri.tryParse(link);
    if (parsed == null ||
        !(parsed.scheme == 'http' || parsed.scheme == 'https') ||
        parsed.host.isEmpty) {
      return (id: null, problem: SubscriptionProblem.invalidUrl);
    }
    if (state.items.any((s) => s.url == link)) {
      return (id: null, problem: SubscriptionProblem.duplicate);
    }

    final fetched = await SubscriptionFetcher.fetch(link);
    if (fetched.problem != null) return (id: null, problem: fetched.problem);

    final now = DateTime.now();
    final sub = UserSubscription(
      id: now.microsecondsSinceEpoch.toRadixString(36),
      // Kept empty when the user gives none; the screen numbers it. A name
      // taken from the link would be its publisher's.
      name: name.trim(),
      url: link,
      addedAt: now,
      fetchedAt: now,
      uris: fetched.parsed!.uris,
      unsupported: fetched.parsed!.unsupported,
    );
    final items = [...state.items, sub];
    state = state.copyWith(items: items);
    await UserSubscriptionStore.write(items);
    AppLog.instance.info('Subscription added',
        detail: '${sub.uris.length} servers, ${sub.unsupported} unsupported');
    return (id: sub.id, problem: null);
  }

  Future<void> refresh(String id) async {
    final current = state.items.where((s) => s.id == id).firstOrNull;
    if (current == null || state.refreshing.contains(id)) return;
    state = state.copyWith(refreshing: {...state.refreshing, id});

    final fetched = await SubscriptionFetcher.fetch(current.url);
    // Re-read: the list may have changed while the fetch was in flight -- the
    // subscription could even have been deleted.
    final items = [
      for (final sub in state.items)
        if (sub.id != id)
          sub
        else if (fetched.problem != null)
          // Keep what it served before; only record that this fetch failed.
          sub.copyWith(problem: fetched.problem)
        else
          sub.copyWith(
            fetchedAt: DateTime.now(),
            uris: fetched.parsed!.uris,
            unsupported: fetched.parsed!.unsupported,
            clearProblem: true,
          ),
    ];
    state = state.copyWith(
      items: items,
      refreshing: {...state.refreshing}..remove(id),
    );
    await UserSubscriptionStore.write(items);
  }

  Future<void> refreshAll() async {
    for (final sub in [...state.items]) {
      await refresh(sub.id);
    }
  }

  Future<void> remove(String id) async {
    final items = [
      for (final sub in state.items)
        if (sub.id != id) sub,
    ];
    state = state.copyWith(items: items);
    await UserSubscriptionStore.write(items);
  }
}

/// Every server the user's subscriptions list, as ordinary rows.
///
/// Watches only the list itself, not the refreshing set, so a spinner starting
/// on one row does not rebuild every server in the app.
final userConfigsProvider = Provider<List<VpnConfig>>((ref) {
  final subs = ref.watch(userSubscriptionsProvider.select((s) => s.items));
  final seen = <String>{};
  return [
    for (final sub in subs)
      for (final uri in sub.uris)
        if (seen.add(uri))
          SubscriptionParser.toConfig(
            uri,
            subscriptionId: sub.id,
            subscriptionName: sub.name,
          ),
  ];
});
