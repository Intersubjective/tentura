import 'dart:ui';

const _defaultJitterRange = 8.0;

/// Stable across VM runs (unlike [Object.hash]).
int stableScatterHash(String id, int salt) {
  var hash = 2166136261;
  for (final unit in id.codeUnits) {
    hash ^= unit;
    hash = (hash * 16777619) & 0xFFFFFFFF;
  }
  hash ^= salt;
  hash = (hash * 16777619) & 0xFFFFFFFF;
  return hash;
}

Offset scatterPlotJitterOffsetForId(
  String id, {
  double jitterRange = _defaultJitterRange,
}) {
  final h = stableScatterHash(id, 0);
  final h2 = stableScatterHash(id, 1);
  final dx = ((h % 1000) / 1000.0 * 2 - 1) * jitterRange;
  final dy = ((h2 % 1000) / 1000.0 * 2 - 1) * jitterRange;
  return Offset(dx, dy);
}
