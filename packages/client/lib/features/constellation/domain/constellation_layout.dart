import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:tentura/features/graph/domain/layout/radial_hop_positions.dart';

import 'constellation_anchor_composition.dart';
import 'constellation_consts.dart';
import 'constellation_path_resolution.dart';
import 'entity/constellation_anchor.dart';

typedef ConstellationPoint = ({double x, double y});
typedef ConstellationSize = ({double width, double height});
typedef ConstellationBounds = ({double left, double top, double right, double bottom});

typedef ConstellationLayout = ({
  Map<String, ConstellationPoint> positions,
  Map<String, int> ring,
});

typedef ConstellationLayoutPriorHints = ({
  Map<String, ConstellationPoint> positions,
  Map<String, int> ring,
  ConstellationViewportClass viewportClass,
});

typedef ConstellationPlacedLayoutInput = ({
  String egoId,
  ConstellationPathResolution paths,
  Set<String> automaticKeptPeerIds,
  Set<String> pinnedPersonIds,
  Set<String> pinnedRequestIds,
  Set<String> supportPersonIds,
  Map<String, ConstellationAnchorPosition> anchorByNodeId,
  ConstellationLayoutPriorHints? priorHints,
  Map<String, ConstellationSize> nodeSizes,
  Map<String, List<String>> satelliteRequestIdsByAuthor,
  Map<String, String> requestAuthorById,
  Set<String> egoOwnRequestIds,
  double spacing,
  int maxHops,
  ConstellationViewportClass viewportClass,
});

const _kCandidateRadiiMultipliers = [1, 2, 3, 4];
const _kCandidateAngleCount = 16;

ConstellationPoint constellationCanvasCentrePoint() => (
  x: kConstellationCanvasCentre,
  y: kConstellationCanvasCentre,
);

ConstellationPoint constellationV1AnchorToPoint(
  ConstellationAnchorPosition position,
) {
  final centre = constellationCanvasCentrePoint();
  return (
    x: centre.x + position.xUnits * kConstellationRingUnitPixels,
    y: centre.y + position.yUnits * kConstellationRingUnitPixels,
  );
}

ConstellationAnchorPosition constellationPointToV1Anchor(
  ConstellationPoint point,
) {
  final centre = constellationCanvasCentrePoint();
  return ConstellationAnchorPosition(
    xUnits: (point.x - centre.x) / kConstellationRingUnitPixels,
    yUnits: (point.y - centre.y) / kConstellationRingUnitPixels,
    coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
  );
}

bool constellationPointWithinEnvelope(ConstellationPoint centre) {
  final normalized = constellationPointToV1Anchor(centre);
  return ConstellationAnchorPosition.validate(
        xUnits: normalized.xUnits,
        yUnits: normalized.yUnits,
        coordinateSpaceVersion: normalized.coordinateSpaceVersion,
      )
      is ConstellationAnchorPositionValid;
}

bool constellationBoundsWithinCanvas(ConstellationBounds bounds) {
  return bounds.left >= 0 &&
      bounds.top >= 0 &&
      bounds.right <= kConstellationCanvasExtent &&
      bounds.bottom <= kConstellationCanvasExtent;
}

ConstellationBounds constellationRenderedBounds({
  required ConstellationPoint centre,
  required ConstellationSize size,
}) {
  final halfW = size.width / 2;
  final halfH = size.height / 2;
  return (
    left: centre.x - halfW,
    top: centre.y - halfH,
    right: centre.x + halfW,
    bottom: centre.y + halfH,
  );
}

Map<String, Offset> constellationLayoutPointsToOffsets(
  Map<String, ConstellationPoint> positions,
) {
  return {
    for (final entry in positions.entries)
      entry.key: Offset(entry.value.x, entry.value.y),
  };
}

