import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:tentura/features/graph/domain/layout/radial_hop_positions.dart';

import 'constellation_anchor_composition.dart';
import 'constellation_consts.dart';
import 'layout/layout_geometry.dart';
import 'layout/spatial_index.dart';
import 'package:tentura_root/domain/constellation/constellation_path_resolution.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

typedef ConstellationPoint = LPoint;
typedef ConstellationSize = ({double width, double height});
typedef ConstellationBounds = ({
  double left,
  double top,
  double right,
  double bottom,
});

/// Screen-space label/chip/badge sizes at readable scale (R03 → R04 footprints).
typedef ConstellationFootprintMetrics = ({
  double labelGap,
  double personLabelWidth,
  double personLabelHeight,
  double requestLabelWidth,
  double requestLabelHeight,
  double chipWidth,
  double chipHeight,
  double badgeOverhang,
});

typedef ConstellationFootprint = ({
  double left,
  double top,
  double right,
  double bottom,
});

enum ConstellationFootprintKind { person, request }

ConstellationFootprint constellationNodeFootprint({
  required ConstellationFootprintKind kind,
  required double bodySize,
  required bool hasAuthorChip,
  required ConstellationFootprintMetrics metrics,
}) {
  final r = bodySize / 2;
  final labelW = kind == ConstellationFootprintKind.person
      ? metrics.personLabelWidth
      : metrics.requestLabelWidth;
  final labelH = kind == ConstellationFootprintKind.person
      ? metrics.personLabelHeight
      : metrics.requestLabelHeight;
  var half = math.max(r + metrics.badgeOverhang, labelW / 2);
  var bottom = r + metrics.labelGap + labelH;
  if (hasAuthorChip) {
    bottom += metrics.labelGap + metrics.chipHeight;
    half = math.max(half, metrics.chipWidth / 2);
  }
  return (
    left: half,
    top: r + metrics.badgeOverhang,
    right: half,
    bottom: bottom,
  );
}

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
  Map<String, ConstellationFootprint> footprints,
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

/// Scene-space bounds for a placed node (footprint when known, else body only).
ConstellationBounds constellationPlacedNodeBounds({
  required ConstellationPoint centre,
  required ConstellationSize size,
  ConstellationFootprint? footprint,
}) {
  if (footprint != null) {
    return _absoluteFootprintBounds(centre: centre, footprint: footprint);
  }
  return constellationRenderedBounds(centre: centre, size: size);
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
  ConstellationViewportClass viewportClass =
      ConstellationViewportClass.expanded,
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
      footprints: const {},
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
  late ConstellationLayout result;
  for (final _ in constellationPlacedLayoutSteps(
    input: input,
    ringGap: ringGap,
    residualRingFactor: residualRingFactor,
    satelliteOffset: satelliteOffset,
    onComplete: (layout) => result = layout,
  )) {
    // The legacy entry point drains the same deterministic work as a job.
  }
  return result;
}

