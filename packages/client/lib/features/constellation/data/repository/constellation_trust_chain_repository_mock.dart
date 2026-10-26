import 'package:injectable/injectable.dart';
import 'package:mockito/mockito.dart';

import '../../domain/port/constellation_trust_chain_port.dart';

@Injectable(
  as: ConstellationTrustChainPort,
  env: [Environment.test],
  order: 1,
)
class ConstellationTrustChainRepositoryMock extends Mock
    implements ConstellationTrustChainPort {}
