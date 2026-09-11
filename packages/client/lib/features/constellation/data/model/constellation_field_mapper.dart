import 'package:meta/meta.dart';
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';
import 'package:tentura/data/gql/_g/schema.schema.gql.dart';
import 'package:tentura/data/model/image_model_v2.dart';

import '../../domain/entity/constellation_anchor.dart';
import '../../domain/entity/constellation_anchor_projection.dart';
import '../../domain/entity/constellation_field.dart';
import '../gql/_g/constellation_anchors_fetch.data.gql.dart';
import '../gql/_g/constellation_field_fetch.data.gql.dart';

@visibleForTesting
ConstellationField mapConstellationFieldFromFieldFetch(
  GConstellationFieldFetchData_constellationField payload,
) =>
    ConstellationField(
      loadedAt: DateTime.parse(payload.loadedAt),
      context: payload.context,
      peers: [for (final peer in payload.peers) _mapFieldFetchPerson(peer)],
      edges: [for (final edge in payload.edges) _mapFieldFetchEdge(edge)],
      requests: [
        for (final request in payload.requests) _mapFieldFetchRequest(request),
      ],
      peersCapped: payload.peersCapped,
      requestsCapped: payload.requestsCapped,
      anchorProjection: _mapFieldFetchAnchorProjection(payload.anchorProjection),
    );

@visibleForTesting
ConstellationField mapConstellationFieldFromAnchorsFetch(
  GConstellationAnchorsFetchData_constellationField payload,
) =>
    ConstellationField(
      loadedAt: DateTime.parse(payload.loadedAt),
      context: payload.context,
      peers: [for (final peer in payload.peers) _mapAnchorsFetchPerson(peer)],
      edges: [for (final edge in payload.edges) _mapAnchorsFetchEdge(edge)],
      requests: [
        for (final request in payload.requests)
          _mapAnchorsFetchRequest(request),
      ],
      peersCapped: payload.peersCapped,
      requestsCapped: payload.requestsCapped,
      anchorProjection:
          _mapAnchorsFetchAnchorProjection(payload.anchorProjection),
    );

ConstellationPerson _mapFieldFetchPerson(
  GConstellationFieldFetchData_constellationField_peers peer,
) =>
    ConstellationPerson(
      id: peer.id,
      displayName: peer.displayName,
      handle: peer.handle,
      image: (peer.image as ImageModelV2?)?.asEntity,
    );

ConstellationPerson _mapAnchorsFetchPerson(
  GConstellationAnchorsFetchData_constellationField_peers peer,
) =>
    ConstellationPerson(
      id: peer.id,
      displayName: peer.displayName,
      handle: peer.handle,
      image: (peer.image as ImageModelV2?)?.asEntity,
    );

ConstellationTrustEdgeEntity _mapFieldFetchEdge(
  GConstellationFieldFetchData_constellationField_edges edge,
) {
  _assertValidTier(edge.tier);
  return ConstellationTrustEdgeEntity(
    src: edge.src,
    dst: edge.dst,
    tier: edge.tier,
  );
}

ConstellationTrustEdgeEntity _mapAnchorsFetchEdge(
  GConstellationAnchorsFetchData_constellationField_edges edge,
) {
  _assertValidTier(edge.tier);
  return ConstellationTrustEdgeEntity(
    src: edge.src,
    dst: edge.dst,
    tier: edge.tier,
  );
}

ConstellationRequest _mapFieldFetchRequest(
  GConstellationFieldFetchData_constellationField_requests request,
) =>
    ConstellationRequest(
      id: request.id,
      authorId: request.authorId,
      title: request.title,
      status: request.status,
      needs: request.needs.toList(growable: false),
      primaryNeedSlug: request.primaryNeedSlug,
      startAt: request.startAt == null ? null : DateTime.parse(request.startAt!),
      endAt: request.endAt == null ? null : DateTime.parse(request.endAt!),
      addressLabel: request.addressLabel,
      hasCoordinates: request.hasCoordinates,
      isMine: request.isMine,
      viewerHasActiveHelpOffer: request.viewerHasActiveHelpOffer,
      viewerIsRoomParticipant: request.viewerIsRoomParticipant,
      viewerHasForwardEdge: request.viewerHasForwardEdge,
      helpOfferCount: request.helpOfferCount,
      coverSource: BeaconCoverSource.fromWireOrPhoto(request.coverSource),
      coverThumb: (request.coverThumb as ImageModelV2?)?.asEntity,
    );

ConstellationRequest _mapAnchorsFetchRequest(
  GConstellationAnchorsFetchData_constellationField_requests request,
) =>
    ConstellationRequest(
      id: request.id,
      authorId: request.authorId,
      title: request.title,
      status: request.status,
      needs: request.needs.toList(growable: false),
      primaryNeedSlug: request.primaryNeedSlug,
      startAt: request.startAt == null ? null : DateTime.parse(request.startAt!),
      endAt: request.endAt == null ? null : DateTime.parse(request.endAt!),
      addressLabel: request.addressLabel,
      hasCoordinates: request.hasCoordinates,
      isMine: request.isMine,
      viewerHasActiveHelpOffer: request.viewerHasActiveHelpOffer,
      viewerIsRoomParticipant: request.viewerIsRoomParticipant,
      viewerHasForwardEdge: request.viewerHasForwardEdge,
      helpOfferCount: request.helpOfferCount,
      coverSource: BeaconCoverSource.fromWireOrPhoto(request.coverSource),
      coverThumb: (request.coverThumb as ImageModelV2?)?.asEntity,
    );