/// Deferred planning, obstacle preparation and placement shared with layout jobs.
/// Each yielded checkpoint bounds work before the next iterator advance.
Iterable<void> constellationPlacedLayoutSteps({
  required ConstellationPlacedLayoutInput input,
  required void Function(ConstellationLayout) onComplete,
  SpatialIndex Function()? newIndex,
  Set<String>? unchangedNodeIds,
  double ringGap = kConstellationRingUnitPixels,
  double residualRingFactor = 1.6,
  double satelliteOffset = 56,
}) sync* {
  final index = newIndex?.call();
  final centre = constellationCanvasCentrePoint();
  var maxDepth = 0;
  for (final depth in input.paths.depth.values) {
    yield null;
    maxDepth = math.max(maxDepth, depth);
    yield null;
  }
  // Resolve fallback authors once, rather than scanning every satellite list
  // during each person's or request's placement.
  final requestAuthors = <String, String>{};
  for (final entry in input.satelliteRequestIdsByAuthor.entries) {
    yield null;
    for (final id in entry.value) {
      yield null;
      requestAuthors.putIfAbsent(id, () => entry.key);
      yield null;
    }
  }
  for (final entry in input.requestAuthorById.entries) {
    yield null;
    requestAuthors[entry.key] = entry.value;
    yield null;
  }
  for (final id in input.egoOwnRequestIds) {
    yield null;
    requestAuthors[id] = input.egoId;
    yield null;
  }
  final positions = <String, ConstellationPoint>{};
  final ring = <String, int>{};

  positions[input.egoId] = centre;
  ring[input.egoId] = 0;

  for (final personId in input.pinnedPersonIds) {
    yield null;
    final anchor = input.anchorByNodeId[personId];
    if (anchor == null) {
      continue;
    }
    final point = constellationV1AnchorToPoint(anchor);
    positions[personId] = point;
    ring[personId] =
        input.paths.depth[personId] ??
        (input.paths.ring.contains(personId)
            ? input.maxHops + 1
            : input.maxHops);
  }

  for (final requestId in input.pinnedRequestIds) {
    yield null;
    final anchor = input.anchorByNodeId[requestId];
    if (anchor == null) {
      continue;
    }
    positions[requestId] = constellationV1AnchorToPoint(anchor);
  }

  final ideals = <String, ConstellationPoint>{};
  yield* _computeSemanticIdeals(
    egoId: input.egoId,
    paths: input.paths,
    keptPeerIds: input.automaticKeptPeerIds,
    visibleRequestsByAuthor: const {},
    egoOwnRequestIds: const {},
    centre: centre,
    maxHops: input.maxHops,
    ringGap: ringGap,
    residualRingFactor: residualRingFactor,
    satelliteOffset: satelliteOffset,
    spacing: input.spacing,
    nodeSizes: input.nodeSizes,
    footprints: input.footprints,
    alreadyPlaced: positions,
    placed: positions,
    ideals: ideals,
  );

  bool isHardPinnedPerson(String id) =>
      input.pinnedPersonIds.contains(id) &&
      input.anchorByNodeId.containsKey(id);

  final automaticPeople = <String>[];
  for (final id in input.automaticKeptPeerIds) {
    yield null;
    if (!isHardPinnedPerson(id) && !input.supportPersonIds.contains(id)) {
      automaticPeople.add(id);
    }
  }
  yield* _sortLayoutValues(automaticPeople, (a, b) => a.compareTo(b));
  final supportPeople = <String>[];
  for (final id in input.supportPersonIds) {
    yield null;
    if (!isHardPinnedPerson(id)) supportPeople.add(id);
  }
  yield* _sortLayoutValues(supportPeople, (a, b) => a.compareTo(b));

  final automaticRequests = <String>[];
  final authors = <String>[];
  for (final author in input.satelliteRequestIdsByAuthor.keys) {
    yield null;
    authors.add(author);
  }
  yield* _sortLayoutValues(authors, (a, b) => a.compareTo(b));
  for (final author in authors) {
    yield null;
    if (author == input.egoId) {
      continue;
    }
    final requestIds = <String>[];
    for (final id
        in input.satelliteRequestIdsByAuthor[author] ?? const <String>[]) {
      yield null;
      requestIds.add(id);
    }
    yield* _sortLayoutValues(requestIds, (a, b) => a.compareTo(b));
    for (final requestId in requestIds) {
      yield null;
      if (!input.pinnedRequestIds.contains(requestId)) {
        automaticRequests.add(requestId);
      }
    }
  }

  final egoRequests = <String>[];
  for (final id in input.egoOwnRequestIds) {
    yield null;
    egoRequests.add(id);
  }
  yield* _sortLayoutValues(egoRequests, (a, b) => a.compareTo(b));
  for (final requestId in egoRequests) {
    yield null;
    if (!input.pinnedRequestIds.contains(requestId)) {
      automaticRequests.add(requestId);
    }
  }

  final obstacles = <String, ConstellationBounds>{};

  void recordPlacedObstacle(String nodeId, ConstellationPoint point) {
    final footprint = input.footprints[nodeId];
    final bounds = footprint != null
        ? _absoluteFootprintBounds(centre: point, footprint: footprint)
        : constellationRenderedBounds(
            centre: point,
            size: _sizeFor(nodeId, input.nodeSizes),
          );
    obstacles[nodeId] = bounds;
    index?.insert(nodeId, bounds);
  }

  recordPlacedObstacle(input.egoId, centre);

  for (final personId in input.pinnedPersonIds) {
    yield null;
    final point = positions[personId];
    if (point != null) {
      recordPlacedObstacle(personId, point);
    }
  }
  for (final requestId in input.pinnedRequestIds) {
    yield null;
    final point = positions[requestId];
    if (point != null) {
      recordPlacedObstacle(requestId, point);
    }
  }

  Iterable<void> placeAutomatic(String nodeId, ConstellationPoint ideal) sync* {
    final size = _sizeFor(nodeId, input.nodeSizes);
    final isRequest = requestAuthors.containsKey(nodeId);
    final requestFootprint = isRequest
        ? (input.footprints[nodeId] ?? _symmetricBodyFootprint(size))
        : null;
    // Attachment-crossing still uses requestAuthorById only (may be empty on
    // the scene path). Hint-skip resolves author from satellite maps separately
    // so we do not turn on crossing preference for every satellite.
    final requestAuthorId = isRequest
        ? (input.egoOwnRequestIds.contains(nodeId)
              ? input.egoId
              : input.requestAuthorById[nodeId])
        : null;
    final hintSkipAuthorId = requestAuthors[nodeId];
    final chosen = _LayoutValue<({ConstellationPoint point, int? ring})>();
    yield* _chooseAutomaticPosition(
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
      isRequest: isRequest,
      requestFootprint: requestFootprint,
      obstacles: obstacles,
      requestAuthorId: requestAuthorId,
      hintSkipAuthorId: hintSkipAuthorId,
      maxDepth: maxDepth,
      result: chosen,
    );
    positions[nodeId] = chosen.value.point;
    if (chosen.value.ring != null) {
      ring[nodeId] = chosen.value.ring!;
    }
    recordPlacedObstacle(nodeId, chosen.value.point);
  }

  int personRing(String personId) =>
      input.paths.depth[personId] ??
      (input.paths.ring.contains(personId) ? input.maxHops + 1 : input.maxHops);

  // Stability contract (I3): a free node whose inputs are unchanged and that
  // overlaps nothing already placed keeps its previous spot. Every such node
  // is placed before any other free node, so changed or new nodes can never
  // take its place.
  final prior = input.priorHints;
  Iterable<void> hardKeepFreeNodes(
    Iterable<String> nodeIds, {
    required bool requests,
  }) sync* {
    if (prior == null || prior.viewportClass != input.viewportClass) {
      return;
    }
    for (final nodeId in nodeIds) {
      yield null;
      final hint = prior.positions[nodeId];
      if ((unchangedNodeIds != null && !unchangedNodeIds.contains(nodeId)) ||
          hint == null ||
          positions.containsKey(nodeId) ||
          (!requests && ideals[nodeId] == null)) {
        continue;
      }
      final size = _sizeFor(nodeId, input.nodeSizes);
      final footprint = requests
          ? (input.footprints[nodeId] ?? _symmetricBodyFootprint(size))
          : null;
      if (!_priorHintEligible(
        nodeId: nodeId,
        hint: hint,
        size: footprint == null
            ? size
            : (
                width: footprint.left + footprint.right,
                height: footprint.top + footprint.bottom,
              ),
        paths: input.paths,
        priorRing: prior.ring[nodeId],
        maxDepth: maxDepth,
      )) {
        continue;
      }
      if (requests) {
        final authorId = requestAuthors[nodeId];
        if (authorId != null &&
            prior.positions.containsKey(authorId) &&
            (!positions.containsKey(authorId) ||
                _authorSeatMovedSincePrior(
                  authorId: authorId,
                  placed: positions,
                  priorHints: prior,
                ))) {
          continue;
        }
      }
      final overlap = _LayoutDoubleValue();
      if (footprint != null) {
        yield* _totalObstacleIntersectionArea(
          candidate: hint,
          footprint: footprint,
          spacing: input.spacing,
          obstacles: obstacles,
          result: overlap,
          stopAtFirstOverlap: true,
        );
      } else {
        yield* _totalIntersectionArea(
          candidate: hint,
          size: size,
          spacing: input.spacing,
          placed: positions,
          placedSizes: input.nodeSizes,
          result: overlap,
          stopAtFirstOverlap: true,
        );
      }
      if (overlap.value > 0) {
        continue;
      }
      positions[nodeId] = hint;
      if (requests) {
        final priorRing = prior.ring[nodeId];
        if (priorRing != null) {
          ring[nodeId] = priorRing;
        }
      } else {
        ring[nodeId] = personRing(nodeId);
      }
      recordPlacedObstacle(nodeId, hint);
    }
  }

  yield* hardKeepFreeNodes(supportPeople, requests: false);
  yield* hardKeepFreeNodes(automaticPeople, requests: false);
  yield* hardKeepFreeNodes(automaticRequests, requests: true);

  for (final personId in supportPeople) {
    yield null;
    final ideal = ideals[personId];
    if (ideal == null || positions.containsKey(personId)) {
      continue;
    }
    yield* placeAutomatic(personId, ideal);
    ring[personId] = personRing(personId);
  }

  for (final personId in automaticPeople) {
    yield null;
    final ideal = ideals[personId];
    if (ideal == null || positions.containsKey(personId)) {
      continue;
    }
    yield* placeAutomatic(personId, ideal);
    ring[personId] = personRing(personId);
  }

  // Request fans from placed author seats (not pre-placement ideals), so
  // session inertia on the author does not leave satellites at a stale seat.
  final automaticRequestIds = <String>{};
  for (final id in automaticRequests) {
    yield null;
    automaticRequestIds.add(id);
  }
  final requestAlreadyPlaced = <String, ConstellationPoint>{};
  for (final entry in positions.entries) {
    yield null;
    if (!automaticRequestIds.contains(entry.key)) {
      requestAlreadyPlaced[entry.key] = entry.value;
    }
  }
  final requestIdeals = <String, ConstellationPoint>{};
  yield* _computeSemanticIdeals(
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
    spacing: input.spacing,
    nodeSizes: input.nodeSizes,
    footprints: input.footprints,
    alreadyPlaced: requestAlreadyPlaced,
    placed: positions,
    ideals: requestIdeals,
  );

  for (final requestId in automaticRequests) {
    yield null;
    final ideal = requestIdeals[requestId];
    if (ideal == null || positions.containsKey(requestId)) {
      continue;
    }
    yield* placeAutomatic(requestId, ideal);
  }

  onComplete((positions: positions, ring: ring));
}

