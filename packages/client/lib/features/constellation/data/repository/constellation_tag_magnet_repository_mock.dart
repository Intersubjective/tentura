import 'package:injectable/injectable.dart';
import 'package:mockito/mockito.dart';

import '../../domain/port/constellation_tag_magnet_repository_port.dart';

@Injectable(
  as: ConstellationTagMagnetRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class ConstellationTagMagnetRepositoryMock extends Mock
    implements ConstellationTagMagnetRepositoryPort {}
