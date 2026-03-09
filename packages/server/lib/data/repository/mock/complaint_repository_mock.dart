import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/complaint_entity.dart';

import '../complaint_repository.dart';

@Injectable(
  as: ComplaintRepository,
  env: [Environment.test],
  order: 1,
)
class ComplaintRepositoryMock implements ComplaintRepository {
  @override
  Future<void> create(ComplaintEntity complaint) => Future.value();
}
