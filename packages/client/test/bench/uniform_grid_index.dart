import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';
import 'package:tentura/features/constellation/domain/layout/spatial_index.dart';

import 'spatial_bench_geometry.dart';

/// Benchmark-only uniform grid, including cell membership maintenance.
class UniformGridIndex implements SpatialIndex {
  static const _cellSize = 128.0;
  final _rects = <String, LRect>{};
  final _cells = <(int, int), Set<String>>{};
  final _order = <String, int>{};
  int _nextOrder = 0;

  Iterable<(int, int)> _keys(LRect rect) sync* {
    for (
      var x = (rect.left / _cellSize).floor();
      x < (rect.right / _cellSize).ceil();
      x++
    ) {
      for (
        var y = (rect.top / _cellSize).floor();
        y < (rect.bottom / _cellSize).ceil();
        y++
      ) {
        yield (x, y);
      }
    }
  }

  @override
  int get length => _rects.length;

  @override
  void insert(String id, LRect rect) {
    final order = _order[id];
    remove(id);
    _order[id] = order ?? _nextOrder++;
    _rects[id] = rect;
    for (final key in _keys(rect)) {
      (_cells[key] ??= <String>{}).add(id);
    }
  }

  @override
  bool remove(String id) {
    final rect = _rects.remove(id);
    if (rect == null) return false;
    for (final key in _keys(rect)) {
      final cell = _cells[key]!..remove(id);
      if (cell.isEmpty) _cells.remove(key);
    }
    _order.remove(id);
    return true;
  }

  @override
  List<String> queryOverlaps(LRect rect, {String? exceptId}) {
    final candidates = <String>{};
    for (final key in _keys(rect)) {
      final cell = _cells[key];
      if (cell != null) candidates.addAll(cell);
    }
    final result = [
      for (final id in candidates)
        if (id != exceptId && overlaps(_rects[id]!, rect)) id,
    ];
    return result..sort((a, b) => _order[a]!.compareTo(_order[b]!));
  }
}
