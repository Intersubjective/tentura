import 'package:injectable/injectable.dart';
import 'package:mockito/mockito.dart';

import '../../domain/port/constellation_field_search_port.dart';

@Injectable(as: ConstellationFieldSearchPort, env: [Environment.test], order: 1)
class ConstellationFieldSearchRepositoryMock extends Mock
    implements ConstellationFieldSearchPort {}
