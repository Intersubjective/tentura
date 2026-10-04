import 'package:injectable/injectable.dart';
import 'package:mockito/mockito.dart';

import '../../domain/port/constellation_member_webs_port.dart';

@Injectable(
  as: ConstellationMemberWebsPort,
  env: [Environment.test],
  order: 1,
)
class ConstellationMemberWebsRepositoryMock extends Mock
    implements ConstellationMemberWebsPort {}
