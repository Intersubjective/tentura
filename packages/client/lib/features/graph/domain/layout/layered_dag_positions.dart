import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'radial_hop_positions.dart' show kLayoutClampMargin;

/// Deterministic layered ("Sugiyama-lite") layout for the invite genealogy and
/// the forwards graph: rank = distance from the root, drawn top to bottom.
Map<String, Offset> layeredDagPositions({
  required Set<String> nodeIds,
  required Set<(String, String)> edges,
  required Set<String> rootIds,
  required Size canvasSize,
  double layerGap = 150,
  double columnGap = 130,
}) {
  if (nodeIds.isEmpty) {
    return {};
  }

  final forwardAdj = <String, List<String>>{};
  final reverseAdj = <String, List<String>>{};
  final inDegree = <String, int>{for (final id in nodeIds) id: 0};

  for (final id in nodeIds) {
    forwardAdj[id] = [];
    reverseAdj[id] = [];
  }

  for (final (src, dst) in edges) {
    if (!nodeIds.contains(src) || !nodeIds.contains(dst) || src == dst) {
      continue;
    }
    forwardAdj[src]!.add(dst);
    reverseAdj[dst]!.add(src);
    inDegree[dst] = inDegree[dst]! + 1;
  }

  for (final neighbors in forwardAdj.values) {
    neighbors.sort();
    final deduped = neighbors.toSet().toList();
    neighbors
      ..clear()
      ..addAll(deduped);
  }
  for (final neighbors in reverseAdj.values) {
    neighbors.sort();
    final deduped = neighbors.toSet().toList();
    neighbors
      ..clear()
      ..addAll(deduped);
  }

  final roots = _resolveRoots(nodeIds, rootIds, inDegree);
  final rank = <String, int>{};
  final queue = Queue<String>();
  for (final root in roots) {
    rank[root] = 0;
    queue.add(root);
  }

  while (queue.isNotEmpty) {
    final current = queue.removeFirst();
    for (final neighbor in forwardAdj[current]!) {
      final nextRank = rank[current]! + 1;
      if (!rank.containsKey(neighbor) || rank[neighbor]! > nextRank) {
        rank[neighbor] = nextRank;
        queue.add(neighbor);
      }
    }
  }

  final maxRank = rank.values.fold(0, math.max);
  final unreached = nodeIds.where((id) => !rank.containsKey(id)).toList();
  unreached.sort();
  for (final id in unreached) {
    rank[id] = maxRank + 1;
  }

  final layers = <int, List<String>>{};
  for (final id in nodeIds) {
    layers.putIfAbsent(rank[id]!, () => []).add(id);
  }

  final sortedRanks = layers.keys.toList()..sort();
  final layerOrder = <String, int>{};

  for (final layerRank in sortedRanks) {
    final layer = List<String>.from(layers[layerRank]!);
    layer.sort((a, b) {
      final baryA = _barycentreOfPredecessors(a, reverseAdj, layerOrder);
      final baryB = _barycentreOfPredecessors(b, reverseAdj, layerOrder);
      final cmp = baryA.compareTo(baryB);
      if (cmp != 0) {
        return cmp;
      }
      return a.compareTo(b);
    });
    for (var index = 0; index < layer.length; index++) {
      layerOrder[layer[index]] = index;
    }
    layers[layerRank] = layer;
  }

  for (final layerRank in sortedRanks.reversed) {
    final layer = List<String>.from(layers[layerRank]!);
    final passOneOrder = {
      for (var index = 0; index < layer.length; index++) layer[index]: index,
    };
    layer.sort((a, b) {
      final baryA = _barycentreOfSuccessors(a, forwardAdj, layerOrder);
      final baryB = _barycentreOfSuccessors(b, forwardAdj, layerOrder);
      final cmp = baryA.compareTo(baryB);
      if (cmp != 0) {
        return cmp;
      }
      return passOneOrder[a]!.compareTo(passOneOrder[b]!);
    });
    for (var index = 0; index < layer.length; index++) {
      layerOrder[layer[index]] = index;
    }
    layers[layerRank] = layer;
  }

  final x = <String, double>{};
  for (final layerRank in sortedRanks) {
    final layer = layers[layerRank]!;
    final count = layer.length;
    for (var index = 0; index < count; index++) {
      x[layer[index]] =
          canvasSize.width / 2 + (index - (count - 1) / 2) * columnGap;
    }
  }

  final maxRankValue = sortedRanks.last;
  final positions = <String, Offset>{};
  for (final id in nodeIds) {
    final y = canvasSize.height / 2 + (rank[id]! - maxRankValue / 2) * layerGap;
    positions[id] = _clampPosition(Offset(x[id]!, y), canvasSize);
  }

  return positions;
}

Set<String> _resolveRoots(
  Set<String> nodeIds,
  Set<String> rootIds,
  Map<String, int> inDegree,
) {
  if (rootIds.isNotEmpty) {
    return rootIds.where(nodeIds.contains).toSet();
  }
  final zeroInDegree = nodeIds.where((id) => inDegree[id] == 0).toSet();
  if (zeroInDegree.isNotEmpty) {
    return zeroInDegree;
  }
  return {nodeIds.reduce((a, b) => a.compareTo(b) < 0 ? a : b)};
}

double _barycentreOfPredecessors(
  String id,
  Map<String, List<String>> reverseAdj,
  Map<String, int> layerOrder,
) {
  final placed = reverseAdj[id]!
      .where((predecessor) => layerOrder.containsKey(predecessor))
      .toList();
  if (placed.isEmpty) {
    return double.infinity;
  }
  return placed
          .map((predecessor) => layerOrder[predecessor]!.toDouble())
          .reduce(
            (sum, value) => sum + value,
          ) /
      placed.length;
}

double _barycentreOfSuccessors(
  String id,
  Map<String, List<String>> forwardAdj,
  Map<String, int> layerOrder,
) {
  final placed = forwardAdj[id]!
      .where((successor) => layerOrder.containsKey(successor))
      .toList();
  if (placed.isEmpty) {
    return double.infinity;
  }
  return placed
          .map((successor) => layerOrder[successor]!.toDouble())
          .reduce(
            (sum, value) => sum + value,
          ) /
      placed.length;
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
