import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app_shell.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/palette.dart';
import '../../../configs/presentation/providers/local_test_provider.dart';
import '../../domain/tunnel_snapshot.dart';
import '../providers/tunnel_provider.dart';

/// The connect screen, built to the design handoff.
///
/// Its shape: a status chip in the header, a progress ring around a tappable
/// orb, then the chosen server, throughput, and what the tunnel actually is.
///
/// One deliberate difference from the usual VPN app, kept from the previous
/// version because it is about this app rather than about taste: connecting
/// here means trying several servers in a row and can take up to a minute,
/// because the pool is free configs and most are dead at any moment. The ring
/// therefore reports real progress -- "server 3 of 12" -- instead of spinning.
class VpnHomeScreen extends ConsumerStatefulWidget {
  const VpnHomeScreen({super.key});

  @override
  ConsumerState<VpnHomeScreen> createState() => _VpnHomeScreenState();
}

class _VpnHomeScreenState extends ConsumerState<VpnHomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final snapshot = ref.watch(tunnelSnapshotProvider);
    final controller = ref.read(tunnelSnapshotProvider.notifier);

    return SafeArea(
      child: Column(
        children: [
          _Header(snapshot: snapshot, strings: s),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                // The bottom inset matches the 10 between the tiles, so the
                // last card is as far from the navigation bar as the cards
                // are from each other. It was 4, and the tighter final gap
                // made the stack look squeezed against the bar.
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    // Whatever the padding takes, so the column can fill the
                    // viewport exactly rather than overflow it.
                    minHeight: constraints.maxHeight - 16,
                  ),
                  // Two groups, pushed apart: the orb sits in the upper
                  // half and the cards sit against the bottom bar. Centring
                  // the lot left a band of empty background between the last
                  // tile and the navigation, which reads as a layout that ran
                  // out rather than one that ends.
                  //
                  // A Spacer cannot do this here: inside a scroll view the
                  // column's height is unbounded, so there is no free space to
                  // divide -- an earlier attempt left the screen with a
                  // correct header and an empty body.
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        children: [
                          const SizedBox(height: 14),
                          _ConnectOrb(
                            snapshot: snapshot,
                            strings: s,
                            pulse: _pulse,
                            // One control, both directions: tapping it while
                            // connected disconnects. A separate button was
                            // tried and reverted -- a second control for one
                            // action reads as a step backwards, not a
                            // safeguard.
                            onTap: () => snapshot.isConnected || snapshot.isBusy
                                ? controller.disconnect()
                                : controller.retry(),
                          ),
                          if (snapshot.phase == TunnelPhase.failed)
                            _FailureCard(
                              snapshot: snapshot,
                              strings: s,
                              onRetry: controller.retry,
                            ),
                        ],
                      ),
                      Column(
                        children: [
                          const _ServerCard(),
                          const SizedBox(height: 10),
                          _ThroughputRow(snapshot: snapshot, strings: s),
                          const SizedBox(height: 10),
                          _TunnelFacts(snapshot: snapshot, strings: s),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The brand mark and a status chip, as the design has it.
class _Header extends StatelessWidget {
  const _Header({required this.snapshot, required this.strings});

  final TunnelSnapshot snapshot;
  final S strings;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    final colour = statusColour(c, snapshot);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const _BrandMark(),
              const SizedBox(width: 9),
              Text(
                strings.appName,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.15,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _chipSurface(c, snapshot),
              border: Border.all(color: _chipBorder(c, snapshot)),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration:
                      BoxDecoration(color: colour, shape: BoxShape.circle),
                ),
                const SizedBox(width: 7),
                Text(
                  statusCode(snapshot),
                  style: TextStyle(
                    fontFamily: VernaType.mono,
                    color: colour,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.44,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _chipSurface(VernaColors c, TunnelSnapshot s) => switch (s.phase) {
        TunnelPhase.connected => c.okSurface,
        TunnelPhase.failed => c.dangerSurface,
        _ => c.surface,
      };

  Color _chipBorder(VernaColors c, TunnelSnapshot s) => switch (s.phase) {
        TunnelPhase.connected => c.okBorder,
        TunnelPhase.failed => c.dangerBorder,
        _ => c.border,
      };
}

/// The rounded square with a hole, from the design's header and splash.
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  /// Fixed at the size the design uses in the header. A parameter was carried
  /// for a while and never given a second value.
  static const double size = 18;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.accent,
        borderRadius: BorderRadius.circular(size / 3),
      ),
      child: Center(
        child: Container(
          width: size * 0.44,
          height: size * 0.44,
          decoration:
              BoxDecoration(color: c.background, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

/// The ring, and the orb inside it that the whole screen exists for.
class _ConnectOrb extends StatelessWidget {
  const _ConnectOrb({
    required this.snapshot,
    required this.strings,
    required this.pulse,
    required this.onTap,
  });

  final TunnelSnapshot snapshot;
  final S strings;
  final Animation<double> pulse;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    final colour = statusColour(c, snapshot);

    return SizedBox(
      width: 236,
      height: 236,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The ring reports how far through the candidate list the search is,
          // and fills completely once a tunnel is verified. A spinner would
          // say only "wait", which for a minute-long search is not enough.
          AnimatedBuilder(
            animation: pulse,
            builder: (context, _) => CustomPaint(
              size: const Size(236, 236),
              painter: _RingPainter(
                track: c.track,
                colour: colour,
                progress: _progress(),
                pulse: snapshot.isBusy ? pulse.value : 0,
              ),
            ),
          ),
          GestureDetector(
            onTap: onTap,
            child: Container(
              width: 168,
              height: 168,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _orbSurface(c),
                border: Border.all(color: _orbBorder(c)),
              ),
              child: Center(child: _orbContents(context, c, colour)),
            ),
          ),
        ],
      ),
    );
  }

  /// How full the ring is.
  ///
  /// While searching this is real: the service reports which candidate it is
  /// on and how many there are.
  double _progress() {
    if (snapshot.isConnected) return 1;
    if (snapshot.phase == TunnelPhase.searching && snapshot.total > 0) {
      return (snapshot.attempt / snapshot.total).clamp(0.02, 1);
    }
    if (snapshot.isBusy) return 0.06;
    return 0;
  }

  Color _orbSurface(VernaColors c) => switch (snapshot.phase) {
        TunnelPhase.connected => c.okSurface,
        TunnelPhase.failed => c.dangerSurface,
        TunnelPhase.idle => c.surface,
        _ => c.surfaceSunken,
      };

  Color _orbBorder(VernaColors c) => switch (snapshot.phase) {
        TunnelPhase.connected => c.okBorder,
        TunnelPhase.failed => c.dangerBorder,
        _ => c.border,
      };

  Widget _orbContents(BuildContext context, VernaColors c, Color colour) {
    if (snapshot.isConnected || snapshot.isBusy) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _orbLabel(),
            style: TextStyle(
              fontFamily: VernaType.mono,
              color: c.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.47,
            ),
          ),
          const SizedBox(height: 7),
          // Isolated left-to-right: a clock is a number, and an RTL layout
          // would otherwise reorder its parts around the colons.
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              snapshot.isConnected ? snapshot.duration : _searchCount(),
              style: TextStyle(
                fontFamily: VernaType.mono,
                color: colour,
                fontSize: 27,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.27,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            snapshot.isConnected ? strings.hintOn : strings.hintBusy,
            style: TextStyle(color: c.textSecondary, fontSize: 12),
          ),
        ],
      );
    }

    if (snapshot.phase == TunnelPhase.failed) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, size: 30, color: c.danger),
            const SizedBox(height: 9),
            Text(
              'FAILED',
              style: TextStyle(
                fontFamily: VernaType.mono,
                color: c.danger,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.44,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              strings.failHint,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 11.5,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.power_settings_new_rounded, size: 34, color: c.textSecondary),
        const SizedBox(height: 10),
        Text(
          'TAP TO CONNECT',
          style: TextStyle(
            fontFamily: VernaType.mono,
            color: c.textSecondary,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.75,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          strings.hintOff,
          style: TextStyle(color: c.textMuted, fontSize: 11.5),
        ),
      ],
    );
  }

  String _orbLabel() => snapshot.isConnected ? 'SESSION' : 'CONNECTING';

  /// What the search is doing, in the timer's place.
  String _searchCount() {
    if (snapshot.phase == TunnelPhase.searching && snapshot.total > 0) {
      return '${snapshot.attempt}/${snapshot.total}';
    }
    return '···';
  }
}

