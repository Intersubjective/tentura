import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';

import '../../domain/entity/constellation_trust_chain_person.dart';
import '../../domain/port/constellation_trust_chain_port.dart';
import '../gql/_g/constellation_trust_chain_fetch.req.gql.dart';

@LazySingleton(
  as: ConstellationTrustChainPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
final class ConstellationTrustChainRepository
    implements ConstellationTrustChainPort {
  ConstellationTrustChainRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  @override
  Future<List<ConstellationTrustChainPerson>> fetchTrustChain(
    String personId,
  ) => _remoteApiService
      .request(
        GConstellationTrustChainFetchReq((b) {
          b
            ..fetchPolicy = FetchPolicy.NoCache
            ..vars.personId = personId;
        }),
      )
      .firstWhere((response) => response.dataSource == DataSource.Link)
      .then(
        (response) => [
          for (final person
              in response
                  .dataOrThrow(label: 'ConstellationTrustChainFetch')
                  .constellationTrustChain)
            ConstellationTrustChainPerson(
              id: person.userId,
              displayName: person.displayName,
            ),
        ],
      );
}
