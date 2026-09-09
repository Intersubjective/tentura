import 'package:injectable/injectable.dart';
import 'package:tentura/data/model/image_model_v2.dart';
import 'package:tentura/data/service/remote_api_service.dart';

import '../../domain/entity/constellation_field.dart';
import '../../domain/port/constellation_repository_port.dart';
import '../gql/_g/constellation_field_fetch.data.gql.dart';
import '../gql/_g/constellation_field_fetch.req.gql.dart';

@LazySingleton(
  as: ConstellationRepositoryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
final class ConstellationRepository implements ConstellationRepositoryPort {
  ConstellationRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  @override
  Future<ConstellationField> fetch() => _remoteApiService
      .request(GConstellationFieldFetchReq())
      .firstWhere((response) => response.dataSource == DataSource.Link)
      .then((response) {
        final payload = response
            .dataOrThrow(
              label: 'ConstellationFieldFetch',
            )
            .constellationField;
        return mapConstellationField(payload);
      });

  static ConstellationField mapConstellationField(
    GConstellationFieldFetchData_constellationField payload,
  ) => ConstellationField(
    loadedAt: DateTime.parse(payload.loadedAt),
    context: payload.context,
    peers: [for (final peer in payload.peers) _mapPerson(peer)],
    edges: [for (final edge in payload.edges) _mapEdge(edge)],
    requests: [for (final request in payload.requests) _mapRequest(request)],
    peersCapped: payload.peersCapped,
    requestsCapped: payload.requestsCapped,
  );

  static ConstellationPerson _mapPerson(
    GConstellationFieldFetchData_constellationField_peers peer,
  ) => ConstellationPerson(
    id: peer.id,
    displayName: peer.displayName,
    handle: peer.handle,
    image: (peer.image as ImageModelV2?)?.asEntity,
  );

  static ConstellationTrustEdgeEntity _mapEdge(
    GConstellationFieldFetchData_constellationField_edges edge,
  ) {
    _assertValidTier(edge.tier);
    return ConstellationTrustEdgeEntity(
      src: edge.src,
      dst: edge.dst,
      tier: edge.tier,
    );
  }

  static ConstellationRequest _mapRequest(
    GConstellationFieldFetchData_constellationField_requests request,
  ) => ConstellationRequest(
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
    coverThumb: (request.coverThumb as ImageModelV2?)?.asEntity,
  );

  static void _assertValidTier(int tier) {
    if (tier != 1 && tier != 2) {
      throw FormatException('Invalid constellation edge tier: $tier');
    }
  }
}
