import 'package:meta/meta.dart';
import 'package:tentura/consts.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'entity/constellation_anchor_projection.dart';
import 'entity/constellation_field.dart';

/// The viewer's explicit trust (tier-1, `vote_user`) to and from one person,
/// learned outside a FULL read (#672). A null direction is unknown and left
/// as the field has it.
@immutable
final class ConstellationViewerRelation {
  const ConstellationViewerRelation({
    required this.personId,
    this.viewerTrusts,
    this.trustsViewer,
  });

  final String personId;

  /// Whether the viewer trusts [personId].
  final bool? viewerTrusts;

  /// Whether [personId] trusts the viewer.
  final bool? trustsViewer;

  @override
  bool operator ==(Object other) =>
      other is ConstellationViewerRelation &&
      other.personId == personId &&
      other.viewerTrusts == viewerTrusts &&
      other.trustsViewer == trustsViewer;

  @override
  int get hashCode => Object.hash(personId, viewerTrusts, trustsViewer);

  @override
  String toString() =>
      'ConstellationViewerRelation($personId, viewerTrusts: $viewerTrusts, '
      'trustsViewer: $trustsViewer)';
}

/// Whether [personId] is a node of [field]: an ordinary peer, a contact
/// node, a pinned person or a support-path person.
bool constellationFieldHasPerson(ConstellationField field, String personId) {
  final projection = field.resolvedAnchorProjection;
  return field.peers.any((p) => p.id == personId) ||
      projection.pinnedPeers.any((p) => p.id == personId) ||
      projection.supportPeers.any((p) => p.id == personId);
}

/// Whether [personId] is on [field] inside the viewer's visible set, i.e.
/// with content and trust edges of their own (not a contact node, not a
/// pinned person outside the visible set).
bool constellationFieldHasVisiblePerson(
  ConstellationField field,
  String personId,
) {
  final projection = field.resolvedAnchorProjection;
  for (final peer in field.peers) {
    if (peer.id == personId) return !peer.contactOnly;
  }
  return projection.supportPeers.any((p) => p.id == personId) ||
      projection.pinnedPeers.any(
        (p) => p.id == personId && p.visible && !p.contactOnly,
      );
}

/// [field] with the viewer's explicit trust to and from each person in
/// [relations] set as the server would compute it (#672):
///
/// * the tier-1 edge in that direction is added or removed (a tier-1 edge
///   replaces a derived tier-2 one; removing trust leaves a tier-2 edge
///   alone, since `user_trust_edge` decays on its own schedule);
/// * the viewer trusting someone makes them a direct contact; a contact node
///   (outside the visible set) the viewer stops trusting leaves the field,
///   and a pinned person outside the visible set the viewer starts trusting
///   becomes a contact node;
/// * edges into the viewer from a contact node are never added: the field
///   holds only the viewer's own edge for them.
///
/// People not on [field] are skipped. Returns [field] itself when nothing
/// changes.
ConstellationField patchViewerRelations(
  ConstellationField field, {
  required String viewerId,
  required Iterable<ConstellationViewerRelation> relations,
  bool fieldMembershipV2Enabled = kFieldMembershipV2Enabled,
}) {
  if (viewerId.isEmpty) return field;
  var result = field;
  for (final relation in relations) {
    final personId = relation.personId;
    if (personId == viewerId ||
        !constellationFieldHasPerson(result, personId)) {
      continue;
    }
    result = _patchOne(
      result,
      viewerId: viewerId,
      relation: relation,
      fieldMembershipV2Enabled: fieldMembershipV2Enabled,
    );
  }
  return result;
}

