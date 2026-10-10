import 'layout_geometry.dart';
import 'spatial_index.dart';

/// Uniform-grid [SpatialIndex]: each rectangle is bucketed into every cell it
/// touches, so a query only tests rectangles sharing a cell with the probe.
///
/// Results match [BruteForceIndex] exactly, including insertion order (a
/// re-inserted id keeps its original position).
class GridIndex implements SpatialIndex {
  GridIndex({this.cellSize = 128}) : assert(cellSize > 0, 'cellSize > 0');

  final double cellSize;

  final Map<String, _Entry> _entries = {};
  final Map<(int, int), Set<String>> _cells = {};
  int _nextSeq = 0;

  @override
  int get length => _entries.length;

  @override
  void insert(String id, LRect rect) {
    final previous = _entries[id];
    if (previous != null) _unbucket(id, previous.rect);
    _entries[id] = _Entry(previous?.seq ?? _nextSeq++, rect);
    _forEachCell(rect, (cell) => (_cells[cell] ??= {}).add(id));
  }

  @override
  bool remove(String id) {
    final entry = _entries.remove(id);
    if (entry == null) return false;
    _unbucket(id, entry.rect);
    return true;
  }

  @override
  List<String> queryOverlaps(LRect rect, {String? exceptId}) {
    final hits = <String, _Entry>{};
    _forEachCell(rect, (cell) {
      final ids = _cells[cell];
      if (ids == null) return;
      for (final id in ids) {
        if (id == exceptId || hits.containsKey(id)) continue;
        final entry = _entries[id]!;
        if (_overlaps(entry.rect, rect)) hits[id] = entry;
      }
    });
    return (hits.entries.toList()
          ..sort((a, b) => a.value.seq.compareTo(b.value.seq)))
        .map((e) => e.key)
        .toList();
  }

  void _unbucket(String id, LRect rect) => _forEachCell(rect, (cell) {
    final ids = _cells[cell];
    if (ids == null) return;
    ids.remove(id);
    if (ids.isEmpty) _cells.remove(cell);
  });

  void _forEachCell(LRect rect, void Function((int, int) cell) visit) {
    final x0 = (rect.left / cellSize).floor();
    final x1 = (rect.right / cellSize).floor();
    final y0 = (rect.top / cellSize).floor();
    final y1 = (rect.bottom / cellSize).floor();
    for (var x = x0; x <= x1; x++) {
      for (var y = y0; y <= y1; y++) {
        visit((x, y));
      }
    }
  }

  static bool _overlaps(LRect a, LRect b) =>
      a.left < b.right &&
      b.left < a.right &&
      a.top < b.bottom &&
      b.top < a.bottom;
}

class _Entry {
  const _Entry(this.seq, this.rect);

  final int seq;
  final LRect rect;
}
