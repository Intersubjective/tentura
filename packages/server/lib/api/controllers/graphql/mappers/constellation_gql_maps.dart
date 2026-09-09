import 'package:tentura_server/domain/entity/constellation_field.dart';

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
  'coverThumb': request.coverThumb == null
      ? null
      : imagePublicToGqlMap(request.coverThumb!),
};