ConstellationField _patchOne(
  ConstellationField field, {
  required String viewerId,
  required ConstellationViewerRelation relation,
  required bool fieldMembershipV2Enabled,
}) {
  final personId = relation.personId;
  final projection = field.resolvedAnchorProjection;
  var peers = field.peers;
  // Freezed list getters wrap anew on each read: track changes explicitly.
  var peersChanged = false;
  var edges = field.edges;
  var supportEdges = projection.supportEdges;
  var directContactIds = field.directContactIds;

  bool isPair(ConstellationTrustEdgeEntity e, String src, String dst) =>
      e.src == src && e.dst == dst;

  final contactNode = peers.any((p) => p.id == personId && p.contactOnly);

  final viewerTrusts = relation.viewerTrusts;
  if (viewerTrusts != null) {
    if (viewerTrusts) {
      edges = [
        for (final e in edges)
          if (!isPair(e, viewerId, personId)) e,
        ConstellationTrustEdgeEntity(src: viewerId, dst: personId, tier: 1),
      ];
      supportEdges = [
        for (final e in supportEdges)
          if (!(isPair(e, viewerId, personId) && e.tier != 1)) e,
      ];
      if (!directContactIds.contains(personId)) {
        directContactIds = [...directContactIds, personId];
      }
      final inPeers = peers.any((p) => p.id == personId);
      if (!inPeers) {
        // A pinned person outside the visible set is a contact node once the
        // viewer trusts them (#246): identity only.
        for (final pinned in projection.pinnedPeers) {
          if (pinned.id == personId && !pinned.visible) {
            peers = [
              ...peers,
              pinned.copyWith(visible: false, contactOnly: true),
            ];
            peersChanged = true;
          }
        }
      }
    } else {
      edges = [
        for (final e in edges)
          if (!(isPair(e, viewerId, personId) && e.tier == 1)) e,
      ];
      supportEdges = [
        for (final e in supportEdges)
          if (!(isPair(e, viewerId, personId) && e.tier == 1)) e,
      ];
      directContactIds = [
        for (final id in directContactIds)
          if (id != personId) id,
      ];
      if (contactNode) {
        // A contact node is on the field only because the viewer trusts them.
        peers = [
          for (final p in peers)
            if (p.id != personId) p,
        ];
        peersChanged = true;
        edges = [
          for (final e in edges)
            if (e.src != personId && e.dst != personId) e,
        ];
      }
    }
  }

  final trustsViewer = relation.trustsViewer;
  // Their edge to the viewer exists on the field only while they are inside
  // the visible set: a contact node or a pinned person outside it has none.
  final visibleNow = peers.any((p) => p.id == personId)
      ? peers.any((p) => p.id == personId && !p.contactOnly)
      : projection.supportPeers.any((p) => p.id == personId) ||
            projection.pinnedPeers.any(
              (p) => p.id == personId && p.visible && !p.contactOnly,
            );
  if (trustsViewer != null && visibleNow) {
    if (trustsViewer) {
      edges = [
        for (final e in edges)
          if (!isPair(e, personId, viewerId)) e,
        ConstellationTrustEdgeEntity(src: personId, dst: viewerId, tier: 1),
      ];
      supportEdges = [
        for (final e in supportEdges)
          if (!(isPair(e, personId, viewerId) && e.tier != 1)) e,
      ];
    } else {
      edges = [
        for (final e in edges)
          if (!(isPair(e, personId, viewerId) && e.tier == 1)) e,
      ];
      supportEdges = [
        for (final e in supportEdges)
          if (!(isPair(e, personId, viewerId) && e.tier == 1)) e,
      ];
    }
  }

  if (fieldMembershipV2Enabled) {
    final kinds = _patchedAutoTagKinds(peers, relation);
    if (kinds != null) {
      peers = [
        for (final p in peers)
          if (p.id == personId) p.copyWith(autoTagKinds: kinds) else p,
      ];
      peersChanged = true;
    }
  }

  final edgesChanged = !_sameEdges(edges, field.edges);
  final supportChanged = !_sameEdges(supportEdges, projection.supportEdges);
  final contactsChanged = !_sameIds(directContactIds, field.directContactIds);
  if (!edgesChanged && !supportChanged && !peersChanged && !contactsChanged) {
    return field;
  }
  return field.copyWith(
    peers: peersChanged ? peers : field.peers,
    edges: edgesChanged ? edges : field.edges,
    directContactIds: contactsChanged
        ? directContactIds
        : field.directContactIds,
    anchorProjection: supportChanged
        ? _withSupportEdges(projection, supportEdges)
        : field.anchorProjection,
  );
}

