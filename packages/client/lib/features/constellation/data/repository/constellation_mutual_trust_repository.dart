import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';

import '../../domain/port/constellation_mutual_trust_port.dart';
import '../gql/_g/constellation_mutual_trust_fetch.req.gql.dart';

@LazySingleton(
  as: ConstellationMutualTrustPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
final class ConstellationMutualTrustRepository
    implements ConstellationMutualTrustPort {
  ConstellationMutualTrustRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  @override
  Future<Set<String>> fetchMutualTrust(String personId) => _remoteApiService
      .request(
        GConstellationMutualTrustFetchReq((b) {
          b
            ..fetchPolicy = FetchPolicy.NoCache
            ..vars.personId = personId;
        }),
      )
      .firstWhere((response) => response.dataSource == DataSource.Link)
      .then(
        (response) => response
            .dataOrThrow(label: 'ConstellationMutualTrustFetch')
            .constellationMutualTrust
            .toSet(),
      );
}
