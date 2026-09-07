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
