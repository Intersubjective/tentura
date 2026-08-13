import 'package:tentura_server/domain/entity/user_availability_entity.dart';

abstract class UserAvailabilityRepositoryPort {
  Future<Map<String, UserAvailabilityEntity>> fetchByUserIds(
    Set<String> userIds,
  );

  Future<void> setLimited({
    required String userId,
    required bool isLimited,
  });

  Future<void> pause({
    required String userId,
    required DateTime resumeOn,
  });

  Future<void> resume({required String userId});

  Future<void> cleanupExpired(DateTime todayUtc);
}
