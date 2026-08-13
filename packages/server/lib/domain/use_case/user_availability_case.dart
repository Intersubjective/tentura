import 'package:injectable/injectable.dart';

import 'package:tentura_root/domain/availability.dart';

import 'package:tentura_server/domain/entity/user_availability_entity.dart';
import 'package:tentura_server/domain/port/user_availability_repository_port.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class UserAvailabilityCase extends UseCaseBase {
  UserAvailabilityCase(
    this._repository, {
    required super.env,
    required super.logger,
  });

  static const maxPauseHorizonDays = 90;

  final UserAvailabilityRepositoryPort _repository;

  DateTime todayUtcFrom(DateTime now) =>
      DateTime.utc(now.toUtc().year, now.toUtc().month, now.toUtc().day);

  Future<Map<String, UserAvailabilityEntity>> fetchByUserIds(
    Set<String> userIds,
  ) =>
      _repository.fetchByUserIds(userIds);

  Future<void> setLimited({
    required String userId,
    required bool isLimited,
  }) =>
      _repository.setLimited(userId: userId, isLimited: isLimited);

  Future<void> pause({
    required String userId,
    required DateTime resumeOn,
    DateTime? now,
  }) async {
    final todayUtc = todayUtcFrom(now ?? DateTime.timestamp());
    _validateResumeOn(resumeOn, todayUtc);
    await _repository.pause(userId: userId, resumeOn: resumeOn);
  }

  Future<void> resume({required String userId}) =>
      _repository.resume(userId: userId);

  Future<void> cleanupExpired({DateTime? now}) async {
    final todayUtc = todayUtcFrom(now ?? DateTime.timestamp());
    await _repository.cleanupExpired(todayUtc);
  }

  void _validateResumeOn(DateTime resumeOn, DateTime todayUtc) {
    if (!isUtcCalendarDate(resumeOn)) {
      throw ArgumentError.value(
        resumeOn,
        'resumeOn',
        'must be a UTC calendar date',
      );
    }
    if (!resumeOn.isAfter(todayUtc)) {
      throw ArgumentError.value(
        resumeOn,
        'resumeOn',
        'must be after todayUtc',
      );
    }
    final maxResumeOn = DateTime.utc(
      todayUtc.year,
      todayUtc.month,
      todayUtc.day + maxPauseHorizonDays,
    );
    if (resumeOn.isAfter(maxResumeOn)) {
      throw ArgumentError.value(
        resumeOn,
        'resumeOn',
        'must be at most $maxPauseHorizonDays calendar days after todayUtc',
      );
    }
  }
}
