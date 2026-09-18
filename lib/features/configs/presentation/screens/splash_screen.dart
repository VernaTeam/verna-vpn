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

  late final AnimationController _float;
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
    // The design floats the mark 6 px and back over 3.4 s. Slow on purpose:
    // it is the only thing moving, and a boot screen that bounces reads as a
    // loading spinner pretending to be a brand.
    _float = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
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
    _float.dispose();
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
                  // The design's floating mark: 104 at radius 30, rising 6 px
                  // and settling over 3.4 s, over a glow in the accent.
                  AnimatedBuilder(
                    animation: _float,
                    builder: (context, child) => Transform.translate(
                      offset: Offset(
                        0,
                        -6 * Curves.easeInOut.transform(_float.value),
                      ),
                      child: child,
                    ),
                    child: Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: c.glow,
                            blurRadius: 54,
                            spreadRadius: -20,
                            offset: const Offset(0, 26),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset(
                        'assets/images/icon.png',
                        fit: BoxFit.cover,
                      ),
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
                  // Three dots, the current one stretched to 26 px: the
                  // design's own progress indicator. It says "three things,
                  // this is the second" rather than inventing a percentage
                  // nobody measured.
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < _steps.length; i++) ...[
                        if (i > 0) const SizedBox(width: 7),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOut,
                          width: i == _step ? 26 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: i <= _step ? c.accent : c.track,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ],
                    ],
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
