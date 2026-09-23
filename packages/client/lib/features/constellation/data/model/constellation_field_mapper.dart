import 'package:tentura_root/domain/entity/beacon_cover_source.dart';
import 'package:tentura/data/gql/_g/schema.schema.gql.dart';
import 'package:tentura/data/model/image_model_v2.dart';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import '../../domain/entity/constellation_anchor_projection.dart';
import '../../domain/entity/constellation_field.dart';
import '../gql/_g/constellation_anchors_fetch.data.gql.dart';
import '../gql/_g/constellation_field_fetch.data.gql.dart';

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

ConstellationPerson _mapPersonFields({
  required String id,
  String? displayName,
  String? handle,
  ImageModelV2? image,
}) =>
    ConstellationPerson(
      id: id,
      displayName: displayName,
      handle: handle,
      image: image?.asEntity,
    );

ConstellationPerson _mapFieldFetchPerson(
  GConstellationFieldFetchData_constellationField_peers peer,
) =>
    _mapPersonFields(
      id: peer.id,
      displayName: peer.displayName,
      handle: peer.handle,
      image: peer.image as ImageModelV2?,
    );

ConstellationPerson _mapAnchorsFetchPerson(
  GConstellationAnchorsFetchData_constellationField_peers peer,
) =>
    _mapPersonFields(
      id: peer.id,
      displayName: peer.displayName,
      handle: peer.handle,
      image: peer.image as ImageModelV2?,
    );

ConstellationTrustEdgeEntity _mapEdgeFields({
  required String src,
  required String dst,
  required int tier,
}) {
  _assertValidTier(tier);
  return ConstellationTrustEdgeEntity(
    src: src,
    dst: dst,
    tier: tier,
  );
}

ConstellationTrustEdgeEntity _mapFieldFetchEdge(
  GConstellationFieldFetchData_constellationField_edges edge,
) =>
    _mapEdgeFields(src: edge.src, dst: edge.dst, tier: edge.tier);

ConstellationTrustEdgeEntity _mapAnchorsFetchEdge(
  GConstellationAnchorsFetchData_constellationField_edges edge,
) =>
    _mapEdgeFields(src: edge.src, dst: edge.dst, tier: edge.tier);

ConstellationRequest _mapRequestFields({
  required String id,
  required String authorId,
  required String title,
  required int status,
  required Iterable<String> needs,
  String? primaryNeedSlug,
  String? startAt,
  String? endAt,
  String? addressLabel,
  required bool hasCoordinates,
  required bool isMine,
  required bool viewerHasActiveHelpOffer,
  required bool viewerIsRoomParticipant,
  required bool viewerHasForwardEdge,
  required int helpOfferCount,
  required int coverSource,
  ImageModelV2? coverThumb,
}) =>
    ConstellationRequest(
      id: id,
      authorId: authorId,
      title: title,
      status: status,
      needs: needs.toList(growable: false),
      primaryNeedSlug: primaryNeedSlug,
      startAt: startAt == null ? null : DateTime.parse(startAt),
      endAt: endAt == null ? null : DateTime.parse(endAt),
      addressLabel: addressLabel,
      hasCoordinates: hasCoordinates,
      isMine: isMine,
      viewerHasActiveHelpOffer: viewerHasActiveHelpOffer,
      viewerIsRoomParticipant: viewerIsRoomParticipant,
      viewerHasForwardEdge: viewerHasForwardEdge,
      helpOfferCount: helpOfferCount,
      coverSource: BeaconCoverSource.fromWireOrPhoto(coverSource),
      coverThumb: coverThumb?.asEntity,
    );

ConstellationRequest _mapFieldFetchRequest(
  GConstellationFieldFetchData_constellationField_requests request,
) =>
    _mapRequestFields(
      id: request.id,
      authorId: request.authorId,
      title: request.title,
      status: request.status,
      needs: request.needs,
      primaryNeedSlug: request.primaryNeedSlug,
      startAt: request.startAt,
      endAt: request.endAt,
      addressLabel: request.addressLabel,
      hasCoordinates: request.hasCoordinates,
      isMine: request.isMine,
      viewerHasActiveHelpOffer: request.viewerHasActiveHelpOffer,
      viewerIsRoomParticipant: request.viewerIsRoomParticipant,
      viewerHasForwardEdge: request.viewerHasForwardEdge,
      helpOfferCount: request.helpOfferCount,
      coverSource: request.coverSource,
      coverThumb: request.coverThumb as ImageModelV2?,
    );