ConstellationLayout computeConstellationLayout({
  required String egoId,
  required ConstellationPathResolution paths,
  required Set<String> keptPeerIds,
  required Map<String, List<String>> visibleRequestsByAuthor,
  required Set<String> egoOwnRequestIds,
  int maxHops = 3,
  double ringGap = kConstellationRingUnitPixels,
  double residualRingFactor = 1.6,
  double satelliteOffset = 56,
  Map<String, ConstellationSize> nodeSizes = const {},
  double spacing = 16,
  Set<String> pinnedPersonIds = const {},
  Set<String> pinnedRequestIds = const {},
  Set<String> supportPersonIds = const {},
  Map<String, ConstellationAnchorPosition> anchorByNodeId = const {},
  ConstellationLayoutPriorHints? priorHints,
  ConstellationViewportClass viewportClass = ConstellationViewportClass.expanded,
}) {
  return computeConstellationPlacedLayout(
    input: (
      egoId: egoId,
      paths: paths,
      automaticKeptPeerIds: keptPeerIds,
      pinnedPersonIds: pinnedPersonIds,
      pinnedRequestIds: pinnedRequestIds,
      supportPersonIds: supportPersonIds,
      anchorByNodeId: anchorByNodeId,
      priorHints: priorHints,
      nodeSizes: nodeSizes,
      satelliteRequestIdsByAuthor: visibleRequestsByAuthor,
      requestAuthorById: const {},
      egoOwnRequestIds: egoOwnRequestIds,
      spacing: spacing,
      maxHops: maxHops,
      viewportClass: viewportClass,
    ),
    ringGap: ringGap,
    residualRingFactor: residualRingFactor,
    satelliteOffset: satelliteOffset,
  );
}

