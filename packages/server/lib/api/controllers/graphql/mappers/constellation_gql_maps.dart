import 'package:tentura_server/domain/entity/constellation_anchor.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';

import 'gql_public_user_maps.dart';

Map<String, dynamic> constellationFieldToGqlMap(
  ConstellationFieldSnapshot snapshot,
) => {
  'loadedAt': snapshot.loadedAt.toIso8601String(),
  'context': snapshot.context,
  'peers': snapshot.peers.map(_peerToGqlMap).toList(growable: false),
  'edges': snapshot.edges.map(_edgeToGqlMap).toList(growable: false),
  'requests': snapshot.requests.map(_requestToGqlMap).toList(growable: false),
  'peersCapped': snapshot.peersCapped,
  'requestsCapped': snapshot.requestsCapped,
  'anchorProjection': constellationAnchorProjectionToGqlMap(
    snapshot.anchorProjection,
  ),
};

Map<String, dynamic> constellationAnchorProjectionToGqlMap(
  ConstellationAnchorProjection projection,
) => {
  'revision': projection.revision.toDecimalString(),
  'anchors': projection.anchors
      .map(constellationAnchorToGqlMap)
      .toList(growable: false),
  'pinnedPeers': projection.pinnedPeers
      .map(_peerToGqlMap)
      .toList(growable: false),
  'pinnedRequests': projection.pinnedRequests
      .map(_requestToGqlMap)
      .toList(growable: false),
  'supportPeers': projection.supportPeers
      .map(_peerToGqlMap)
      .toList(growable: false),
  'supportEdges': projection.supportEdges
      .map(_edgeToGqlMap)
      .toList(growable: false),
  'serverFilteredBeaconIds': List<String>.from(
    projection.serverFilteredBeaconIds,
    growable: false,
  ),
  'serverFilteredBeaconCount': projection.serverFilteredBeaconCount,
};

Map<String, dynamic> constellationAnchorToGqlMap(ConstellationAnchor anchor) =>
    {
      'targetKind': anchor.target.kind.wireValue,
      'targetId': anchor.target.id,
      'xUnits': anchor.position.xUnits,
      'yUnits': anchor.position.yUnits,
      'coordinateSpaceVersion': anchor.position.coordinateSpaceVersion,
      'revision': anchor.revision.toDecimalString(),
      'placedAt': anchor.placedAt.toIso8601String(),
    };

Map<String, dynamic> constellationAnchorUpsertResultToGqlMap(
  ConstellationAnchorUpsertResult result,
) => {
  'anchor': constellationAnchorToGqlMap(result.anchor),
  'revision': result.watermark.revision.toDecimalString(),
};

Map<String, dynamic> constellationAnchorDeleteResultToGqlMap(
  ConstellationAnchorDeleteResult result,
) => {
  'targetKind': result.target.kind.wireValue,
  'targetId': result.target.id,
  'revision': result.watermark.revision.toDecimalString(),
};

Map<String, dynamic> _peerToGqlMap(ConstellationPeerRecord peer) => {
  'id': peer.id,
  'displayName': peer.displayName,
  'handle': peer.handle,
  'image': peer.image == null ? null : imagePublicToGqlMap(peer.image!),
};

Map<String, dynamic> _edgeToGqlMap(ConstellationEdgeRecord edge) => {
  'src': edge.src,
  'dst': edge.dst,
  'tier': edge.tier,
};

Map<String, dynamic> _requestToGqlMap(ConstellationRequestRecord request) => {
  'id': request.id,
  'authorId': request.authorId,
  'title': request.title,
  'status': request.status,
  'needs': request.needs,
  'primaryNeedSlug': request.primaryNeedSlug,
  'startAt': request.startAt?.toIso8601String(),
  'endAt': request.endAt?.toIso8601String(),
  'addressLabel': request.addressLabel,
  'hasCoordinates': request.hasCoordinates,
  'isMine': request.isMine,
  'viewerHasActiveHelpOffer': request.viewerHasActiveHelpOffer,
  'viewerIsRoomParticipant': request.viewerIsRoomParticipant,
  'viewerHasForwardEdge': request.viewerHasForwardEdge,
  'helpOfferCount': request.helpOfferCount,
  'coverSource': request.coverSource,
  'coverThumb': request.coverThumb == null
      ? null
      : imagePublicToGqlMap(request.coverThumb!),
};
