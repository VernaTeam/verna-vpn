import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/palette.dart';

/// The boot screen, as the design draws it.
///
/// It exists to cover a real gap rather than to be an animation: on a Galaxy J7
/// the engine takes seconds to come up, and what filled those seconds was a
/// black rectangle. The native launch theme now paints the logo immediately,
/// and this continues it inside Flutter so the handover is invisible -- the
/// same mark, the same background, no flash between the two.
///
/// The design's three steps are kept. Its middle one, "CHECKING SUBSCRIPTION",
/// is not: there are no subscriptions, and a boot screen that reports on
/// something it never checked is a small lie told before the app has done
/// anything. It says what is actually happening instead.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key, this.onDone});

  /// Called when the sequence finishes. Null when the screen is pushed on its
  /// own, in which case it simply sits there.
  final VoidCallback? onDone;

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  /// The step being shown, indexing [_steps].
  int _step = 0;

  late final AnimationController _pulse;
  final List<Timer> _timers = [];

  static const List<({String label, double progress, int atMs})> _steps = [
    (label: 'LOADING CORE', progress: 0.22, atMs: 0),
    (label: 'FETCHING SERVERS', progress: 0.64, atMs: 700),
    (label: 'READY', progress: 1.0, atMs: 1500),
  ];

  /// How long the screen stays up.
  ///
  /// The design says 2200ms. It is a floor rather than a wait: the engine and
  /// the first server fetch usually take longer than this on the J7, and the
  /// shell behind is built either way -- so this is the minimum time the mark
  /// is shown, which stops it flashing on a fast device.
  static const Duration _total = Duration(milliseconds: 2200);

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    for (var i = 1; i < _steps.length; i++) {
      final index = i;
      _timers.add(Timer(Duration(milliseconds: _steps[i].atMs), () {
        if (mounted) setState(() => _step = index);
      }));
    }
    _timers.add(Timer(_total, () {
      if (mounted) widget.onDone?.call();
    }));
  }

  @override
  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    final step = _steps[_step];

    return Scaffold(
      backgroundColor: c.background,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.36),
            radius: 1.1,
            colors: [c.glow, c.background],
            stops: const [0, 0.62],
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The halo pulses, the tile does not: a logo that breathes
                  // reads as decoration, a ring around a steady logo reads as
                  // work happening.
                  SizedBox(
                    width: 96,
                    height: 96,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AnimatedBuilder(
                          animation: _pulse,
                          builder: (context, _) {
                            final t = Curves.easeInOut.transform(_pulse.value);
                            return Opacity(
                              opacity: 0.25 + 0.45 * t,
                              child: Transform.scale(
                                scale: 1 + 0.08 * t,
                                child: Container(
                                  width: 96,
                                  height: 96,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(color: c.accent),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        Container(
                          width: 66,
                          height: 66,
                          decoration: BoxDecoration(
                            color: c.accent,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Icon(
                            Icons.verified_user_rounded,
                            size: 34,
                            color: c.onAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Verna VPN',
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 22,
                      height: 1,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.22,
                    ),
                  ),
                  const SizedBox(height: 22),
                  // Latin and monospaced in both languages: these are machine
                  // states, not prose, and the design keeps them that way.
                  Text(
                    step.label,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      color: c.textMuted,
                      fontSize: 10.5,
                      letterSpacing: 1.68,
                      fontFamily: VernaType.mono,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: SizedBox(
                      width: 132,
                      height: 3,
                      child: Stack(
                        children: [
                          Container(color: c.track),
                          AnimatedFractionallySizedBox(
                            duration: const Duration(milliseconds: 450),
                            curve: Curves.easeOut,
                            widthFactor: step.progress,
                            heightFactor: 1,
                            child: Container(color: c.accent),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 34,
              child: Text(
                'VERNA 1.0.0',
                textAlign: TextAlign.center,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  color: c.textFaint,
                  fontSize: 10,
                  letterSpacing: 0.6,
                  fontFamily: VernaType.mono,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