ConstellationLayout computeConstellationPlacedLayout({
  required ConstellationPlacedLayoutInput input,
  double ringGap = kConstellationRingUnitPixels,
  double residualRingFactor = 1.6,
  double satelliteOffset = 56,
}) {
  final centre = constellationCanvasCentrePoint();
  final positions = <String, ConstellationPoint>{};
  final ring = <String, int>{};

  positions[input.egoId] = centre;
  ring[input.egoId] = 0;

  for (final personId in input.pinnedPersonIds) {
    final anchor = input.anchorByNodeId[personId];
    if (anchor == null) {
      continue;
    }
    final point = constellationV1AnchorToPoint(anchor);
    positions[personId] = point;
    ring[personId] = input.paths.depth[personId] ??
        (input.paths.ring.contains(personId)
            ? input.maxHops + 1
            : input.maxHops);
  }

  for (final requestId in input.pinnedRequestIds) {
    final anchor = input.anchorByNodeId[requestId];
    if (anchor == null) {
      continue;
    }
    positions[requestId] = constellationV1AnchorToPoint(anchor);
  }

  final ideals = _computeSemanticIdeals(
    egoId: input.egoId,
    paths: input.paths,
    keptPeerIds: input.automaticKeptPeerIds,
    visibleRequestsByAuthor: input.satelliteRequestIdsByAuthor,
    egoOwnRequestIds: input.egoOwnRequestIds,
    centre: centre,
    maxHops: input.maxHops,
    ringGap: ringGap,
    residualRingFactor: residualRingFactor,
    satelliteOffset: satelliteOffset,
    alreadyPlaced: positions.keys.toSet(),
  );

  final automaticPeople = [
    for (final id in input.automaticKeptPeerIds)
      if (!input.pinnedPersonIds.contains(id) &&
          !input.supportPersonIds.contains(id))
        id,
  ]..sort();

  final supportPeople = [
    for (final id in input.supportPersonIds)
      if (!input.pinnedPersonIds.contains(id)) id,
  ]..sort();

  final automaticRequests = <String>[];
  final authors = input.satelliteRequestIdsByAuthor.keys.toList()..sort();
  for (final author in authors) {
    if (author == input.egoId) {
      continue;
    }
    final requestIds = List<String>.from(
      input.satelliteRequestIdsByAuthor[author] ?? const [],
    )..sort();
    for (final requestId in requestIds) {
      if (!input.pinnedRequestIds.contains(requestId)) {
        automaticRequests.add(requestId);
      }
    }
  }

  final egoRequests = List<String>.from(input.egoOwnRequestIds)..sort();
  for (final requestId in egoRequests) {
    if (!input.pinnedRequestIds.contains(requestId)) {
      automaticRequests.add(requestId);
    }
  }

  void placeAutomatic(String nodeId, ConstellationPoint ideal) {
    final size = _sizeFor(nodeId, input.nodeSizes);
    final authorId = _authorIdForRequest(
      nodeId: nodeId,
      satelliteRequestIdsByAuthor: input.satelliteRequestIdsByAuthor,
      requestAuthorById: input.requestAuthorById,
      egoOwnRequestIds: input.egoOwnRequestIds,
      egoId: input.egoId,
    );
    final collisionIgnore = _isAutomaticRequestNode(
          nodeId: nodeId,
          satelliteRequestIdsByAuthor: input.satelliteRequestIdsByAuthor,
          requestAuthorById: input.requestAuthorById,
          egoOwnRequestIds: input.egoOwnRequestIds,
        ) &&
            authorId != null
        ? {authorId}
        : const <String>{};
    final chosen = _chooseAutomaticPosition(
      nodeId: nodeId,
      ideal: ideal,
      size: size,
      spacing: input.spacing,
      placed: positions,
      placedSizes: input.nodeSizes,
      priorHints: input.priorHints,
      paths: input.paths,
      ring: ring,
      viewportClass: input.viewportClass,
      collisionIgnore: collisionIgnore,
    );
    positions[nodeId] = chosen.point;
    if (chosen.ring != null) {
      ring[nodeId] = chosen.ring!;
    }
  }

  for (final personId in supportPeople) {
    final ideal = ideals[personId];
    if (ideal == null) {
      continue;
    }
    placeAutomatic(personId, ideal);
    ring[personId] = input.paths.depth[personId] ??
        (input.paths.ring.contains(personId)
            ? input.maxHops + 1
            : input.maxHops);
  }

  for (final personId in automaticPeople) {
    final ideal = ideals[personId];
    if (ideal == null) {
      continue;
    }
    placeAutomatic(personId, ideal);
    ring[personId] = input.paths.depth[personId] ??
        (input.paths.ring.contains(personId)
            ? input.maxHops + 1
            : input.maxHops);
  }

  for (final requestId in automaticRequests) {
    final ideal = ideals[requestId];
    if (ideal == null) {
      continue;
    }
    placeAutomatic(requestId, ideal);
  }

  return (positions: positions, ring: ring);
}

ConstellationSize _sizeFor(String nodeId, Map<String, ConstellationSize> sizes) {
  return sizes[nodeId] ?? (width: 64, height: 64);
}

String? _authorIdForRequest({
  required String nodeId,
  required Map<String, List<String>> satelliteRequestIdsByAuthor,
  required Map<String, String> requestAuthorById,
  required Set<String> egoOwnRequestIds,
  required String egoId,
}) {
  if (egoOwnRequestIds.contains(nodeId)) {
    return egoId;
  }
  final direct = requestAuthorById[nodeId];
  if (direct != null) {
    return direct;
  }
  for (final entry in satelliteRequestIdsByAuthor.entries) {
    if (entry.value.contains(nodeId)) {
      return entry.key;
    }
  }
  return null;
}

bool _isAutomaticRequestNode({
  required String nodeId,
  required Map<String, List<String>> satelliteRequestIdsByAuthor,
  required Map<String, String> requestAuthorById,
  required Set<String> egoOwnRequestIds,
}) {
  if (egoOwnRequestIds.contains(nodeId)) {
    return true;
  }
  if (requestAuthorById.containsKey(nodeId)) {
    return true;
  }
  for (final requestIds in satelliteRequestIdsByAuthor.values) {
    if (requestIds.contains(nodeId)) {
      return true;
    }
  }
  return false;
}

