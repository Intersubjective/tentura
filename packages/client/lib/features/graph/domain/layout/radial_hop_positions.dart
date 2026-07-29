import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

/// Fixed margin for clamping positions when node sizes are unknown.
const double kLayoutClampMargin = 80;

/// Deterministic ego-centric layout: concentric rings by BFS hop distance.
///
/// Guarantees, all covered by tests:
///  * the result depends only on the arguments, never on iteration order of the
///    input sets (every neighbour list is sorted by id before use);
///  * a node's ring is its hop distance from [rootId] over the **undirected**
///    projection of [edges], so cycles are handled without special cases;
///  * adding a node does not move any node that was already present, as long as
///    its hop distance and its BFS parent did not change.
Map<String, Offset> radialHopPositions({
  required Set<String> nodeIds,
  required Set<(String, String)> edges,
  required String rootId,
  required Size canvasSize,
  List<String> focusPath = const [],
  double ringGap = 170,
}) {
  if (nodeIds.isEmpty) {
    return {};
  }

  final adj = _buildUndirectedAdjacency(nodeIds, edges);

  final depth = <String, int>{};
  final parent = <String, String>{};
  final children = <String, List<String>>{};
  final visited = <String>{};

  final queue = Queue<String>();
  if (nodeIds.contains(rootId)) {
    queue.add(rootId);
    visited.add(rootId);
    depth[rootId] = 0;
  }

  while (queue.isNotEmpty) {
    final current = queue.removeFirst();
    for (final neighbor in adj[current] ?? const <String>[]) {
      if (visited.contains(neighbor)) {
        continue;
      }
      visited.add(neighbor);
      depth[neighbor] = depth[current]! + 1;
      parent[neighbor] = current;
      children.putIfAbsent(current, () => []).add(neighbor);
      queue.add(neighbor);
    }
  }

  final maxDepth = depth.values.fold(0, math.max);
  final disconnected = nodeIds.where((id) => !visited.contains(id)).toList();
  disconnected.sort();
  for (final id in disconnected) {
    depth[id] = maxDepth + 1;
    parent[id] = rootId;
    children.putIfAbsent(rootId, () => []).add(id);
  }

  final subtreeSize = <String, int>{};
  final nodesByDepth = nodeIds.toList()
    ..sort((a, b) => depth[b]!.compareTo(depth[a]!));
  for (final id in nodesByDepth) {
    final childList = children[id] ?? const [];
    if (childList.isEmpty) {
      subtreeSize[id] = 1;
    } else {
      subtreeSize[id] =
          1 +
          childList
              .map((child) => subtreeSize[child]!)
              .fold<int>(0, (sum, size) => sum + size);
    }
  }

  final angle = <String, double>{};

  void assignSectors(String id, double start, double end) {
    angle[id] = (start + end) / 2;
    final childList = List<String>.from(children[id] ?? const []);
    childList.sort();
    final totalSubtree = childList
        .map((child) => subtreeSize[child]!)
        .fold<int>(0, (sum, size) => sum + size);
    if (totalSubtree == 0) {
      return;
    }
    var current = start;
    final span = end - start;
    for (final child in childList) {
      final childSpan = span * subtreeSize[child]! / totalSubtree;
      assignSectors(child, current, current + childSpan);
      current += childSpan;
    }
  }

  if (nodeIds.contains(rootId)) {
    assignSectors(rootId, 0, 2 * math.pi);
  }

  if (focusPath.length >= 2 && angle.containsKey(focusPath[1])) {
    final rotation = -angle[focusPath[1]]!;
    for (final id in angle.keys) {
      angle[id] = angle[id]! + rotation;
    }
  }

  final centre = canvasSize.center(Offset.zero);
  final positions = <String, Offset>{};

  for (final id in nodeIds) {
    if (id == rootId) {
      positions[id] = centre;
      continue;
    }
    final nodeAngle = angle[id] ?? 0;
    final radius = depth[id]! * ringGap;
    final offset =
        Offset(
          math.cos(nodeAngle - math.pi / 2),
          math.sin(nodeAngle - math.pi / 2),
        ) *
        radius;
    positions[id] = _clampPosition(centre + offset, canvasSize);
  }

  return positions;
}

Map<String, List<String>> _buildUndirectedAdjacency(
  Set<String> nodeIds,
  Set<(String, String)> edges,
) {
  final adj = <String, List<String>>{};
  for (final id in nodeIds) {
    adj[id] = [];
  }
  for (final (src, dst) in edges) {
    if (!nodeIds.contains(src) || !nodeIds.contains(dst) || src == dst) {
      continue;
    }
    adj[src]!.add(dst);
    adj[dst]!.add(src);
  }
  for (final neighbors in adj.values) {
    neighbors.sort();
    final deduped = neighbors.toSet().toList();
    neighbors
      ..clear()
      ..addAll(deduped);
  }
  return adj;
}

Offset _clampPosition(Offset position, Size canvasSize) {
  return Offset(
    position.dx.clamp(
      kLayoutClampMargin,
      canvasSize.width - kLayoutClampMargin,
    ),
    position.dy.clamp(
      kLayoutClampMargin,
      canvasSize.height - kLayoutClampMargin,
    ),
  );
}
