import 'package:injectable/injectable.dart';
import 'package:mockito/mockito.dart';

import '../../domain/port/constellation_anchor_repository_port.dart';

@Injectable(
  as: ConstellationAnchorRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class ConstellationAnchorRepositoryMock extends Mock
    implements ConstellationAnchorRepositoryPort {}