({ConstellationPoint point, int? ring}) _chooseAutomaticPosition({
  required String nodeId,
  required ConstellationPoint ideal,
  required ConstellationSize size,
  required double spacing,
  required Map<String, ConstellationPoint> placed,
  required Map<String, ConstellationSize> placedSizes,
  required ConstellationLayoutPriorHints? priorHints,
  required ConstellationPathResolution paths,
  required Map<String, int> ring,
  required ConstellationViewportClass viewportClass,
  Set<String> collisionIgnore = const {},
}) {
  final candidates = <ConstellationPoint>[];

  final hint = priorHints?.positions[nodeId];
  if (hint != null &&
      priorHints!.viewportClass == viewportClass &&
      _priorHintEligible(
        nodeId: nodeId,
        hint: hint,
        size: size,
        paths: paths,
        priorRing: priorHints.ring[nodeId],
      )) {
    candidates.add(hint);
  }

  if (_envelopeValid(ideal, size: size)) {
    candidates.add(ideal);
  }

  final step = math.max(size.width, size.height) + spacing;
  final radial = math.atan2(
    ideal.y - constellationCanvasCentrePoint().y,
    ideal.x - constellationCanvasCentrePoint().x,
  );
  for (final multiplier in _kCandidateRadiiMultipliers) {
    final radius = step * multiplier;
    for (var i = 0; i < _kCandidateAngleCount; i++) {
      final angle = radial + (2 * math.pi / _kCandidateAngleCount) * i;
      final candidate = (
        x: ideal.x + math.cos(angle) * radius,
        y: ideal.y + math.sin(angle) * radius,
      );
      if (_envelopeValid(candidate, size: size)) {
        candidates.add(candidate);
      }
    }
  }

  final chosenPoint = () {
    if (candidates.isEmpty) {
      return _clampAutomaticPointToEnvelopeAndCanvas(point: ideal, size: size);
    }

    for (final candidate in candidates) {
      if (_totalIntersectionArea(
            candidate: candidate,
            size: size,
            spacing: spacing,
            placed: placed,
            placedSizes: placedSizes,
            ignore: collisionIgnore,
          ) ==
          0) {
        return candidate;
      }
    }

    var bestIndex = 0;
    var bestScore = double.infinity;
    for (var i = 0; i < candidates.length; i++) {
      final score = _totalIntersectionArea(
        candidate: candidates[i],
        size: size,
        spacing: spacing,
        placed: placed,
        placedSizes: placedSizes,
        ignore: collisionIgnore,
      );
      if (score < bestScore || (score == bestScore && i < bestIndex)) {
        bestScore = score;
        bestIndex = i;
      }
    }
    return candidates[bestIndex];
  }();

  return (
    point: chosenPoint,
    ring: priorHints?.ring[nodeId] ?? ring[nodeId],
  );
}

bool _priorHintEligible({
  required String nodeId,
  required ConstellationPoint hint,
  required ConstellationSize size,
  required ConstellationPathResolution paths,
  required int? priorRing,
}) {
  final currentRing = paths.depth[nodeId] ??
      (paths.ring.contains(nodeId) ? (paths.depth.values.fold(0, math.max) + 1) : null);
  if (priorRing != null && currentRing != null && priorRing != currentRing) {
    return false;
  }
  return _envelopeValid(hint, size: size);
}

bool _envelopeValid(
  ConstellationPoint centre, {
  required ConstellationSize size,
}) {
  if (!constellationPointWithinEnvelope(centre)) {
    return false;
  }
  final bounds = constellationRenderedBounds(centre: centre, size: size);
  return constellationBoundsWithinCanvas(bounds);
}

