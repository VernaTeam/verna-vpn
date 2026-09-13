import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app_shell.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/palette.dart';
import '../../../tunnel/domain/local_test.dart';
import '../../../tunnel/presentation/providers/tunnel_provider.dart';
import '../../data/config_actions.dart';
import '../../domain/vpn_config.dart';
import '../providers/local_test_provider.dart';
import 'qr_sheet.dart';

/// One server, as one row.
///
/// Was a card two lines tall carrying a protocol badge and three buttons --
/// QR, copy, connect -- which meant four servers filled the screen and the
/// only thing a user is actually choosing between, country and latency, had to
/// compete with its own toolbar. A list is for scanning: flag, country, how
/// fast, and the whole row connects. Copy and QR still exist, one tap further
/// in, because they are for the rarer job of moving a config to another app.
class ConfigCard extends ConsumerStatefulWidget {
  const ConfigCard({
    super.key,
    required this.config,
    this.onTap,
    this.tapGuard,
  });

  final VpnConfig config;

  /// Opens the detail screen. Kept for the overflow menu; the row itself
  /// connects, because that is what someone tapping a server means.
  final VoidCallback? onTap;

  /// Asked before a tap connects; false swallows the tap.
  ///
  /// The list re-sorts while servers are being tested, and a row can move
  /// between the moment it is seen and the moment it is tapped. On a J7 on
  /// 2026-09-13 a tap aimed at "United Kingdom, Shadowsocks, 217 ms" connected
  /// to a German Trojan server that had just moved into that slot, and the
  /// failure read as the chosen server not working.
  final bool Function()? tapGuard;

  @override
  ConsumerState<ConfigCard> createState() => _ConfigCardState();
}

class _ConfigCardState extends ConsumerState<ConfigCard> {
  bool _busy = false;

  VpnConfig get cfg => widget.config;

