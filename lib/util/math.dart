import 'dart:math' as math;

/// Pearson correlation coefficient. 0 when undefined (constant series / <2 points).
double pearson(List<double> xs, List<double> ys) {
  final n = math.min(xs.length, ys.length);
  if (n < 2) return 0;
  double sx = 0, sy = 0, sxx = 0, syy = 0, sxy = 0;
  for (var i = 0; i < n; i++) {
    final x = xs[i], y = ys[i];
    sx += x;
    sy += y;
    sxx += x * x;
    syy += y * y;
    sxy += x * y;
  }
  final cov = n * sxy - sx * sy;
  final dx = math.sqrt(n * sxx - sx * sx);
  final dy = math.sqrt(n * syy - sy * sy);
  if (dx == 0 || dy == 0 || dx.isNaN || dy.isNaN) return 0;
  return (cov / (dx * dy)).clamp(-1.0, 1.0);
}

/// Plain-language reading of a correlation magnitude.
String correlationLabel(double r) {
  final a = r.abs();
  if (a < 0.12) return 'No clear link';
  final strength = a >= 0.6 ? 'Strong' : a >= 0.3 ? 'Moderate' : 'Mild';
  final dir = r > 0 ? 'higher mood ↔ higher net flow' : 'lower mood ↔ heavier spend';
  return '$strength link · $dir';
}
