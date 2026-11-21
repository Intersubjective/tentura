import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/port/constellation_mutual_trust_port.dart';

@Injectable(
  as: ConstellationMutualTrustPort,
  env: [Environment.test],
  order: 1,
)
class ConstellationMutualTrustRepositoryMock
    implements ConstellationMutualTrustPort {
  @override
  Future<List<ConstellationEdgeRecord>> explicitTrustEdgesOf({
    required String viewerId,
    required String context,
    required String personId,
  }) => Future.value(const []);
}
