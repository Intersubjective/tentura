import 'package:tentura_root/domain/enums.dart';

import 'package:tentura_server/domain/entity/user_presence_entity.dart';

abstract class UserPresenceRepositoryPort {
  Future<UserPresenceEntity?> get(String userId);

  Future<void> update(
    String userId, {
    DateTime? lastSeenAt,
    DateTime? lastNotifiedAt,
    UserPresenceStatus? status,
  });
}
