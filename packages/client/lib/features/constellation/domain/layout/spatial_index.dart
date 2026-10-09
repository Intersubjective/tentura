import 'layout_geometry.dart';

/// Broad-phase overlap index over id-keyed rectangles (ARCH D6).
///
/// Overlap is strict: rectangles that only share an edge or a corner do not
/// overlap.
abstract interface class SpatialIndex {
  /// Number of indexed ids.
  int get length;

  /// Adds [id] at [rect], replacing any previous rectangle for the same id.
  void insert(String id, LRect rect);

  /// Removes [id]; returns whether it was present.
  bool remove(String id);

  /// Ids whose rectangle overlaps [rect], in insertion order, skipping
  /// [exceptId] when given.
  List<String> queryOverlaps(LRect rect, {String? exceptId});
}

/// Linear-scan [SpatialIndex]: the default and the oracle for any faster
/// implementation.
class BruteForceIndex implements SpatialIndex {
  final Map<String, LRect> _rects = {};

  @override
  int get length => _rects.length;

  @override
  void insert(String id, LRect rect) => _rects[id] = rect;

  @override
  bool remove(String id) => _rects.remove(id) != null;

  @override
  List<String> queryOverlaps(LRect rect, {String? exceptId}) => [
    for (final e in _rects.entries)
      if (e.key != exceptId && _overlaps(e.value, rect)) e.key,
  ];

  static bool _overlaps(LRect a, LRect b) =>
      a.left < b.right &&
      b.left < a.right &&
      a.top < b.bottom &&
      b.top < a.bottom;
}
