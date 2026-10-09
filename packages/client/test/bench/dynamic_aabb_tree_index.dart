import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';
import 'package:tentura/features/constellation/domain/layout/spatial_index.dart';

import 'spatial_bench_geometry.dart';

class _Node {
  _Node(this.rect, {this.id, this.order = 0, this.left, this.right});

  LRect rect;
  final String? id;
  final int order;
  _Node? parent;
  _Node? left;
  _Node? right;
}

/// Benchmark-only dynamic bounding-volume tree with greedy perimeter insertion.
class DynamicAabbTreeIndex implements SpatialIndex {
  final _leaves = <String, _Node>{};
  _Node? _root;
  int _nextOrder = 0;

  @override
  int get length => _leaves.length;

  void _refit(_Node? node) {
    var current = node;
    while (current != null) {
      current.rect = bounds(current.left!.rect, current.right!.rect);
      current = current.parent;
    }
  }

  @override
  void insert(String id, LRect rect) {
    final order = _leaves[id]?.order;
    remove(id);
    final leaf = _Node(rect, id: id, order: order ?? _nextOrder++);
    _leaves[id] = leaf;
    var sibling = _root;
    if (sibling == null) {
      _root = leaf;
      return;
    }
    while (sibling!.id == null) {
      final left = sibling.left!;
      final right = sibling.right!;
      final leftCost =
          perimeter(bounds(left.rect, rect)) - perimeter(left.rect);
      final rightCost =
          perimeter(bounds(right.rect, rect)) - perimeter(right.rect);
      sibling = leftCost <= rightCost ? left : right;
    }
    final parent = sibling.parent;
    final branch = _Node(bounds(sibling.rect, rect), left: sibling, right: leaf)
      ..parent = parent;
    sibling.parent = branch;
    leaf.parent = branch;
    if (parent == null) {
      _root = branch;
    } else if (parent.left == sibling) {
      parent.left = branch;
    } else {
      parent.right = branch;
    }
    _refit(parent);
  }

  @override
  bool remove(String id) {
    final leaf = _leaves.remove(id);
    if (leaf == null) return false;
    final parent = leaf.parent;
    if (parent == null) {
      _root = null;
      return true;
    }
    final sibling = parent.left == leaf ? parent.right! : parent.left!;
    final grandparent = parent.parent;
    sibling.parent = grandparent;
    if (grandparent == null) {
      _root = sibling;
    } else {
      if (grandparent.left == parent) {
        grandparent.left = sibling;
      } else {
        grandparent.right = sibling;
      }
      _refit(grandparent);
    }
    return true;
  }

  @override
  List<String> queryOverlaps(LRect rect, {String? exceptId}) {
    final result = <_Node>[];
    final pending = <_Node>[?_root];
    while (pending.isNotEmpty) {
      final node = pending.removeLast();
      if (!overlaps(node.rect, rect)) continue;
      if (node.id != null) {
        if (node.id != exceptId) result.add(node);
      } else {
        pending
          ..add(node.left!)
          ..add(node.right!);
      }
    }
    result.sort((a, b) => a.order.compareTo(b.order));
    return [for (final node in result) node.id!];
  }
}