/// The trust kinds of the person in [relation] as the patched relation leaves
/// them, or null when they do not change.
Set<ConstellationAutoTagKind>? _patchedAutoTagKinds(
  List<ConstellationPerson> peers,
  ConstellationViewerRelation relation,
) {
  for (final peer in peers) {
    if (peer.id != relation.personId || peer.contactOnly) continue;
    final old = peer.autoTagKinds;
    final iTrust =
        relation.viewerTrusts ??
        old.contains(ConstellationAutoTagKind.iTrust);
    final trustsMe =
        relation.trustsViewer ??
        old.contains(ConstellationAutoTagKind.trustsMe);
    final kinds = {
      if (iTrust) ConstellationAutoTagKind.iTrust,
      if (trustsMe) ConstellationAutoTagKind.trustsMe,
      if (iTrust && trustsMe) ConstellationAutoTagKind.mutualContact,
    };
    final same = kinds.length == old.length && kinds.containsAll(old);
    return same ? null : kinds;
  }
  return null;
}

/// [field] with every one of [requests] it lacks added to its Requests.
ConstellationField addFieldRequests(
  ConstellationField field,
  Iterable<ConstellationRequest> requests,
) {
  final present = {
    for (final r in field.requests) r.id,
    for (final r in field.resolvedAnchorProjection.pinnedRequests) r.id,
  };
  final added = [
    for (final r in requests)
      if (present.add(r.id)) r,
  ];
  if (added.isEmpty) return field;
  return field.copyWith(requests: [...field.requests, ...added]);
}

/// [field] keeping as ordinary Requests the pinned Requests of [before] that
/// are no longer pinned (no anchor) in [field]'s projection (#673).
///
/// A FULL read carries a pinned Request only in the anchor projection, so the
/// projection is its only copy on the field: unpinning must hand it back to
/// the automatic layer instead of dropping it until the next FULL. (Whether
/// it is still discoverable is not known here; the next FULL decides.)
ConstellationField keepUnpinnedRequests(
  ConstellationField field, {
  required Iterable<ConstellationRequest> before,
}) {
  final projection = field.resolvedAnchorProjection;
  // An anchor the server withheld (an unreadable target) is not an unpin.
  final stillAnchored = {
    for (final anchor in projection.anchors)
      if (anchor.target.kind == ConstellationAnchorTargetKind.beacon)
        anchor.target.id,
    ...projection.serverFilteredBeaconIds,
  };
  // Only a Request the automatic layer could hold: the viewer's own, or one
  // whose author is on the field inside the visible set. Anything else (a
  // pinned Request of someone outside it) leaves with its pin.
  return addFieldRequests(field, [
    for (final request in before)
      if (!stillAnchored.contains(request.id) &&
          (request.isMine ||
              constellationFieldHasVisiblePerson(field, request.authorId)))
        request,
  ]);
}

ConstellationAnchorProjection _withSupportEdges(
  ConstellationAnchorProjection p,
  List<ConstellationTrustEdgeEntity> supportEdges,
) => ConstellationAnchorProjection(
  revision: p.revision,
  anchors: p.anchors,
  pinnedPeers: p.pinnedPeers,
  pinnedRequests: p.pinnedRequests,
  supportPeers: p.supportPeers,
  supportEdges: supportEdges,
  serverFilteredBeaconIds: p.serverFilteredBeaconIds,
  serverFilteredBeaconCount: p.serverFilteredBeaconCount,
);

bool _sameEdges(
  List<ConstellationTrustEdgeEntity> a,
  List<ConstellationTrustEdgeEntity> b,
) => a.length == b.length && a.toSet().containsAll(b);

bool _sameIds(List<String> a, List<String> b) =>
    a.length == b.length && a.toSet().containsAll(b);