ConstellationSize _sizeFor(
  String nodeId,
  Map<String, ConstellationSize> sizes,
) {
  return sizes[nodeId] ?? (width: 64, height: 64);
}

/// Scene-space epsilon for "author seat moved" prior-hint invalidation.
const _kAuthorSeatMovedEpsilon = 1.0;

bool _authorSeatMovedSincePrior({
  required String? authorId,
  required Map<String, ConstellationPoint> placed,
  required ConstellationLayoutPriorHints? priorHints,
}) {
  if (authorId == null || priorHints == null) {
    return false;
  }
  final priorAuthor = priorHints.positions[authorId];
  final currentAuthor = placed[authorId];
  if (priorAuthor == null || currentAuthor == null) {
    return false;
  }
  final dx = currentAuthor.x - priorAuthor.x;
  final dy = currentAuthor.y - priorAuthor.y;
  return math.sqrt(dx * dx + dy * dy) > _kAuthorSeatMovedEpsilon;
}

Iterable<void> _chooseAutomaticPosition({
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
  required int maxDepth,
  required _LayoutValue<({ConstellationPoint point, int? ring})> result,
  bool isRequest = false,
  ConstellationFootprint? requestFootprint,
  Map<String, ConstellationBounds> obstacles = const {},
  String? requestAuthorId,
  String? hintSkipAuthorId,
}) sync* {
  final effectiveSize = isRequest && requestFootprint != null
      ? (
          width: requestFootprint.left + requestFootprint.right,
          height: requestFootprint.top + requestFootprint.bottom,
        )
      : size;
  final candidates = <ConstellationPoint>[];

  final hint = priorHints?.positions[nodeId];
  final skipHintForMovedAuthor =
      isRequest &&
      _authorSeatMovedSincePrior(
        authorId: hintSkipAuthorId,
        placed: placed,
        priorHints: priorHints,
      );
  if (hint != null &&
      !skipHintForMovedAuthor &&
      priorHints!.viewportClass == viewportClass &&
      _priorHintEligible(
        nodeId: nodeId,
        hint: hint,
        size: effectiveSize,
        paths: paths,
        priorRing: priorHints.ring[nodeId],
        maxDepth: maxDepth,
      )) {
    candidates.add(hint);
  }

  if (_envelopeValid(ideal, size: effectiveSize)) {
    candidates.add(ideal);
  }

  final step = math.max(effectiveSize.width, effectiveSize.height) + spacing;
  final radial = math.atan2(
    ideal.y - constellationCanvasCentrePoint().y,
    ideal.x - constellationCanvasCentrePoint().x,
  );
  for (final multiplier in _kCandidateRadiiMultipliers) {
    yield null;
    final radius = step * multiplier;
    for (var i = 0; i < _kCandidateAngleCount; i++) {
      yield null;
      final angle = radial + (2 * math.pi / _kCandidateAngleCount) * i;
      final candidate = (
        x: ideal.x + math.cos(angle) * radius,
        y: ideal.y + math.sin(angle) * radius,
      );
      if (_envelopeValid(candidate, size: effectiveSize)) {
        candidates.add(candidate);
      }
    }
  }

  final chosenPoint = _LayoutValue<ConstellationPoint>();
  Iterable<void> choosePoint() sync* {
    if (candidates.isEmpty) {
      chosenPoint.value = _clampAutomaticPointToEnvelopeAndCanvas(
        point: ideal,
        size: effectiveSize,
      );
      return;
    }

    if (isRequest && requestFootprint != null) {
      final zeroOverlap = <ConstellationPoint>[];
      for (final candidate in candidates) {
        yield null;
        final overlap = _LayoutDoubleValue();
        yield* _totalObstacleIntersectionArea(
          candidate: candidate,
          footprint: requestFootprint,
          spacing: spacing,
          obstacles: obstacles,
          result: overlap,
          stopAtFirstOverlap: true,
        );
        if (overlap.value == 0) {
          zeroOverlap.add(candidate);
        }
      }
      if (zeroOverlap.isNotEmpty) {
        final authorCentre = requestAuthorId != null
            ? placed[requestAuthorId]
            : null;
        if (authorCentre != null) {
          for (final candidate in zeroOverlap) {
            yield null;
            final crosses = _LayoutValue<bool>();
            yield* _attachmentSegmentCrossesBody(
              authorCentre: authorCentre,
              candidateCentre: candidate,
              placed: placed,
              placedSizes: placedSizes,
              skipNodeIds: {
                nodeId,
                ?requestAuthorId,
              },
              result: crosses,
            );
            if (!crosses.value) {
              chosenPoint.value = candidate;
              return;
            }
          }
        }
        chosenPoint.value = zeroOverlap.first;
        return;
      }

      var bestIndex = 0;
      var bestScore = double.infinity;
      for (var i = 0; i < candidates.length; i++) {
        yield null;
        final score = _LayoutDoubleValue();
        yield* _totalObstacleIntersectionArea(
          candidate: candidates[i],
          footprint: requestFootprint,
          spacing: spacing,
          obstacles: obstacles,
          result: score,
        );
        if (score.value < bestScore ||
            (score.value == bestScore && i < bestIndex)) {
          bestScore = score.value;
          bestIndex = i;
        }
      }
      chosenPoint.value = candidates[bestIndex];
      return;
    }

    for (final candidate in candidates) {
      yield null;
      final overlap = _LayoutDoubleValue();
      yield* _totalIntersectionArea(
        candidate: candidate,
        size: size,
        spacing: spacing,
        placed: placed,
        placedSizes: placedSizes,
        result: overlap,
        stopAtFirstOverlap: true,
      );
      if (overlap.value == 0) {
        chosenPoint.value = candidate;
        return;
      }
    }

    var bestIndex = 0;
    var bestScore = double.infinity;
    for (var i = 0; i < candidates.length; i++) {
      yield null;
      final score = _LayoutDoubleValue();
      yield* _totalIntersectionArea(
        candidate: candidates[i],
        size: size,
        spacing: spacing,
        placed: placed,
        placedSizes: placedSizes,
        result: score,
      );
      if (score.value < bestScore ||
          (score.value == bestScore && i < bestIndex)) {
        bestScore = score.value;
        bestIndex = i;
      }
    }
    chosenPoint.value = candidates[bestIndex];
    return;
  }

  yield* choosePoint();
  result.value = (
    point: chosenPoint.value,
    ring: priorHints?.ring[nodeId] ?? ring[nodeId],
  );
}

