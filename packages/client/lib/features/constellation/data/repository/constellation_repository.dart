import 'package:injectable/injectable.dart';
import 'package:tentura/data/service/remote_api_service.dart';

import '../../domain/entity/constellation_anchor_projection.dart';
import '../../domain/entity/constellation_field.dart';
import '../../domain/port/constellation_repository_port.dart';
import '../gql/_g/constellation_anchors_fetch.req.gql.dart';
import '../gql/_g/constellation_field_fetch.req.gql.dart';
import '../model/constellation_field_mapper.dart';

@LazySingleton(
  as: ConstellationRepositoryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
final class ConstellationRepository implements ConstellationRepositoryPort {
  ConstellationRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) {
    if (projection == ConstellationProjection.anchors) {
      return _remoteApiService
          .request(
            GConstellationAnchorsFetchReq((b) {
              b.vars
                ..showClosed = membershipFilters.showClosed
                ..participatedOnly = membershipFilters.participatedOnly;
            }),
          )
          .firstWhere((response) => response.dataSource == DataSource.Link)
          .then((response) => mapConstellationFieldFromAnchorsFetch(
                response
                    .dataOrThrow(label: 'ConstellationAnchorsFetch')
                    .constellationField,
              ));
    }

    return _remoteApiService
        .request(
          GConstellationFieldFetchReq((b) {
            b.vars
              ..showClosed = membershipFilters.showClosed
              ..participatedOnly = membershipFilters.participatedOnly
              ..projection = projectionToWire(projection);
          }),
        )
        .firstWhere((response) => response.dataSource == DataSource.Link)
        .then((response) => mapConstellationFieldFromFieldFetch(
              response
                  .dataOrThrow(label: 'ConstellationFieldFetch')
                  .constellationField,
            ));
  }
}
