import 'package:injectable/injectable.dart';
import 'package:mockito/mockito.dart';

import '../../domain/port/constellation_visibility_port.dart';

@Injectable(
  as: ConstellationVisibilityPort,
  env: [Environment.test],
  order: 1,
)
class ConstellationVisibilityRepositoryMock extends Mock
    implements ConstellationVisibilityPort {}
