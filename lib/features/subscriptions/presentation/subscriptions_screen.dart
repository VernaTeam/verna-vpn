import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/palette.dart';
import '../../configs/domain/vpn_config.dart';
import '../../configs/presentation/providers/local_test_provider.dart';
import '../../tunnel/presentation/providers/tunnel_provider.dart';
import '../data/builtin_subscription.dart';
import '../data/user_subscription.dart';
import 'builtin_subscriptions_provider.dart';
import 'user_subscriptions_provider.dart';

/// Every subscription behind the server list: Verna's own lists, on by
/// default, and the links the user added.
class SubscriptionsScreen extends ConsumerWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final c = context.verna;
    final mine = ref.watch(userSubscriptionsProvider);
    final builtIn = ref.watch(builtInSubscriptionsProvider);
    final busy = mine.refreshing.isNotEmpty || builtIn.loading;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: Text(s.subTitle),
        backgroundColor: c.background,
        foregroundColor: c.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: s.subRefreshAll,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            onPressed: busy
                ? null
                : () {
                    ref.read(builtInSubscriptionsProvider.notifier).refresh();
                    ref.read(userSubscriptionsProvider.notifier).refreshAll();
                  },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            _SectionLabel(s.subSectionBuiltIn),
            const SizedBox(height: 6),
            Text(
              s.subBuiltInHint,
              style: TextStyle(color: c.textMuted, fontSize: 12, height: 1.6),
            ),
            const SizedBox(height: 12),
            if (builtIn.items.isEmpty)
              _Notice(
                text: builtIn.loading ? s.subBuiltInLoading : s.subBuiltInFailed,
                busy: builtIn.loading,
              )
            else
              for (final sub in builtIn.items) ...[
                _BuiltInRow(sub: sub, enabled: builtIn.isEnabled(sub.id)),
                const SizedBox(height: 10),
              ],
            const SizedBox(height: 22),
            _SectionLabel(s.subMine),
            const SizedBox(height: 12),
            if (mine.loaded && mine.items.isEmpty) _EmptyState(s: s),
            for (var i = 0; i < mine.items.length; i++) ...[
              _SubscriptionRow(
                sub: mine.items[i],
                index: i,
                refreshing: mine.refreshing.contains(mine.items[i].id),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 6),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: c.onAccent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.add_rounded),
              label: Text(s.subAdd,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              onPressed: () => _AddSheet.show(context),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline_rounded, size: 15, color: c.textFaint),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.subPrivacy,
                    style: TextStyle(
                        color: c.textMuted, fontSize: 12, height: 1.6),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "VLESS 2", "Mixed 1": what a built-in list carries and its number, which
/// is all the server tells the app about it.
String builtInLabel(S s, BuiltInSubscription sub) {
  final kind = switch (sub.kind) {
    'vless' => 'VLESS',
    'vmess' => 'VMess',
    'ss' => 'Shadowsocks',
    'trojan' => 'Trojan',
    'hysteria2' => 'Hysteria2',
    _ => s.subKindMixed,
  };
  return '$kind ${sub.number}';
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: c.textFaint,
        fontSize: 10.5,
        letterSpacing: 0.12,
        fontFamily: VernaType.mono,
      ),
    );
  }
}

