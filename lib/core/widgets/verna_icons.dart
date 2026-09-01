import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The navigation icons, drawn rather than borrowed.
///
/// The design specifies five line icons on a 24x24 grid with a 1.9 stroke and
/// round caps, and gives their exact geometry. Material's set has nothing that
/// matches: its globe has a different meridian, its card has no magnetic
/// stripe, and its settings glyph is a gear where the design draws sliders. Ten
/// near-misses read as a different app, so these are transcribed from the
/// design's own paths.
///
/// Each is a [CustomPainter] over the same 24-unit box, scaled to whatever size
/// the caller asks for, so the set stays consistent if the bar ever changes
/// height.
enum VernaIcon {
  /// Power: a stem inside a broken ring. Connect.
  connect,

  /// A globe with one meridian and an equator. Servers.
  servers,

  /// Four bars rising from a baseline. Usage.
  usage,

  /// A card with a stripe and a short number run. Plan.
  plan,

  /// Two sliders with their handles at different positions. Settings.
  settings,
}

class VernaIconView extends StatelessWidget {
  const VernaIconView(
    this.icon, {
    super.key,
    this.size = 20,
    required this.color,
  });

  final VernaIcon icon;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _IconPainter(icon, color)),
    );
  }
}

class _IconPainter extends CustomPainter {
  const _IconPainter(this.icon, this.color);

  final VernaIcon icon;
  final Color color;

  /// The design's grid. Everything below is written in these units and scaled
  /// once, so the numbers can be read against the handoff without arithmetic.
  static const double _grid = 24;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _grid;
    canvas.save();
    canvas.scale(scale);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    switch (icon) {
      case VernaIcon.connect:
        // The stem, then an arc left open at the top so the stem reads as
        // passing through the gap rather than sitting on a closed ring.
        canvas.drawLine(const Offset(12, 3.5), const Offset(12, 11.5), stroke);
        canvas.drawArc(
          Rect.fromCircle(center: const Offset(12, 12.2), radius: 7.2),
          // Starting just past the top-left of the ring and sweeping the long
          // way round, which is what leaves the gap under the stem.
          -math.pi * 0.72,
          math.pi * 1.94,
          false,
          stroke,
        );

      case VernaIcon.servers:
        canvas.drawCircle(const Offset(12, 12), 8.5, stroke);
        canvas.drawLine(const Offset(3.5, 12), const Offset(20.5, 12), stroke);
        // The meridian: two mirrored curves meeting at the poles, which is
        // what makes a circle read as a globe rather than a clock.
        final meridian = Path()
          ..moveTo(12, 3.5)
          ..cubicTo(14.2, 5.9, 15.3, 8.8, 15.3, 12)
          ..cubicTo(15.3, 15.2, 14.2, 18.1, 12, 20.5)
          ..cubicTo(9.8, 18.1, 8.7, 15.2, 8.7, 12)
          ..cubicTo(8.7, 8.8, 9.8, 5.9, 12, 3.5);
        canvas.drawPath(meridian, stroke);

      case VernaIcon.usage:
        canvas.drawLine(const Offset(4, 19.5), const Offset(20, 19.5), stroke);
        canvas.drawLine(const Offset(7, 19.5), const Offset(7, 13.5), stroke);
        canvas.drawLine(const Offset(12, 19.5), const Offset(12, 6.5), stroke);
        canvas.drawLine(const Offset(17, 19.5), const Offset(17, 10.5), stroke);

      case VernaIcon.plan:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(3, 5.5, 18, 13),
            const Radius.circular(2.5),
          ),
          stroke,
        );
        canvas.drawLine(const Offset(3, 10), const Offset(21, 10), stroke);
        canvas.drawLine(const Offset(7, 14.5), const Offset(10.5, 14.5), stroke);

      case VernaIcon.settings:
        // Two rails, each broken where its handle sits, so the handle reads as
        // being on the rail rather than floating over it.
        canvas.drawLine(const Offset(4, 8), const Offset(14, 8), stroke);
        canvas.drawLine(const Offset(18, 8), const Offset(20, 8), stroke);
        canvas.drawLine(const Offset(4, 16), const Offset(8, 16), stroke);
        canvas.drawLine(const Offset(12, 16), const Offset(20, 16), stroke);
        canvas.drawCircle(const Offset(16, 8), 2.2, stroke);
        canvas.drawCircle(const Offset(10, 16), 2.2, stroke);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.icon != icon || old.color != color;
}
