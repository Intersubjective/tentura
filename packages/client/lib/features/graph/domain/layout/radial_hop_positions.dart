import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

/// Fixed margin for clamping positions when node sizes are unknown.
const double kLayoutClampMargin = 80;

/// Padding added to the largest child diameter when deriving [minChord].
const double kFanSizePadding = 24;

/// Soft cap on local-fan radius as a multiple of [ringGap].
const double kFanRadiusMultiplier = 3;

/// Default forward-cone width for local fan (120°).
const double kDefaultMaxFanRadians = 2 * math.pi / 3;

/// Result of a radial-hop pass: absolute seats plus the BFS parent map used to
/// park newly revealed nodes next to an already-pinned parent.
typedef RadialHopLayout = ({
  Map<String, Offset> positions,
  Map<String, String> parent,
  Map<String, int> depth,
});

/// Deterministic ego-centric layout: concentric rings by BFS hop distance.
///
/// Guarantees, all covered by tests:
///  * the result depends only on the arguments, never on iteration order of the
///    input sets (every neighbour list is sorted by id before use);
///  * a node's ring is its hop distance from [rootId] over the **undirected**
///    projection of [edges], so cycles are handled without special cases;
///  * adding a node does not move any node that was already present, as long as
///    its hop distance and its BFS parent did not change.
///  * angles are assigned once from sorted BFS sectors — there is no rotation
///    based on the active focus path, so selecting a node does not spin the
///    graph.
RadialHopLayout computeRadialHopLayout({
  required Set<String> nodeIds,
  required Set<(String, String)> edges,
  required String rootId,
  required Size canvasSize,
  double ringGap = 170,
}) {
  if (nodeIds.isEmpty) {
    return (
      positions: <String, Offset>{},
      parent: <String, String>{},
      depth: <String, int>{},
    );
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
  final minChord = amenityChordForRingGap(ringGap);

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
    final span = end - start;
    // Every child gets a floor share wide enough to keep its ring chord at
    // [minChord]; only the surplus is handed out by subtree size. BFS attaches
    // a shared frontier to whichever sibling it dequeues first, so raw
    // subtree-proportional sectors let one arbitrary sibling eat the circle and
    // squeeze the rest into a few overlapping degrees. When the floors do not
    // fit, `guaranteed` collapses to an equal split and the surplus is zero.
    final childRadius = (depth[id]! + 1) * ringGap;
    final guaranteed = math.min(
      preferredFanStep(childRadius, minChord),
      span / childList.length,
    );
    final surplus = span - guaranteed * childList.length;
    var current = start;
    for (final child in childList) {
      final childSpan =
          guaranteed + surplus * subtreeSize[child]! / totalSubtree;
      assignSectors(child, current, current + childSpan);
      current += childSpan;
    }
  }

  if (nodeIds.contains(rootId)) {
    assignSectors(rootId, 0, 2 * math.pi);
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
    positions[id] = clampLayoutPosition(centre + offset, canvasSize);
  }

  return (positions: positions, parent: parent, depth: depth);
}

/// Convenience wrapper kept for call sites that only need absolute seats.
Map<String, Offset> radialHopPositions({
  required Set<String> nodeIds,
  required Set<(String, String)> edges,
  required String rootId,
  required Size canvasSize,
  double ringGap = 170,
}) => computeRadialHopLayout(
  nodeIds: nodeIds,
  edges: edges,
  rootId: rootId,
  canvasSize: canvasSize,
  ringGap: ringGap,
).positions;

