import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';
import 'package:tentura/features/constellation/domain/layout/spatial_index.dart';

import 'spatial_bench_geometry.dart';

/// Benchmark-only sweep on the left edge; updates maintain sorted endpoints.
class SweepAndPruneIndex implements SpatialIndex {
  final _rects = <String, LRect>{};
  final _sorted = <String>[];
  final _order = <String, int>{};
  int _nextOrder = 0;

  @override
  int get length => _rects.length;

  @override
  void insert(String id, LRect rect) {
    _sorted.remove(id);
    _order.putIfAbsent(id, () => _nextOrder++);
    _rects[id] = rect;
    var low = 0;
    var high = _sorted.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_rects[_sorted[middle]]!.left < rect.left) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    _sorted.insert(low, id);
  }

  @override
  bool remove(String id) {
    if (_rects.remove(id) == null) return false;
    _sorted.remove(id);
    _order.remove(id);
    return true;
  }

  @override
  List<String> queryOverlaps(LRect rect, {String? exceptId}) {
    final result = <String>[];
    for (final id in _sorted) {
      final candidate = _rects[id]!;
      if (candidate.left >= rect.right) break;
      if (id != exceptId && overlaps(candidate, rect)) result.add(id);
    }
    return result..sort((a, b) => _order[a]!.compareTo(_order[b]!));
  }
}
