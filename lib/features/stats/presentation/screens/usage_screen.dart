import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/palette.dart';
import '../../../tunnel/presentation/providers/tunnel_provider.dart';
import '../../data/usage_store.dart';

/// What this device has moved through the tunnel.
///
/// Built to the design's usage screen -- the same hero figure, the same
/// fourteen-bar chart, the same card rhythm -- with its subject changed. The
/// design shows a quota, a renewal date and a device roster, all of which
/// belong to a service with accounts. This app has none, so those figures could
/// only be decoration, and a number that looks measured but is not is worse
/// than no number.
///
/// What is left is what the core actually counts, which turns out to answer the
/// question the quota card was standing in for anyway: am I using this, and how
/// much.
class UsageScreen extends ConsumerWidget {
  const UsageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.verna;
    final s = ref.watch(stringsProvider);
    final usage = ref.watch(usageProvider);
    final snapshot = ref.watch(tunnelSnapshotProvider);

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Text(
              s.usage,
              // `.h1`: 23px, 700, -.025em -- the same heading as every other
              // screen, so the tabs read as one app.
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 23,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.575,
              ),
            ),
            const SizedBox(height: 16),

            _TotalCard(usage: usage, snapshot: snapshot, strings: s),
            const SizedBox(height: 14),

            _SectionLabel(s.lastFourteenDays),
            const SizedBox(height: 8),
            _HistoryCard(usage: usage, strings: s),
            const SizedBox(height: 14),

            _SectionLabel(s.thisSession),
            const SizedBox(height: 8),
            _SessionCard(usage: usage, snapshot: snapshot, strings: s),
          ],
        ),
      ),
    );
  }
}

/// The hero figure: everything moved in the retained window.
///
/// The design puts a quota bar here. Without a quota there is no denominator,
/// so the bar shows today against the busiest day instead -- which is a real
/// comparison, and the one a person actually makes when they glance at this.
class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.usage,
    required this.snapshot,
    required this.strings,
  });

  final UsageSummary usage;
  final dynamic snapshot;
  final S strings;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    final busiest = usage.busiestDayBytes;
    final fraction =
        busiest == 0 ? 0.0 : (usage.todayBytes / busiest).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _Bytes.value(usage.totalBytes),
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 30,
                  height: 1,
                  fontWeight: FontWeight.bold,
                  fontFamily: VernaType.mono,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _Bytes.unit(usage.totalBytes),
                style: TextStyle(
                  color: c.textMuted,
                  fontSize: 13,
                  fontFamily: VernaType.mono,
                ),
              ),
              const Spacer(),
              Text(
                '${_Bytes.short(usage.todayBytes)} ${strings.today}',
                style: TextStyle(
                  color: c.ok,
                  fontSize: 11.5,
                  fontFamily: VernaType.mono,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: 8,
              child: Stack(
                children: [
                  Container(color: c.track),
                  // Container rather than DecoratedBox: the fill has no
                  // child, and only Container grows to fill loose constraints.
                  FractionallySizedBox(
                    widthFactor: fraction,
                    heightFactor: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [c.accent, c.ok],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            busiest == 0
                ? strings.usageEmpty
                : '${strings.today} · ${strings.comparedToBusiestDay}',
            style: TextStyle(color: c.textFaint, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

/// Fourteen bars, oldest to newest, the newest in accent.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.usage, required this.strings});

  final UsageSummary usage;
  final S strings;

  static const List<String> _months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    final peak = usage.busiestDayBytes;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 104,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < usage.history.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2.5),
                      child: _Bar(
                        // A day with traffic never draws as nothing: a 2px stub
                        // says "a little", an empty column says "none", and the
                        // difference matters when the whole point is spotting
                        // which days you used it.
                        fraction: peak == 0
                            ? 0.0
                            : (usage.history[i].bytes / peak).clamp(0.0, 1.0),
                        colour: i == usage.history.length - 1
                            ? c.accent
                            : c.track,
                        hasTraffic: usage.history[i].bytes > 0,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _axis(context, usage.history.isEmpty ? null : usage.history.first),
              _axis(context, usage.history.isEmpty ? null : usage.history.last),
            ],
          ),
        ],
      ),
    );
  }

  Widget _axis(BuildContext context, UsageDay? day) {
    if (day == null) return const SizedBox.shrink();
    return Text(
      '${_months[day.date.month - 1]} ${day.date.day.toString().padLeft(2, '0')}',
      style: TextStyle(
        color: context.verna.textFaint,
        fontSize: 10,
        letterSpacing: 0.08,
        fontFamily: VernaType.mono,
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.fraction,
    required this.colour,
    required this.hasTraffic,
  });

  final double fraction;
  final Color colour;
  final bool hasTraffic;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: FractionallySizedBox(
        heightFactor: hasTraffic ? fraction.clamp(0.03, 1.0) : 0.015,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: hasTraffic ? colour : context.verna.track,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(4),
              bottom: Radius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

/// The live session, which is the only part of this screen that moves.
class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.usage,
    required this.snapshot,
    required this.strings,
  });

  final UsageSummary usage;
  final dynamic snapshot;
  final S strings;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    final connected = snapshot.isConnected as bool;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          _Stat(
            label: strings.duration,
            value: connected ? snapshot.duration as String : '--:--:--',
          ),
          _Divider(),
          _Stat(
            label: strings.download,
            value: _Bytes.short(
                connected ? snapshot.downloadTotal as int : 0),
            colour: c.ok,
          ),
          _Divider(),
          _Stat(
            label: strings.upload,
            value: _Bytes.short(connected ? snapshot.uploadTotal as int : 0),
            colour: c.accent,
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 30,
        color: context.verna.borderFaint,
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.colour});

  final String label;
  final String value;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    return Expanded(
      child: Column(
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
          const SizedBox(height: 7),
          Text(
            value,
            style: TextStyle(
              color: colour ?? c.mono,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFamily: VernaType.mono,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          color: context.verna.textFaint,
          fontSize: 10,
          letterSpacing: 0.12,
          fontFamily: VernaType.mono,
        ),
      );
}

/// Byte formatting, split so the figure and its unit can be styled apart --
/// the design sets the number at 30px and the unit at 13.
class _Bytes {
  const _Bytes._();

  static const List<String> _units = ['B', 'KB', 'MB', 'GB', 'TB'];

  static (double, String) _scale(int bytes) {
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < _units.length - 1) {
      value /= 1024;
      unit++;
    }
    return (value, _units[unit]);
  }

  static String value(int bytes) {
    final (v, _) = _scale(bytes);
    return v >= 100 || v == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  }

  static String unit(int bytes) => _scale(bytes).$2;

  static String short(int bytes) => '${value(bytes)} ${unit(bytes)}';
}
