import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/constellation_trust_chain_port.dart';

@Injectable(
  as: ConstellationTrustChainPort,
  env: [Environment.test],
  order: 1,
)
class ConstellationTrustChainRepositoryMock
    implements ConstellationTrustChainPort {
  @override
  Future<List<ConstellationTrustChainPerson>> trustChain({
    required String viewerId,
    required String context,
    required String personId,
  }) => Future.value(const []);
}
