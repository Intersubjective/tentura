import 'package:injectable/injectable.dart';
import 'package:mockito/mockito.dart';

import '../../domain/port/constellation_targeted_read_port.dart';

@Injectable(
  as: ConstellationTargetedReadPort,
  env: [Environment.test],
  order: 1,
)
class ConstellationTargetedReadRepositoryMock extends Mock
    implements ConstellationTargetedReadPort {}