/// A single line in place of the built-in lists, while they load or when they
/// could not be fetched.
class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.busy});

  final String text;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          if (busy)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
            )
          else
            Icon(Icons.cloud_off_rounded, size: 18, color: c.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: c.textSecondary, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// One of Verna's lists: its name, how many of its servers are healthy, how
/// many work from this phone, and a switch.
class _BuiltInRow extends ConsumerWidget {
  const _BuiltInRow({required this.sub, required this.enabled});

  final BuiltInSubscription sub;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final c = context.verna;
    final servers = ref.watch(
            builtInSubscriptionsProvider.select((st) => st.configs[sub.id])) ??
        const <VpnConfig>[];
    final results = ref.watch(localTestResultsProvider);

    // The server's count is about the whole list; the phone's is about the
    // sample it was given, so it says "of" that sample rather than implying
    // the rest failed.
    var tested = 0;
    var working = 0;
    for (final server in servers) {
      final result = results[server.id];
      if (result == null) continue;
      tested++;
      if (result.works) working++;
    }
    final status = [
      '${sub.healthy} ${s.subHealthy} ${s.subOf} ${sub.total}',
      if (tested > 0) '$working ${s.subOf} $tested ${s.subWorkHere}',
    ].join('  ·  ');

    return Container(
      padding: const EdgeInsets.fromLTRB(15, 12, 8, 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  builtInLabel(s, sub),
                  style: TextStyle(
                    color: enabled ? c.textPrimary : c.textMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  status,
                  style: TextStyle(color: c.textMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          Switch(
            value: enabled,
            activeTrackColor: c.accent,
            onChanged: (on) => ref
                .read(builtInSubscriptionsProvider.notifier)
                .setEnabled(sub.id, on),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.s});

  final S s;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          Icon(Icons.playlist_add_rounded, size: 34, color: c.accent),
          const SizedBox(height: 12),
          Text(
            s.subEmptyTitle,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            s.subEmptyBody,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.7),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionRow extends ConsumerWidget {
  const _SubscriptionRow({
    required this.sub,
    required this.index,
    required this.refreshing,
  });

  final UserSubscription sub;

  /// Its place in the list, which names it when the user did not.
  final int index;
  final bool refreshing;

  /// No host line under it any more: the host of a subscription link is
  /// usually where its publisher keeps it.
  String _name(S s) =>
      sub.name.isEmpty ? '${s.subDefaultName} ${index + 1}' : sub.name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final c = context.verna;

    final status = <String>[
      '${sub.uris.length} ${s.subServers}',
      if (sub.unsupported > 0) '${sub.unsupported} ${s.subUnsupported}',
      sub.fetchedAt == null
          ? s.subNever
          : '${s.subUpdated} ${_ago(s, sub.fetchedAt!)}',
    ].join('  ·  ');

    return Container(
      padding: const EdgeInsets.fromLTRB(15, 12, 4, 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: sub.problem == null ? c.border : c.dangerBorder,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _name(s),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  status,
                  style: TextStyle(color: c.textMuted, fontSize: 11.5),
                ),
                if (sub.problem != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    problemText(s, sub.problem!),
                    style: TextStyle(color: c.danger, fontSize: 11.5),
                  ),
                ],
              ],
            ),
          ),
          if (refreshing)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              tooltip: s.refresh,
              icon: Icon(Icons.refresh_rounded, color: c.textSecondary),
              onPressed: () =>
                  ref.read(userSubscriptionsProvider.notifier).refresh(sub.id),
            ),
          IconButton(
            tooltip: s.subDelete,
            icon: Icon(Icons.delete_outline_rounded, color: c.textMuted),
            onPressed: () => _confirmDelete(context, ref, s),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, S s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_name(s)),
        content: Text(s.subDeleteQ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.subCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.subDelete,
                style: TextStyle(color: context.verna.danger)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(userSubscriptionsProvider.notifier).remove(sub.id);
    }
  }

  static String _ago(S s, DateTime when) {
    final age = DateTime.now().difference(when);
    if (age.inMinutes < 1) return s.subJustNow;
    if (age.inHours < 1) return '${age.inMinutes} ${s.subMinAgo}';
    if (age.inDays < 1) return '${age.inHours} ${s.subHourAgo}';
    return '${age.inDays} ${s.subDayAgo}';
  }
}

String problemText(S s, SubscriptionProblem problem) => switch (problem) {
      SubscriptionProblem.invalidUrl => s.subErrInvalidUrl,
      SubscriptionProblem.duplicate => s.subErrDuplicate,
      SubscriptionProblem.unreachable => s.subErrUnreachable,
      SubscriptionProblem.badStatus => s.subErrStatus,
      SubscriptionProblem.empty => s.subErrEmpty,
      SubscriptionProblem.nothingSupported => s.subErrUnsupported,
    };

/// The add form, as a bottom sheet: a link and an optional name.
class _AddSheet extends ConsumerStatefulWidget {
  const _AddSheet();

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: context.verna.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => const _AddSheet(),
      );

  @override
  ConsumerState<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends ConsumerState<_AddSheet> {
  final _url = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;
  SubscriptionProblem? _problem;

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      setState(() {
        _url.text = text;
        _problem = null;
      });
    }
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    final result = await ref
        .read(userSubscriptionsProvider.notifier)
        .add(name: _name.text, url: _url.text);
    if (!mounted) return;
    if (result.problem != null) {
      setState(() {
        _busy = false;
        _problem = result.problem;
      });
      return;
    }
    _testNewServers(result.id!);
    Navigator.pop(context);
  }

  /// Tests the new servers straight away, so the list can show which of them
  /// work from here without the user going looking for the test button.
  ///
  /// Not while a tunnel is up -- probing restarts the core -- and not over a
  /// run already in progress.
  void _testNewServers(String id) {
    if (ref.read(tunnelSnapshotProvider).isConnected) return;
    if (ref.read(localTestProgressProvider).running) return;
    final fresh = ref
        .read(userConfigsProvider)
        .where((c) => c.id.startsWith('sub:$id:'))
        .toList();
    if (fresh.isNotEmpty) {
      ref.read(localTestResultsProvider.notifier).run(fresh);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final c = context.verna;

    InputDecoration field(String label) => InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: c.textMuted),
          filled: true,
          fillColor: c.surfaceSunken,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.border),
          ),
        );

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 18, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.subAdd,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _url,
            enabled: !_busy,
            autofocus: true,
            keyboardType: TextInputType.url,
            textDirection: TextDirection.ltr,
            style: TextStyle(color: c.textPrimary, fontSize: 13.5),
            decoration: field(s.subUrl).copyWith(
              suffixIcon: IconButton(
                tooltip: s.subPaste,
                icon: Icon(Icons.content_paste_rounded,
                    size: 20, color: c.accent),
                onPressed: _busy ? null : _paste,
              ),
            ),
            onChanged: (_) {
              if (_problem != null) setState(() => _problem = null);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            enabled: !_busy,
            style: TextStyle(color: c.textPrimary, fontSize: 13.5),
            decoration: field(s.subName),
          ),
          if (_problem != null) ...[
            const SizedBox(height: 12),
            Text(
              problemText(s, _problem!),
              style: TextStyle(color: c.danger, fontSize: 12.5, height: 1.5),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: Text(s.subCancel),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: c.accent,
                    foregroundColor: c.onAccent,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: c.onAccent),
                        )
                      : Text(s.subAdd),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
