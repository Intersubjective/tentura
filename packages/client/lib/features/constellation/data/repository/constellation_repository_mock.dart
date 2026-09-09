import 'package:injectable/injectable.dart';
import 'package:mockito/mockito.dart';

import '../../domain/port/constellation_repository_port.dart';

@Injectable(
  as: ConstellationRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class ConstellationRepositoryMock extends Mock
    implements ConstellationRepositoryPort {}
