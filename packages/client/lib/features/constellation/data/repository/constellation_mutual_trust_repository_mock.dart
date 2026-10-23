import 'package:injectable/injectable.dart';
import 'package:mockito/mockito.dart';

import '../../domain/port/constellation_mutual_trust_port.dart';

@Injectable(
  as: ConstellationMutualTrustPort,
  env: [Environment.test],
  order: 1,
)
class ConstellationMutualTrustRepositoryMock extends Mock
    implements ConstellationMutualTrustPort {}