ConstellationAnchorProjection _mapFieldFetchAnchorProjection(
  GConstellationFieldFetchData_constellationField_anchorProjection projection,
) =>
    ConstellationAnchorProjection(
      revision: _parseRevision(projection.revision),
      anchors: [
        for (final anchor in projection.anchors) _mapFieldFetchAnchor(anchor),
      ],
      pinnedPeers: [
        for (final peer in projection.pinnedPeers)
          _mapFieldFetchPerson(peer),
      ],
      pinnedRequests: [
        for (final request in projection.pinnedRequests)
          _mapFieldFetchRequest(request),
      ],
      supportPeers: [
        for (final peer in projection.supportPeers) _mapFieldFetchPerson(peer),
      ],
      supportEdges: [
        for (final edge in projection.supportEdges) _mapFieldFetchEdge(edge),
      ],
      serverFilteredBeaconIds: projection.serverFilteredBeaconIds
          .toList(growable: false),
      serverFilteredBeaconCount: projection.serverFilteredBeaconCount,
    );

ConstellationAnchorProjection _mapAnchorsFetchAnchorProjection(
  GConstellationAnchorsFetchData_constellationField_anchorProjection projection,
) =>
    ConstellationAnchorProjection(
      revision: _parseRevision(projection.revision),
      anchors: [
        for (final anchor in projection.anchors)
          _mapAnchorsFetchAnchor(anchor),
      ],
      pinnedPeers: [
        for (final peer in projection.pinnedPeers)
          _mapAnchorsFetchPerson(peer),
      ],
      pinnedRequests: [
        for (final request in projection.pinnedRequests)
          _mapAnchorsFetchRequest(request),
      ],
      supportPeers: [
        for (final peer in projection.supportPeers)
          _mapAnchorsFetchPerson(peer),
      ],
      supportEdges: [
        for (final edge in projection.supportEdges) _mapAnchorsFetchEdge(edge),
      ],
      serverFilteredBeaconIds: projection.serverFilteredBeaconIds
          .toList(growable: false),
      serverFilteredBeaconCount: projection.serverFilteredBeaconCount,
    );

ConstellationAnchor _mapFieldFetchAnchor(
  GConstellationFieldFetchData_constellationField_anchorProjection_anchors
      anchor,
) =>
    _mapWireAnchor(
      targetKind: anchor.targetKind,
      targetId: anchor.targetId,
      xUnits: anchor.xUnits,
      yUnits: anchor.yUnits,
      coordinateSpaceVersion: anchor.coordinateSpaceVersion,
      revision: anchor.revision,
      placedAt: anchor.placedAt,
    );

ConstellationAnchor _mapAnchorsFetchAnchor(
  GConstellationAnchorsFetchData_constellationField_anchorProjection_anchors
      anchor,
) =>
    _mapWireAnchor(
      targetKind: anchor.targetKind,
      targetId: anchor.targetId,
      xUnits: anchor.xUnits,
      yUnits: anchor.yUnits,
      coordinateSpaceVersion: anchor.coordinateSpaceVersion,
      revision: anchor.revision,
      placedAt: anchor.placedAt,
    );

@visibleForTesting
ConstellationAnchor mapWireAnchor({
  required Gv2_ConstellationAnchorTargetKind targetKind,
  required String targetId,
  required double xUnits,
  required double yUnits,
  required int coordinateSpaceVersion,
  required String revision,
  required String placedAt,
}) =>
    _mapWireAnchor(
      targetKind: targetKind,
      targetId: targetId,
      xUnits: xUnits,
      yUnits: yUnits,
      coordinateSpaceVersion: coordinateSpaceVersion,
      revision: revision,
      placedAt: placedAt,
    );

ConstellationAnchor _mapWireAnchor({
  required Gv2_ConstellationAnchorTargetKind targetKind,
  required String targetId,
  required double xUnits,
  required double yUnits,
  required int coordinateSpaceVersion,
  required String revision,
  required String placedAt,
}) {
  final target = ConstellationAnchorTarget.tryFromWire(
    kindWire: targetKind.name,
    targetId: targetId,
  );
  if (target == null) {
    throw FormatException(
      'Malformed constellation anchor target kind: ${targetKind.name}',
    );
  }
  final positionValidation = ConstellationAnchorPosition.validate(
    xUnits: xUnits,
    yUnits: yUnits,
    coordinateSpaceVersion: coordinateSpaceVersion,
  );
  if (positionValidation is! ConstellationAnchorPositionValid) {
    throw FormatException('Malformed constellation anchor coordinates');
  }
  return ConstellationAnchor(
    target: target,
    position: positionValidation.position,
    revision: _parseRevision(revision),
    placedAt: DateTime.parse(placedAt),
  );
}

ConstellationAnchorRevision _parseRevision(String wire) {
  final parsed = ConstellationAnchorRevision.parseDecimalString(wire);
  if (parsed is! ConstellationAnchorRevisionParsed) {
    throw FormatException('Malformed constellation anchor revision: $wire');
  }
  return parsed.revision;
}

void _assertValidTier(int tier) {
  if (tier != 1 && tier != 2) {
    throw FormatException('Invalid constellation edge tier: $tier');
  }
}

Gv2_ConstellationProjection projectionToWire(ConstellationProjection projection) =>
    switch (projection) {
      ConstellationProjection.full => Gv2_ConstellationProjection.FULL,
      ConstellationProjection.anchors => Gv2_ConstellationProjection.ANCHORS,
    };

Gv2_ConstellationAnchorTargetKind targetKindToWire(
  ConstellationAnchorTargetKind kind,
) =>
    switch (kind) {
      ConstellationAnchorTargetKind.person =>
        Gv2_ConstellationAnchorTargetKind.PERSON,
      ConstellationAnchorTargetKind.beacon =>
        Gv2_ConstellationAnchorTargetKind.BEACON,
    };