bool _priorHintEligible({
  required String nodeId,
  required ConstellationPoint hint,
  required ConstellationSize size,
  required ConstellationPathResolution paths,
  required int? priorRing,
  required int maxDepth,
}) {
  final currentRing =
      paths.depth[nodeId] ??
      (paths.ring.contains(nodeId) ? (maxDepth + 1) : null);
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

Iterable<void> _totalIntersectionArea({
  required ConstellationPoint candidate,
  required ConstellationSize size,
  required double spacing,
  required Map<String, ConstellationPoint> placed,
  required Map<String, ConstellationSize> placedSizes,
  required _LayoutDoubleValue result,
  bool stopAtFirstOverlap = false,
}) sync* {
  final bounds = _inflatedBounds(
    constellationRenderedBounds(centre: candidate, size: size),
    spacing: spacing,
  );
  final halfSpacing = spacing / 2;
  final ids = placed.keys.iterator;
  result.value = 0;
  // Keep arithmetic outside the suspended generator frame so intermediate
  // doubles stay unboxed. Only the accumulated chunk total crosses a yield.
  bool scanChunk() {
    var total = result.value;
    for (var i = 0; i < 32; i++) {
      if (!ids.moveNext()) {
        result.value = total;
        return true;
      }
      final centre = placed[ids.current]!;
      final placedSize = placedSizes[ids.current] ?? (width: 64, height: 64);
      final halfW = placedSize.width / 2;
      final halfH = placedSize.height / 2;
      if (bounds.right <= centre.x - halfW - halfSpacing ||
          bounds.left >= centre.x + halfW + halfSpacing ||
          bounds.bottom <= centre.y - halfH - halfSpacing ||
          bounds.top >= centre.y + halfH + halfSpacing) {
        continue;
      }
      // Inlined: a call returning double would box every term.
      final left = math.max(bounds.left, centre.x - halfW - halfSpacing);
      final top = math.max(bounds.top, centre.y - halfH - halfSpacing);
      final right = math.min(bounds.right, centre.x + halfW + halfSpacing);
      final bottom = math.min(bounds.bottom, centre.y + halfH + halfSpacing);
      if (right > left && bottom > top) {
        total += (right - left) * (bottom - top);
      }
      if (stopAtFirstOverlap && total > 0) {
        result.value = total;
        return true;
      }
    }
    result.value = total;
    return false;
  }

  while (!scanChunk()) {
    yield null;
  }
}

Iterable<void> _totalObstacleIntersectionArea({
  required ConstellationPoint candidate,
  required ConstellationFootprint footprint,
  required double spacing,
  required Map<String, ConstellationBounds> obstacles,
  required _LayoutDoubleValue result,
  bool stopAtFirstOverlap = false,
}) sync* {
  final bounds = _inflatedBounds(
    _absoluteFootprintBounds(centre: candidate, footprint: footprint),
    spacing: spacing,
  );
  final halfSpacing = spacing / 2;
  final rectangles = obstacles.values.iterator;
  result.value = 0;
  bool scanChunk() {
    var total = result.value;
    for (var i = 0; i < 32; i++) {
      if (!rectangles.moveNext()) {
        result.value = total;
        return true;
      }
      final obstacle = rectangles.current;
      if (bounds.right <= obstacle.left - halfSpacing ||
          bounds.left >= obstacle.right + halfSpacing ||
          bounds.bottom <= obstacle.top - halfSpacing ||
          bounds.top >= obstacle.bottom + halfSpacing) {
        continue;
      }
      final left = math.max(bounds.left, obstacle.left - halfSpacing);
      final top = math.max(bounds.top, obstacle.top - halfSpacing);
      final right = math.min(bounds.right, obstacle.right + halfSpacing);
      final bottom = math.min(bounds.bottom, obstacle.bottom + halfSpacing);
      if (right > left && bottom > top) {
        total += (right - left) * (bottom - top);
      }
      if (stopAtFirstOverlap && total > 0) {
        result.value = total;
        return true;
      }
    }
    result.value = total;
    return false;
  }

  while (!scanChunk()) {
    yield null;
  }
}

ConstellationFootprint _symmetricBodyFootprint(ConstellationSize size) {
  final halfW = size.width / 2;
  final halfH = size.height / 2;
  return (left: halfW, top: halfH, right: halfW, bottom: halfH);
}

ConstellationBounds _absoluteFootprintBounds({
  required ConstellationPoint centre,
  required ConstellationFootprint footprint,
}) {
  return (
    left: centre.x - footprint.left,
    top: centre.y - footprint.top,
    right: centre.x + footprint.right,
    bottom: centre.y + footprint.bottom,
  );
}

@visibleForTesting
Set<(String, String)> constellationFootprintOverlaps(
  ConstellationPlacedLayoutInput input,
  ConstellationLayout layout,
) {
  final pinned = {...input.pinnedPersonIds, ...input.pinnedRequestIds};
  final ids = layout.positions.keys.toList()..sort();
  final overlaps = <(String, String)>{};

  ConstellationBounds boundsFor(String id) {
    final centre = layout.positions[id]!;
    final footprint = input.footprints[id];
    if (footprint != null) {
      return _absoluteFootprintBounds(centre: centre, footprint: footprint);
    }
    final nodeSize = _sizeFor(id, input.nodeSizes);
    return constellationRenderedBounds(centre: centre, size: nodeSize);
  }

  for (var i = 0; i < ids.length; i++) {
    for (var j = i + 1; j < ids.length; j++) {
      final a = ids[i];
      final b = ids[j];
      if (pinned.contains(a) && pinned.contains(b)) {
        continue;
      }
      if (_intersectionArea(a: boundsFor(a), b: boundsFor(b)) > 0) {
        overlaps.add(a.compareTo(b) < 0 ? (a, b) : (b, a));
      }
    }
  }
  return overlaps;
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
}) => _intersectionAreaWithEdges(a, b.left, b.top, b.right, b.bottom);

