import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/user_availability_entity.dart';
import 'package:tentura_server/domain/port/user_availability_repository_port.dart';

@Injectable(
  as: UserAvailabilityRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class UserAvailabilityRepositoryMock implements UserAvailabilityRepositoryPort {
  @override
  Future<Map<String, UserAvailabilityEntity>> fetchByUserIds(
    Set<String> userIds,
  ) => Future.value(const {});

  @override
  Future<void> setLimited({required String userId, required bool isLimited}) =>
      Future.value();

  @override
  Future<void> pause({required String userId, required DateTime resumeOn}) =>
      Future.value();

  @override
  Future<void> resume({required String userId}) => Future.value();

  @override
  Future<void> cleanupExpired(DateTime todayUtc) => Future.value();
}
