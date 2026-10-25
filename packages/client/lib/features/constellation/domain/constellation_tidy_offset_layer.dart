import 'layout/layout_geometry.dart';

/// Post-layout offsets left by «Tidy up»: every layout pass is shifted by
/// them, so a data refresh keeps the tidied positions.
class ConstellationTidyOffsetLayer {
  ConstellationTidyOffsetLayer();

  factory ConstellationTidyOffsetLayer.fromJson(Map<String, dynamic> json) =>
      ConstellationTidyOffsetLayer()..replaceAll({
        for (final e in json.entries)
          e.key: (
            x: ((e.value as Map<String, dynamic>)['x'] as num).toDouble(),
            y: ((e.value as Map<String, dynamic>)['y'] as num).toDouble(),
          ),
      });

  final _offsets = <String, LPoint>{};

  bool get isEmpty => _offsets.isEmpty;

  /// A copy of the current offsets.
  Map<String, LPoint> get offsets => Map.of(_offsets);

  LPoint? offsetOf(String id) => _offsets[id];

  /// Adds each person's move from [from] to [to] to their offset.
  void recordMoves({
    required Map<String, LPoint> from,
    required Map<String, LPoint> to,
  }) {
    for (final e in to.entries) {
      final start = from[e.key];
      if (start == null) continue;
      final old = _offsets[e.key] ?? (x: 0.0, y: 0.0);
      _offsets[e.key] = (
        x: old.x + e.value.x - start.x,
        y: old.y + e.value.y - start.y,
      );
    }
  }

  void replaceAll(Map<String, LPoint> offsets) {
    _offsets
      ..clear()
      ..addAll(offsets);
  }

  void clear(Set<String> ids) =>
      _offsets.removeWhere((id, _) => ids.contains(id));

  void clearAll() => _offsets.clear();

  void retainOnly(Set<String> ids) =>
      _offsets.removeWhere((id, _) => !ids.contains(id));

  /// [layout] shifted by the offsets; people without one keep their place.
  Map<String, LPoint> apply(Map<String, LPoint> layout) => {
    for (final e in layout.entries)
      e.key: switch (_offsets[e.key]) {
        final LPoint o => (x: e.value.x + o.x, y: e.value.y + o.y),
        null => e.value,
      },
  };

  Map<String, dynamic> toJson() => {
    for (final e in _offsets.entries) e.key: {'x': e.value.x, 'y': e.value.y},
  };
}
