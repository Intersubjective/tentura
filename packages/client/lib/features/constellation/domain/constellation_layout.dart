import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:tentura/features/graph/domain/layout/radial_hop_positions.dart';

import 'constellation_path_resolution.dart';

typedef ConstellationLayout = ({
  Map<String, Offset> positions,
  Map<String, int> ring,
});

ConstellationLayout computeConstellationLayout({
  required String egoId,
  required ConstellationPathResolution paths,
  required Set<String> keptPeerIds,
  required Map<String, List<String>> visibleRequestsByAuthor,
  required Set<String> egoOwnRequestIds,
  required Size canvasSize,
  int maxHops = 3,
  double ringGap = 170,
  double residualRingFactor = 1.6,
  double satelliteOffset = 56,
}) {
  final centre = canvasSize.center(Offset.zero);
  final positions = <String, Offset>{};
  final ring = <String, int>{};

  // Pass 1 — person tree over paths.keep ∩ keptPeerIds; ego always included.
  final treePeers = paths.keep.intersection(keptPeerIds);
  final children = <String, List<String>>{};

  for (final id in treePeers) {
    final parentId = paths.parent[id];
    if (parentId == null) {
      continue;
    }
    if (parentId == egoId || treePeers.contains(parentId)) {
      children.putIfAbsent(parentId, () => <String>[]).add(id);
    }
  }

  final angle = <String, double>{};

  void assignEqualSectors(String id, double start, double end) {
    angle[id] = (start + end) / 2;
    final childList = List<String>.from(children[id] ?? const <String>[]);
    childList.sort();
    if (childList.isEmpty) {
      return;
    }
    final childSpan = (end - start) / childList.length;
    var current = start;
    for (final child in childList) {
      assignEqualSectors(child, current, current + childSpan);
      current += childSpan;
    }
  }

  assignEqualSectors(egoId, 0, 2 * math.pi);

  positions[egoId] = centre;
  ring[egoId] = 0;

  for (final id in treePeers) {
    final depth = paths.depth[id];
    if (depth == null) {
      continue;
    }
    final nodeAngle = angle[id] ?? 0;
    final radius = depth * ringGap;
    final offset =
        Offset(
          math.cos(nodeAngle - math.pi / 2),
          math.sin(nodeAngle - math.pi / 2),
        ) *
        radius;
    positions[id] = clampLayoutPosition(centre + offset, canvasSize);
    ring[id] = depth;
  }

  // Pass 2 — residual ring: paths.ring ∩ keptPeerIds, evenly spaced by id.
  final ringPeers = paths.ring.intersection(keptPeerIds).toList()
    ..sort();
  if (ringPeers.isNotEmpty) {
    final ringRadius = (maxHops + residualRingFactor) * ringGap;
    final step = 2 * math.pi / ringPeers.length;
    for (var i = 0; i < ringPeers.length; i++) {
      final nodeAngle = step * i;
      final offset =
          Offset(
            math.cos(nodeAngle - math.pi / 2),
            math.sin(nodeAngle - math.pi / 2),
          ) *
          ringRadius;
      final id = ringPeers[i];
      positions[id] = clampLayoutPosition(centre + offset, canvasSize);
      ring[id] = maxHops + 1;
    }
  }

  // Pass 3 — satellites along each author's radial direction (D16: ego off centre).
  final egoRequests = egoOwnRequestIds.toList()..sort();
  if (egoRequests.isNotEmpty) {
    final egoSatellites = localFanPositions(
      parentPos: centre,
      direction: branchUnitDirection(parentPos: centre),
      childIds: egoRequests,
      canvasSize: canvasSize,
      ringGap: satelliteOffset,
    );
    positions.addAll(egoSatellites);
  }

  final authors = visibleRequestsByAuthor.keys.toList()..sort();
  for (final author in authors) {
    if (author == egoId) {
      continue;
    }
    final authorPos = positions[author];
    if (authorPos == null) {
      continue;
    }
    final requestIds = List<String>.from(visibleRequestsByAuthor[author]!)
      ..sort();
    if (requestIds.isEmpty) {
      continue;
    }

    final radial = authorPos - centre;
    final direction = radial.distanceSquared < 1e-6
        ? branchUnitDirection(parentPos: centre)
        : radial / radial.distance;

    final satellites = localFanPositions(
      parentPos: authorPos,
      direction: direction,
      childIds: requestIds,
      canvasSize: canvasSize,
      ringGap: satelliteOffset,
    );
    positions.addAll(satellites);
  }

  return (positions: positions, ring: ring);
}
