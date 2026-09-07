import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import '../../../../core/constants/colors.dart';
import '../../../../data/models/trading_models.dart';
import 'chart_tools_sidebar.dart';
import 'chart_price_window.dart';
import 'dart:math' as math;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Drawing Object Models ───────────────────────────────────
enum DrawingType {
  trendLine,
  horizontalLine,
  verticalLine,
  rectangle,
  fibonacci,
  text,
  ruler,
}

abstract class DrawingObject {
  final String id;
  DrawingType get type;
  DrawingObject(this.id);
}

class TrendLineDrawing extends DrawingObject {
  Offset p1; // canvas-fraction coords (0..1 in both axes mapped to price/index)
  Offset p2;
  bool isComplete;
  TrendLineDrawing({
    required String id,
    required this.p1,
    required this.p2,
    this.isComplete = false,
  }) : super(id);
  @override
  DrawingType get type => DrawingType.trendLine;
}

class HorizontalLineDrawing extends DrawingObject {
  double price;
  HorizontalLineDrawing({required String id, required this.price}) : super(id);
  @override
  DrawingType get type => DrawingType.horizontalLine;
}

class VerticalLineDrawing extends DrawingObject {
  double xFraction; // 0..1 across chart width
  VerticalLineDrawing({required String id, required this.xFraction})
    : super(id);
  @override
  DrawingType get type => DrawingType.verticalLine;
}

class RectangleDrawing extends DrawingObject {
  Offset p1;
  Offset p2;
  bool isComplete;
  RectangleDrawing({
    required String id,
    required this.p1,
    required this.p2,
    this.isComplete = false,
  }) : super(id);
  @override
  DrawingType get type => DrawingType.rectangle;
}

class FibonacciDrawing extends DrawingObject {
  Offset p1;
  Offset p2;
  bool isComplete;
  static const List<double> levels = [
    0.0,
    0.236,
    0.382,
    0.5,
    0.618,
    0.786,
    1.0,
  ];
  static const List<String> labels = [
    '0%',
    '23.6%',
    '38.2%',
    '50%',
    '61.8%',
    '78.6%',
    '100%',
  ];
  FibonacciDrawing({
    required String id,
    required this.p1,
    required this.p2,
    this.isComplete = false,
  }) : super(id);
  @override
  DrawingType get type => DrawingType.fibonacci;
}

class TextDrawing extends DrawingObject {
  Offset position;
  String text;
  TextDrawing({required String id, required this.position, required this.text})
    : super(id);
  @override
  DrawingType get type => DrawingType.text;
}

class RulerDrawing extends DrawingObject {
  Offset p1;
  Offset p2;
  bool isComplete;
  RulerDrawing({
    required String id,
    required this.p1,
    required this.p2,
    this.isComplete = false,
  }) : super(id);
  @override
  DrawingType get type => DrawingType.ruler;
}

// ─── Coordinate helpers (shared between state & painter) ─────
class _ChartCoords {
  final List<Candle> candles;
  final double scaleX;
  final double offsetX;

  /// >1 zooms into price (narrower window); <1 zooms out.
  final double scaleY;

  /// Shifts the visible price window (positive = view higher prices).
  final double priceOffset;
  final Size size;

  static const double yAxisWidth = 60.0;
  static const double xAxisHeight = 30.0;
  static const double baseCandleWidth = 8.0;
  static const double candleSpacing = 2.0;
  static const double rightMargin = 120.0;

  late final Rect chartRect;
  late final Rect yAxisRect;
  late final double effectiveCandleWidth;
  late final double effectiveSpacing;
  late final double totalCandleWidth;
  late final int startIndex;
  late final int endIndex;
  late final double maxPrice;
  late final double minPrice;
  late final double priceRange;

  /// Auto-fit range (before scaleY / priceOffset) — used for pan math.
  late final double autoPriceRange;

  _ChartCoords({
    required this.candles,
    required this.scaleX,
    required this.offsetX,
    required this.size,
    this.scaleY = 1.0,
    this.priceOffset = 0.0,
  }) {
    chartRect = Rect.fromLTWH(
      0,
      0,
      size.width - yAxisWidth,
      size.height - xAxisHeight,
    );
    yAxisRect = Rect.fromLTWH(chartRect.width, 0, yAxisWidth, chartRect.height);
    effectiveCandleWidth = baseCandleWidth * scaleX;
    effectiveSpacing = candleSpacing * scaleX;
    totalCandleWidth = effectiveCandleWidth + effectiveSpacing;

    final double revAtLeft =
        (chartRect.width - rightMargin + offsetX) / totalCandleWidth;
    final double revAtRight =
        (chartRect.width - rightMargin + offsetX - chartRect.width) /
        totalCandleWidth;

    startIndex = (candles.length - 1 - revAtLeft.ceil() - 2).clamp(
      0,
      candles.length - 1,
    );
    endIndex = (candles.length - 1 - revAtRight.floor() + 2).clamp(
      0,
      candles.length - 1,
    );

    double mx = -double.infinity, mn = double.infinity;
    for (int i = startIndex; i <= endIndex; i++) {
      if (candles[i].high > mx) mx = candles[i].high;
      if (candles[i].low < mn) mn = candles[i].low;
    }
    if (mx == -double.infinity) {
      mx = 100;
      mn = 0;
    }
    double rng = mx - mn;
    if (rng == 0) rng = 1;
    mx += rng * 0.1;
    mn -= rng * 0.1;
    autoPriceRange = mx - mn;

    final window = computePriceWindow(
      autoMin: mn,
      autoMax: mx,
      scaleY: scaleY,
      priceOffset: priceOffset,
    );
    maxPrice = window.max;
    minPrice = window.min;
    priceRange = window.range;
  }

  bool isOnYAxis(Offset local) => yAxisRect.contains(local);

  double getY(double price) =>
      chartRect.height - ((price - minPrice) / priceRange) * chartRect.height;

  double getX(int index) {
    int rev = candles.length - 1 - index;
    return (chartRect.width - rightMargin) - (rev * totalCandleWidth) + offsetX;
  }

  /// Convert canvas pixel position to price
  double pixelToPrice(double y) =>
      maxPrice - (y / chartRect.height) * priceRange;

  /// Convert canvas pixel position to x-fraction (0..1)
  double pixelToXFraction(double x) => x / chartRect.width;

  /// Convert x-fraction to pixel
  double xFractionToPixel(double frac) => frac * chartRect.width;

  /// Snap offset position to nearest OHLC if magnet mode
  Offset snapToOHLC(Offset pos) {
    if (candles.isEmpty) return pos;
    double minDist = double.infinity;
    Offset snapped = pos;
    for (int i = startIndex; i <= endIndex; i++) {
      final cx = getX(i);
      final dist = (cx - pos.dx).abs();
      if (dist < minDist) {
        minDist = dist;
        final c = candles[i];
        final prices = [c.open, c.high, c.low, c.close];
        double closestPrice = prices.reduce(
          (a, b) => (getY(a) - pos.dy).abs() < (getY(b) - pos.dy).abs() ? a : b,
        );
        snapped = Offset(cx, getY(closestPrice));
      }
    }
    return snapped;
  }
}

// ═══════════════════════════════════════════════════════════
// KINETIC CHART WIDGET
// ═══════════════════════════════════════════════════════════
class KineticChart extends StatefulWidget {
  final String symbol;
  final TradingSignal? signal;
  final List<Candle> candles;
  final ChartTool activeTool;

  const KineticChart({
    super.key,
    required this.symbol,
    this.signal,
    this.candles = const [],
    this.activeTool = ChartTool.pointer,
  });

  @override
  State<KineticChart> createState() => _KineticChartState();
}

class _KineticChartState extends State<KineticChart> {
  late SharedPreferences _prefs;
  bool _prefsInitialized = false;

  // Pan / Zoom state (X = time, Y = price)
  double _scaleX = 1.0;
  double _offsetX = 0.0;
  double _scaleY = 1.0;
  double _priceOffset = 0.0;
  double _previousScale = 1.0;
  double _previousScaleY = 1.0;
  double _dragStartOffset = 0.0;
  double _dragStartPriceOffset = 0.0;
  Offset _dragStartPoint = Offset.zero;
  bool _gestureOnYAxis = false;

  // Crosshair state
  Offset? _crosshairPos;
  Offset? _hoverPos;
  bool _showCrosshair = false;

  // Drawing state
  final List<DrawingObject> _drawings = [];
  DrawingObject? _inProgressDrawing;
  int _drawingCounter = 0;
  bool _showAISignal = true;

  String _newId() => 'draw_${_drawingCounter++}';

  @override
  void initState() {
    super.initState();
    _initPrefs();
  }

