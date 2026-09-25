import 'dart:math' as math;

/// Pure helpers for KineticChart price viewport (Y-scale / pan).
({double min, double max, double range}) computePriceWindow({
  required double autoMin,
  required double autoMax,
  double scaleY = 1.0,
  double priceOffset = 0.0,
}) {
  var rng = autoMax - autoMin;
  if (rng == 0) rng = 1;
  final sy = scaleY.clamp(0.25, 8.0);
  final center = (autoMax + autoMin) / 2 + priceOffset;
  final half = (rng / 2) / sy;
  final max = center + half;
  final min = center - half;
  return (min: min, max: max, range: max - min);
}

double computeTimeAxisDragScale({
  required double initialScale,
  required double horizontalDelta,
}) => (initialScale * math.exp(horizontalDelta / 180)).clamp(0.2, 10.0);

double computePriceAxisDragScale({
  required double initialScale,
  required double verticalDelta,
}) => (initialScale * math.exp(-verticalDelta / 180)).clamp(0.25, 8.0);
