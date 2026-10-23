import 'package:injectable/injectable.dart';
import 'package:tentura/data/service/remote_api_service.dart';

import '../../domain/constellation_field_patches.dart';
import '../../domain/entity/constellation_anchor_projection.dart';
import '../../domain/entity/constellation_field.dart';
import '../../domain/port/constellation_targeted_read_port.dart';
import '../gql/_g/constellation_field_requests_fetch.req.gql.dart';
import '../gql/_g/constellation_viewer_relations.req.gql.dart';
import '../model/constellation_field_mapper.dart';

@LazySingleton(
  as: ConstellationTargetedReadPort,
  env: [Environment.dev, Environment.prod],
)
final class ConstellationTargetedReadRepository
    implements ConstellationTargetedReadPort {
  ConstellationTargetedReadRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  @override
  Future<List<ConstellationViewerRelation>> readViewerRelations(
    Set<String> personIds,
  ) async {
    if (personIds.isEmpty) return const [];
    final ids = personIds.take(ConstellationTargetedReadPort.maxRelationIds);
    final rows = await _remoteApiService
        .request(
          GConstellationViewerRelationsReq((b) {
            b
              ..fetchPolicy = FetchPolicy.NoCache
              ..vars.ids.replace(ids);
          }),
        )
        .firstWhere((response) => response.dataSource == DataSource.Link)
        .then(
          (response) =>
              response.dataOrThrow(label: 'ConstellationViewerRelations').user,
        );
    return [
      for (final row in rows)
        ConstellationViewerRelation(
          personId: row.id,
          viewerTrusts: (row.my_vote ?? 0) > 0,
          trustsViewer: row.trusts_viewer ?? false,
        ),
    ];
  }

  @override
  Future<List<ConstellationRequest>> fetchRequests(
    Set<String> beaconIds, {
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
  }) async {
    if (beaconIds.isEmpty) return const [];
    final ids = beaconIds.take(ConstellationTargetedReadPort.maxRequestIds);
    final rows = await _remoteApiService
        .request(
          GConstellationFieldRequestsFetchReq((b) {
            b
              ..fetchPolicy = FetchPolicy.NoCache
              ..vars.ids.replace(ids)
              ..vars.showClosed = membershipFilters.showClosed
              ..vars.participatedOnly = membershipFilters.participatedOnly;
          }),
        )
        .firstWhere((response) => response.dataSource == DataSource.Link)
        .then(
          (response) => response
              .dataOrThrow(label: 'ConstellationFieldRequestsFetch')
              .constellationFieldRequests,
        );
    return mapConstellationFieldRequestsFetch(rows);
  }
}