ConstellationPoint _clampAutomaticPointToEnvelopeAndCanvas({
  required ConstellationPoint point,
  required ConstellationSize size,
}) {
  final anchor = constellationPointToV1Anchor(point);
  final clampedUnits = (
    xUnits: anchor.xUnits.clamp(
      kConstellationCoordinateMinUnits,
      kConstellationCoordinateMaxUnits,
    ),
    yUnits: anchor.yUnits.clamp(
      kConstellationCoordinateMinUnits,
      kConstellationCoordinateMaxUnits,
    ),
  );
  var centre = constellationV1AnchorToPoint(
    ConstellationAnchorPosition(
      xUnits: clampedUnits.xUnits,
      yUnits: clampedUnits.yUnits,
      coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
    ),
  );
  final halfW = size.width / 2;
  final halfH = size.height / 2;
  centre = (
    x: centre.x.clamp(halfW, kConstellationCanvasExtent - halfW),
    y: centre.y.clamp(halfH, kConstellationCanvasExtent - halfH),
  );
  if (_envelopeValid(centre, size: size)) {
    return centre;
  }
  return constellationCanvasCentrePoint();
}

double _totalIntersectionArea({
  required ConstellationPoint candidate,
  required ConstellationSize size,
  required double spacing,
  required Map<String, ConstellationPoint> placed,
  required Map<String, ConstellationSize> placedSizes,
  Set<String> ignore = const {},
}) {
  final bounds = _inflatedBounds(
    constellationRenderedBounds(centre: candidate, size: size),
    spacing: spacing,
  );
  var total = 0.0;
  for (final entry in placed.entries) {
    if (ignore.contains(entry.key)) {
      continue;
    }
    total += _intersectionArea(
      a: bounds,
      b: _inflatedBounds(
        constellationRenderedBounds(
          centre: entry.value,
          size: placedSizes[entry.key] ?? (width: 64, height: 64),
        ),
        spacing: spacing,
      ),
    );
  }
  return total;
}

ConstellationBounds _inflatedBounds(
  ConstellationBounds bounds, {
  required double spacing,
}) {
  final half = spacing / 2;
  return (
    left: bounds.left - half,
    top: bounds.top - half,
    right: bounds.right + half,
    bottom: bounds.bottom + half,
  );
}

double _intersectionArea({
  required ConstellationBounds a,
  required ConstellationBounds b,
}) {
  final left = math.max(a.left, b.left);
  final top = math.max(a.top, b.top);
  final right = math.min(a.right, b.right);
  final bottom = math.min(a.bottom, b.bottom);
  if (right <= left || bottom <= top) {
    return 0;
  }
  return (right - left) * (bottom - top);
}