/// Clamps a canvas position inside [canvasSize] with [kLayoutClampMargin].
Offset clampLayoutPosition(Offset position, Size canvasSize) {
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

/// Unit vector continuing the branch past [parentPos], preferring
/// `parentPos - grandparentPos` so expand keeps the trail's direction.
Offset branchUnitDirection({
  required Offset parentPos,
  Offset? grandparentPos,
  Offset? rootPos,
}) {
  Offset? from(Offset? origin) {
    if (origin == null) {
      return null;
    }
    final delta = parentPos - origin;
    if (delta.distanceSquared < 1e-6) {
      return null;
    }
    return delta / delta.distance;
  }

  return from(grandparentPos) ??
      from(rootPos) ??
      const Offset(0, 1); // canvas "down" when everything coincides
}

/// Amenity chord matching the legacy 30° step at [ringGap].
double amenityChordForRingGap(double ringGap) =>
    2 * ringGap * math.sin(math.pi / 12);

/// Angular step that keeps adjacent centres at least [minChord] apart on a
/// circle of radius [radius].
double preferredFanStep(double radius, double minChord) {
  if (radius < 1e-9) {
    return math.pi;
  }
  final ratio = (minChord / (2 * radius)).clamp(0.0, 1.0);
  return 2 * math.asin(ratio);
}

/// Solves radius so equal steps over [span] keep chord ≥ [minChord].
double radiusForFanSpan({
  required double span,
  required int childCount,
  required double minChord,
  required double ringGap,
  required double rMax,
}) {
  if (childCount < 2) {
    return ringGap;
  }
  final halfStep = span / (2 * (childCount - 1));
  if (halfStep < 1e-9) {
    return rMax;
  }
  final sinHalf = math.sin(halfStep);
  final solved = sinHalf < 1e-9
      ? minChord / halfStep
      : minChord / (2 * sinHalf);
  return solved.clamp(ringGap, rMax);
}

/// Geometry for a local fan: equal angular steps, compactness first.
({double span, double radius, double step}) computeLocalFanGeometry({
  required int childCount,
  required double ringGap,
  required double minChord,
  double maxFanRadians = kDefaultMaxFanRadians,
  double? rMax,
}) {
  if (childCount < 2) {
    return (span: 0, radius: ringGap, step: 0);
  }

  final effectiveRMax = rMax ?? ringGap * kFanRadiusMultiplier;

  final effectiveMaxSpan = maxFanRadians < 1e-6 ? 1e-6 : maxFanRadians;
  final preferredAtRing = preferredFanStep(ringGap, minChord);
  final naturalSpan = (childCount - 1) * preferredAtRing;

  if (naturalSpan <= effectiveMaxSpan) {
    return (
      span: naturalSpan,
      radius: ringGap,
      step: preferredAtRing,
    );
  }

  final span = effectiveMaxSpan;
  final radius = radiusForFanSpan(
    span: span,
    childCount: childCount,
    minChord: minChord,
    ringGap: ringGap,
    rMax: effectiveRMax,
  );
  return (
    span: span,
    radius: radius,
    step: span / (childCount - 1),
  );
}

/// Parks [childIds] (already sorted) in a compact fan around [parentPos]
/// along [direction], at distance [ringGap]. Preserves branch heading instead
/// of reusing global radial sectors (which fling siblings across the canvas).
///
/// Packing uses [minChord] (default: [amenityChordForRingGap]) and expands the
/// forward cone up to [maxFanRadians] before growing radius (capped at [rMax]).
Map<String, Offset> localFanPositions({
  required Offset parentPos,
  required Offset direction,
  required List<String> childIds,
  required Size canvasSize,
  double ringGap = 170,
  double maxFanRadians = kDefaultMaxFanRadians,
  double? minChord,
  double? rMax,
}) {
  if (childIds.isEmpty) {
    return {};
  }

  final unit = direction.distanceSquared < 1e-6
      ? const Offset(0, 1)
      : direction / direction.distance;
  final baseAngle = math.atan2(unit.dy, unit.dx);
  final n = childIds.length;
  final positions = <String, Offset>{};
  final effectiveMinChord = minChord ?? amenityChordForRingGap(ringGap);
  final effectiveRMax = rMax ?? ringGap * kFanRadiusMultiplier;

  if (n == 1) {
    positions[childIds.single] = clampLayoutPosition(
      parentPos + unit * ringGap,
      canvasSize,
    );
    return positions;
  }

  final geometry = computeLocalFanGeometry(
    childCount: n,
    ringGap: ringGap,
    minChord: effectiveMinChord,
    maxFanRadians: maxFanRadians,
    rMax: effectiveRMax,
  );
  final start = baseAngle - geometry.span / 2;
  for (var i = 0; i < n; i++) {
    final angle = start + geometry.step * i;
    final offset = Offset(math.cos(angle), math.sin(angle)) * geometry.radius;
    positions[childIds[i]] = clampLayoutPosition(parentPos + offset, canvasSize);
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
