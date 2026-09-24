/// Reads a MeritRank score column: SQL `NULL` means no score (0).
double mrScoreAsDouble(Object? value) {
  if (value == null) {
    return 0;
  }
  if (value is num) {
    return value.toDouble();
  }
  throw StateError('Expected num, got ${value.runtimeType}');
}