  Future<void> _initPrefs() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _prefsInitialized = true;
      _loadDrawings();
    } catch (e) {
      print('KineticChart: Error initializing prefs: $e');
    }
  }

  @override
  void didUpdateWidget(covariant KineticChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.symbol != widget.symbol && _prefsInitialized) {
      _loadDrawings();
    }
  }

  void _loadDrawings() {
    if (!_prefsInitialized) return;
    try {
      final jsonStr = _prefs.getString('drawings_${widget.symbol}');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        setState(() {
          _drawings.clear();
          _drawings.addAll(deserializeDrawings(jsonStr));
        });
      } else {
        setState(() {
          _drawings.clear();
        });
      }
    } catch (e) {
      print('KineticChart: Error loading drawings: $e');
    }
  }

  Future<void> _saveDrawings() async {
    if (!_prefsInitialized) return;
    try {
      final jsonStr = serializeDrawings(_drawings);
      await _prefs.setString('drawings_${widget.symbol}', jsonStr);
    } catch (e) {
      print('KineticChart: Error saving drawings: $e');
    }
  }

  void _zoom(double factor, Size size) {
    setState(() {
      final oldScale = _scaleX;
      _scaleX = (_scaleX * factor).clamp(0.2, 10.0);

      final chartWidth = size.width - _ChartCoords.yAxisWidth;
      final effectiveCandleWidth = _ChartCoords.baseCandleWidth * _scaleX;
      final effectiveSpacing = _ChartCoords.candleSpacing * _scaleX;
      final totalCandleWidth = effectiveCandleWidth + effectiveSpacing;

      final minOffset = -(chartWidth - _ChartCoords.rightMargin - 100.0);
      final maxOffset = (widget.candles.length - 1) * totalCandleWidth;

      final centerX = (chartWidth - _ChartCoords.rightMargin) / 2;
      _offsetX = (centerX - (centerX - _offsetX) * (_scaleX / oldScale)).clamp(
        minOffset,
        maxOffset,
      );
    });
  }

  void _zoomY(double factor) {
    setState(() {
      _scaleY = (_scaleY * factor).clamp(0.25, 8.0);
    });
  }

  void _resetView() {
    setState(() {
      _scaleX = 1.0;
      _offsetX = 0.0;
      _scaleY = 1.0;
      _priceOffset = 0.0;
    });
  }

  void _handlePointerSignal(PointerSignalEvent event, Size size) {
    if (event is! PointerScrollEvent) return;
    if (widget.activeTool != ChartTool.pointer &&
        widget.activeTool != ChartTool.crosshair) {
      return;
    }
    final onY = event.localPosition.dx >= size.width - _ChartCoords.yAxisWidth;
    final dy = event.scrollDelta.dy;
    if (dy == 0) return;
    final factor = dy > 0 ? 0.9 : 1.1;
    if (onY) {
      _zoomY(factor);
    } else {
      _zoom(factor, size);
    }
  }

  // Tool flags
  bool get _isMagnetOn => widget.activeTool == ChartTool.magnet;
  bool get _isDrawingTool =>
      widget.activeTool == ChartTool.trendLine ||
      widget.activeTool == ChartTool.horizontalLine ||
      widget.activeTool == ChartTool.verticalLine ||
      widget.activeTool == ChartTool.rectangle ||
      widget.activeTool == ChartTool.fibonacci ||
      widget.activeTool == ChartTool.ruler;

  Offset _processPos(Offset raw, _ChartCoords coords) {
    if (_isMagnetOn || widget.activeTool == ChartTool.magnet) {
      return coords.snapToOHLC(raw);
    }
    return raw;
  }

  void _handleTapDown(TapDownDetails d, _ChartCoords coords) {
    final pos = _processPos(d.localPosition, coords);
    if (!coords.chartRect.contains(pos)) return;

    final tool = widget.activeTool;

    if (tool == ChartTool.eraser) {
      _eraseAt(pos, coords);
      return;
    }

    if (tool == ChartTool.horizontalLine) {
      final price = coords.pixelToPrice(pos.dy);
      setState(
        () => _drawings.add(HorizontalLineDrawing(id: _newId(), price: price)),
      );
      _saveDrawings();
      return;
    }

    if (tool == ChartTool.verticalLine) {
      final frac = coords.pixelToXFraction(pos.dx);
      setState(
        () => _drawings.add(VerticalLineDrawing(id: _newId(), xFraction: frac)),
      );
      _saveDrawings();
      return;
    }

    if (tool == ChartTool.text) {
      _showTextInputDialog(pos, coords);
      return;
    }

    // Two-click tools: trendLine, rectangle, fibonacci, ruler
    if (_isDrawingTool) {
      if (_inProgressDrawing == null) {
        // Start new drawing
        DrawingObject newDrawing;
        switch (tool) {
          case ChartTool.trendLine:
            newDrawing = TrendLineDrawing(id: _newId(), p1: pos, p2: pos);
            break;
          case ChartTool.rectangle:
            newDrawing = RectangleDrawing(id: _newId(), p1: pos, p2: pos);
            break;
          case ChartTool.fibonacci:
            newDrawing = FibonacciDrawing(id: _newId(), p1: pos, p2: pos);
            break;
          case ChartTool.ruler:
            newDrawing = RulerDrawing(id: _newId(), p1: pos, p2: pos);
            break;
          default:
            return;
        }
        setState(() => _inProgressDrawing = newDrawing);
      } else {
        // Complete drawing
        _completeDragDrawing(pos);
      }
    }
  }

  void _completeDragDrawing(Offset pos) {
    final d = _inProgressDrawing;
    if (d == null) return;
    setState(() {
      if (d is TrendLineDrawing) {
        d.p2 = pos;
        d.isComplete = true;
      }
      if (d is RectangleDrawing) {
        d.p2 = pos;
        d.isComplete = true;
      }
      if (d is FibonacciDrawing) {
        d.p2 = pos;
        d.isComplete = true;
      }
      if (d is RulerDrawing) {
        d.p2 = pos;
        d.isComplete = true;
      }
      _drawings.add(d);
      _inProgressDrawing = null;
    });
    _saveDrawings();
  }

  void _handleMouseMove(PointerEvent e, _ChartCoords coords) {
    final pos = e.localPosition;
    if (coords.isOnYAxis(pos)) {
      setState(() {
        _hoverPos = pos;
        _showCrosshair = false;
        _crosshairPos = null;
      });
      return;
    }
    if (!coords.chartRect.contains(pos)) {
      if (_showCrosshair || _hoverPos != null) {
        setState(() {
          _showCrosshair = false;
          _hoverPos = pos;
        });
      }
      return;
    }

    final snapped = _processPos(pos, coords);

    setState(() {
      _hoverPos = pos;
      _crosshairPos = snapped;
      _showCrosshair =
          widget.activeTool == ChartTool.crosshair ||
          widget.activeTool == ChartTool.pointer ||
          _isDrawingTool;

      // Update in-progress drawing second point
      if (_inProgressDrawing != null) {
        final d = _inProgressDrawing!;
        if (d is TrendLineDrawing) d.p2 = snapped;
        if (d is RectangleDrawing) d.p2 = snapped;
        if (d is FibonacciDrawing) d.p2 = snapped;
        if (d is RulerDrawing) d.p2 = snapped;
      }
    });
  }

  void _eraseAt(Offset pos, _ChartCoords coords) {
    const hitRadius = 12.0;
    setState(() {
      _drawings.removeWhere((d) {
        if (d is HorizontalLineDrawing) {
          return (coords.getY(d.price) - pos.dy).abs() < hitRadius;
        }
        if (d is VerticalLineDrawing) {
          return (coords.xFractionToPixel(d.xFraction) - pos.dx).abs() <
              hitRadius;
        }
        if (d is TrendLineDrawing) {
          return _pointNearLine(pos, d.p1, d.p2, hitRadius);
        }
        if (d is RectangleDrawing) {
          final r = Rect.fromPoints(d.p1, d.p2).inflate(hitRadius);
          return r.contains(pos) &&
              !Rect.fromPoints(d.p1, d.p2).deflate(hitRadius).contains(pos);
        }
        if (d is FibonacciDrawing) {
          return _pointNearLine(pos, d.p1, d.p2, hitRadius);
        }
        if (d is RulerDrawing) {
          return _pointNearLine(pos, d.p1, d.p2, hitRadius);
        }
        if (d is TextDrawing) {
          return (d.position - pos).distance < hitRadius * 2;
        }
        return false;
      });
    });
    _saveDrawings();
  }

  bool _pointNearLine(Offset p, Offset a, Offset b, double radius) {
    final ab = b - a;
    final ap = p - a;
    final len2 = ab.distanceSquared;
    if (len2 == 0) return (p - a).distance < radius;
    final t = (ap.dx * ab.dx + ap.dy * ab.dy) / len2;
    final closest = a + ab * t.clamp(0.0, 1.0);
    return (p - closest).distance < radius;
  }

  void _showTextInputDialog(Offset pos, _ChartCoords coords) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1d20),
        title: const Text(
          'Add Text Label',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter label text...',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: AppColors.primary.withValues(alpha: 0.5),
              ),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.primary),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                setState(
                  () => _drawings.add(
                    TextDrawing(
                      id: _newId(),
                      position: pos,
                      text: controller.text.trim(),
                    ),
                  ),
                );
                _saveDrawings();
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text(
              'Add',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

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

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final coords = _ChartCoords(
          candles: widget.candles,
          scaleX: _scaleX,
          offsetX: _offsetX,
          scaleY: _scaleY,
          priceOffset: _priceOffset,
          size: size,
        );

        return Container(
          width: double.infinity,
          height: double.infinity,
          color: const Color(0xFF0b0e11),
          child: MouseRegion(
            cursor: _getCursor(coords),
            onHover: (e) => _handleMouseMove(e, coords),
            onExit: (_) => setState(() {
              _showCrosshair = false;
              _crosshairPos = null;
              _hoverPos = null;
            }),
            child: Listener(
              onPointerSignal: (e) => _handlePointerSignal(e, size),
              child: Stack(
                children: [
                  // Base chart gesture detector
                  GestureDetector(
                    onScaleStart: (d) {
                      if (widget.activeTool == ChartTool.pointer ||
                          widget.activeTool == ChartTool.crosshair) {
                        _previousScale = _scaleX;
                        _previousScaleY = _scaleY;
                        _dragStartOffset = _offsetX;
                        _dragStartPriceOffset = _priceOffset;
                        _dragStartPoint = d.localFocalPoint;
                        _gestureOnYAxis =
                            d.localFocalPoint.dx >=
                            size.width - _ChartCoords.yAxisWidth;
                      }
                    },
                    onScaleUpdate: (d) {
                      if (widget.activeTool != ChartTool.pointer &&
                          widget.activeTool != ChartTool.crosshair) {
                        return;
                      }
                      setState(() {
                        final double deltaY =
                            d.localFocalPoint.dy - _dragStartPoint.dy;
                        final chartHeight = math.max(
                          size.height - _ChartCoords.xAxisHeight,
                          1.0,
                        );

                        if (_gestureOnYAxis) {
                          // Drag price axis: compress/expand visible price range (TV-like).
                          final zoomFactor = math.exp(-deltaY / 180.0);
                          _scaleY = (_previousScaleY * zoomFactor).clamp(
                            0.25,
                            8.0,
                          );
                          if (d.pointerCount >= 2 && d.scale != 1.0) {
                            _scaleY = (_previousScaleY * d.scale).clamp(
                              0.25,
                              8.0,
                            );
                          }
                          return;
                        }

                        _scaleX = (_previousScale * d.scale).clamp(0.2, 10.0);

                        final chartWidth = size.width - _ChartCoords.yAxisWidth;
                        final effectiveCandleWidth =
                            _ChartCoords.baseCandleWidth * _scaleX;
                        final effectiveSpacing =
                            _ChartCoords.candleSpacing * _scaleX;
                        final totalCandleWidth =
                            effectiveCandleWidth + effectiveSpacing;

                        final minOffset =
                            -(chartWidth - _ChartCoords.rightMargin - 100.0);
                        final maxOffset =
                            (widget.candles.length - 1) * totalCandleWidth;

                        final double deltaX =
                            d.localFocalPoint.dx - _dragStartPoint.dx;
                        _offsetX = (_dragStartOffset + deltaX).clamp(
                          minOffset,
                          maxOffset,
                        );

                        // Vertical pan: drag down reveals lower prices (chart follows finger).
                        final visibleRange = coords.autoPriceRange / _scaleY;
                        _priceOffset =
                            _dragStartPriceOffset -
                            (deltaY / chartHeight) * visibleRange;
                      });
                    },
                    onTapDown: (d) => _handleTapDown(d, coords),
                    child: CustomPaint(
                      painter: _KineticChartPainter(
                        candles: widget.candles,
                        signal: _showAISignal ? widget.signal : null,
                        scaleX: _scaleX,
                        offsetX: _offsetX,
                        scaleY: _scaleY,
                        priceOffset: _priceOffset,
                        drawings: [
                          ..._drawings,
                          if (_inProgressDrawing != null) _inProgressDrawing!,
                        ],
                        crosshairPos: _showCrosshair ? _crosshairPos : null,
                        activeTool: widget.activeTool,
                      ),
                      size: Size.infinite,
                    ),
                  ),

                  // Overlay widgets from signal (Wyckoff phase, HTF trend)
                  if (widget.signal != null && _showAISignal)
                    ..._buildOverlayWidgets(widget.signal!),

                  // Reset + Zoom + Erase All buttons
                  Positioned(
                    bottom: 40,
                    right: 80,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1a1d20).withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Tooltip(
                            message: 'Zoom In',
                            child: IconButton(
                              icon: const Text(
                                '+',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              onPressed: () => _zoom(1.25, size),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                            ),
                          ),
                          Tooltip(
                            message: 'Zoom Out',
                            child: IconButton(
                              icon: const Text(
                                '−',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              onPressed: () => _zoom(0.8, size),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                            ),
                          ),
                          const Divider(color: Colors.white10, height: 8),
                          Tooltip(
                            message: 'Reset View',
                            child: IconButton(
                              icon: const Icon(
                                Icons.refresh,
                                color: Colors.white60,
                                size: 19,
                              ),
                              onPressed: _resetView,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                            ),
                          ),
                          const Divider(color: Colors.white10, height: 8),
                          if (_showAISignal)
                            Tooltip(
                              message: 'Hide AI Analysis',
                              child: IconButton(
                                icon: const Icon(
                                  CupertinoIcons.eye,
                                  color: AppColors.primary,
                                  size: 19,
                                ),
                                onPressed: () =>
                                    setState(() => _showAISignal = false),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                              ),
                            )
                          else
                            Tooltip(
                              message: 'Show AI Analysis',
                              child: IconButton(
                                icon: const Icon(
                                  CupertinoIcons.eye_slash,
                                  color: Colors.white60,
                                  size: 19,
                                ),
                                onPressed: () =>
                                    setState(() => _showAISignal = true),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                              ),
                            ),
                          if (_drawings.isNotEmpty) ...[
                            const Divider(color: Colors.white10, height: 8),
                            Tooltip(
                              message: 'Clear All Drawings',
                              child: IconButton(
                                icon: const Icon(
                                  Icons.delete_sweep,
                                  color: AppColors.bear,
                                  size: 19,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _drawings.clear();
                                    _inProgressDrawing = null;
                                  });
                                  _saveDrawings();
                                },
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // Crosshair tooltip bubble
                  if (_showCrosshair && _crosshairPos != null)
                    _buildCrosshairTooltip(coords),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  MouseCursor _getCursor([_ChartCoords? coords]) {
    final probe = _hoverPos ?? _crosshairPos;
    if (coords != null &&
        probe != null &&
        coords.isOnYAxis(probe) &&
        (widget.activeTool == ChartTool.pointer ||
            widget.activeTool == ChartTool.crosshair)) {
      return SystemMouseCursors.resizeUpDown;
    }
    switch (widget.activeTool) {
      case ChartTool.crosshair:
        return SystemMouseCursors.precise;
      case ChartTool.pointer:
        return SystemMouseCursors.grab;
      case ChartTool.eraser:
        return SystemMouseCursors.noDrop;
      case ChartTool.text:
        return SystemMouseCursors.text;
      default:
        return SystemMouseCursors.click;
    }
  }

  Widget _buildCrosshairTooltip(_ChartCoords coords) {
    if (_crosshairPos == null) return const SizedBox.shrink();
    final price = coords.pixelToPrice(_crosshairPos!.dy);
    final priceStr = price.toStringAsFixed(price > 100 ? 2 : 5);

    // Ruler: show delta
    String? rulerInfo;
    if (widget.activeTool == ChartTool.ruler &&
        _inProgressDrawing is RulerDrawing) {
      final r = _inProgressDrawing as RulerDrawing;
      final p1Price = coords.pixelToPrice(r.p1.dy);
      final delta = (price - p1Price);
      final pct = p1Price != 0 ? (delta / p1Price * 100) : 0;
      rulerInfo =
          '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(price > 100 ? 2 : 5)} (${pct.toStringAsFixed(2)}%)';
    }

    return Positioned(
      left: (_crosshairPos!.dx + 12).clamp(0, double.infinity),
      top: (_crosshairPos!.dy - 30).clamp(0, double.infinity),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1a1d20),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              priceStr,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (rulerInfo != null)
              Text(
                rulerInfo,
                style: TextStyle(color: AppColors.primary, fontSize: 10),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildOverlayWidgets(TradingSignal signal) {
    final widgets = <Widget>[];
    for (final layer in signal.layers) {
      if (layer['layer'] == 5 && layer['type'] == 'overlay') {
        final items = layer['items'] as List<dynamic>? ?? [];
        for (final item in items) {
          final itemMap = Map<String, dynamic>.from(item as Map);
          if (itemMap['type'] == 'wyckoff_phase') {
            widgets.add(
              Positioned(
                bottom: 45,
                left: 20,
                child: Text(
                  itemMap['text'] ?? '',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: Colors.white.withValues(alpha: 0.15),
                    letterSpacing: 4,
                  ),
                ),
              ),
            );
          }
          if (itemMap['type'] == 'htf_trend') {
            widgets.add(
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'HTF TREND',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: Colors.white.withValues(alpha: 0.5),
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _htfRow(
                        itemMap['htf1_label'] ?? 'H4',
                        itemMap['htf1_trend'] ?? '',
                      ),
                      const SizedBox(height: 4),
                      _htfRow(
                        itemMap['htf2_label'] ?? 'D1',
                        itemMap['htf2_trend'] ?? '',
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
        }
      }
    }
    return widgets;
  }

  Widget _htfRow(String label, String trend) {
    final isBullish = trend.toLowerCase().contains('bullish');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        Icon(
          isBullish ? Icons.arrow_upward : Icons.arrow_downward,
          size: 12,
          color: isBullish ? AppColors.primary : AppColors.bear,
        ),
        const SizedBox(width: 2),
        Text(
          trend,
          style: TextStyle(
            color: isBullish ? AppColors.primary : AppColors.bear,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
// KINETIC CHART PAINTER
// ═══════════════════════════════════════════════════════════
class _KineticChartPainter extends CustomPainter {
  final List<Candle> candles;
  final TradingSignal? signal;
  final double scaleX;
  final double offsetX;
  final double scaleY;
  final double priceOffset;
  final List<DrawingObject> drawings;
  final Offset? crosshairPos;
  final ChartTool activeTool;

  _KineticChartPainter({
    required this.candles,
    required this.signal,
    required this.scaleX,
    required this.offsetX,
    required this.scaleY,
    required this.priceOffset,
    required this.drawings,
    required this.crosshairPos,
    required this.activeTool,
  });

  // These are set in paint()
  late _ChartCoords _c;
  final List<Rect> _occupiedTextRects = [];

  Offset _getNonOverlappingOffset(
    Offset preferredOffset,
    Size size, {
    double margin = 3.0,
  }) {
    Rect rect = Rect.fromLTWH(
      preferredOffset.dx,
      preferredOffset.dy,
      size.width,
      size.height,
    );
    bool hasOverlap = true;
    int attempts = 0;
    while (hasOverlap && attempts < 15) {
      hasOverlap = false;
      for (final r in _occupiedTextRects) {
        if (rect.overlaps(r)) {
          hasOverlap = true;
          final shiftY = (r.bottom - rect.top) + margin;
          rect = rect.translate(0, shiftY);
          preferredOffset = Offset(
            preferredOffset.dx,
            preferredOffset.dy + shiftY,
          );
          break;
        }
      }
      attempts++;
    }
    _occupiedTextRects.add(rect);
    return preferredOffset;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;
    _occupiedTextRects.clear();
    _c = _ChartCoords(
      candles: candles,
      scaleX: scaleX,
      offsetX: offsetX,
      scaleY: scaleY,
      priceOffset: priceOffset,
      size: size,
    );
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    _drawGrid(canvas);

    canvas.save();
    canvas.clipRect(_c.chartRect);

    // Signal layers
    if (signal != null && signal!.layers.isNotEmpty) {
      _renderLayer5Background(canvas, signal!.layers);
      _renderLayer1StructureZones(canvas, signal!.layers);
    }

    final layer3Items = _getLayer3Items();
    _drawCandles(canvas, layer3Items);

    if (signal != null && signal!.layers.isNotEmpty) {
      _renderLayer1StructureLabels(canvas, signal!.layers);
      _renderLayer2Warnings(canvas, signal!.layers);
    }

    if (signal != null) {
      final hardSetup = signal!.setupReady && !signal!.veto;
      if (signal!.layers.isNotEmpty) {
        if (hardSetup) {
          _renderLayer4Execution(canvas, signal!.layers);
        }
      } else if (hardSetup) {
        _drawLegacyExecutionLines(canvas, signal!);
      }
    }

    // User drawings
    _paintDrawings(canvas, size);

    // Crosshair
    if (crosshairPos != null) _paintCrosshair(canvas, size);

    canvas.restore();

    _drawYAxis(canvas, size);
    _drawXAxis(canvas, size);
  }

  // ─── User Drawings ───────────────────────────────────────
  void _paintDrawings(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.9)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final d in drawings) {
      switch (d.type) {
        case DrawingType.horizontalLine:
          _paintHorizontalLine(canvas, d as HorizontalLineDrawing, linePaint);
          break;
        case DrawingType.verticalLine:
          _paintVerticalLine(canvas, d as VerticalLineDrawing, linePaint);
          break;
        case DrawingType.trendLine:
          _paintTrendLine(canvas, d as TrendLineDrawing, linePaint);
          break;
        case DrawingType.rectangle:
          _paintRectangle(canvas, d as RectangleDrawing, linePaint);
          break;
        case DrawingType.fibonacci:
          _paintFibonacci(canvas, d as FibonacciDrawing);
          break;
        case DrawingType.ruler:
          _paintRuler(canvas, d as RulerDrawing);
          break;
        case DrawingType.text:
          _paintText(canvas, d as TextDrawing);
          break;
      }
    }
  }

  void _paintHorizontalLine(
    Canvas canvas,
    HorizontalLineDrawing d,
    Paint paint,
  ) {
    final y = _c.getY(d.price);
    if (y < 0 || y > _c.chartRect.height) return;
    _drawDashedLine(
      canvas,
      Offset(0, y),
      Offset(_c.chartRect.width, y),
      Paint()
        ..color = AppColors.primary
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke,
    );
    // Price label
    _drawLabel(
      canvas,
      Offset(_c.chartRect.width - 65, y - 9),
      d.price.toStringAsFixed(d.price > 100 ? 2 : 5),
      AppColors.primary,
      Colors.black,
    );
  }

  void _paintVerticalLine(Canvas canvas, VerticalLineDrawing d, Paint paint) {
    final x = _c.xFractionToPixel(d.xFraction);
    _drawDashedLine(
      canvas,
      Offset(x, 0),
      Offset(x, _c.chartRect.height),
      paint,
    );
  }

  void _paintTrendLine(Canvas canvas, TrendLineDrawing d, Paint paint) {
    // Extend line beyond endpoints (like TradingView)
    final dx = d.p2.dx - d.p1.dx;
    final dy = d.p2.dy - d.p1.dy;
    if (dx.abs() < 0.001) {
      canvas.drawLine(
        Offset(d.p1.dx, 0),
        Offset(d.p1.dx, _c.chartRect.height),
        paint,
      );
      return;
    }
    // Extend to chart edges
    final slope = dy / dx;
    final x0 = 0.0;
    final x1 = _c.chartRect.width;
    final y0 = d.p1.dy + slope * (x0 - d.p1.dx);
    final y1 = d.p1.dy + slope * (x1 - d.p1.dx);
    canvas.drawLine(Offset(x0, y0), Offset(x1, y1), paint);
    // Anchor dots
    canvas.drawCircle(d.p1, 4, Paint()..color = AppColors.primary);
    canvas.drawCircle(d.p2, 4, Paint()..color = AppColors.primary);
  }

  void _paintRectangle(Canvas canvas, RectangleDrawing d, Paint paint) {
    final rect = Rect.fromPoints(d.p1, d.p2);
    canvas.drawRect(
      rect,
      Paint()
        ..color = AppColors.primary.withValues(alpha: 0.08)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRect(rect, paint);
  }

  void _paintFibonacci(Canvas canvas, FibonacciDrawing d) {
    final priceTop = _c.pixelToPrice(d.p1.dy);
    final priceBottom = _c.pixelToPrice(d.p2.dy);
    final priceRange = priceTop - priceBottom;

    final fibColors = [
      Colors.white38,
      const Color(0xFFF0E68C),
      const Color(0xFFFF9800),
      AppColors.primary,
      const Color(0xFFFF5252),
      AppColors.bear,
      Colors.white54,
    ];

    for (int i = 0; i < FibonacciDrawing.levels.length; i++) {
      final level = FibonacciDrawing.levels[i];
      final price = priceTop - (priceRange * level);
      final y = _c.getY(price);
      if (y < 0 || y > _c.chartRect.height) continue;

      final color = fibColors[i % fibColors.length];
      canvas.drawLine(
        Offset(math.min(d.p1.dx, d.p2.dx), y),
        Offset(_c.chartRect.width, y),
        Paint()
          ..color = color.withValues(alpha: 0.7)
          ..strokeWidth = 1.0,
      );

      // Fill between levels
      if (i < FibonacciDrawing.levels.length - 1) {
        final nextLevel = FibonacciDrawing.levels[i + 1];
        final nextPrice = priceTop - (priceRange * nextLevel);
        final nextY = _c.getY(nextPrice);
        canvas.drawRect(
          Rect.fromLTRB(
            math.min(d.p1.dx, d.p2.dx),
            y,
            _c.chartRect.width,
            nextY.clamp(0.0, _c.chartRect.height),
          ),
          Paint()
            ..color = color.withValues(alpha: 0.03)
            ..style = PaintingStyle.fill,
        );
      }

      // Label
      _drawText(
        canvas,
        '${FibonacciDrawing.labels[i]}  ${price.toStringAsFixed(price > 100 ? 2 : 5)}',
        Offset(_c.chartRect.width - 110, y - 8),
        color,
        9,
        fontWeight: FontWeight.bold,
      );
    }

    // Anchor handles
    canvas.drawCircle(d.p1, 4, Paint()..color = const Color(0xFFF0E68C));
    canvas.drawCircle(d.p2, 4, Paint()..color = const Color(0xFFF0E68C));
  }

  void _paintRuler(Canvas canvas, RulerDrawing d) {
    final p1Price = _c.pixelToPrice(d.p1.dy);
    final p2Price = _c.pixelToPrice(d.p2.dy);
    final delta = p2Price - p1Price;
    final pct = p1Price != 0 ? (delta / p1Price * 100) : 0;
    final sign = delta >= 0 ? '+' : '';

    // Main ruler line
    canvas.drawLine(
      d.p1,
      d.p2,
      Paint()
        ..color = const Color(0xFFF0E68C).withValues(alpha: 0.9)
        ..strokeWidth = 1.5,
    );

    // Horizontal dashes at endpoints
    canvas.drawLine(
      Offset(d.p1.dx - 8, d.p1.dy),
      Offset(d.p1.dx + 8, d.p1.dy),
      Paint()
        ..color = const Color(0xFFF0E68C)
        ..strokeWidth = 2,
    );
    canvas.drawLine(
      Offset(d.p2.dx - 8, d.p2.dy),
      Offset(d.p2.dx + 8, d.p2.dy),
      Paint()
        ..color = const Color(0xFFF0E68C)
        ..strokeWidth = 2,
    );

    // Measurement label
    final midX = (d.p1.dx + d.p2.dx) / 2;
    final midY = (d.p1.dy + d.p2.dy) / 2;
    final label =
        '$sign${delta.toStringAsFixed(delta.abs() > 100 ? 2 : 5)} ($sign${pct.toStringAsFixed(2)}%)';
    _drawLabel(
      canvas,
      Offset(midX - 60, midY - 10),
      label,
      const Color(0xFFF0E68C).withValues(alpha: 0.9),
      Colors.black,
    );
  }

  void _paintText(Canvas canvas, TextDrawing d) {
    _drawText(
      canvas,
      d.text,
      d.position,
      AppColors.primary,
      13,
      fontWeight: FontWeight.bold,
    );
  }

  void _paintCrosshair(Canvas canvas, Size size) {
    if (crosshairPos == null) return;
    final x = crosshairPos!.dx;
    final y = crosshairPos!.dy;
    final crossPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1.0;

    // Vertical line
    canvas.drawLine(Offset(x, 0), Offset(x, _c.chartRect.height), crossPaint);
    // Horizontal line
    canvas.drawLine(Offset(0, y), Offset(_c.chartRect.width, y), crossPaint);

    // Price tag on Y-axis
    final price = _c.pixelToPrice(y);
    final priceStr = price.toStringAsFixed(price > 100 ? 2 : 5);
    final tp = TextPainter(
      text: TextSpan(
        text: priceStr,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.drawRect(
      Rect.fromLTWH(_c.chartRect.width, y - 10, _ChartCoords.yAxisWidth, 20),
      Paint()..color = Colors.white.withValues(alpha: 0.6),
    );
    tp.paint(canvas, Offset(_c.chartRect.width + 4, y - 7));
  }

  // ─── (All original painting methods preserved below) ─────

  void _drawGrid(Canvas canvas) {
    final gridPaint = Paint()
      ..color = const Color(0xFF434655).withValues(alpha: 0.1)
      ..strokeWidth = 1.0;
    const gridLinesY = 8;
    final priceStep = _c.priceRange / gridLinesY;
    for (int i = 0; i <= gridLinesY; i++) {
      final price = _c.minPrice + i * priceStep;
      canvas.drawLine(
        Offset(0, _c.getY(price)),
        Offset(_c.chartRect.width, _c.getY(price)),
        gridPaint,
      );
    }
    final xStep = _c.chartRect.width / 6;
    for (int i = 0; i <= 6; i++) {
      final x = i * xStep;
      canvas.drawLine(Offset(x, 0), Offset(x, _c.chartRect.height), gridPaint);
    }
  }

  void _renderLayer5Background(
    Canvas canvas,
    List<Map<String, dynamic>> layers,
  ) {
    for (final layer in layers) {
      if (layer['layer'] != 5) continue;
      final items = _getItems(layer);
      for (final item in items) {
        final type = item['type'] ?? '';
        if (type == 'ghost_box') {
          final priceTop = (item['price_top'] as num?)?.toDouble();
          final priceBottom = (item['price_bottom'] as num?)?.toDouble();
          if (priceTop == null || priceBottom == null) continue;
          final zoneType = item['zone_type'] ?? 'danger';
          final color = zoneType == 'danger'
              ? AppColors.bear
              : AppColors.primary;
          final label = item['label'] ?? '';
          final top = _c.getY(priceTop);
          final bottom = _c.getY(priceBottom);
          canvas.drawRect(
            Rect.fromLTRB(0, top, _c.chartRect.width, bottom),
            Paint()
              ..color = color.withValues(alpha: 0.05)
              ..style = PaintingStyle.fill,
          );
          _drawDashedRect(
            canvas,
            Rect.fromLTRB(10, top, _c.chartRect.width - 10, bottom),
            Paint()
              ..color = color.withValues(alpha: 0.25)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.0,
          );
          _drawLabel(
            canvas,
            Offset(15, top + 5),
            '#$label',
            color.withValues(alpha: 0.4),
            Colors.white70,
          );
        }
        if (type == 'news_column') {
          canvas.drawRect(
            Rect.fromLTWH(_c.chartRect.width - 40, 0, 40, _c.chartRect.height),
            Paint()
              ..color = AppColors.bear.withValues(alpha: 0.08)
              ..style = PaintingStyle.fill,
          );
          _drawLabel(
            canvas,
            Offset(_c.chartRect.width - 38, 8),
            item['text'] ?? 'NEWS',
            AppColors.bear.withValues(alpha: 0.5),
            Colors.white,
          );
        }
      }
    }
  }

  void _renderLayer1StructureZones(
    Canvas canvas,
    List<Map<String, dynamic>> layers,
  ) {
    for (final layer in layers) {
      if (layer['layer'] != 1) continue;
      final items = _getItems(layer);
      for (final item in items) {
        final color = _parseColor(item['color'] ?? 'green_opacity');
        if (item.containsKey('price_top') && item.containsKey('price_bottom')) {
          final top = _c.getY((item['price_top'] as num).toDouble());
          final bottom = _c.getY((item['price_bottom'] as num).toDouble());
          final left = _getXFromTime(item['time_start'] as int? ?? 0);
          final right = _getXFromTime(item['time_end'] as int? ?? 0);
          canvas.drawRect(
            Rect.fromLTRB(left, top, right, bottom),
            Paint()
              ..color = color.withValues(alpha: 0.08)
              ..style = PaintingStyle.fill,
          );
          canvas.drawRect(
            Rect.fromLTRB(left, top, right, bottom),
            Paint()
              ..color = color.withValues(alpha: 0.4)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.0,
          );
        } else if (item.containsKey('price_y')) {
          final y = _c.getY((item['price_y'] as num).toDouble());
          final x = _getXFromTime(item['time_x'] as int? ?? 0);
          _drawDashedLine(
            canvas,
            Offset(x, y),
            Offset(_c.chartRect.width, y),
            Paint()
              ..color = color
              ..strokeWidth = 1.0,
          );
        }
      }
    }
  }

  void _renderLayer1StructureLabels(
    Canvas canvas,
    List<Map<String, dynamic>> layers,
  ) {
    for (final layer in layers) {
      if (layer['layer'] != 1) continue;
      final items = _getItems(layer);
      for (final item in items) {
        final label = item['label'] ?? '';
        final color = _parseColor(item['color'] ?? 'green_opacity');
        if (item.containsKey('price_top') && item.containsKey('price_bottom')) {
          final top = _c.getY((item['price_top'] as num).toDouble());
          final left = _getXFromTime(item['time_start'] as int? ?? 0);
          _drawLabel(
            canvas,
            Offset(left + 4, top + 3),
            label,
            color.withValues(alpha: 0.6),
            Colors.white,
          );
        } else if (item.containsKey('price_y')) {
          final y = _c.getY((item['price_y'] as num).toDouble());
          final x = _getXFromTime(item['time_x'] as int? ?? 0);
          _drawLabel(canvas, Offset(x + 2, y - 12), label, color, Colors.black);
        }
      }
    }
  }

  void _renderLayer2Warnings(Canvas canvas, List<Map<String, dynamic>> layers) {
    for (final layer in layers) {
      if (layer['layer'] != 2) continue;
      for (final item in _getItems(layer)) {
        final color = _parseColor(item['color'] ?? 'yellow');
        final x = _getXFromTime(item['time_x'] as int? ?? 0);
        final y = _c.getY((item['price_y'] as num?)?.toDouble() ?? 0);
        _drawText(
          canvas,
          _getIconString(item['icon'] ?? 'arrow'),
          Offset(x - 8, y - 20),
          color,
          16,
          fontWeight: FontWeight.bold,
        );
        _drawLabel(
          canvas,
          Offset(x - 4, y + 4),
          item['text'] ?? '',
          color.withValues(alpha: 0.7),
          Colors.white,
        );
      }
    }
  }

  Map<int, Map<String, dynamic>> _getLayer3Items() {
    final overrides = <int, Map<String, dynamic>>{};
    if (signal == null) return overrides;
    for (final layer in signal!.layers) {
      if (layer['layer'] != 3) continue;
      for (final item in _getItems(layer)) {
        overrides[item['candle_time'] as int? ?? 0] = Map<String, dynamic>.from(
          item,
        );
      }
    }
    return overrides;
  }

  void _drawCandles(Canvas canvas, Map<int, Map<String, dynamic>> layer3) {
    for (int i = _c.startIndex; i <= _c.endIndex; i++) {
      final candle = candles[i];
      final x = _c.getX(i);
      if (x < -_c.totalCandleWidth ||
          x > _c.chartRect.width + _c.totalCandleWidth)
        continue;
      final openY = _c.getY(candle.open);
      final closeY = _c.getY(candle.close);
      final highY = _c.getY(candle.high);
      final lowY = _c.getY(candle.low);
      final override = layer3[candle.timestamp.millisecondsSinceEpoch ~/ 1000];
      Color candleColor;
      String? labelBottom;
      if (override != null) {
        candleColor = _parseColor(override['fill_color'] ?? 'purple');
        labelBottom = override['label_bottom'];
      } else {
        // V2.1 P0#4: body is ONLY bull green / bear red unless Layer 3 overrides
        candleColor = candle.close >= candle.open
            ? const Color(0xFF00FF7F)
            : const Color(0xFFFF3B30);
      }
      final paint = Paint()
        ..color = candleColor
        ..strokeWidth = 1.5 * scaleX.clamp(0.5, 2.0)
        ..style = PaintingStyle.fill;
      canvas.drawLine(Offset(x, highY), Offset(x, lowY), paint);
      final bodyTop = math.min(openY, closeY);
      final bodyHeight = math.max(1.0, math.max(openY, closeY) - bodyTop);
      canvas.drawRect(
        Rect.fromLTWH(
          x - (_c.effectiveCandleWidth / 2),
          bodyTop,
          _c.effectiveCandleWidth,
          bodyHeight,
        ),
        paint,
      );
      if (labelBottom != null)
        _drawText(
          canvas,
          labelBottom,
          Offset(x - 10, lowY + 4),
          candleColor,
          8,
          fontWeight: FontWeight.bold,
        );
    }
  }

  void _renderLayer4Execution(
    Canvas canvas,
    List<Map<String, dynamic>> layers,
  ) {
    final List<_RightLabel> labels = [];
    for (final layer in layers) {
      if (layer['layer'] != 4) continue;
      final entryLine = layer['entry_line'];
      if (entryLine != null) {
        final double price = (entryLine['price'] as num).toDouble();
        final y = _c.getY(price);
        final color = _parseColor(entryLine['color'] ?? 'cyan');
        canvas.drawLine(
          Offset(0, y),
          Offset(_c.chartRect.width, y),
          Paint()
            ..color = color
            ..strokeWidth = 1.5,
        );
        labels.add(
          _RightLabel(
            text:
                '${price.toStringAsFixed(price > 100 ? 2 : 5)} (${signal?.probability}%)',
            targetY: y,
            bgColor: color,
            textColor: Colors.black,
            isBadge: true,
            badgeTitle: 'ENTRY',
          ),
        );
      }
      final slLine = layer['sl_line'];
      if (slLine != null) {
        final double price = (slLine['price'] as num).toDouble();
        final y = _c.getY(price);
        _drawDashedLine(
          canvas,
          Offset(0, y),
          Offset(_c.chartRect.width, y),
          Paint()
            ..color = AppColors.bear
            ..strokeWidth = 1.5,
        );
        labels.add(
          _RightLabel(
            text: 'SL: ${price.toStringAsFixed(price > 100 ? 2 : 5)}',
            targetY: y,
            bgColor: AppColors.bear,
            textColor: Colors.white,
          ),
        );
      }
      final tpLines = layer['tp_lines'] as List<dynamic>? ?? [];
      for (final tp in tpLines) {
        final tpMap = Map<String, dynamic>.from(tp as Map);
        final double price = (tpMap['price'] as num).toDouble();
        final y = _c.getY(price);
        final label = tpMap['label'] ?? 'TP';
        _drawDashedLine(
          canvas,
          Offset(0, y),
          Offset(_c.chartRect.width, y),
          Paint()
            ..color = const Color(0xFF3772FF)
            ..strokeWidth = 1.0,
        );
        labels.add(
          _RightLabel(
            text: '$label: ${price.toStringAsFixed(price > 100 ? 2 : 5)}',
            targetY: y,
            bgColor: const Color(0xFF3772FF),
            textColor: Colors.white,
          ),
        );
      }
      final curves = layer['curves'] as List<dynamic>? ?? [];
      for (final curve in curves) {
        _drawBezierCurve(canvas, Map<String, dynamic>.from(curve as Map));
      }
    }

    _resolveOverlap(labels);

    for (final label in labels) {
      if (label.isBadge) {
        _drawRightAlignedBadge(
          canvas,
          _c.chartRect.width - 6,
          label.actualY - 10,
          label.badgeTitle ?? 'ENTRY',
          label.text,
          label.bgColor,
        );
      } else {
        _drawRightAlignedLabel(
          canvas,
          _c.chartRect.width - 6,
          label.actualY - 8,
          label.text,
          label.bgColor,
          label.textColor,
        );
      }
    }
  }

  void _drawLegacyExecutionLines(Canvas canvas, TradingSignal signal) {
    final List<_RightLabel> labels = [];
    final entryPrice = signal.entryPrice;
    final entryY = _c.getY(entryPrice);
    canvas.drawLine(
      Offset(0, entryY),
      Offset(_c.chartRect.width, entryY),
      Paint()
        ..color = AppColors.primary
        ..strokeWidth = 1.5,
    );
    labels.add(
      _RightLabel(
        text:
            '${entryPrice.toStringAsFixed(entryPrice > 100 ? 2 : 5)} (${signal.probability}%)',
        targetY: entryY,
        bgColor: AppColors.primary,
        textColor: Colors.black,
        isBadge: true,
        badgeTitle: 'ENTRY',
      ),
    );

    final slPrice = signal.slPrice;
    final slY = _c.getY(slPrice);
    _drawDashedLine(
      canvas,
      Offset(0, slY),
      Offset(_c.chartRect.width, slY),
      Paint()
        ..color = AppColors.bear
        ..strokeWidth = 1.5,
    );
    labels.add(
      _RightLabel(
        text: 'SL: ${slPrice.toStringAsFixed(slPrice > 100 ? 2 : 5)}',
        targetY: slY,
        bgColor: AppColors.bear,
        textColor: Colors.white,
      ),
    );

    if (signal.tpPrices.isNotEmpty) {
      final tpPrice = signal.tpPrices.first;
      final tpY = _c.getY(tpPrice);
      _drawDashedLine(
        canvas,
        Offset(0, tpY),
        Offset(_c.chartRect.width, tpY),
        Paint()
          ..color = const Color(0xFF3772FF)
          ..strokeWidth = 1.5,
      );
      labels.add(
        _RightLabel(
          text: 'TP: ${tpPrice.toStringAsFixed(tpPrice > 100 ? 2 : 5)}',
          targetY: tpY,
          bgColor: const Color(0xFF3772FF),
          textColor: Colors.white,
        ),
      );
    }

    _resolveOverlap(labels);

    for (final label in labels) {
      if (label.isBadge) {
        _drawRightAlignedBadge(
          canvas,
          _c.chartRect.width - 6,
          label.actualY - 10,
          label.badgeTitle ?? 'ENTRY',
          label.text,
          label.bgColor,
        );
      } else {
        _drawRightAlignedLabel(
          canvas,
          _c.chartRect.width - 6,
          label.actualY - 8,
          label.text,
          label.bgColor,
          label.textColor,
        );
      }
    }
  }

  void _resolveOverlap(List<_RightLabel> labels) {
    if (labels.isEmpty) return;
    labels.sort((a, b) => a.targetY.compareTo(b.targetY));
    const minSpacing = 28.0;
    for (int i = 1; i < labels.length; i++) {
      if (labels[i].actualY < labels[i - 1].actualY + minSpacing) {
        labels[i].actualY = labels[i - 1].actualY + minSpacing;
      }
    }
    final maxHeight = _c.chartRect.height - 15.0;
    if (labels.last.actualY > maxHeight) {
      labels.last.actualY = maxHeight;
      for (int i = labels.length - 2; i >= 0; i--) {
        if (labels[i].actualY > labels[i + 1].actualY - minSpacing) {
          labels[i].actualY = labels[i + 1].actualY - minSpacing;
        }
      }
    }
  }

  void _drawRightAlignedLabel(
    Canvas canvas,
    double rightX,
    double y,
    String text,
    Color bgColor,
    Color textColor,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final startX = rightX - tp.width - 10;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(startX - 6, y - 4, tp.width + 12, tp.height + 8),
        const Radius.circular(4),
      ),
      Paint()..color = bgColor,
    );
    tp.paint(canvas, Offset(startX, y));
  }

  void _drawRightAlignedBadge(
    Canvas canvas,
    double rightX,
    double y,
    String title,
    String value,
    Color color,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: '$title | $value',
        style: const TextStyle(
          color: Colors.black,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final startX = rightX - tp.width - 14;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(startX - 8, y - 6, tp.width + 16, tp.height + 12),
        const Radius.circular(6),
      ),
      Paint()..color = color,
    );
    tp.paint(canvas, Offset(startX, y));
  }

  void _drawYAxis(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(
        _c.chartRect.width,
        0,
        _ChartCoords.yAxisWidth,
        size.height,
      ),
      Paint()..color = const Color(0xFF0b0e11),
    );
    canvas.drawLine(
      Offset(_c.chartRect.width, 0),
      Offset(_c.chartRect.width, _c.chartRect.height),
      Paint()..color = Colors.white10,
    );
    const gridLinesY = 8;
    final priceStep = _c.priceRange / gridLinesY;
    for (int i = 0; i <= gridLinesY; i++) {
      final price = _c.minPrice + i * priceStep;
      _drawText(
        canvas,
        price.toStringAsFixed(price > 100 ? 2 : 5),
        Offset(_c.chartRect.width + 5, _c.getY(price) - 6),
        Colors.white54,
        11,
      );
    }
    if (candles.isNotEmpty) {
      final lastPrice = candles.last.close;
      final lastY = _c.getY(lastPrice);
      final pColor = candles.last.close >= candles.last.open
          ? AppColors.primary
          : AppColors.bear;
      canvas.drawRect(
        Rect.fromLTWH(
          _c.chartRect.width,
          lastY - 11,
          _ChartCoords.yAxisWidth,
          22,
        ),
        Paint()..color = pColor,
      );
      _drawText(
        canvas,
        lastPrice.toStringAsFixed(lastPrice > 100 ? 2 : 5),
        Offset(_c.chartRect.width + 5, lastY - 7),
        Colors.white,
        11,
        fontWeight: FontWeight.bold,
      );
      _drawDashedLine(
        canvas,
        Offset(0, lastY),
        Offset(_c.chartRect.width, lastY),
        Paint()
          ..color = pColor
          ..strokeWidth = 1.0,
      );
    }
  }

  void _drawXAxis(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(
        0,
        _c.chartRect.height,
        size.width,
        _ChartCoords.xAxisHeight,
      ),
      Paint()..color = const Color(0xFF0b0e11),
    );
    canvas.drawLine(
      Offset(0, _c.chartRect.height),
      Offset(_c.chartRect.width, _c.chartRect.height),
      Paint()..color = Colors.white10,
    );
    int step = ((_c.endIndex - _c.startIndex) / 5).ceil();
    if (step < 1) step = 1;
    for (int i = _c.startIndex; i <= _c.endIndex; i += step) {
      final x = _c.getX(i);
      if (x < 0 || x > _c.chartRect.width) continue;
      final time = candles[i].timestamp;
      final label =
          '${time.day.toString().padLeft(2, '0')}/${time.month.toString().padLeft(2, '0')} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(color: Colors.white54, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, _c.chartRect.height + 8));
      canvas.drawLine(
        Offset(x, _c.chartRect.height),
        Offset(x, _c.chartRect.height + 4),
        Paint()..color = Colors.white54,
      );
    }
  }

  // ─── Drawing Helpers ─────────────────────────────────────
  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const dashWidth = 5.0, dashSpace = 5.0;
    final distance = (p2 - p1).distance;
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

  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    _drawDashedLine(canvas, rect.topLeft, rect.topRight, paint);
    _drawDashedLine(canvas, rect.topRight, rect.bottomRight, paint);
    _drawDashedLine(canvas, rect.bottomRight, rect.bottomLeft, paint);
    _drawDashedLine(canvas, rect.bottomLeft, rect.topLeft, paint);
  }

  void _drawLabel(
    Canvas canvas,
    Offset offset,
    String text,
    Color bgColor,
    Color textColor,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final size = Size(tp.width + 8, tp.height + 4);
    final resolvedOffset = _getNonOverlappingOffset(
      Offset(offset.dx - 4, offset.dy - 2),
      size,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          resolvedOffset.dx,
          resolvedOffset.dy,
          size.width,
          size.height,
        ),
        const Radius.circular(4),
      ),
      Paint()..color = bgColor,
    );
    tp.paint(canvas, Offset(resolvedOffset.dx + 4, resolvedOffset.dy + 2));
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    Color color,
    double fontSize, {
    FontWeight fontWeight = FontWeight.normal,
  }) {
    TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: fontWeight,
          ),
        ),
        textDirection: TextDirection.ltr,
      )
      ..layout()
      ..paint(canvas, offset);
  }

  void _drawBezierCurve(Canvas canvas, Map<String, dynamic> curveData) {
    final points = curveData['points'] as List<dynamic>? ?? [];
    if (points.length < 3) return;
    final color = _parseHexColor(curveData['color'] ?? '#00FFFF');
    final mappedPoints = points.map((p) {
      final pm = Map<String, dynamic>.from(p as Map);
      return Offset(
        _getXFromTime((pm['x_time'] as num).toInt()),
        _c.getY((pm['y_price'] as num).toDouble()),
      );
    }).toList();
    final path = Path()..moveTo(mappedPoints[0].dx, mappedPoints[0].dy);
    if (mappedPoints.length == 3) {
      path.quadraticBezierTo(
        mappedPoints[1].dx,
        mappedPoints[1].dy,
        mappedPoints[2].dx,
        mappedPoints[2].dy,
      );
    } else if (mappedPoints.length >= 4) {
      path.cubicTo(
        mappedPoints[1].dx,
        mappedPoints[1].dy,
        mappedPoints[2].dx,
        mappedPoints[2].dy,
        mappedPoints[3].dx,
        mappedPoints[3].dy,
      );
    }
    final dashedPath = _dashPath(path);
    canvas.drawPath(
      dashedPath,
      Paint()
        ..color = color.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 3.0),
    );
    canvas.drawPath(
      dashedPath,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final midIdx = mappedPoints.length ~/ 2;
    final labelText = curveData['id'] ?? '';
    final tp = TextPainter(
      text: TextSpan(
        text: labelText,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final preferredOffset = Offset(
      mappedPoints[midIdx].dx + 4,
      mappedPoints[midIdx].dy - 14,
    );
    final resolvedOffset = _getNonOverlappingOffset(preferredOffset, tp.size);
    tp.paint(canvas, resolvedOffset);
  }

  Path _dashPath(Path source) {
    final result = Path();
    for (final metric in source.computeMetrics()) {
      double distance = 0;
      const dashLen = 6.0, gapLen = 4.0;
      while (distance < metric.length) {
        final end = math.min(distance + dashLen, metric.length);
        result.addPath(metric.extractPath(distance, end), Offset.zero);
        distance = end + gapLen;
      }
    }
    return result;
  }

  double _getXFromTime(int timestamp) {
    for (int i = 0; i < candles.length; i++) {
      if (candles[i].timestamp.millisecondsSinceEpoch ~/ 1000 >= timestamp)
        return _c.getX(i);
    }
    if (candles.isNotEmpty) {
      final lastTime = candles.last.timestamp.millisecondsSinceEpoch ~/ 1000;
      final diffSec = timestamp - lastTime;
      final avgInterval = candles.length > 1
          ? (candles.last.timestamp.millisecondsSinceEpoch -
                    candles.first.timestamp.millisecondsSinceEpoch) /
                (candles.length - 1) /
                1000
          : 300;
      return _c.getX(candles.length - 1) +
          (diffSec / avgInterval) * _c.totalCandleWidth;
    }
    return _c.chartRect.width;
  }

  Color _parseColor(String name) {
    switch (name.toLowerCase()) {
      case 'green_opacity':
      case 'green':
        return AppColors.primary;
      case 'red_opacity':
      case 'red':
        return AppColors.bear;
      case 'cyan':
        return const Color(0xFF00FFFF);
      case 'yellow':
        return const Color(0xFFF0E68C);
      case 'purple':
        return const Color(0xFF8A2BE2);
      case 'white':
        return Colors.white;
      case 'blue':
        return const Color(0xFF3772FF);
      case 'orange':
        return Colors.orange;
      default:
        if (name.startsWith('#')) return _parseHexColor(name);
        return Colors.white;
    }
  }

  Color _parseHexColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }

  String _getIconString(String iconType) {
    switch (iconType.toLowerCase()) {
      case 'dollar':
        return '\$\$\$';
      case 'skull':
        return '☠';
      case 'arrow':
      case 'down_arrow':
        return '↓';
      case 'up_arrow':
        return '↑';
      case 'warning':
        return '⚠';
      default:
        return '●';
    }
  }

  List<Map<String, dynamic>> _getItems(Map<String, dynamic> layer) {
    final items = layer['items'];
    if (items == null) return [];
    return (items as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  @override
  bool shouldRepaint(covariant _KineticChartPainter old) {
    // Fast checks first — most common change triggers
    if (candles.length != old.candles.length) return true;
    if (scaleX != old.scaleX || offsetX != old.offsetX) return true;
    if (scaleY != old.scaleY || priceOffset != old.priceOffset) return true;
    if (crosshairPos != old.crosshairPos) return true;
    if (signal != old.signal) return true;
    if (activeTool != old.activeTool) return true;
    if (drawings.length != old.drawings.length) return true;
    // Check if the last candle changed (most frequent tick update)
    if (candles.isNotEmpty && old.candles.isNotEmpty) {
      final last = candles.last;
      final oldLast = old.candles.last;
      if (last.close != oldLast.close ||
          last.high != oldLast.high ||
          last.low != oldLast.low)
        return true;
    }
    return false;
  }
}

// ─── Helper classes for Right-Aligned Price Labels ──────────
class _RightLabel {
  final String text;
  final double targetY;
  final Color bgColor;
  final Color textColor;
  final bool isBadge;
  final String? badgeTitle;
  double actualY;

  _RightLabel({
    required this.text,
    required this.targetY,
    required this.bgColor,
    required this.textColor,
    this.isBadge = false,
    this.badgeTitle,
  }) : actualY = targetY;
}

// ─── Drawing Serialization Helpers ───────────────────────────
Map<String, dynamic> drawingToJson(DrawingObject obj) {
  final map = <String, dynamic>{'id': obj.id, 'type': obj.type.name};
  if (obj is TrendLineDrawing) {
    map['p1_x'] = obj.p1.dx;
    map['p1_y'] = obj.p1.dy;
    map['p2_x'] = obj.p2.dx;
    map['p2_y'] = obj.p2.dy;
    map['isComplete'] = obj.isComplete;
  } else if (obj is HorizontalLineDrawing) {
    map['price'] = obj.price;
  } else if (obj is VerticalLineDrawing) {
    map['xFraction'] = obj.xFraction;
  } else if (obj is RectangleDrawing) {
    map['p1_x'] = obj.p1.dx;
    map['p1_y'] = obj.p1.dy;
    map['p2_x'] = obj.p2.dx;
    map['p2_y'] = obj.p2.dy;
    map['isComplete'] = obj.isComplete;
  } else if (obj is FibonacciDrawing) {
    map['p1_x'] = obj.p1.dx;
    map['p1_y'] = obj.p1.dy;
    map['p2_x'] = obj.p2.dx;
    map['p2_y'] = obj.p2.dy;
    map['isComplete'] = obj.isComplete;
  } else if (obj is TextDrawing) {
    map['pos_x'] = obj.position.dx;
    map['pos_y'] = obj.position.dy;
    map['text'] = obj.text;
  } else if (obj is RulerDrawing) {
    map['p1_x'] = obj.p1.dx;
    map['p1_y'] = obj.p1.dy;
    map['p2_x'] = obj.p2.dx;
    map['p2_y'] = obj.p2.dy;
    map['isComplete'] = obj.isComplete;
  }
  return map;
}

DrawingObject? drawingFromJson(Map<String, dynamic> json) {
  final id = json['id'] as String? ?? '';
  final typeName = json['type'] as String? ?? '';
  if (typeName == DrawingType.trendLine.name) {
    return TrendLineDrawing(
      id: id,
      p1: Offset(
        json['p1_x'] as double? ?? 0.0,
        json['p1_y'] as double? ?? 0.0,
      ),
      p2: Offset(
        json['p2_x'] as double? ?? 0.0,
        json['p2_y'] as double? ?? 0.0,
      ),
      isComplete: json['isComplete'] as bool? ?? false,
    );
  } else if (typeName == DrawingType.horizontalLine.name) {
    return HorizontalLineDrawing(
      id: id,
      price: json['price'] as double? ?? 0.0,
    );
  } else if (typeName == DrawingType.verticalLine.name) {
    return VerticalLineDrawing(
      id: id,
      xFraction: json['xFraction'] as double? ?? 0.0,
    );
  } else if (typeName == DrawingType.rectangle.name) {
    return RectangleDrawing(
      id: id,
      p1: Offset(
        json['p1_x'] as double? ?? 0.0,
        json['p1_y'] as double? ?? 0.0,
      ),
      p2: Offset(
        json['p2_x'] as double? ?? 0.0,
        json['p2_y'] as double? ?? 0.0,
      ),
      isComplete: json['isComplete'] as bool? ?? false,
    );
  } else if (typeName == DrawingType.fibonacci.name) {
    return FibonacciDrawing(
      id: id,
      p1: Offset(
        json['p1_x'] as double? ?? 0.0,
        json['p1_y'] as double? ?? 0.0,
      ),
      p2: Offset(
        json['p2_x'] as double? ?? 0.0,
        json['p2_y'] as double? ?? 0.0,
      ),
      isComplete: json['isComplete'] as bool? ?? false,
    );
  } else if (typeName == DrawingType.text.name) {
    return TextDrawing(
      id: id,
      position: Offset(
        json['pos_x'] as double? ?? 0.0,
        json['pos_y'] as double? ?? 0.0,
      ),
      text: json['text'] as String? ?? '',
    );
  } else if (typeName == DrawingType.ruler.name) {
    return RulerDrawing(
      id: id,
      p1: Offset(
        json['p1_x'] as double? ?? 0.0,
        json['p1_y'] as double? ?? 0.0,
      ),
      p2: Offset(
        json['p2_x'] as double? ?? 0.0,
        json['p2_y'] as double? ?? 0.0,
      ),
      isComplete: json['isComplete'] as bool? ?? false,
    );
  }
  return null;
}

String serializeDrawings(List<DrawingObject> list) {
  final listJson = list.map((e) => drawingToJson(e)).toList();
  return jsonEncode(listJson);
}

List<DrawingObject> deserializeDrawings(String jsonStr) {
  try {
    final list = jsonDecode(jsonStr) as List<dynamic>? ?? [];
    return list
        .map((e) => drawingFromJson(Map<String, dynamic>.from(e as Map)))
        .whereType<DrawingObject>()
        .toList();
  } catch (e) {
    return [];
  }
}
