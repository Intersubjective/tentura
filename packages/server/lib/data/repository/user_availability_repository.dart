import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_root/domain/availability.dart';

import 'package:tentura_server/domain/entity/user_availability_entity.dart';
import 'package:tentura_server/domain/port/user_availability_repository_port.dart';

import '../database/tentura_db.dart';
import '../mapper/user_availability_mapper.dart';

@Injectable(
  as: UserAvailabilityRepositoryPort,
  env: [
    Environment.dev,
    Environment.prod,
  ],
  order: 1,
)
class UserAvailabilityRepository implements UserAvailabilityRepositoryPort {
  const UserAvailabilityRepository(this._database);

  final TenturaDb _database;

  @override
  Future<Map<String, UserAvailabilityEntity>> fetchByUserIds(
    Set<String> userIds,
  ) async {
    if (userIds.isEmpty) {
      return const {};
    }
    final idList = userIds.where((id) => id.isNotEmpty).toList(growable: false);
    if (idList.isEmpty) {
      return const {};
    }

    final rows = await _database.managers.userAvailability
        .filter((t) => t.userId.id.isIn(idList))
        .get();
    return {
      for (final row in rows) row.userId: userAvailabilityModelToEntity(row),
    };
  }

  @override
  Future<void> setLimited({
    required String userId,
    required bool isLimited,
  }) =>
      _database.withMutatingUser(userId, () async {
        await _acquireLock(userId);
        if (isLimited) {
          await _database.customStatement(
            r'''
INSERT INTO public.user_availability (user_id, is_limited, updated_at)
VALUES ($1, true, now())
ON CONFLICT (user_id) DO UPDATE SET
  is_limited = EXCLUDED.is_limited,
  updated_at = now()
''',
            [userId],
          );
          return;
        }

        await _database.customStatement(
          r'''
WITH limited_clear AS (
  UPDATE public.user_availability
     SET is_limited = false,
         updated_at = now()
   WHERE user_id = $1
     AND resume_on IS NOT NULL
  RETURNING user_id
)
DELETE FROM public.user_availability
 WHERE user_id = $1
   AND resume_on IS NULL
''',
          [userId],
        );
      });

  @override
  Future<void> pause({
    required String userId,
    required DateTime resumeOn,
  }) =>
      _database.withMutatingUser(userId, () async {
        await _acquireLock(userId);
        final resumeDateIso = _isoUtcCalendarDate(resumeOn);
        await _database.customStatement(
          r'''
INSERT INTO public.user_availability (user_id, resume_on, updated_at)
VALUES ($1, $2::date, now())
ON CONFLICT (user_id) DO UPDATE SET
  resume_on = EXCLUDED.resume_on,
  updated_at = now()
''',
          [userId, resumeDateIso],
        );
      });

  @override
  Future<void> resume({required String userId}) =>
      _database.withMutatingUser(userId, () async {
        await _acquireLock(userId);
        await _database.customStatement(
          r'''
WITH pause_clear AS (
  UPDATE public.user_availability
     SET resume_on = NULL,
         updated_at = now()
   WHERE user_id = $1
     AND is_limited
  RETURNING user_id
)
DELETE FROM public.user_availability
 WHERE user_id = $1
   AND NOT is_limited
   AND resume_on IS NOT NULL
''',
          [userId],
        );
      });

  @override
  Future<void> cleanupExpired(DateTime todayUtc) {
    assert(() {
      if (!isUtcCalendarDate(todayUtc)) {
        throw ArgumentError.value(
          todayUtc,
          'todayUtc',
          'must be a UTC calendar date',
        );
      }
      return true;
    }());

    final today = PgDate.fromDateTime(todayUtc);
    return _database.withMutatingSystem(() async {
      await _database.customStatement(
        r'''
DELETE FROM public.user_availability
 WHERE resume_on <= $1::date
   AND NOT is_limited
''',
        [today],
      );
      await _database.customStatement(
        r'''
UPDATE public.user_availability
   SET resume_on = NULL,
       updated_at = now()
 WHERE resume_on <= $1::date
   AND is_limited
''',
        [today],
      );
    });
  }

  Future<void> _acquireLock(String userId) => _database.customStatement(
    r"SELECT pg_advisory_xact_lock(hashtextextended('user_availability:' || $1, 4242))",
    [userId],
  );
}

String _isoUtcCalendarDate(DateTime value) {
  assert(() {
    if (!isUtcCalendarDate(value)) {
      throw ArgumentError.value(
        value,
        'value',
        'must be a UTC calendar date',
      );
    }
    return true;
  }());
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