double _intersectionAreaWithEdges(
  ConstellationBounds a,
  double bLeft,
  double bTop,
  double bRight,
  double bBottom,
) {
  final left = math.max(a.left, bLeft);
  final top = math.max(a.top, bTop);
  final right = math.min(a.right, bRight);
  final bottom = math.min(a.bottom, bBottom);
  if (right <= left || bottom <= top) {
    return 0;
  }
  return (right - left) * (bottom - top);
}

@visibleForTesting
({LPoint direction, double gap}) constellationEgoSatelliteDirection(
  List<double> depthOneAngles,
) {
  final result = _LayoutValue<({LPoint direction, double gap})>();
  for (final _ in _egoSatelliteDirectionSteps(depthOneAngles, result)) {}
  return result.value;
}

Iterable<void> _egoSatelliteDirectionSteps(
  List<double> depthOneAngles,
  _LayoutValue<({LPoint direction, double gap})> result,
) sync* {
  if (depthOneAngles.isEmpty) {
    result.value = (direction: (x: 0, y: 1), gap: 2 * math.pi);
    return;
  }
  final normalized = <double>[];
  for (final angle in depthOneAngles) {
    yield null;
    final a = angle % (2 * math.pi);
    normalized.add(a < 0 ? a + 2 * math.pi : a);
  }
  yield* _sortLayoutValues(normalized, (a, b) => a.compareTo(b));
  var bestGapStart = 0;
  var bestGap = -1.0;
  for (var i = 0; i < normalized.length; i++) {
    yield null;
    final next = normalized[(i + 1) % normalized.length];
    final wrap = i == normalized.length - 1;
    final gap = wrap
        ? (next + 2 * math.pi) - normalized[i]
        : next - normalized[i];
    if (gap > bestGap) {
      bestGap = gap;
      bestGapStart = i;
    }
  }
  final start = normalized[bestGapStart];
  final mid = start + bestGap / 2;
  result.value = (
    direction: (x: math.cos(mid), y: math.sin(mid)),
    gap: bestGap,
  );
}

