import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../../data/models/trading_models.dart';
import 'dart:math' as math;

class KineticChart extends StatefulWidget {
  final TradingSignal? signal;
  final List<Candle> candles;

  const KineticChart({
    super.key,
    this.signal,
    this.candles = const [],
  });

  @override
  State<KineticChart> createState() => _KineticChartState();
}

class _KineticChartState extends State<KineticChart> {
  double _scaleX = 1.0;
  double _offsetX = 0.0;

  double _previousScale = 1.0;
  double _previousOffset = 0.0;

  @override
  Widget build(BuildContext context) {
    if (widget.candles.isEmpty) {
      return Container(
        color: const Color(0xFF0b0e11),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppColors.primary),
              SizedBox(height: 20),
              Text(
                'WAITING FOR MARKET DATA...',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Connecting to Global Data Engine...',
                style: TextStyle(color: Colors.white24, fontSize: 10),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: const Color(0xFF0b0e11),
      child: Stack(
        children: [
          // Lớp nền & Lưới + Lớp Vẽ Nến + Lớp Vẽ 5 Layer Chính
          GestureDetector(
            onScaleStart: (details) {
              _previousScale = _scaleX;
              _previousOffset = _offsetX;
            },
            onScaleUpdate: (details) {
              setState(() {
                _scaleX = (_previousScale * details.scale).clamp(0.2, 10.0);
                _offsetX = _previousOffset + details.focalPointDelta.dx;
              });
            },
            child: CustomPaint(
              painter: _ChartPainter(
                candles: widget.candles,
                signal: widget.signal,
                scaleX: _scaleX,
                offsetX: _offsetX,
              ),
              size: Size.infinite,
            ),
          ),
          // Nút reset view
          Positioned(
            bottom: 40,
            right: 80,
            child: IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white54),
              onPressed: () {
                setState(() {
                  _scaleX = 1.0;
                  _offsetX = 0.0;
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<Candle> candles;
  final TradingSignal? signal;
  final double scaleX;
  final double offsetX;

  static const double yAxisWidth = 60.0;
  static const double xAxisHeight = 30.0;
  static const double baseCandleWidth = 8.0;
  static const double candleSpacing = 2.0;

  _ChartPainter({
    required this.candles,
    required this.signal,
    required this.scaleX,
    required this.offsetX,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) {
      print('KineticChart: Waiting for candles...');
      return;
    }
    print('KineticChart: Attempting to paint ${candles.length} candles. Last Price: ${candles.last.close}');

    final chartRect = Rect.fromLTWH(0, 0, size.width - yAxisWidth, size.height - xAxisHeight);
    
    // Khung vẽ chính, không lấn sang trục X và Y
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final effectiveCandleWidth = baseCandleWidth * scaleX;
    final effectiveSpacing = candleSpacing * scaleX;
    final totalCandleWidth = effectiveCandleWidth + effectiveSpacing;

    // Tính toán số nến hiển thị
    final maxVisibleCandles = (chartRect.width / totalCandleWidth).ceil() + 1;
    
    // OffsetX < 0 nghĩa là kéo sang trái. Nến mới nhất nằm ở bên phải cùng.
    final rightOffset = offsetX; 
    
    // Tính toán index của nến
    int endIndex = candles.length - 1 - (rightOffset / totalCandleWidth).floor();
    if (endIndex >= candles.length) endIndex = candles.length - 1;
    int startIndex = endIndex - maxVisibleCandles;
    if (startIndex < 0) startIndex = 0;
    if (endIndex < 0) endIndex = 0;

    if (startIndex >= candles.length) return;

    double maxPrice = -double.infinity;
    double minPrice = double.infinity;

    for (int i = startIndex; i <= endIndex; i++) {
      if (candles[i].high > maxPrice) maxPrice = candles[i].high;
      if (candles[i].low < minPrice) minPrice = candles[i].low;
    }

    if (maxPrice == -double.infinity || minPrice == double.infinity) {
      maxPrice = 100;
      minPrice = 0;
    }

    double priceRange = maxPrice - minPrice;
    if (priceRange == 0) priceRange = 1;
    
    // Thêm padding cho Y axis
    maxPrice += priceRange * 0.1;
    minPrice -= priceRange * 0.1;
    priceRange = maxPrice - minPrice;

    double getY(double price) {
      return chartRect.height - ((price - minPrice) / priceRange) * chartRect.height;
    }

    double getX(int index) {
      int reversedIndex = candles.length - 1 - index;
      return chartRect.width - (reversedIndex * totalCandleWidth) - (totalCandleWidth / 2) + rightOffset;
    }

    // 1. VẼ NỀN & LƯỚI (Grid)
    _drawGrid(canvas, chartRect, maxPrice, minPrice, priceRange, getY);

    canvas.save();
    canvas.clipRect(chartRect); // Clip riêng phần biểu đồ nến

    // 2. VẼ LAYER 1 & 5 (Structures & Ghost Overlay)
    _drawBackgroundLayers(canvas, chartRect, size, getY);

    // 3. VẼ LAYER 3 (Candlestick Mapping)
    for (int i = startIndex; i <= endIndex; i++) {
      final candle = candles[i];
      final x = getX(i);

      if (x < -totalCandleWidth || x > chartRect.width + totalCandleWidth) continue;

      final openY = getY(candle.open);
      final closeY = getY(candle.close);
      final highY = getY(candle.high);
      final lowY = getY(candle.low);

      // Thêm Logic "Color Mapping" Cyberpunk
      // Giả lập logic AI trả về: Nến có biên độ bất thường thì đổi màu
      bool isVolatile = (candle.high - candle.low) / candle.open > 0.005; // 0.5% fluctuation
      
      Color candleColor;
      if (isVolatile) {
        candleColor = candle.close >= candle.open ? const Color(0xFF8A2BE2) : const Color(0xFFBA55D3); // Nến tím
      } else {
        candleColor = candle.close >= candle.open ? AppColors.primary : AppColors.bear;
      }
      
      final paint = Paint()
        ..color = candleColor
        ..strokeWidth = 1.5 * scaleX.clamp(0.5, 2.0)
        ..style = PaintingStyle.fill;

      // Vẽ râu nến (Wick)
      canvas.drawLine(Offset(x, highY), Offset(x, lowY), paint);

      // Vẽ thân nến (Body)
      double bodyTop = math.min(openY, closeY);
      double bodyBottom = math.max(openY, closeY);
      double bodyHeight = math.max(1.0, bodyBottom - bodyTop);
      
      canvas.drawRect(
        Rect.fromLTWH(x - (effectiveCandleWidth / 2), bodyTop, effectiveCandleWidth, bodyHeight),
        paint,
      );
    }

    // 4. VẼ LAYER 2 & 4 (Execution & Traps)
    if (signal != null) {
      _drawExecutionLayers(canvas, chartRect, signal!, getY);
    }

    canvas.restore(); // Kết thúc vùng clip biểu đồ nến

    // 5. VẼ TRỤC Y (Price)
    _drawYAxis(canvas, size, chartRect, maxPrice, minPrice, getY);

    // 6. VẼ TRỤC X (Time)
    _drawXAxis(canvas, size, chartRect, startIndex, endIndex, getX);
  }

  void _drawGrid(Canvas canvas, Rect chartRect, double maxPrice, double minPrice, double priceRange, double Function(double) getY) {
    final gridPaint = Paint()
      ..color = const Color(0xFF434655).withOpacity(0.1)
      ..strokeWidth = 1.0;

    int gridLinesY = 8;
    double priceStep = priceRange / gridLinesY;
    for (int i = 0; i <= gridLinesY; i++) {
      double price = minPrice + i * priceStep;
      double y = getY(price);
      canvas.drawLine(Offset(0, y), Offset(chartRect.width, y), gridPaint);
    }

    double xStep = chartRect.width / 6;
    for (int i = 0; i <= 6; i++) {
      double x = i * xStep;
      canvas.drawLine(Offset(x, 0), Offset(x, chartRect.height), gridPaint);
    }
  }

  void _drawYAxis(Canvas canvas, Size size, Rect chartRect, double maxPrice, double minPrice, double Function(double) getY) {
    final bgPaint = Paint()..color = const Color(0xFF0b0e11);
    canvas.drawRect(Rect.fromLTWH(chartRect.width, 0, yAxisWidth, size.height), bgPaint);

    canvas.drawLine(Offset(chartRect.width, 0), Offset(chartRect.width, chartRect.height), Paint()..color = Colors.white10);

    int gridLinesY = 8;
    double priceStep = (maxPrice - minPrice) / gridLinesY;
    for (int i = 0; i <= gridLinesY; i++) {
      double price = minPrice + i * priceStep;
      double y = getY(price);
      
      _drawText(canvas, price.toStringAsFixed(3), Offset(chartRect.width + 5, y - 6), Colors.white54, 10);
    }
    
    // Current price indicator
    if (candles.isNotEmpty) {
      double lastPrice = candles.last.close;
      double lastY = getY(lastPrice);
      Color pColor = candles.last.close >= candles.last.open ? AppColors.primary : AppColors.bear;
      
      canvas.drawRect(Rect.fromLTWH(chartRect.width, lastY - 10, yAxisWidth, 20), Paint()..color = pColor);
      _drawText(canvas, lastPrice.toStringAsFixed(3), Offset(chartRect.width + 5, lastY - 6), Colors.white, 10, fontWeight: FontWeight.bold);
      
      final dashedPaint = Paint()..color = pColor..strokeWidth = 1.0;
      _drawDashedLine(canvas, Offset(0, lastY), Offset(chartRect.width, lastY), dashedPaint);
    }
  }

  void _drawXAxis(Canvas canvas, Size size, Rect chartRect, int startIndex, int endIndex, double Function(int) getX) {
    final bgPaint = Paint()..color = const Color(0xFF0b0e11);
    canvas.drawRect(Rect.fromLTWH(0, chartRect.height, size.width, xAxisHeight), bgPaint);

    canvas.drawLine(Offset(0, chartRect.height), Offset(chartRect.width, chartRect.height), Paint()..color = Colors.white10);

    int step = ((endIndex - startIndex) / 5).ceil();
    if (step < 1) step = 1;

    for (int i = startIndex; i <= endIndex; i += step) {
      double x = getX(i);
      if (x < 0 || x > chartRect.width) continue;
      
      DateTime time = candles[i].timestamp;
      String hh = time.hour.toString().padLeft(2, '0');
      String mm = time.minute.toString().padLeft(2, '0');
      
      _drawText(canvas, '$hh:$mm', Offset(x - 15, chartRect.height + 8), Colors.white54, 10);
      
      canvas.drawLine(Offset(x, chartRect.height), Offset(x, chartRect.height + 4), Paint()..color = Colors.white54);
    }
  }

  void _drawBackgroundLayers(Canvas canvas, Rect chartRect, Size size, double Function(double) getY) {
    // Red Zone (Ghost Overlay - Phase Tracker) Layer 5
    final redZonePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppColors.bear.withOpacity(0.15), Colors.transparent],
      ).createShader(Rect.fromLTWH(chartRect.width * 0.5, 0, chartRect.width * 0.3, chartRect.height * 0.4));
    
    canvas.drawRect(Rect.fromLTWH(chartRect.width * 0.5, 0, chartRect.width * 0.3, chartRect.height * 0.4), redZonePaint);
    _drawLabel(canvas, Offset(chartRect.width * 0.5 + 10, 20), 'DANGER ZONE - HIGH VOL', AppColors.bear.withOpacity(0.5), Colors.white);
    
    // Liquidity Trap Box (Solid Box Layer 1)
    final trapPaint = Paint()
      ..color = const Color(0xFFF0E68C).withOpacity(0.05)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(chartRect.width * 0.2, chartRect.height * 0.7, chartRect.width * 0.2, chartRect.height * 0.2), trapPaint);
    
    final trapBorderPaint = Paint()
      ..color = const Color(0xFFF0E68C).withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRect(Rect.fromLTWH(chartRect.width * 0.2, chartRect.height * 0.7, chartRect.width * 0.2, chartRect.height * 0.2), trapBorderPaint);
    _drawLabel(canvas, Offset(chartRect.width * 0.2 + 5, chartRect.height * 0.7 + 5), '\$\$\$ LIQUIDITY', const Color(0xFFF0E68C).withOpacity(0.8), Colors.black);
  }

  void _drawExecutionLayers(Canvas canvas, Rect chartRect, TradingSignal signal, double Function(double) getY) {
    final entryY = getY(signal.entryPrice);
    final slY = getY(signal.slPrice);
    final tpY = getY(signal.tpPrices.first);

    // Entry
    if (entryY > 0 && entryY < chartRect.height) {
      final entryPaint = Paint()..color = AppColors.primary..strokeWidth = 1.5;
      canvas.drawLine(Offset(0, entryY), Offset(chartRect.width, entryY), entryPaint);
      _drawBadge(canvas, Offset(chartRect.width - 60, entryY - 10), 'ENTRY', '${signal.probability}%', AppColors.primary);
    }

    // Stop Loss
    if (slY > 0 && slY < chartRect.height) {
      final slPaint = Paint()..color = AppColors.bear..strokeWidth = 1.5;
      _drawDashedLine(canvas, Offset(0, slY), Offset(chartRect.width, slY), slPaint);
      _drawLabel(canvas, Offset(chartRect.width - 40, slY - 8), 'SL', AppColors.bear, Colors.white);
    }

    // Take Profit
    if (tpY > 0 && tpY < chartRect.height) {
      final tpPaint = Paint()..color = const Color(0xFF3772FF)..strokeWidth = 1.5;
      _drawDashedLine(canvas, Offset(0, tpY), Offset(chartRect.width, tpY), tpPaint);
      _drawLabel(canvas, Offset(chartRect.width - 40, tpY - 8), 'TP', const Color(0xFF3772FF), Colors.white);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const dashWidth = 5.0;
    const dashSpace = 5.0;
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

  void _drawLabel(Canvas canvas, Offset offset, String text, Color bgColor, Color textColor) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: textColor, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final rect = Rect.fromLTWH(offset.dx - 4, offset.dy - 2, textPainter.width + 8, textPainter.height + 4);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), Paint()..color = bgColor);
    textPainter.paint(canvas, offset);
  }

  void _drawBadge(Canvas canvas, Offset offset, String title, String prob, Color color) {
    // Vẽ Probability Badge Layer 4
    final textPainter = TextPainter(
      text: TextSpan(
        text: '$title | $prob',
        style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final rect = Rect.fromLTWH(offset.dx - 6, offset.dy - 4, textPainter.width + 12, textPainter.height + 8);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), Paint()..color = color);
    textPainter.paint(canvas, offset);
  }

  void _drawText(Canvas canvas, String text, Offset offset, Color color, double fontSize, {FontWeight fontWeight = FontWeight.normal}) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fontSize, fontWeight: fontWeight),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) {
    return oldDelegate.candles != candles || 
           oldDelegate.signal != signal || 
           oldDelegate.scaleX != scaleX || 
           oldDelegate.offsetX != offsetX;
  }
}
