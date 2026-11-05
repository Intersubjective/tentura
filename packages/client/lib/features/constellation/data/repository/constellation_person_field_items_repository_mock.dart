import 'package:injectable/injectable.dart';
import 'package:mockito/mockito.dart';

import '../../domain/port/constellation_person_field_items_port.dart';

@Injectable(
  as: ConstellationPersonFieldItemsPort,
  env: [Environment.test],
  order: 1,
)
class ConstellationPersonFieldItemsRepositoryMock extends Mock
    implements ConstellationPersonFieldItemsPort {}