bool _segmentIntersectsRect(
  ConstellationPoint a,
  ConstellationPoint b,
  ConstellationBounds r,
) {
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  const eps = 1e-9;
  var t0 = 0.0;
  var t1 = 1.0;

  bool clip(double p, double q) {
    if (p.abs() < eps) {
      return q >= 0;
    }
    final r = q / p;
    if (p < 0) {
      if (r > t1) {
        return false;
      }
      if (r > t0) {
        t0 = r;
      }
    } else {
      if (r < t0) {
        return false;
      }
      if (r < t1) {
        t1 = r;
      }
    }
    return true;
  }

  if (!clip(-dx, a.x - r.left)) {
    return false;
  }
  if (!clip(dx, r.right - a.x)) {
    return false;
  }
  if (!clip(-dy, a.y - r.top)) {
    return false;
  }
  if (!clip(dy, r.bottom - a.y)) {
    return false;
  }
  return t0 <= t1;
}

Iterable<void> _attachmentSegmentCrossesBody({
  required ConstellationPoint authorCentre,
  required ConstellationPoint candidateCentre,
  required Map<String, ConstellationPoint> placed,
  required Map<String, ConstellationSize> placedSizes,
  required Set<String> skipNodeIds,
  required _LayoutValue<bool> result,
}) sync* {
  var scanned = 0;
  for (final id in placed.keys) {
    if (++scanned % 32 == 0) yield null;
    if (skipNodeIds.contains(id)) {
      continue;
    }
    final body = constellationRenderedBounds(
      centre: placed[id]!,
      size: _sizeFor(id, placedSizes),
    );
    if (_segmentIntersectsRect(authorCentre, candidateCentre, body)) {
      result.value = true;
      return;
    }
  }
  result.value = false;
}

