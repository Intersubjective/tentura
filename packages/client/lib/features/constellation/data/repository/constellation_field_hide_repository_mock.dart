import 'package:injectable/injectable.dart';
import 'package:mockito/mockito.dart';

import '../../domain/port/constellation_field_hide_port.dart';

@Injectable(as: ConstellationFieldHidePort, env: [Environment.test], order: 1)
class ConstellationFieldHideRepositoryMock extends Mock
    implements ConstellationFieldHidePort {}
