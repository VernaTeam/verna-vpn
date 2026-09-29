import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app_shell.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/palette.dart';
import '../../../configs/presentation/providers/configs_provider.dart';
import '../../../configs/presentation/providers/local_test_provider.dart';
import '../../../map/presentation/world_map.dart';
import '../../../stats/data/protected_time_store.dart';
import '../../domain/tunnel_snapshot.dart';
import '../providers/own_ip_provider.dart';
import '../providers/tunnel_provider.dart';

/// The connect screen, built to the Aurora design handoff.
///
/// Its shape: an aura that tints with the connection state, a power button
/// straddling its lower edge, the status line, the chosen location, a live map
/// that flies to the exit country, and four cards.
///
/// Every number on it is measured. The handoff's own screen carries a quota,
/// an ad-blocker toggle and a device list, none of which exist here -- those
/// cards were not rebuilt with invented values, they were replaced by the four
/// things this app actually knows.
///
/// One deliberate difference from the usual VPN app, kept because it is about
/// this app rather than about taste: connecting means trying several servers in
/// a row and can take up to a minute, because the pool is free configs and most
/// are dead at any moment. The ring therefore reports real progress -- "server
/// 3 of 12" -- instead of the design's fixed sweep.
class VpnHomeScreen extends ConsumerStatefulWidget {
  const VpnHomeScreen({super.key});

  @override
  ConsumerState<VpnHomeScreen> createState() => _VpnHomeScreenState();
}

class _VpnHomeScreenState extends ConsumerState<VpnHomeScreen> {
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final snapshot = ref.watch(tunnelSnapshotProvider);
    final controller = ref.read(tunnelSnapshotProvider.notifier);