({
  double ringGap,
  double minChord,
  double? maxFanRadians,
})?
_footprintAwareFanParams({
  required String authorId,
  required List<String> sortedRequestIds,
  required Map<String, ConstellationFootprint> footprints,
  required Map<String, ConstellationSize> nodeSizes,
  required double satelliteOffset,
  required double spacing,
  double? egoAngularGap,
}) {
  if (footprints.isEmpty || sortedRequestIds.isEmpty) {
    return null;
  }
  final firstId = sortedRequestIds.first;
  final requestFootprint =
      footprints[firstId] ??
      _symmetricBodyFootprint(_sizeFor(firstId, nodeSizes));
  final requestHalfExtent = math.max(
    math.max(requestFootprint.left, requestFootprint.right),
    math.max(requestFootprint.top, requestFootprint.bottom),
  );
  final authorSize = _sizeFor(authorId, nodeSizes);
  final authorBodyRadius = math.max(authorSize.width, authorSize.height) / 2;
  final radius = math.max(
    satelliteOffset,
    authorBodyRadius + spacing + requestHalfExtent,
  );
  final minChord = requestFootprint.left + requestFootprint.right + spacing;
  final maxFanRadians = egoAngularGap != null
      ? math.min(kDefaultMaxFanRadians, egoAngularGap * 0.8)
      : null;
  return (
    ringGap: radius,
    minChord: minChord,
    maxFanRadians: maxFanRadians,
  );
}

