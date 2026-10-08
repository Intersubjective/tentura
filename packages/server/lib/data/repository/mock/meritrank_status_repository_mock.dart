import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/meritrank_status.dart';
import 'package:tentura_server/domain/port/meritrank_status_port.dart';

@Injectable(
  as: MeritrankStatusPort,
  env: [Environment.test],
  order: 1,
)
class MeritrankStatusRepositoryMock implements MeritrankStatusPort {
  @override
  Future<MeritrankStatus> status() {
    throw UnimplementedError();
  }
}