  bool get _isHandoff => handoffTypes.contains(cfg.type);

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final c = context.verna;
    final local = ref.watch(localTestResultsProvider)[cfg.id];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _busy ? null : _primaryAction,
          onLongPress: () => _showActions(s),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            child: Row(
              children: [
                Text(
                  cfg.flag.isEmpty ? '🌐' : cfg.flag,
                  style: const TextStyle(fontSize: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cfg.country.isEmpty ? s.unknownCountry : cfg.country,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // The protocol, and nothing about where the server
                      // came from: a subscription's name is usually its
                      // publisher's, and this list does not advertise them.
                      Text(
                        cfg.type.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_busy)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: c.accent,
                      ),
                    ),
                  )
                else
                  _Latency(local: local, isHandoff: _isHandoff, s: s),
                IconButton(
                  icon: Icon(Icons.more_vert_rounded,
                      size: 20, color: c.textMuted),
                  tooltip: s.moreActions,
                  onPressed: () => _showActions(s),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// What tapping the row does.
  ///
  /// An MTProto proxy is not something this app can run: it tunnels Telegram
  /// alone, inside Telegram. Handing the tg:// link over is the whole of the
  /// integration, and it is genuinely one tap.
  Future<void> _primaryAction() async {
    if (widget.tapGuard?.call() == false) return;
    return _isHandoff ? _openInTelegram() : _connectHere();
  }

  void _showActions(S s) {
    final c = context.verna;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(
                _isHandoff ? Icons.send_rounded : Icons.bolt_rounded,
                color: c.accent,
              ),
              title: Text(
                _isHandoff ? s.openInTelegram : s.connect,
                style: TextStyle(color: c.textPrimary),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _primaryAction();
              },
            ),
            if (cfg.content != null)
              ListTile(
                leading: Icon(Icons.copy_rounded, color: c.textSecondary),
                title: Text(s.copy, style: TextStyle(color: c.textPrimary)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _copyConfig();
                },
              ),
            ListTile(
              leading: Icon(Icons.qr_code_rounded, color: c.textSecondary),
              title: Text(s.showQr, style: TextStyle(color: c.textPrimary)),
              onTap: () {
                Navigator.pop(sheetContext);
                QrSheet.show(context, cfg, s);
              },
            ),
            if (widget.onTap != null)
              ListTile(
                leading:
                    Icon(Icons.info_outline_rounded, color: c.textSecondary),
                title: Text(s.details, style: TextStyle(color: c.textPrimary)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onTap!();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Hands an MTProto proxy to Telegram.
  ///
  /// The manifest already declares the `tg` scheme under <queries>, without
  /// which Android 11+ silently refuses to launch it.
  Future<void> _openInTelegram() async {
    setState(() => _busy = true);
    final result = await ConfigActions.openInApp(cfg);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.status != ActionStatus.ok) {
      _snack(ref.read(stringsProvider).noApp, isError: true);
    }
  }

  Future<void> _copyConfig() async {
    if (cfg.content == null) return;
    await Clipboard.setData(ClipboardData(text: cfg.content!));
    _snack(ref.read(stringsProvider).copied);
  }

  /// Connect to this config inside the app.
  ///
  /// This used to hand the URI to v2rayNG through a URL scheme, from back when
  /// the app was only a config browser. The app runs its own tunnel now, so
  /// sending the user to another app to use our own list made no sense.
  ///
  /// Moves to the connect tab first: that is where progress and the result are
  /// shown, and the search can take a few seconds.
  Future<void> _connectHere() async {
    setState(() => _busy = true);
    final controller = ref.read(tunnelSnapshotProvider.notifier);
    ref.read(shellTabProvider.notifier).select(0);
    unawaited(controller.connectTo(cfg));
    // The row is no longer on screen; clearing the flag keeps it from coming
    // back mid-spinner when the user returns to the list.
    if (mounted) setState(() => _busy = false);
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            isError ? context.verna.danger : context.verna.surfaceSunken,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

/// The right-hand side of a row: what this phone measured, or nothing yet.
class _Latency extends StatelessWidget {
  const _Latency({
    required this.local,
    required this.isHandoff,
    required this.s,
  });

  /// What this phone measured, if it has been tested. Outranks anything the
  /// server said: the server proves a config is alive where the server is, and
  /// that is a different question from whether it works here.
  final LocalTest? local;
  final bool isHandoff;
  final S s;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;

    // A Telegram proxy is never tested here -- whether Telegram can use it is
    // Telegram's business, and this device cannot find out. Saying "not
    // tested" on a row that can never be tested reads as a failure.
    if (isHandoff) {
      return Icon(Icons.send_rounded, size: 18, color: c.accent);
    }

    final tested = local;
    if (tested == null) {
      // Nothing is shown until this phone has measured it.
      //
      // The server's `ping_ms` was displayed here once, and it reads like a
      // promise: a row saying "34 ms" invites "what a fast server" when in
      // fact nothing had been tried from this device. Even the server's own
      // tunnel-verified figure describes a datacentre in Germany, not a phone
      // on Irancell. A number the user can act on has to come from the user's
      // own connection.
      return Text(
        s.notTested,
        style: TextStyle(color: c.textMuted, fontSize: 12),
      );
    }

    if (!tested.works) {
      return Icon(
        tested.reachable ? Icons.link_off_rounded : Icons.block_rounded,
        size: 18,
        color: c.danger,
      );
    }

    final ms = tested.milliseconds!;
    // Green, amber, red -- the ladder everyone already reads without a
    // legend. The good band used to be the accent blue, which is the brand
    // colour and appears on every tappable thing in the app, so a 250ms
    // server looked like a button rather than a good result.
    final color = ms < 400
        ? c.ok
        : ms < 900
            ? c.warn
            : c.danger;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SignalBars(milliseconds: ms, color: color),
        const SizedBox(width: 8),
        Text(
          '$ms ms',
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Three rising bars, filled according to measured latency.
///
/// The number is the honest answer, but nobody reads a list of numbers to
/// compare them; the bars are what makes one row visibly better than the next
/// while scrolling past.
class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.milliseconds, required this.color});

  final int milliseconds;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final strength = milliseconds < 400
        ? 3
        : milliseconds < 900
            ? 2
            : 1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(3, (i) {
        final on = i < strength;
        return Container(
          width: 3,
          height: 5.0 + i * 4,
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: on ? color : context.verna.border,
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }
}
