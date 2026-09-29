import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/user_contact_entity.dart';
import 'package:tentura_server/domain/port/user_contact_repository_port.dart';

@Injectable(
  as: UserContactRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class UserContactRepositoryMock implements UserContactRepositoryPort {
  @override
  Future<void> upsert({
    required String viewerId,
    required String subjectId,
    required String contactName,
  }) => Future.value();

  @override
  Future<bool> delete({required String viewerId, required String subjectId}) =>
      Future.value(false);

  @override
  Future<List<UserContactEntity>> fetchAllByViewer({required String viewerId}) =>
      Future.value(const []);

  @override
  Future<String?> getName({required String viewerId, required String subjectId}) =>
      Future.value();
}
