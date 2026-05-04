import 'package:flutter/material.dart';

class ArcGaugePainter extends CustomPainter {
  final double ratio;
  final double strokeWidth;
  final Color  color;
  final Color  trackColor;

  const ArcGaugePainter({
    required this.ratio,
    required this.strokeWidth,
    required this.color,
    this.trackColor = const Color(0xFFE0E0E0),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center     = Offset(size.width / 2, size.height / 2);
    final radius     = size.width / 2 - strokeWidth / 2;
    const startAngle = -2.356; // -135°
    const sweepFull  =  4.712; // 270°

    final trackPaint = Paint()
      ..color      = trackColor
      ..strokeWidth = strokeWidth
      ..style      = PaintingStyle.stroke
      ..strokeCap  = StrokeCap.round;

    final valuePaint = Paint()
      ..color      = color
      ..strokeWidth = strokeWidth
      ..style      = PaintingStyle.stroke
      ..strokeCap  = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle, sweepFull, false, trackPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle, sweepFull * ratio.clamp(0.0, 1.0), false, valuePaint,
    );
  }

  @override
  bool shouldRepaint(ArcGaugePainter old) => old.ratio != ratio;
}