/// Draws the design's two-layer ring.
class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.track,
    required this.colour,
    required this.progress,
    required this.pulse,
  });

  final Color track;
  final Color colour;
  final double progress;

  /// 0 when still, otherwise the breathing halo shown while working.
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    const radius = 102.0;

    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10;
    canvas.drawCircle(centre, radius, trackPaint);

    if (pulse > 0) {
      final halo = Paint()
        ..color = colour.withValues(alpha: 0.10 + pulse * 0.30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawCircle(centre, radius - 16 + pulse * 6, halo);
    }

    if (progress <= 0) return;
    final arc = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      -3.14159 / 2,
      6.28318 * progress,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.colour != colour ||
      old.pulse != pulse ||
      old.track != track;
}

/// Shown when every candidate failed, with the two things worth doing next.
class _FailureCard extends StatelessWidget {
  const _FailureCard({
    required this.snapshot,
    required this.strings,
    required this.onRetry,
  });

  final TunnelSnapshot snapshot;
  final S strings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    return Consumer(
      builder: (context, ref, _) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        decoration: BoxDecoration(
          color: c.dangerSurface,
          border: Border.all(color: c.dangerBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    failureTitle(strings, snapshot.failure),
                    style: TextStyle(
                      color: c.danger,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  // The reason in the app's own words, not a code borrowed
                  // from the design's mock: this one is true.
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      failureDetail(snapshot),
                      style: TextStyle(
                        fontFamily: VernaType.mono,
                        color: c.textMuted,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _SmallButton(
              label: strings.otherServer,
              onTap: () => ref.read(shellTabProvider.notifier).select(1),
            ),
            const SizedBox(width: 7),
            _SmallButton(
              label: strings.retry,
              filled: true,
              onTap: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: filled ? c.accent : c.surface,
          border: filled ? null : Border.all(color: c.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: filled ? c.onAccent : c.textPrimary,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Which server is in use, or which will be tried.
class _ServerCard extends ConsumerWidget {
  const _ServerCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.verna;
    final s = ref.watch(stringsProvider);
    final snapshot = ref.watch(tunnelSnapshotProvider);
    final chosen = ref.watch(chosenServerProvider);

    final connected = snapshot.isConnected;
    final flag = connected
        ? (snapshot.active?.flag ?? '')
        : (chosen?.flag ?? '');
    final title = connected
        ? (snapshot.active?.country.isNotEmpty == true
            ? snapshot.active!.country
            : s.unknownCountry)
        : (chosen?.country.isNotEmpty == true
            ? chosen!.country
            : s.autoSelect);
    final meta = connected
        ? [
            if (snapshot.active != null) snapshot.active!.type.label,
            if (snapshot.exitIp != null) snapshot.exitIp!,
          ].join(' · ')
        : (chosen != null ? chosen.type.label : s.autoMeta);

    return GestureDetector(
      onTap: () => ref.read(shellTabProvider.notifier).select(1),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.chip,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                flag.isEmpty ? '🌐' : flag,
                style: const TextStyle(fontSize: 18),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: VernaType.mono,
                        color: c.textMuted,
                        fontSize: 11,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // A hand-picked server stays picked -- the button and "Try
            // again" both use it -- so there has to be a way back to letting
            // the app choose.
            if (chosen != null && !connected && !snapshot.isBusy)
              Semantics(
                button: true,
                label: s.autoSelect,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () =>
                      ref.read(chosenServerProvider.notifier).state = null,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.close_rounded,
                        size: 18, color: c.textMuted),
                  ),
                ),
              ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: c.surfaceSunken,
                border: Border.all(color: c.border),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                s.change,
                style: TextStyle(color: c.accent, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Download and upload, side by side, as the design lays them out.
class _ThroughputRow extends StatelessWidget {
  const _ThroughputRow({required this.snapshot, required this.strings});

  final TunnelSnapshot snapshot;
  final S strings;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    return Row(
      children: [
        Expanded(
          child: _RateTile(
            label: 'DOWNLOAD',
            bytesPerSecond: snapshot.downloadSpeed,
            colour: c.ok,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _RateTile(
            label: 'UPLOAD',
            bytesPerSecond: snapshot.uploadSpeed,
            colour: c.accent,
          ),
        ),
      ],
    );
  }
}

class _RateTile extends StatelessWidget {
  const _RateTile({
    required this.label,
    required this.bytesPerSecond,
    required this.colour,
  });

  final String label;
  final int bytesPerSecond;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    final idle = bytesPerSecond <= 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: VernaType.mono,
              color: c.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 7),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  _rate(bytesPerSecond),
                  style: TextStyle(
                    fontFamily: VernaType.mono,
                    // Muted at rest. Throughput is zero whenever the app is in
                    // the foreground -- nobody downloads anything while looking
                    // at a VPN screen -- and a bright zero twice over teaches
                    // the reader to ignore the row.
                    color: idle ? c.textFaint : colour,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  'KB/s',
                  style: TextStyle(
                    fontFamily: VernaType.mono,
                    color: c.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _rate(int bytesPerSecond) {
    if (bytesPerSecond <= 0) return '0';
    final kb = bytesPerSecond / 1024;
    return kb >= 100 ? kb.toStringAsFixed(0) : kb.toStringAsFixed(1);
  }
}

/// What the tunnel is, in two small tiles: the protocol and the exit address.
class _TunnelFacts extends ConsumerWidget {
  const _TunnelFacts({required this.snapshot, required this.strings});

  final TunnelSnapshot snapshot;
  final S strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final measured =
        ref.watch(localTestResultsProvider)[snapshot.active?.id]?.milliseconds;
    final ping = measured ?? snapshot.pingMs;

    return Row(
      children: [
        Expanded(
          child: _FactTile(
            label: 'PROTOCOL',
            value: snapshot.active?.type.label ?? '—',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _FactTile(
            label: 'PUBLIC IP',
            value: snapshot.exitIp ?? '—',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _FactTile(
            label: 'PING',
            value: ping == null ? '—' : '$ping ms',
          ),
        ),
      ],
    );
  }
}

class _FactTile extends StatelessWidget {
  const _FactTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        border: Border.all(color: c.borderFaint),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: VernaType.mono,
              color: c.textFaint,
              fontSize: 9.5,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.95,
            ),
          ),
          const SizedBox(height: 5),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: VernaType.mono,
                color: c.mono,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── shared with the rest of the app ────────────────────────────────────────

/// The colour that stands for the tunnel's state, everywhere it is shown.
///
/// Green means traffic is moving, blue means the app is working on it, red
/// means it failed. The brand's blue doubles as the busy colour deliberately:
/// "we are doing something" is the app speaking, while green and red are the
/// tunnel speaking.
Color statusColour(VernaColors c, TunnelSnapshot s) => switch (s.phase) {
      TunnelPhase.connected => c.ok,
      TunnelPhase.failed => c.danger,
      TunnelPhase.preparing || TunnelPhase.searching => c.accent,
      TunnelPhase.idle => c.textMuted,
    };

/// The short code in the header chip. Deliberately untranslated: it reads as a
/// machine's word for the state, and the design sets it in mono for that
/// reason.
String statusCode(TunnelSnapshot s) => switch (s.phase) {
      TunnelPhase.connected => 'CONNECTED',
      TunnelPhase.failed => 'FAILED',
      TunnelPhase.preparing => 'PREPARING',
      TunnelPhase.searching => 'SEARCHING',
      TunnelPhase.idle => 'OFF',
    };

String failureTitle(S s, TunnelFailure failure) => switch (failure) {
      TunnelFailure.permissionDenied => s.permissionDenied,
      TunnelFailure.noInternet => s.noInternet,
      TunnelFailure.fetchFailed => s.fetchFailed,
      TunnelFailure.noCandidates => s.noCandidates,
      _ => s.failTitle,
    };

/// A one-line reason, in the mono face, that says something specific.
String failureDetail(TunnelSnapshot s) {
  if (s.failure == TunnelFailure.noneAnswered && s.total > 0) {
    return 'NONE_ANSWERED · ${s.total} tried';
  }
  return switch (s.failure) {
    TunnelFailure.permissionDenied => 'VPN_PERMISSION_DENIED',
    TunnelFailure.noInternet => 'NO_NETWORK · Wi-Fi and mobile data are off',
    TunnelFailure.fetchFailed => 'SERVER_LIST_UNREACHABLE',
    TunnelFailure.noCandidates => 'NO_USABLE_CONFIGS',
    TunnelFailure.unstable => 'TUNNEL_UNSTABLE',
    TunnelFailure.error => s.errorDetail ?? 'UNKNOWN_ERROR',
    _ => 'NONE_ANSWERED',
  };
}
