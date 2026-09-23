import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Ring-of-dots for hostless events. Painted so it cannot fail as a missing asset.
class HostlessMark extends StatelessWidget {
  final double size;
  final Color color;

  const HostlessMark({
    super.key,
    this.size = 20,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _HostlessMarkPainter(color),
    );
  }
}

class _HostlessMarkPainter extends CustomPainter {
  final Color color;

  _HostlessMarkPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final center = Offset(size.width / 2, size.height / 2);
    final orbit = size.shortestSide * 0.32;
    final dotRadius = size.shortestSide * 0.14;
    for (var i = 0; i < 6; i++) {
      final angle = -math.pi / 2 + i * math.pi / 3;
      canvas.drawCircle(
        Offset(
          center.dx + orbit * math.cos(angle),
          center.dy + orbit * math.sin(angle),
        ),
        dotRadius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HostlessMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}
