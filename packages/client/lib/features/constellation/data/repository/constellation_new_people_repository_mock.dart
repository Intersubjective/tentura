import 'package:injectable/injectable.dart';
import 'package:mockito/mockito.dart';

import '../../domain/port/constellation_new_people_port.dart';

@Injectable(as: ConstellationNewPeoplePort, env: [Environment.test], order: 1)
class ConstellationNewPeopleRepositoryMock extends Mock
    implements ConstellationNewPeoplePort {}