ConstellationRequest _mapAnchorsFetchRequest(
  GConstellationAnchorsFetchData_constellationField_requests request,
) =>
    _mapRequestFields(
      id: request.id,
      authorId: request.authorId,
      title: request.title,
      status: request.status,
      needs: request.needs,
      primaryNeedSlug: request.primaryNeedSlug,
      startAt: request.startAt,
      endAt: request.endAt,
      addressLabel: request.addressLabel,
      hasCoordinates: request.hasCoordinates,
      isMine: request.isMine,
      viewerHasActiveHelpOffer: request.viewerHasActiveHelpOffer,
      viewerIsRoomParticipant: request.viewerIsRoomParticipant,
      viewerHasForwardEdge: request.viewerHasForwardEdge,
      helpOfferCount: request.helpOfferCount,
      coverSource: request.coverSource,
      coverThumb: request.coverThumb as ImageModelV2?,
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
          _mapPersonFields(
            id: peer.id,
            displayName: peer.displayName,
            handle: peer.handle,
            image: peer.image as ImageModelV2?,
          ),
      ],
      pinnedRequests: [
        for (final request in projection.pinnedRequests)
          _mapRequestFields(
            id: request.id,
            authorId: request.authorId,
            title: request.title,
            status: request.status,
            needs: request.needs,
            primaryNeedSlug: request.primaryNeedSlug,
            startAt: request.startAt,
            endAt: request.endAt,
            addressLabel: request.addressLabel,
            hasCoordinates: request.hasCoordinates,
            isMine: request.isMine,
            viewerHasActiveHelpOffer: request.viewerHasActiveHelpOffer,
            viewerIsRoomParticipant: request.viewerIsRoomParticipant,
            viewerHasForwardEdge: request.viewerHasForwardEdge,
            helpOfferCount: request.helpOfferCount,
            coverSource: request.coverSource,
            coverThumb: request.coverThumb as ImageModelV2?,
          ),
      ],
      supportPeers: [
        for (final peer in projection.supportPeers)
          _mapPersonFields(
            id: peer.id,
            displayName: peer.displayName,
            handle: peer.handle,
            image: peer.image as ImageModelV2?,
          ),
      ],
      supportEdges: [
        for (final edge in projection.supportEdges)
          _mapEdgeFields(src: edge.src, dst: edge.dst, tier: edge.tier),
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
          _mapPersonFields(
            id: peer.id,
            displayName: peer.displayName,
            handle: peer.handle,
            image: peer.image as ImageModelV2?,
          ),
      ],
      pinnedRequests: [
        for (final request in projection.pinnedRequests)
          _mapRequestFields(
            id: request.id,
            authorId: request.authorId,
            title: request.title,
            status: request.status,
            needs: request.needs,
            primaryNeedSlug: request.primaryNeedSlug,
            startAt: request.startAt,
            endAt: request.endAt,
            addressLabel: request.addressLabel,
            hasCoordinates: request.hasCoordinates,
            isMine: request.isMine,
            viewerHasActiveHelpOffer: request.viewerHasActiveHelpOffer,
            viewerIsRoomParticipant: request.viewerIsRoomParticipant,
            viewerHasForwardEdge: request.viewerHasForwardEdge,
            helpOfferCount: request.helpOfferCount,
            coverSource: request.coverSource,
            coverThumb: request.coverThumb as ImageModelV2?,
          ),
      ],
      supportPeers: [
        for (final peer in projection.supportPeers)
          _mapPersonFields(
            id: peer.id,
            displayName: peer.displayName,
            handle: peer.handle,
            image: peer.image as ImageModelV2?,
          ),
      ],
      supportEdges: [
        for (final edge in projection.supportEdges)
          _mapEdgeFields(src: edge.src, dst: edge.dst, tier: edge.tier),
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