    // A pinned sliver, not a fixed header over a scroll view: with two
    // separate widgets the content moved by the scroll *and* the header shrank
    // under it, so the cards travelled faster than the finger and slid behind
    // the button. As a sliver the first 144 px of scroll are spent collapsing
    // the header and the cards stay exactly where they are; after that the
    // list scrolls under a header that no longer changes.
    return CustomScrollView(
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _AuraHeaderDelegate(
            snapshot: snapshot,
            strings: s,
            onTap: () => snapshot.isConnected || snapshot.isBusy
                ? controller.disconnect()
                : controller.retry(),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          sliver: SliverToBoxAdapter(
            child: Column(
              children: [
                const _LocationCard(),
                const SizedBox(height: 12),
                _MapCard(snapshot: snapshot, strings: s),
                const SizedBox(height: 12),
                if (snapshot.phase == TunnelPhase.failed) ...[
                  _FailureCard(
                    snapshot: snapshot,
                    strings: s,
                    onRetry: controller.retry,
                  ),
                  const SizedBox(height: 12),
                ],
                _MiniCardGrid(snapshot: snapshot, strings: s),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Hands the header its own collapse, driven by the scroll it sits over.
class _AuraHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _AuraHeaderDelegate({
    required this.snapshot,
    required this.strings,
    required this.onTap,
  });

  final TunnelSnapshot snapshot;
  final S strings;
  final VoidCallback onTap;

  @override
  double get maxExtent => _AuraHeader.openHeight;

  @override
  double get minExtent => _AuraHeader.shutHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final range = maxExtent - minExtent;
    return _AuraHeader(
      snapshot: snapshot,
      strings: strings,
      collapse: range == 0 ? 0 : (shrinkOffset / range).clamp(0.0, 1.0),
      onTap: onTap,
    );
  }

  @override
  bool shouldRebuild(_AuraHeaderDelegate old) =>
      old.snapshot != snapshot || old.strings != strings;
}

// ── the aura, the power button, and the status line ────────────────────────

/// The three stacked half-ellipses and the button that straddles them.
///
/// The aura's colours carry the connection state for the whole top of the
/// screen: the design has the wordmark and the status text inherit its ink, so
/// the header tints as one thing rather than as a row of separately-coloured
/// widgets.
class _AuraHeader extends StatelessWidget {
  const _AuraHeader({
    required this.snapshot,
    required this.strings,
    required this.collapse,
    required this.onTap,
  });

  final TunnelSnapshot snapshot;
  final S strings;

  /// 0 while the screen is at rest, 1 once it has been scrolled past the
  /// header's own height.
  ///
  /// The header shrinks with the scroll instead of the cards sliding under a
  /// fixed one: on a phone where the four cards do not fit, the screen was
  /// asking the user to choose between seeing the button and seeing the list.
  final double collapse;

  final VoidCallback onTap;

  /// Straight from the prototype's CSS: `.aura` 196 tall, `.powerwrap` 62
  /// under it, `.power` 114 pulled up 58 so it straddles the edge, then
  /// `.status` with 16 above and 18 below.
  static const double _auraHeight = 196;
  static const double _powerWell = 62;
  static const double _buttonSize = 114;
  static const double _buttonRise = 58;

  /// What each measurement becomes once the header is fully collapsed.
  static const double _auraCollapsed = 104;
  static const double _wellCollapsed = 30;
  static const double _buttonCollapsed = 62;

  /// The two heights the sliver moves between.
  static const double openHeight = _auraHeight + _powerWell + 62;
  static const double shutHeight = _auraCollapsed + _wellCollapsed + 42;

  static double _at(double open, double shut, double t) =>
      open + (shut - open) * t;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    final rings = _AuraRings.of(c, snapshot.phase);

    final t = collapse.clamp(0.0, 1.0);
    final aura = _at(_auraHeight, _auraCollapsed, t);
    final well = _at(_powerWell, _wellCollapsed, t);
    final button = _at(_buttonSize, _buttonCollapsed, t);
    final rise = _at(_buttonRise, _buttonCollapsed / 2, t);
    final tail = _at(62, 42, t);
    // The wordmark goes first: it is the least useful thing up there, and it
    // would otherwise end up sitting on the button as the dome closes in.
    final wordmark = (1 - t * 1.8).clamp(0.0, 1.0);

    // Where the button's circle actually sits, which is what the glow is
    // centred on. The widget is 28 taller than the button (the ring's inset),
    // so its centre is this, not the widget's top.
    final buttonCentre = aura - rise + button / 2;
    final glowRadius = button * 1.6;

    return SizedBox(
      height: aura + well + tail,
      // One builder over the whole header: the domes, the glow and the
      // wordmark's ink all cross-fade together when the state changes, which
      // is what makes the top of the screen read as one thing.
      child: TweenAnimationBuilder<_AuraRings>(
        tween: _AuraTween(end: rings),
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeOut,
        builder: (context, value, _) => Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            // Opaque, or the cards scrolling underneath show through the strip
            // between the dome's edge and the status line.
            Positioned.fill(child: ColoredBox(color: c.background)),
            // ClipRect, because the dome is drawn in a box far taller than the
            // aura and the design lets the top of it fall off the screen.
            ClipRect(
              child: SizedBox(
                height: aura,
                width: double.infinity,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _AuraPainter(rings: value),
                        child: Padding(
                          padding: EdgeInsets.only(top: _at(46, 22, t)),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Opacity(
                              opacity: wordmark,
                              child: Text(
                                'VERNA VPN',
                                style: TextStyle(
                                  fontFamily: VernaType.mono,
                                  color: value.ink,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 3.4,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // The light comes from behind the button, and only from
                    // above it.
                    //
                    // Centred on the button's own centre -- which sits on the
                    // aura's bottom edge -- and clipped by this box, so what
                    // shows is the upper half: light rising from behind the
                    // button rather than a ring around it. Outside the clip it
                    // lit the whole circle; and the prototype's own geometry
                    // put the centre 120 px higher, where it read as a patch
                    // floating over nothing.
                    Positioned(
                      top: buttonCentre - glowRadius,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: IgnorePointer(
                          child: Container(
                            width: glowRadius * 2,
                            height: glowRadius * 2,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  value.glow.withValues(
                                    alpha: value.glow.a * value.glowOpacity,
                                  ),
                                  value.glow.withValues(
                                    alpha:
                                        value.glow.a * value.glowOpacity * 0.45,
                                  ),
                                  value.glow.withValues(alpha: 0),
                                ],
                                stops: const [0, 0.42, 1],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              // Minus the ring's own inset: the button widget is 28 wider than
              // the button, so placing the widget at -58 put the circle 14 px
              // lower than the design and halved the gap to the status line.
              top: aura - rise - _PowerButton.ringInset,
              child: _PowerButton(
                snapshot: snapshot,
                size: button,
                onTap: onTap,
              ),
            ),
            Positioned(
              top: aura + well + _at(16, 6, t),
              child: _StatusLine(
                snapshot: snapshot,
                strings: strings,
                scale: _at(1, 0.82, t),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The four colour sets the aura moves between, from the handoff's table.
///
/// Only the off state differs between light and dark: the rest are state
/// colours rather than surface colours, so they read the same either way.
class _AuraRings {
  const _AuraRings({
    required this.inner,
    required this.mid,
    required this.outer,
    required this.ink,
    required this.glow,
    required this.glowOpacity,
  });

  final Color inner;
  final Color mid;
  final Color outer;
  final Color ink;
  final Color glow;

  /// `--glowO` in the prototype: .7 while the tunnel is down, 1 otherwise.
  final double glowOpacity;

  static _AuraRings lerp(_AuraRings a, _AuraRings b, double t) => _AuraRings(
        inner: Color.lerp(a.inner, b.inner, t)!,
        mid: Color.lerp(a.mid, b.mid, t)!,
        outer: Color.lerp(a.outer, b.outer, t)!,
        ink: Color.lerp(a.ink, b.ink, t)!,
        glow: Color.lerp(a.glow, b.glow, t)!,
        glowOpacity: a.glowOpacity + (b.glowOpacity - a.glowOpacity) * t,
      );

  static _AuraRings of(VernaColors c, TunnelPhase phase) => switch (phase) {
        TunnelPhase.connected => _AuraRings(
            inner: const Color(0xFF0C3B45),
            mid: const Color(0xFF0F5F6B),
            outer: const Color(0xFF159AA4),
            ink: Colors.white.withValues(alpha: 0.78),
            glow: c.ok.withValues(alpha: 0.9),
            glowOpacity: 1,
          ),
        TunnelPhase.failed => _AuraRings(
            inner: const Color(0xFF46203A),
            mid: const Color(0xFF682C4C),
            outer: const Color(0xFF8F3A5B),
            ink: Colors.white.withValues(alpha: 0.78),
            glow: c.danger.withValues(alpha: 0.75),
            glowOpacity: 1,
          ),
        // The domes stay the handoff's navy; only the halo changes.
        //
        // Meysam asked for the amber to carry the same weight as the teal and
        // the rose, whose glows sit at .9 and .75 against the design's .55.
        // Amber domes were tried and were too much -- "the yellow light and
        // its halo are a bit heavy" -- because a lit dome covers a third of
        // the screen while a halo only pools under the button. So: navy dome,
        // halo at .85.
        TunnelPhase.preparing || TunnelPhase.searching => _AuraRings(
            inner: const Color(0xFF222D47),
            mid: const Color(0xFF313F5C),
            outer: const Color(0xFF455372),
            ink: Colors.white.withValues(alpha: 0.7),
            glow: c.warn.withValues(alpha: 0.85),
            glowOpacity: 1,
          ),
        TunnelPhase.idle => _AuraRings(
            inner: c.auraOffInner,
            mid: c.auraOffMid,
            outer: c.auraOffOuter,
            ink: c.auraOffInk,
            glow: c.accent.withValues(alpha: 0.22),
            glowOpacity: 0.7,
          ),
      };
}

/// Lets [TweenAnimationBuilder] interpolate a whole ring set at once.
class _AuraTween extends Tween<_AuraRings> {
  _AuraTween({super.end});

  @override
  _AuraRings lerp(double t) => _AuraRings.lerp(begin!, end!, t);
}

/// The aura, painted to the prototype's geometry.
///
/// The domes are drawn in a box 338 tall whose bottom sits on the aura's
/// bottom edge and which reaches 40 px past each side -- `.rings` in the CSS.
/// Only its lowest 196 px are visible, which is why the design reads as a
/// gentle curve rather than as three complete domes: the apexes of the two
/// larger ones are off the top of the screen.
class _AuraPainter extends CustomPainter {
  const _AuraPainter({required this.rings});

  final _AuraRings rings;

  /// `.rings` height, and the ring heights as fractions of it (100/79/58%).
  static const double _box = 338;
  static const double _sideBleed = 40;

  @override
  void paint(Canvas canvas, Size size) {
    final spread = size.width + _sideBleed * 2;
    final bottom = size.height;

    // Widest and darkest at the back, narrowest and lightest at the front:
    // the stack reads as light pooling under the power button.
    void dome(double widthFactor, double heightFraction, Color colour) {
      final rect = Rect.fromCenter(
        center: Offset(size.width / 2, bottom),
        width: spread * widthFactor,
        height: _box * heightFraction * 2,
      );
      final path = Path()
        ..moveTo(rect.left, bottom)
        ..arcTo(rect, math.pi, math.pi, false)
        ..close();
      canvas.drawPath(path, Paint()..color = colour);
    }

    dome(2.0, 1.0, rings.inner);
    dome(1.46, 0.79, rings.mid);
    dome(1.0, 0.58, rings.outer);

    // No glow here. The prototype paints it inside this box, where the clip
    // cuts it at the dome's edge and its centre lands well above the button;
    // on a phone that reads as a bright patch floating over nothing. It is
    // drawn behind the button instead -- see `_AuraHeader`.
  }

  @override
  bool shouldRepaint(_AuraPainter old) =>
      old.rings.inner != rings.inner ||
      old.rings.mid != rings.mid ||
      old.rings.outer != rings.outer ||
      old.rings.glow != rings.glow ||
      old.rings.glowOpacity != rings.glowOpacity;
}

/// The button, its progress ring, and the glyph inside it.
class _PowerButton extends StatelessWidget {
  const _PowerButton({
    required this.snapshot,
    required this.size,
    required this.onTap,
  });

  final TunnelSnapshot snapshot;
  final double size;
  final VoidCallback onTap;

  /// `.powerring{inset:-7}` on each side, so the widget is 14 larger than the
  /// button in every direction.
  static const double ringInset = 14;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    final colour = statusColour(c, snapshot);
    final connected = snapshot.isConnected;

    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: size + ringInset * 2,
          height: size + ringInset * 2,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Real progress, not the design's fixed sweep: while searching
              // this is "how far through the candidate list are we", which is
              // the one thing a user waiting a minute wants to know.
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: _progress()),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOut,
                builder: (context, value, _) => CustomPaint(
                  size: Size(size + 28, size + 28),
                  painter: _RingPainter(
                    track: c.track,
                    colour: colour,
                    progress: value,
                  ),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 450),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.surface,
                  boxShadow: connected
                      ? [
                          BoxShadow(
                            color: c.ok.withValues(alpha: 0.65),
                            blurRadius: 46,
                            spreadRadius: -18,
                          ),
                        ]
                      : const [],
                  border: Border.all(
                    color: connected
                        ? c.ok.withValues(alpha: 0.35)
                        : c.border,
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.power_settings_new_rounded,
                    // The design's 48 on a 114 button: kept as a ratio so the
                    // glyph shrinks with the button as the header collapses.
                    size: size * 0.42,
                    color: colour,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _progress() {
    if (snapshot.isConnected) return 1;
    if (snapshot.phase == TunnelPhase.searching && snapshot.total > 0) {
      return (snapshot.attempt / snapshot.total).clamp(0.04, 1);
    }
    if (snapshot.isBusy) return 0.08;
    return 0;
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.track,
    required this.colour,
    required this.progress,
  });

  final Color track;
  final Color colour;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );

    if (progress <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..color = colour
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.colour != colour || old.track != track;
}

/// Padlock, the state in words, and the session timer when there is one.
class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.snapshot,
    required this.strings,
    this.scale = 1,
  });

  final TunnelSnapshot snapshot;
  final S strings;

  /// Shrinks with the header, so the line stays proportionate to the button
  /// it sits under rather than dominating it once the dome has closed.
  final double scale;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    final connected = snapshot.isConnected;
    final colour = statusColour(c, snapshot);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          connected ? Icons.lock_rounded : Icons.lock_open_rounded,
          size: 15 * scale,
          color: connected ? c.ok : c.textMuted,
        ),
        SizedBox(width: 7 * scale),
        Text(
          _label(),
          style: TextStyle(
            color: connected ? c.textPrimary : c.textSecondary,
            fontSize: 18 * scale,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.36,
          ),
        ),
        if (connected) ...[
          const SizedBox(width: 9),
          Text('|', style: TextStyle(color: c.textFaint, fontSize: 15)),
          const SizedBox(width: 9),
          // A clock is a number: isolated so an RTL layout cannot reorder its
          // parts around the colons.
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              snapshot.duration,
              style: TextStyle(
                fontFamily: VernaType.mono,
                color: colour,
                fontSize: 20 * scale,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
        if (snapshot.phase == TunnelPhase.searching && snapshot.total > 0) ...[
          const SizedBox(width: 9),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              '${snapshot.attempt}/${snapshot.total}',
              style: TextStyle(
                fontFamily: VernaType.mono,
                color: c.warn,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _label() => switch (snapshot.phase) {
        TunnelPhase.connected => strings.statusProtected,
        TunnelPhase.failed => strings.statusFailed,
        TunnelPhase.preparing => strings.statusPreparing,
        TunnelPhase.searching => strings.statusSearching,
        TunnelPhase.idle => strings.statusNotProtected,
      };
}

// ── location, map, cards ───────────────────────────────────────────────────

/// Which country the tunnel is using, or will use. Opens the locations tab.
class _LocationCard extends ConsumerWidget {
  const _LocationCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.verna;
    final s = ref.watch(stringsProvider);
    final snapshot = ref.watch(tunnelSnapshotProvider);
    final chosen = ref.watch(chosenServerProvider);
    final preferred = ref.watch(preferredCountryProvider);

    final connected = snapshot.isConnected;
    final code = connected
        ? snapshot.displayCountryCode
        : (chosen?.countryCode ?? preferred);
    // A config's own flag is often empty -- the pool carries plenty of rows
    // with no emoji in them -- so the country code is the source of truth and
    // the config's flag is only a shortcut when it has one.
    final flag = flagEmoji(code, fallback: connected
        ? (snapshot.active?.flag ?? '')
        : (chosen?.flag ?? ''));
    final title =
        code == null || code.isEmpty ? s.autoSelect : s.countryName(code);
    // Just the label. The design appends "· Fastest", which only repeats the
    // word underneath it, and appending the protocol instead truncated to
    // "Selected location · Shado…" the moment a Shadowsocks server won -- for
    // a value the Protocol card already shows in full.
    final subtitle = s.selectedLocation;

    return GestureDetector(
      onTap: () => ref.read(shellTabProvider.notifier).select(1),
      child: Container(
        // `.loc`: 13px 15px, radius 20.
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            _FlagTile(flag: flag),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.textFaint,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            // A hand-picked server stays picked -- the button and "Try again"
            // both use it -- so there has to be a way back to letting the app
            // choose.
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
                    child:
                        Icon(Icons.close_rounded, size: 18, color: c.textMuted),
                  ),
                ),
              ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: c.accentSoft,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    s.change,
                    style: TextStyle(
                      color: c.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Icon(Icons.place_outlined, size: 13, color: c.accent),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

}

/// The flag for a country code, built from the code itself.
///
/// Regional-indicator pairs rather than bundled images: two code points that
/// every Android since 6 draws, against 250 PNGs in the APK. [fallback] is
/// whatever the config carried, used only when the code cannot produce one.
String flagEmoji(String? code, {String fallback = ''}) {
  if (code == null || code.length != 2) return fallback;
  final upper = code.toUpperCase();
  final first = upper.codeUnitAt(0);
  final second = upper.codeUnitAt(1);
  if (first < 0x41 || first > 0x5A || second < 0x41 || second > 0x5A) {
    return fallback;
  }
  return String.fromCharCodes([
    0x1F1E6 + first - 0x41,
    0x1F1E6 + second - 0x41,
  ]);
}

class _FlagTile extends StatelessWidget {
  const _FlagTile({required this.flag, this.width = 42, this.height = 31});

  final String flag;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.chip,
        // `.flag` carries an inset hairline, which keeps a pale flag from
        // dissolving into a light card.
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(width > 36 ? 9 : 7),
      ),
      child: Text(
        flag.isEmpty ? '🌐' : flag,
        style: TextStyle(fontSize: height * 0.66),
      ),
    );
  }
}

/// The map, and the callout that names what it is pointing at.
class _MapCard extends ConsumerWidget {
  const _MapCard({required this.snapshot, required this.strings});

  final TunnelSnapshot snapshot;
  final S strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.verna;
    final chosen = ref.watch(chosenServerProvider);
    final preferred = ref.watch(preferredCountryProvider);
    // Read only while nothing is tunnelling; see OwnIpNotifier.
    final ownIp = ref.watch(ownIpProvider).valueOrNull;

    final connected = snapshot.isConnected;
    final chosenCode = connected
        ? snapshot.displayCountryCode
        : (chosen?.countryCode ?? preferred);
    // In automatic mode there is no chosen country, and the map sat on the
    // whole world with an address in the corner and no place attached to it.
    // The user's own country is the honest thing to show there: it is where
    // they are now, and it is what the tunnel is about to change.
    final showingOwn = !connected && chosenCode == null;
    final code = showingOwn ? ownIp?.country : chosenCode;

    // Cyan only ever means protected. A country the app has merely been asked
    // to use is amber, and one that just failed is rose -- the design's rule,
    // applied to the states this app actually has. The user's own country is
    // none of those: it is where they are, not a plan, so it stays idle grey.
    final highlight = switch (snapshot.phase) {
      TunnelPhase.connected => MapHighlight.connected,
      TunnelPhase.failed => MapHighlight.failed,
      _ => chosenCode == null ? MapHighlight.idle : MapHighlight.pending,
    };

    // 158 as the design has it, less on a short screen. The handoff's layout
    // "fits with no scrolling" on a 412 x 872 phone; on anything shorter --
    // a J7, or an A54 with the font scale turned up -- honouring that intent
    // means giving back the sixth of the map nobody was reading.
    final tall = MediaQuery.sizeOf(context).height >= 820;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: tall ? 158 : 132,
        decoration: BoxDecoration(
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: WorldMap(
                countryCode: code,
                highlight: highlight,
                // Hidden mid-handshake: a pin on a country the app has not
                // reached yet is a claim it cannot make.
                pinVisible: !snapshot.isBusy,
                dimPin: snapshot.isBusy,
              ),
            ),
            // Beside the pin, vertically centred, as `.callout.right` has it:
            // the pin is always at the middle of the card because the camera
            // put it there.
            // A country, or an address, or both. Automatic mode with nothing
            // chosen has no country to name -- and that is exactly the state
            // the user's own address belongs in.
            if ((code != null || ownIp != null) && !snapshot.isBusy)
              PositionedDirectional(
                start: 0,
                end: 10,
                top: 0,
                bottom: 0,
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: _MapCallout(
                    code: code,
                    flag: code == null
                        ? ''
                        : flagEmoji(
                            code,
                            fallback: connected
                                ? (snapshot.active?.flag ?? '')
                                : (showingOwn ? '' : (chosen?.flag ?? '')),
                          ),
                    // Before: the address the user actually has. After: the
                    // one the tunnel gives them. Seeing both is the whole
                    // point of the card.
                    ip: connected ? snapshot.exitIp : ownIp?.ip,
                    label:
                        connected ? strings.vpnIpLabel : strings.ownIpLabel,
                    strings: strings,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MapCallout extends StatelessWidget {
  const _MapCallout({
    required this.code,
    required this.flag,
    required this.ip,
    required this.label,
    required this.strings,
  });

  /// Null in automatic mode before a connection: there is no country to
  /// name yet, only an address.
  final String? code;
  final String flag;
  final String? ip;
  final String? label;
  final S strings;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    return Container(
      constraints: const BoxConstraints(maxWidth: 196),
      // `.callout`: 11px 13px, radius 16, on the card colour with its own
      // shadow -- it sits over the map, so it has to read as a card rather
      // than as a tint.
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: c.shadow.withValues(alpha: 0.45),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (code != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _FlagTile(flag: flag, width: 32, height: 24),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  strings.countryName(code!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
          if (ip != null && label != null) ...[
            if (code != null) const SizedBox(height: 6),
            Text(
              label!,
              style: TextStyle(color: c.textFaint, fontSize: 9.5),
            ),
            const SizedBox(height: 2),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                ip!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: VernaType.mono,
                  color: c.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The design's 2 x 2 grid, carrying the four things this app can measure.
class _MiniCardGrid extends ConsumerWidget {
  const _MiniCardGrid({required this.snapshot, required this.strings});

  final TunnelSnapshot snapshot;
  final S strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.verna;
    final protected = ref.watch(protectedTimeProvider);
    final results = ref.watch(localTestResultsProvider);
    final pool = ref.watch(filteredConfigsProvider);
    final working = results.values.where((r) => r.works).length;
    final ping = results[snapshot.active?.id]?.milliseconds ?? snapshot.pingMs;

    return Column(
      children: [
        // IntrinsicHeight, not CrossAxisAlignment.stretch: inside a scroll view
        // the incoming height is unbounded, and stretch asks the children to
        // fill infinity. This pairs the two cards to the taller of them, which
        // is what the design's grid does.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _MiniCard(
                  title: strings.timeProtected,
                  onTap: () => ref.read(shellTabProvider.notifier).select(2),
                  child: _ProtectedBody(protected: protected, strings: strings),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: _MiniCard(
                  title: strings.liveSpeed,
                  onTap: () => ref.read(shellTabProvider.notifier).select(2),
                  child: _SpeedBody(snapshot: snapshot, strings: strings),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 11),
        IntrinsicHeight(
          child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _MiniCard(
                title: strings.protocol,
                onTap: () => ref.read(shellTabProvider.notifier).select(1),
                child: _ValueBody(
                  value: snapshot.active?.type.label.toUpperCase() ?? '—',
                  // The healthy count moved here when ping took its card.
                  // It is a fact about the list, and the protocol is the other
                  // one -- neither needed a card of its own.
                  sub: working > 0
                      ? '$working ${strings.subHealthy}'
                      : '${pool.length} ${strings.untestedYet}',
                  colour: c.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MiniCard(
                title: strings.ping,
                onTap: () => ref.read(shellTabProvider.notifier).select(1),
                child: _PingBody(milliseconds: ping, strings: strings),
              ),
            ),
          ],
          ),
        ),
      ],
    );
  }
}

class _MiniCard extends StatelessWidget {
  const _MiniCard({
    required this.title,
    required this.child,
    required this.onTap,
  });

  final String title;
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        // `.mini`: 13px 14px, radius 19, 11 between its rows.
        padding: const EdgeInsets.fromLTRB(14, 13, 11, 13),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(19),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 16, color: c.textFaint),
              ],
            ),
            const SizedBox(height: 11),
            // One height for all four, so the grid is a grid.
            //
            // They used to size themselves: each row was paired by an
            // IntrinsicHeight and the two rows ended up different heights,
            // which Meysam saw immediately -- «دوتا مربع بالا با دوتا مربع
            // پایین سایزش برابر نیست». Every body now gets the same box and
            // lays itself out inside it.
            SizedBox(height: bodyHeight, child: child),
          ],
        ),
      ),
    );
  }

  /// Tall enough for the roomiest body: two stacked rates in the speed card.
  static const double bodyHeight = 46;
}

/// Hours behind a tunnel this week, with a bar per day.
class _ProtectedBody extends StatelessWidget {
  const _ProtectedBody({required this.protected, required this.strings});

  final ProtectedTime protected;
  final S strings;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    final hours = protected.weekSeconds / 3600;
    final peak = math.max(protected.busiestDaySeconds, 1);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  hours >= 10
                      ? '${hours.round()}h'
                      : hours >= 1
                          ? '${hours.toStringAsFixed(1)}h'
                          : '${(protected.weekSeconds / 60).round()}m',
                  style: TextStyle(
                    fontFamily: VernaType.mono,
                    color: c.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                strings.thisWeek,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.textFaint, fontSize: 10.5),
              ),
            ],
          ),
        ),
        // `.weekbars`: 30 tall, 3.5 apart, radius 3. Narrower than the
        // design's 96 so the figure beside them keeps its line at a larger
        // font scale -- "this week" was arriving as "this w…".
        SizedBox(
          height: 30,
          width: 74,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < protected.history.length; i++) ...[
                if (i > 0) const SizedBox(width: 3.5),
                Expanded(
                  child: Container(
                    height: math.max(4, 30 * (protected.history[i].seconds / peak)),
                    decoration: BoxDecoration(
                      // A day with time on it is filled with the accent; an
                      // empty one stays a track-coloured stub, so "nothing
                      // here" still reads as a day rather than as a gap.
                      color: protected.history[i].seconds > 0
                          ? c.accent
                          : c.track,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Down and up, as the core reports them.
/// Down and up, each with its unit, over a line of the last half-minute.
///
/// It used to be two bare numbers in kilobytes with no unit on them, which
/// told the reader a quantity and not what of -- Meysam, 2026-09-30: "فقط عدد
/// نشون میده و معلوم نیست چیه". Now each rate carries a direction and a unit
/// that scales with it, and the strip underneath shows where those numbers
/// have just been, which is what makes a live reading worth looking at.
///
/// The core reports once a second and that cannot be changed from here -- the
/// interval is fixed in the plugin's Kotlin (`statusInterval`), and its pull
/// API returns the same cached sample. So the numbers are *animated* between
/// readings instead: the value glides to each new sample over most of a
/// second rather than stepping, which is what "faster" actually looks like on
/// a screen.
class _SpeedBody extends StatefulWidget {
  const _SpeedBody({required this.snapshot, required this.strings});

  final TunnelSnapshot snapshot;
  final S strings;

  @override
  State<_SpeedBody> createState() => _SpeedBodyState();
}

class _SpeedBodyState extends State<_SpeedBody> {
  /// How many samples the strip holds. At one a second this is the last
  /// half-minute, which is long enough to show a burst and short enough that
  /// the line still moves visibly.
  static const int _window = 30;

  final List<int> _down = <int>[];
  final List<int> _up = <int>[];
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // On a clock of its own rather than on the snapshot: a second of no
    // traffic produces an identical snapshot and no rebuild, and the line has
    // to keep moving through the quiet part or it reads as frozen.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _sample());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _sample() {
    if (!mounted) return;
    final snapshot = widget.snapshot;
    setState(() {
      if (!snapshot.isConnected) {
        // Nothing to draw, and a strip left over from the last session would
        // describe a tunnel that no longer exists.
        _down.clear();
        _up.clear();
        return;
      }
      _down.add(snapshot.downloadSpeed);
      _up.add(snapshot.uploadSpeed);
      while (_down.length > _window) {
        _down.removeAt(0);
      }
      while (_up.length > _window) {
        _up.removeAt(0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    // The strip sits *behind* the two readings rather than under them. A row
    // of its own made the card taller than the one beside it and pushed the
    // protocol and ping cards under the nav bar -- measured on the A54, and
    // the same complaint as the scroll fix in §39. Behind, it costs nothing
    // in height and still shows where the numbers have been.
    return SizedBox(
      width: double.infinity,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _SparkPainter(
                down: List<int>.unmodifiable(_down),
                up: List<int>.unmodifiable(_up),
                downColour: c.ok,
                upColour: c.accentBlue,
                idleColour: c.border,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _RateLine(
                icon: Icons.south_rounded,
                bytesPerSecond: widget.snapshot.downloadSpeed,
                colour: c.ok,
              ),
              const SizedBox(height: 5),
              _RateLine(
                icon: Icons.north_rounded,
                bytesPerSecond: widget.snapshot.uploadSpeed,
                colour: c.accentBlue,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One direction: an arrow, the number, and the unit it is in.
class _RateLine extends StatelessWidget {
  const _RateLine({
    required this.icon,
    required this.bytesPerSecond,
    required this.colour,
  });

  final IconData icon;
  final int bytesPerSecond;
  final Color colour;

  /// Kilobytes per second, always.
  ///
  /// It scaled to MB/s at first, and the unit changing under a moving number
  /// made the card impossible to read at a glance -- Meysam, 2026-09-30:
  /// «خیلی سریع عدد عوض میکنه، فقط KB نشون بده». One unit, whole numbers, one
  /// new reading a second: a value that stays still long enough to be read.
  static String format(int bps) {
    final kb = bps / 1024;
    if (kb <= 0) return '0';
    // Below a tenth of a kilobyte there is traffic but nothing to round to.
    return kb < 1 ? kb.toStringAsFixed(1) : kb.round().toString();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    final idle = bytesPerSecond <= 0;
    // Muted at rest: throughput is zero whenever the app is in the foreground
    // -- nobody downloads anything while looking at a VPN screen -- and two
    // bright zeroes teach the reader to ignore the row.
    final ink = idle ? c.textFaint : colour;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(icon, size: 12, color: ink),
          ),
          Text(
            format(bytesPerSecond),
            style: TextStyle(
              fontFamily: VernaType.mono,
              color: ink,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 3),
          Text(
            'KB/s',
            style: TextStyle(
              color: c.textFaint,
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  const _SparkPainter({
    required this.down,
    required this.up,
    required this.downColour,
    required this.upColour,
    required this.idleColour,
  });

  final List<int> down;
  final List<int> up;
  final Color downColour;
  final Color upColour;
  final Color idleColour;

  /// 16 KB/s. Under this the line stays flat rather than magnifying noise.
  static const double _floor = 16 * 1024;

  @override
  void paint(Canvas canvas, Size size) {
    final baseline = Paint()
      ..color = idleColour
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      baseline,
    );
    if (down.length < 2) return;

    var peak = _floor;
    for (final value in [...down, ...up]) {
      if (value > peak) peak = value.toDouble();
    }

    void series(List<int> values, Color colour) {
      if (values.length < 2) return;
      final step = size.width / (_SpeedBodyState._window - 1);
      // Right-aligned: the newest reading sits at the right edge, so a short
      // history grows from there instead of stretching to fit.
      final offset = size.width - step * (values.length - 1);
      final path = Path();
      for (var i = 0; i < values.length; i++) {
        final x = offset + step * i;
        final y = size.height - (values[i] / peak).clamp(0.0, 1.0) * (size.height - 2);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      final fill = Path.from(path)
        ..lineTo(offset + step * (values.length - 1), size.height)
        ..lineTo(offset, size.height)
        ..close();
      canvas.drawPath(
        fill,
        Paint()..color = colour.withValues(alpha: 0.10),
      );
      canvas.drawPath(
        path,
        Paint()
          // Half-lit: it is behind two lines of text, and a bright line
          // through a number costs more than the graph adds.
          ..color = colour.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }

    series(up, upColour);
    series(down, downColour);
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      !listEquals(old.down, down) || !listEquals(old.up, up);
}

/// The round trip to the server this phone is on, and what that number means.
///
/// A bare "212 ms" asks the reader to know what a good one is. The word under
/// it answers that, and the colour says the same thing again for anyone who
/// reads the card without reading the word.
class _PingBody extends StatelessWidget {
  const _PingBody({required this.milliseconds, required this.strings});

  final int? milliseconds;
  final S strings;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    final ms = milliseconds;
    // Bands for a tunnel out of Iran, not for a LAN: under 120 ms is as good
    // as this gets, and past 300 ms pages start feeling slow to open however
    // much bandwidth is behind it.
    final (label, colour) = switch (ms) {
      null => (strings.pingUnknown, c.textMuted),
      final v when v <= 120 => (strings.pingExcellent, c.ok),
      final v when v <= 300 => (strings.pingGood, c.textPrimary),
      _ => (strings.pingSlow, c.warn),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                ms == null ? '—' : '$ms',
                style: TextStyle(
                  fontFamily: VernaType.mono,
                  color: colour,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (ms != null) ...[
                const SizedBox(width: 3),
                Text(
                  'ms',
                  style: TextStyle(
                    color: c.textFaint,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    height: 1,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: c.textMuted, fontSize: 11),
        ),
      ],
    );
  }
}

class _ValueBody extends StatelessWidget {
  const _ValueBody({
    required this.value,
    required this.sub,
    required this.colour,
  });

  final String value;
  final String sub;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: VernaType.mono,
              color: colour,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          sub,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: c.textFaint, fontSize: 10),
        ),
      ],
    );
  }
}

/// Shown when every candidate failed, with the two things worth doing next.
class _FailureCard extends ConsumerWidget {
  const _FailureCard({
    required this.snapshot,
    required this.strings,
    required this.onRetry,
  });

  final TunnelSnapshot snapshot;
  final S strings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.verna;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: c.dangerSurface,
        border: Border.all(color: c.dangerBorder),
        borderRadius: BorderRadius.circular(19),
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
                // The reason in the app's own words, not a code borrowed from
                // the design's mock: this one is true.
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
          _SmallButton(label: strings.retry, filled: true, onTap: onRetry),
        ],
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

// ── shared with the rest of the app ────────────────────────────────────────

/// The colour that stands for the tunnel's state, everywhere it is shown.
///
/// Aurora makes cyan mean protected -- the aura, the ring, the map highlight
/// and the pin all use it -- so "connected" and "the brand" are the same
/// colour here, and amber carries "working on it" instead.
Color statusColour(VernaColors c, TunnelSnapshot s) => switch (s.phase) {
      TunnelPhase.connected => c.ok,
      TunnelPhase.failed => c.danger,
      TunnelPhase.preparing || TunnelPhase.searching => c.warn,
      TunnelPhase.idle => c.textMuted,
    };

/// The short code in a status chip. Deliberately untranslated: it reads as a
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
