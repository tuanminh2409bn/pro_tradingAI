import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../../data/models/trading_models.dart';
import 'dart:math' as math;

class KineticChart extends StatelessWidget {
  final TradingSignal? signal;
  final List<Candle> candles;
  
  const KineticChart({
    super.key, 
    this.signal,
    this.candles = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: const Color(0xFF0b0e11),
      child: Stack(
        children: [
          // Lớp nền & Lưới
          CustomPaint(
            painter: _ChartBackgroundPainter(),
            size: Size.infinite,
          ),
          
          // Lớp Vẽ Nến
          if (candles.isNotEmpty)
            CustomPaint(
              painter: _CandlePainter(candles: candles),
              size: Size.infinite,
            ),
          
          // Lớp Vẽ 5 Layer Chính (Signals & Markers)
          CustomPaint(
            painter: _KineticPainter(signal: signal),
            size: Size.infinite,
          ),
        ],
      ),
    );
  }
}

class _ChartBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF434655).withOpacity(0.1)
      ..strokeWidth = 1.0;

    double step = 40.0;
    for (double i = 0; i < size.width; i += step) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += step) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class _CandlePainter extends CustomPainter {
  final List<Candle> candles;
  _CandlePainter({required this.candles});

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;

    double maxHigh = candles.map((c) => c.high).reduce(math.max);
    double minLow = candles.map((c) => c.low).reduce(math.min);
    double priceRange = maxHigh - minLow;
    if (priceRange == 0) priceRange = 1;

    double candleWidth = size.width / candles.length;
    double padding = candleWidth * 0.2;

    for (int i = 0; i < candles.length; i++) {
      final candle = candles[i];
      double x = i * candleWidth + candleWidth / 2;

      double getY(double price) {
        return size.height - ((price - minLow) / priceRange) * size.height;
      }

      final openY = getY(candle.open);
      final closeY = getY(candle.close);
      final highY = getY(candle.high);
      final lowY = getY(candle.low);

      Color candleColor = candle.close >= candle.open ? AppColors.primary : AppColors.bear;
      
      final paint = Paint()
        ..color = candleColor
        ..strokeWidth = 1.0
        ..style = PaintingStyle.fill;

      // Draw wick
      canvas.drawLine(Offset(x, highY), Offset(x, lowY), paint);

      // Draw body
      double bodyTop = math.min(openY, closeY);
      double bodyBottom = math.max(openY, closeY);
      double bodyHeight = math.max(1.0, bodyBottom - bodyTop);
      
      canvas.drawRect(
        Rect.fromLTWH(x - (candleWidth / 2 - padding), bodyTop, candleWidth - 2 * padding, bodyHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CandlePainter oldDelegate) => oldDelegate.candles != candles;
}

class _KineticPainter extends CustomPainter {
  final TradingSignal? signal;
  _KineticPainter({this.signal});

  @override
  void paint(Canvas canvas, Size size) {
    if (signal == null) return;

    final structurePaint = Paint()
      ..color = AppColors.primary.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    
    _drawDashedLine(canvas, Offset(40, size.height * 0.25), Offset(size.width - 40, size.height * 0.25), structurePaint);

    final redZonePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [AppColors.bear.withOpacity(0.1), Colors.transparent],
      ).createShader(Rect.fromLTWH(size.width * 0.6, 0, size.width * 0.4, size.height * 0.3));
    
    canvas.drawRect(Rect.fromLTWH(size.width * 0.6, 0, size.width * 0.4, size.height * 0.3), redZonePaint);

    _drawExecutionLines(canvas, size);
    _drawMarkers(canvas, size);
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const dashWidth = 8.0;
    const dashSpace = 4.0;
    double distance = (p2 - p1).distance;
    double currentDist = 0;
    while (currentDist < distance) {
      canvas.drawLine(
        p1 + (p2 - p1) * (currentDist / distance),
        p1 + (p2 - p1) * ((currentDist + dashWidth) / distance),
        paint,
      );
      currentDist += dashWidth + dashSpace;
    }
  }

  void _drawExecutionLines(Canvas canvas, Size size) {
    final entryPaint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2.0;
    double entryY = size.height * 0.6;
    canvas.drawLine(Offset(0, entryY), Offset(size.width, entryY), entryPaint);
    _drawLabel(canvas, Offset(size.width - 80, entryY - 10), 'ENTRY: ${signal?.entryPrice}', AppColors.primary, Colors.black);

    final slPaint = Paint()
      ..color = AppColors.bear
      ..strokeWidth = 1.0;
    double slY = size.height * 0.75;
    _drawDashedLine(canvas, Offset(0, slY), Offset(size.width, slY), slPaint);
    _drawLabel(canvas, Offset(size.width - 80, slY - 10), 'SL: ${signal?.slPrice}', AppColors.bear, Colors.white);

    final tpPaint = Paint()
      ..color = const Color(0xFF3772FF)
      ..strokeWidth = 1.0;
    double tpY = size.height * 0.35;
    _drawDashedLine(canvas, Offset(0, tpY), Offset(size.width, tpY), tpPaint);
    _drawLabel(canvas, Offset(size.width - 80, tpY - 10), 'TP: ${signal?.tpPrices.first}', const Color(0xFF3772FF), Colors.white);
  }

  void _drawMarkers(Canvas canvas, Size size) {
    _drawLabel(canvas, Offset(size.width * 0.2, size.height * 0.4), 'DIVERGENCE', AppColors.secondary, Colors.white);
    _drawLabel(canvas, Offset(size.width * 0.7, size.height * 0.65), 'LIQUIDITY TRAP', AppColors.primary, Colors.black);
  }

  void _drawLabel(Canvas canvas, Offset offset, String text, Color bgColor, Color textColor) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final rect = Rect.fromLTWH(offset.dx - 4, offset.dy - 2, textPainter.width + 8, textPainter.height + 4);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), Paint()..color = bgColor);
    textPainter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _KineticPainter oldDelegate) => oldDelegate.signal != signal;
}
