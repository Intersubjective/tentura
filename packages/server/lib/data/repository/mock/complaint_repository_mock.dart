import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/complaint_entity.dart';

import 'package:tentura_server/domain/port/complaint_repository_port.dart';

@Injectable(
  as: ComplaintRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class ComplaintRepositoryMock implements ComplaintRepositoryPort {
  @override
  Future<void> create(ComplaintEntity complaint) => Future.value();
}
