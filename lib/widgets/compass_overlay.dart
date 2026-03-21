import 'dart:math';

import 'package:flutter/material.dart';

class CompassOverlay extends StatelessWidget {
  final double heading;

  const CompassOverlay({super.key, required this.heading});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: SizedBox(
          width: 220,
          height: 220,
          child: CustomPaint(painter: _CompassPainter(heading: heading)),
        ),
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  final double heading;

  _CompassPainter({required this.heading});

  static const _cardinals = ['N', 'E', 'S', 'W'];
  static const _intercardinals = ['NE', 'SE', 'SW', 'NW'];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final headingRad = -heading * pi / 180;

    // Background circle
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );

    // Outer ring
    canvas.drawCircle(
      center,
      radius - 1,
      Paint()
        ..color = Colors.white24
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(headingRad);

    // Tick marks — 72 ticks for every 5°
    for (int i = 0; i < 72; i++) {
      final angle = i * 5 * pi / 180;
      final isCardinal = i % 18 == 0; // 0, 90, 180, 270
      final isIntercardinal = i % 9 == 0 && !isCardinal; // 45, 135, 225, 315
      final isMajor =
          i % 3 == 0 && !isCardinal && !isIntercardinal; // every 15°

      double innerR;
      double strokeW;
      Color color;

      if (isCardinal) {
        innerR = radius - 18;
        strokeW = 2.5;
        color = Colors.white70;
      } else if (isIntercardinal) {
        innerR = radius - 14;
        strokeW = 1.8;
        color = Colors.white38;
      } else if (isMajor) {
        innerR = radius - 10;
        strokeW = 1.2;
        color = Colors.white24;
      } else {
        innerR = radius - 6;
        strokeW = 0.8;
        color = Colors.white12;
      }

      final outerR = radius - 3;
      canvas.drawLine(
        Offset(innerR * cos(angle - pi / 2), innerR * sin(angle - pi / 2)),
        Offset(outerR * cos(angle - pi / 2), outerR * sin(angle - pi / 2)),
        Paint()
          ..color = color
          ..strokeWidth = strokeW
          ..strokeCap = StrokeCap.round,
      );
    }

    // North pointer triangle
    final pointerPath = Path()
      ..moveTo(0, -(radius - 30))
      ..lineTo(-7, -(radius - 42))
      ..lineTo(7, -(radius - 42))
      ..close();
    canvas.drawPath(pointerPath, Paint()..color = Colors.orangeAccent);

    // Cardinal labels
    final labelRadius = radius - 48;
    for (int i = 0; i < 4; i++) {
      final angle = i * pi / 2 - pi / 2; // N=top, E=right, S=bottom, W=left
      final isNorth = i == 0;
      final tp = TextPainter(
        text: TextSpan(
          text: _cardinals[i],
          style: TextStyle(
            color: isNorth ? Colors.orangeAccent : Colors.white,
            fontSize: isNorth ? 22 : 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final x = labelRadius * cos(angle) - tp.width / 2;
      final y = labelRadius * sin(angle) - tp.height / 2;

      canvas.save();
      canvas.translate(x + tp.width / 2, y + tp.height / 2);
      canvas.rotate(-headingRad); // Counter-rotate so text stays upright
      canvas.translate(-tp.width / 2, -tp.height / 2);
      tp.paint(canvas, Offset.zero);
      canvas.restore();
    }

    // Intercardinal labels
    final interRadius = radius - 48;
    for (int i = 0; i < 4; i++) {
      final angle = i * pi / 2 + pi / 4 - pi / 2; // NE, SE, SW, NW
      final tp = TextPainter(
        text: TextSpan(
          text: _intercardinals[i],
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final x = interRadius * cos(angle) - tp.width / 2;
      final y = interRadius * sin(angle) - tp.height / 2;

      canvas.save();
      canvas.translate(x + tp.width / 2, y + tp.height / 2);
      canvas.rotate(-headingRad);
      canvas.translate(-tp.width / 2, -tp.height / 2);
      tp.paint(canvas, Offset.zero);
      canvas.restore();
    }

    canvas.restore();

    // Center crosshair dot
    canvas.drawCircle(center, 3, Paint()..color = Colors.white54);
  }

  @override
  bool shouldRepaint(_CompassPainter oldDelegate) =>
      oldDelegate.heading != heading;
}
