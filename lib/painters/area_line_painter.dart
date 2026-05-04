import 'package:flutter/material.dart';

class AreaLinePainter extends CustomPainter {
  final List<double> data;
  final double       maxVal;
  final Color        lineColor;

  const AreaLinePainter({
    required this.data,
    required this.maxVal,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final n    = data.length;
    final step = size.width / (n - 1);

    final linePaint = Paint()
      ..color      = lineColor
      ..strokeWidth = 2.0
      ..style      = PaintingStyle.stroke
      ..strokeCap  = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;

    double y(int i) =>
        size.height * (1 - (data[i] / maxVal).clamp(0.0, 1.0));

    final linePath = Path()..moveTo(0, y(0));
    final fillPath = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, y(0));

    for (int i = 1; i < n; i++) {
      linePath.lineTo(i * step, y(i));
      fillPath.lineTo(i * step, y(i));
    }

    fillPath
      ..lineTo((n - 1) * step, size.height)
      ..close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(linePath, linePaint);

    final dotPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset((n - 1) * step, y(n - 1)), 4, dotPaint);
  }

  @override
  bool shouldRepaint(AreaLinePainter old) => old.data != data;
}
