import 'package:meta/meta.dart';

import 'constellation_layout.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
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
  return ConstellationAuthorSatellites(
    pinnedIds: pinned,
    unpinnedIds: unpinned,
  );
}

/// Beacon ids among [anchors] that are Request pins.
Set<String> constellationPinnedBeaconIds(
  Iterable<ConstellationAnchor> anchors,
) => {
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

bool _centreValid(ConstellationPoint centre, ConstellationSize size) =>
    constellationPointWithinEnvelope(centre) &&
    constellationBoundsWithinCanvas(
      constellationRenderedBounds(centre: centre, size: size),
    );

/// The largest part of [raw] that [valid] accepts, given that a part [valid]
/// accepts is accepted at every smaller part too (the bounds are convex and
/// the start is inside them).
double _settleAxis(double raw, bool Function(double) valid) {
  if (valid(raw)) {
    return raw;
  }
  var lo = 0.0;
  var hi = 1.0;
  for (var i = 0; i < 30; i++) {
    final mid = (lo + hi) / 2;
    if (valid(raw * mid)) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return raw * lo;
}

/// Moves [start] by [delta] one axis at a time, stopping each axis at the last
/// valid position, so a body pressed against a wall keeps sliding along it.
ConstellationPoint _slideWithinBounds(
  ConstellationPoint start,
  ConstellationPoint delta,
  ConstellationSize size,
) {
  final dx = _settleAxis(
    delta.x,
    (d) => _centreValid((x: start.x + d, y: start.y), size),
  );
  final dy = _settleAxis(
    delta.y,
    (d) => _centreValid((x: start.x + dx, y: start.y + d), size),
  );
  return (x: start.x + dx, y: start.y + dy);
}

/// Scene delta for the dragged parent, limited by the parent's own bounds only
/// (the envelope and the canvas); pinned companions never limit it.
///
/// [companionStarts] is accepted for call-site symmetry and ignored: each
/// companion is limited on its own by [constellationCompanionPosition].
ConstellationPoint constellationLimitClusterDelta({
  required ConstellationPoint parentStart,
  required ConstellationPoint proposedParent,
  required Iterable<ConstellationPoint> companionStarts,
  ConstellationSize parentSize = kConstellationDragPersonBodySize,
  ConstellationSize companionSize = kConstellationDragRequestBodySize,
}) {
  final parent = _slideWithinBounds(
    parentStart,
    (
      x: proposedParent.x - parentStart.x,
      y: proposedParent.y - parentStart.y,
    ),
    parentSize,
  );
  return (x: parent.x - parentStart.x, y: parent.y - parentStart.y);
}

/// Where a pinned companion rests when its parent moved by [parentDelta]: it
/// follows the parent and stops at the envelope and canvas edges by itself.
ConstellationPoint constellationCompanionPosition({
  required ConstellationPoint companionStart,
  required ConstellationPoint parentDelta,
  ConstellationSize companionSize = kConstellationDragRequestBodySize,
}) => _slideWithinBounds(companionStart, parentDelta, companionSize);

/// Scene delta for a selection moved as one group: the largest part of the
/// pointer's delta, axis by axis, that the dragged parent and every other
/// member can travel together. The group stays rigid, as in a graphics
/// editor, instead of members bunching up against a wall one by one.
///
/// Each member is held to the bounds it has when dragged alone (the envelope
/// and the canvas, at the parent [size] [constellationLimitClusterDelta]
/// uses). A member that already starts outside them would hold the whole
/// group still, so it does not count; it follows on its own through
/// [constellationGroupMemberPosition]. The parent always counts, exactly as in
/// [constellationLimitClusterDelta].
ConstellationPoint constellationLimitGroupDelta({
  required ConstellationPoint parentStart,
  required ConstellationPoint proposedParent,
  required Iterable<ConstellationPoint> memberStarts,
  ConstellationSize size = kConstellationDragPersonBodySize,
}) {
  final starts = [
    parentStart,
    for (final start in memberStarts)
      if (_centreValid(start, size)) start,
  ];
  bool allValid(double dx, double dy) => starts.every(
    (start) => _centreValid((x: start.x + dx, y: start.y + dy), size),
  );
  final dx = _settleAxis(
    proposedParent.x - parentStart.x,
    (d) => allValid(d, 0),
  );
  final dy = _settleAxis(
    proposedParent.y - parentStart.y,
    (d) => allValid(dx, d),
  );
  return (x: dx, y: dy);
}

/// Where a group member rests when the group moved by [groupDelta] (already
/// limited by [constellationLimitGroupDelta]): by the same delta as the
/// parent, unless it started outside the bounds, when it slides on its own.
ConstellationPoint constellationGroupMemberPosition({
  required ConstellationPoint memberStart,
  required ConstellationPoint groupDelta,
  ConstellationSize size = kConstellationDragPersonBodySize,
}) => _centreValid(memberStart, size)
    ? (x: memberStart.x + groupDelta.x, y: memberStart.y + groupDelta.y)
    : _slideWithinBounds(memberStart, groupDelta, size);
