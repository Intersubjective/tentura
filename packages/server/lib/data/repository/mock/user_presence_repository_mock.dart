import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/enums.dart';
import 'package:tentura_server/domain/entity/user_presence_entity.dart';

import 'package:tentura_server/domain/port/user_presence_repository_port.dart';

@Injectable(
  as: UserPresenceRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class UserPresenceRepositoryMock implements UserPresenceRepositoryPort {
  @override
  Future<UserPresenceEntity?> get(String userId) {
    throw UnimplementedError();
  }

  @override
  Future<void> update(
    String userId, {
    DateTime? lastSeenAt,
    DateTime? lastNotifiedAt,
    UserPresenceStatus? status,
  }) {
    throw UnimplementedError();
  }
}
