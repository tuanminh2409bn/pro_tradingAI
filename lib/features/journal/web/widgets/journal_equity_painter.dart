import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class JournalEquityPainter extends CustomPainter {
  final List<double> data;
  JournalEquityPainter({required List<double> data})
    : data = List.unmodifiable(data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty ||
        data.any((value) => !value.isFinite) ||
        !size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0 ||
        size.height <= 0) {
      return;
    }
    final paint = Paint()
      ..color = const Color(0xFF3772FF)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    if (data.length == 1) {
      paint.style = PaintingStyle.fill;
      canvas.drawCircle(Offset(size.width / 2, size.height / 2), 3, paint);
      return;
    }
    final minValue = data.reduce(math.min);
    final range = data.reduce(math.max) - minValue;
    if (!range.isFinite) return;
    final dx = size.width / (data.length - 1);
    final path = Path();
    for (var index = 0; index < data.length; index++) {
      final y = range == 0
          ? size.height / 2
          : size.height * (1 - (data[index] - minValue) / range);
      if (index == 0) {
        path.moveTo(0, y);
      } else {
        path.lineTo(index * dx, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant JournalEquityPainter oldDelegate) =>
      !listEquals(data, oldDelegate.data);
}