Map<String, ConstellationPoint> _computeSemanticIdeals({
  required String egoId,
  required ConstellationPathResolution paths,
  required Set<String> keptPeerIds,
  required Map<String, List<String>> visibleRequestsByAuthor,
  required Set<String> egoOwnRequestIds,
  required ConstellationPoint centre,
  required int maxHops,
  required double ringGap,
  required double residualRingFactor,
  required double satelliteOffset,
  required Set<String> alreadyPlaced,
}) {
  final ideals = <String, ConstellationPoint>{};
  final canvasSize = (
    width: kConstellationCanvasExtent,
    height: kConstellationCanvasExtent,
  );

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
  ideals[egoId] = centre;

  for (final id in treePeers) {
    if (alreadyPlaced.contains(id)) {
      continue;
    }
    final depth = paths.depth[id];
    if (depth == null) {
      continue;
    }
    final nodeAngle = angle[id] ?? 0;
    final radius = depth * ringGap;
    final offset = (
      x: math.cos(nodeAngle - math.pi / 2) * radius,
      y: math.sin(nodeAngle - math.pi / 2) * radius,
    );
    ideals[id] = _toPoint(
      _clampLegacy(
        (
          x: centre.x + offset.x,
          y: centre.y + offset.y,
        ),
        canvasSize,
      ),
    );
  }

  final ringPeers = paths.ring.intersection(keptPeerIds).toList()..sort();
  if (ringPeers.isNotEmpty) {
    final ringRadius = (maxHops + residualRingFactor) * ringGap;
    final step = 2 * math.pi / ringPeers.length;
    for (var i = 0; i < ringPeers.length; i++) {
      final id = ringPeers[i];
      if (alreadyPlaced.contains(id)) {
        continue;
      }
      final nodeAngle = step * i;
      final offset = (
        x: math.cos(nodeAngle - math.pi / 2) * ringRadius,
        y: math.sin(nodeAngle - math.pi / 2) * ringRadius,
      );
      ideals[id] = _toPoint(
        _clampLegacy(
          (
            x: centre.x + offset.x,
            y: centre.y + offset.y,
          ),
          canvasSize,
        ),
      );
    }
  }

  final egoRequests = egoOwnRequestIds.toList()..sort();
  if (egoRequests.isNotEmpty) {
    final egoSatellites = localFanPositions(
      parentPos: Offset(centre.x, centre.y),
      direction: branchUnitDirection(parentPos: Offset(centre.x, centre.y)),
      childIds: egoRequests,
      canvasSize: Size(canvasSize.width, canvasSize.height),
      ringGap: satelliteOffset,
    );
    for (final entry in egoSatellites.entries) {
      if (!alreadyPlaced.contains(entry.key)) {
        ideals[entry.key] = (x: entry.value.dx, y: entry.value.dy);
      }
    }
  }

  final authors = visibleRequestsByAuthor.keys.toList()..sort();
  for (final author in authors) {
    if (author == egoId) {
      continue;
    }
    final authorPoint = ideals[author];
    if (authorPoint == null) {
      continue;
    }
    final requestIds = List<String>.from(visibleRequestsByAuthor[author]!)
      ..sort();
    if (requestIds.isEmpty) {
      continue;
    }

    final radial = (
      x: authorPoint.x - centre.x,
      y: authorPoint.y - centre.y,
    );
    final distance = math.sqrt(radial.x * radial.x + radial.y * radial.y);
    final direction = distance < 1e-6
        ? branchUnitDirection(parentPos: Offset(centre.x, centre.y))
        : Offset(radial.x / distance, radial.y / distance);

    final satellites = localFanPositions(
      parentPos: Offset(authorPoint.x, authorPoint.y),
      direction: direction,
      childIds: requestIds,
      canvasSize: Size(canvasSize.width, canvasSize.height),
      ringGap: satelliteOffset,
    );
    for (final entry in satellites.entries) {
      if (!alreadyPlaced.contains(entry.key)) {
        ideals[entry.key] = (x: entry.value.dx, y: entry.value.dy);
      }
    }
  }

  return ideals;
}

ConstellationPoint _toPoint(Offset offset) => (x: offset.dx, y: offset.dy);

Offset _clampLegacy(ConstellationPoint point, ConstellationSize canvasSize) {
  return clampLayoutPosition(
    Offset(point.x, point.y),
    Size(canvasSize.width, canvasSize.height),
  );
}

/// Adapter for graph code that still consumes [Offset] positions.
({Map<String, Offset> positions, Map<String, int> ring})
computeConstellationLayoutWithOffsets({
  required String egoId,
  required ConstellationPathResolution paths,
  required Set<String> keptPeerIds,
  required Map<String, List<String>> visibleRequestsByAuthor,
  required Set<String> egoOwnRequestIds,
  required Size canvasSize,
  int maxHops = 3,
  double ringGap = kConstellationRingUnitPixels,
  double residualRingFactor = 1.6,
  double satelliteOffset = 56,
}) {
  final layout = computeConstellationLayout(
    egoId: egoId,
    paths: paths,
    keptPeerIds: keptPeerIds,
    visibleRequestsByAuthor: visibleRequestsByAuthor,
    egoOwnRequestIds: egoOwnRequestIds,
    maxHops: maxHops,
    ringGap: ringGap,
    residualRingFactor: residualRingFactor,
    satelliteOffset: satelliteOffset,
  );
  return (
    positions: constellationLayoutPointsToOffsets(layout.positions),
    ring: layout.ring,
  );
}