Iterable<void> _computeSemanticIdeals({
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
  required double spacing,
  required Map<String, ConstellationSize> nodeSizes,
  required Map<String, ConstellationFootprint> footprints,
  required Map<String, ConstellationPoint> alreadyPlaced,
  required Map<String, ConstellationPoint> placed,
  required Map<String, ConstellationPoint> ideals,
}) sync* {
  const canvasSize = (
    width: kConstellationCanvasExtent,
    height: kConstellationCanvasExtent,
  );

  final treePeers = <String>{};
  for (final id in paths.keep) {
    yield null;
    if (keptPeerIds.contains(id)) treePeers.add(id);
  }
  final children = <String, List<String>>{};

  for (final id in treePeers) {
    yield null;
    final parentId = paths.parent[id];
    if (parentId == null) {
      continue;
    }
    if (parentId == egoId || treePeers.contains(parentId)) {
      children.putIfAbsent(parentId, () => <String>[]).add(id);
    }
  }

  final angle = <String, double>{};

  Iterable<void> assignEqualSectors(String id, double start, double end) sync* {
    angle[id] = (start + end) / 2;
    final childList = children[id] ?? const <String>[];
    yield* _sortLayoutValues(childList, (a, b) => a.compareTo(b));
    if (childList.isEmpty) {
      return;
    }
    final childSpan = (end - start) / childList.length;
    var current = start;
    for (final child in childList) {
      yield null;
      yield* assignEqualSectors(child, current, current + childSpan);
      current += childSpan;
    }
  }

  yield* assignEqualSectors(egoId, 0, 2 * math.pi);
  ideals[egoId] = centre;

  for (final id in treePeers) {
    yield null;
    if (alreadyPlaced.containsKey(id)) {
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
    ideals[id] = _clampLegacy(
      (
        x: centre.x + offset.x,
        y: centre.y + offset.y,
      ),
      canvasSize,
    );
  }

  final ringPeers = <String>[];
  for (final id in paths.ring) {
    yield null;
    if (keptPeerIds.contains(id)) ringPeers.add(id);
  }
  yield* _sortLayoutValues(ringPeers, (a, b) => a.compareTo(b));
  if (ringPeers.isNotEmpty) {
    final ringRadius = (maxHops + residualRingFactor) * ringGap;
    final step = 2 * math.pi / ringPeers.length;
    for (var i = 0; i < ringPeers.length; i++) {
      yield null;
      final id = ringPeers[i];
      if (alreadyPlaced.containsKey(id)) {
        continue;
      }
      final nodeAngle = step * i;
      final offset = (
        x: math.cos(nodeAngle - math.pi / 2) * ringRadius,
        y: math.sin(nodeAngle - math.pi / 2) * ringRadius,
      );
      ideals[id] = _clampLegacy(
        (
          x: centre.x + offset.x,
          y: centre.y + offset.y,
        ),
        canvasSize,
      );
    }
  }

  final depthOneAngles = <double>[];
  for (final id in treePeers) {
    yield null;
    if (paths.depth[id] == 1) {
      depthOneAngles.add((angle[id] ?? 0) - math.pi / 2);
    }
  }
  final egoFanHeading = _LayoutValue<({LPoint direction, double gap})>();
  yield* _egoSatelliteDirectionSteps(depthOneAngles, egoFanHeading);
  final egoRequests = <String>[];
  for (final id in egoOwnRequestIds) {
    yield null;
    egoRequests.add(id);
  }
  yield* _sortLayoutValues(egoRequests, (a, b) => a.compareTo(b));
  if (egoRequests.isNotEmpty) {
    final fanOverrides = _footprintAwareFanParams(
      authorId: egoId,
      sortedRequestIds: egoRequests,
      footprints: footprints,
      nodeSizes: nodeSizes,
      satelliteOffset: satelliteOffset,
      spacing: spacing,
      egoAngularGap: egoFanHeading.value.gap,
    );
    final egoSatellites = localFanPositionEntries(
      parentPos: centre,
      direction: egoFanHeading.value.direction,
      childIds: egoRequests,
      canvasSize: (w: canvasSize.width, h: canvasSize.height),
      ringGap: fanOverrides?.ringGap ?? satelliteOffset,
      minChord: fanOverrides?.minChord,
      maxFanRadians: fanOverrides?.maxFanRadians ?? kDefaultMaxFanRadians,
    );
    for (final entry in egoSatellites) {
      yield null;
      if (!alreadyPlaced.containsKey(entry.key)) {
        ideals[entry.key] = entry.value;
      }
    }
  }

  final authors = <String>[];
  for (final author in visibleRequestsByAuthor.keys) {
    yield null;
    authors.add(author);
  }
  yield* _sortLayoutValues(authors, (a, b) => a.compareTo(b));
  for (final author in authors) {
    yield null;
    if (author == egoId) {
      continue;
    }
    final authorPoint = placed[author] ?? ideals[author];
    if (authorPoint == null) {
      continue;
    }
    final requestIds = <String>[];
    for (final id in visibleRequestsByAuthor[author]!) {
      yield null;
      requestIds.add(id);
    }
    yield* _sortLayoutValues(requestIds, (a, b) => a.compareTo(b));
    if (requestIds.isEmpty) {
      continue;
    }

    final radial = (
      x: authorPoint.x - centre.x,
      y: authorPoint.y - centre.y,
    );
    final distance = math.sqrt(radial.x * radial.x + radial.y * radial.y);
    final direction = distance < 1e-6
        ? branchUnitDirection(parentPos: centre)
        : (x: radial.x / distance, y: radial.y / distance);

    final fanOverrides = _footprintAwareFanParams(
      authorId: author,
      sortedRequestIds: requestIds,
      footprints: footprints,
      nodeSizes: nodeSizes,
      satelliteOffset: satelliteOffset,
      spacing: spacing,
    );
    final satellites = localFanPositionEntries(
      parentPos: authorPoint,
      direction: direction,
      childIds: requestIds,
      canvasSize: (w: canvasSize.width, h: canvasSize.height),
      ringGap: fanOverrides?.ringGap ?? satelliteOffset,
      minChord: fanOverrides?.minChord,
    );
    for (final entry in satellites) {
      yield null;
      if (!alreadyPlaced.containsKey(entry.key)) {
        ideals[entry.key] = entry.value;
      }
    }
  }
}

ConstellationPoint _clampLegacy(
  ConstellationPoint point,
  ConstellationSize canvasSize,
) {
  return clampLayoutPosition(
    point,
    (w: canvasSize.width, h: canvasSize.height),
  );
}

/// A value produced by a nested resumable calculation.
final class _LayoutValue<T> {
  late T value;
}

/// Keeps obstacle-scan totals unboxed across resumable checkpoints.
final class _LayoutDoubleValue {
  double value = 0;
}

/// In-place heap sort: one logarithmic sift per unit, never a whole list sort.
Iterable<void> _sortLayoutValues<T>(
  List<T> values,
  int Function(T, T) compare,
) sync* {
  void sift(int root, int end) {
    var current = root;
    while (current * 2 + 1 < end) {
      var child = current * 2 + 1;
      if (child + 1 < end && compare(values[child], values[child + 1]) < 0) {
        child++;
      }
      if (compare(values[current], values[child]) >= 0) return;
      final value = values[current];
      values[current] = values[child];
      values[child] = value;
      current = child;
    }
  }

  for (var root = values.length ~/ 2 - 1; root >= 0; root--) {
    sift(root, values.length);
    yield null;
  }
  for (var end = values.length - 1; end > 0; end--) {
    final value = values[0];
    values[0] = values[end];
    values[end] = value;
    sift(0, end);
    yield null;
  }
}
