import 'package:meta/meta.dart';

import 'constellation_consts.dart';
import 'constellation_layout.dart';
import 'entity/constellation_anchor.dart';
import 'entity/constellation_field.dart';

/// Scene-space sizes used when clamping a drag cluster to the canvas.
const kConstellationDragPersonBodySize = (width: 40.0, height: 40.0);
const kConstellationDragRequestBodySize = (width: 36.0, height: 36.0);

/// Units epsilon for "anchor adopted at intended position" after recovery.
const kConstellationAnchorAdoptEpsilonUnits = 1e-4;

/// Pinned vs unpinned Request satellites of one author from field/overlay.
@immutable
final class ConstellationAuthorSatellites {
  const ConstellationAuthorSatellites({
    required this.pinnedIds,
    required this.unpinnedIds,
  });

  final Set<String> pinnedIds;
  final Set<String> unpinnedIds;

  Set<String> get allIds => {...pinnedIds, ...unpinnedIds};
}

/// Partitions an author's Requests using field + overlay rows and pinned ids.
///
/// Does **not** use layout-visible maps — dormant/filter-hidden pins stay in
/// [pinnedIds] when present in [pinnedBeaconIds] even if not drawn.
ConstellationAuthorSatellites constellationAuthorSatellites({
  required String authorId,
  required Iterable<ConstellationRequest> fieldRequests,
  required Iterable<ConstellationRequest> overlayPinnedRequests,
  required Set<String> pinnedBeaconIds,
}) {
  final byId = <String, ConstellationRequest>{
    for (final request in fieldRequests)
      if (request.authorId == authorId) request.id: request,
    for (final request in overlayPinnedRequests)
      if (request.authorId == authorId) request.id: request,
  };
  final pinned = <String>{};
  final unpinned = <String>{};
  for (final id in byId.keys) {
    if (pinnedBeaconIds.contains(id)) {
      pinned.add(id);
    } else {
      unpinned.add(id);
    }
  }
  return ConstellationAuthorSatellites(pinnedIds: pinned, unpinnedIds: unpinned);
}

/// Beacon ids among [anchors] that are Request pins.
Set<String> constellationPinnedBeaconIds(
  Iterable<ConstellationAnchor> anchors,
) =>
    {
      for (final anchor in anchors)
        if (anchor.target.kind == ConstellationAnchorTargetKind.beacon)
          anchor.target.id,
    };

/// True when [anchors] holds [target] within [epsilon] of [intended].
bool constellationAnchorAdoptedAt({
  required Iterable<ConstellationAnchor> anchors,
  required ConstellationAnchorTarget target,
  required ConstellationAnchorPosition intended,
  double epsilon = kConstellationAnchorAdoptEpsilonUnits,
}) {
  for (final anchor in anchors) {
    if (anchor.target != target) {
      continue;
    }
    return (anchor.position.xUnits - intended.xUnits).abs() <= epsilon &&
        (anchor.position.yUnits - intended.yUnits).abs() <= epsilon;
  }
  return false;
}

/// Scene delta that keeps a rigid cluster inside the envelope and canvas.
ConstellationPoint constellationLimitClusterDelta({
  required ConstellationPoint parentStart,
  required ConstellationPoint proposedParent,
  required Iterable<ConstellationPoint> companionStarts,
  ConstellationSize parentSize = kConstellationDragPersonBodySize,
  ConstellationSize companionSize = kConstellationDragRequestBodySize,
}) {
  final raw = (
    x: proposedParent.x - parentStart.x,
    y: proposedParent.y - parentStart.y,
  );

  bool valid(ConstellationPoint centre, {required ConstellationSize size}) {
    return constellationPointWithinEnvelope(centre) &&
        constellationBoundsWithinCanvas(
          constellationRenderedBounds(centre: centre, size: size),
        );
  }

  bool clusterOk(ConstellationPoint delta) {
    final parent = (x: parentStart.x + delta.x, y: parentStart.y + delta.y);
    if (!valid(parent, size: parentSize)) {
      return false;
    }
    for (final start in companionStarts) {
      final next = (x: start.x + delta.x, y: start.y + delta.y);
      if (!valid(next, size: companionSize)) {
        return false;
      }
    }
    return true;
  }

  if (clusterOk(raw)) {
    return raw;
  }
  var lo = 0.0;
  var hi = 1.0;
  for (var i = 0; i < 24; i++) {
    final mid = (lo + hi) / 2;
    final scaled = (x: raw.x * mid, y: raw.y * mid);
    if (clusterOk(scaled)) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return (x: raw.x * lo, y: raw.y * lo);
}
