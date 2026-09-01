import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/palette.dart';

/// Where a paid plan will live.
///
/// The design draws this screen fully: a gradient hero with days and data
/// remaining, three priced tiers, a referral code. All of it describes a
/// service with accounts and quotas, and this app has neither -- so shipping it
/// as drawn would mean inventing a balance, a renewal date and a discount, and
/// putting a "Pay and renew" button under them that cannot take money.
///
/// The design's own note says as much: keep the screen only if a paid tier
/// ships. It ships here anyway, empty on purpose, because the tab was asked
/// for -- and an empty room is honest in a way a furnished fake is not. The
/// hero card, the gradient and the card rhythm are the design's; only the
/// claims are missing, and they are the part that would have been false.
class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final c = context.verna;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Text(
              s.tabPlan,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // The hero, with the one true claim it can make: this is free.
            Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [c.glow, c.surface],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.selectedBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.planCurrent,
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: c.okSurface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: c.okBorder),
                        ),
                        child: Text(
                          s.planActive.toUpperCase(),
                          style: TextStyle(
                            color: c.ok,
                            fontSize: 10,
                            letterSpacing: 0.06,
                            fontFamily: VernaType.mono,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Three stats, like the design -- but the ones this app can
                  // actually answer. No quota, no expiry, no device roster.
                  Row(
                    children: [
                      _Stat(label: s.planData, value: '∞'),
                      _Stat(label: s.planDays, value: '∞'),
                      _Stat(label: s.planPrice, value: '0'),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 22),

            // No tier list, because there is nothing to choose between.
            Container(
              padding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: c.border,
                  // Dashed is not available on a Border, and a lighter solid
                  // reads the same way here: this card is a placeholder.
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: c.chip,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.border),
                    ),
                    child: Icon(
                      Icons.workspace_premium_rounded,
                      size: 34,
                      color: c.accent,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    s.planHeadline,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: c.chip,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: c.border),
                    ),
                    child: Text(
                      s.planSoon,
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 11.5,
                        fontFamily: VernaType.mono,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    s.planBody,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 13.5,
                      height: 1.7,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: c.textFaint,
              fontSize: 10,
              letterSpacing: 0.12,
              fontFamily: VernaType.mono,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: c.mono,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontFamily: VernaType.mono,
            ),
          ),
        ],
      ),
    );
  }
}
