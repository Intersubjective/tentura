import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/enums.dart';
import 'package:tentura_server/domain/entity/user_availability_entity.dart';
import 'package:tentura_server/domain/port/user_availability_repository_port.dart';
import 'package:tentura_server/domain/use_case/user_availability_case.dart';
import 'package:tentura_server/env.dart';

void main() {
  late InMemoryUserAvailabilityRepository repo;
  late UserAvailabilityCase case_;

  const userId = 'Uavail';

  setUp(() {
    repo = InMemoryUserAvailabilityRepository();
    case_ = UserAvailabilityCase(
      repo,
      env: Env(environment: Environment.test),
      logger: Logger('UserAvailabilityCaseTest'),
    );
  });

  group('UserAvailabilityCase.todayUtcFrom', () {
    test('uses UTC year/month/day regardless of process offset', () {
      final now = DateTime.parse('2026-08-13T23:45:00-04:00');
      expect(
        case_.todayUtcFrom(now),
        DateTime.utc(2026, 8, 14),
      );
    });
  });

  group('UserAvailabilityCase.pause validation', () {
    final todayUtc = DateTime.utc(2026, 8, 13);
    final fixedNow = DateTime.utc(2026, 8, 13, 15, 30);

    test('rejects non-UTC-midnight resumeOn', () async {
      await expectLater(
        case_.pause(
          userId: userId,
          resumeOn: DateTime.utc(2026, 8, 14, 12),
          now: fixedNow,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.name,
            'name',
            'resumeOn',
          ),
        ),
      );
      expect(repo.pauseCalls, isEmpty);
    });

    test('rejects resumeOn on todayUtc', () async {
      await expectLater(
        case_.pause(
          userId: userId,
          resumeOn: todayUtc,
          now: fixedNow,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(repo.pauseCalls, isEmpty);
    });

    test('rejects resumeOn before todayUtc', () async {
      await expectLater(
        case_.pause(
          userId: userId,
          resumeOn: DateTime.utc(2026, 8, 12),
          now: fixedNow,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('accepts tomorrow', () async {
      await case_.pause(
        userId: userId,
        resumeOn: DateTime.utc(2026, 8, 14),
        now: fixedNow,
      );
      expect(repo.pauseCalls.single.resumeOn, DateTime.utc(2026, 8, 14));
    });

    test('accepts exactly 90 calendar days later', () async {
      final resumeOn = DateTime.utc(2026, 8, 13 + 90);
      await case_.pause(
        userId: userId,
        resumeOn: resumeOn,
        now: fixedNow,
      );
      expect(repo.pauseCalls.single.resumeOn, resumeOn);
    });

    test('rejects 91 calendar days later', () async {
      await expectLater(
        case_.pause(
          userId: userId,
          resumeOn: DateTime.utc(2026, 8, 13 + 91),
          now: fixedNow,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('90-day boundary respects month rollover', () async {
      final now = DateTime.utc(2026, 1, 31, 10);
      final maxAllowed = DateTime.utc(2026, 1, 31 + 90);
      await case_.pause(
        userId: userId,
        resumeOn: maxAllowed,
        now: now,
      );
      expect(repo.pauseCalls.single.resumeOn, maxAllowed);

      await expectLater(
        case_.pause(
          userId: userId,
          resumeOn: DateTime.utc(2026, 1, 31 + 91),
          now: now,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('UserAvailabilityCase commands', () {
    test('setLimited delegates to repository', () async {
      await case_.setLimited(userId: userId, isLimited: true);
      expect(repo.setLimitedCalls, [(userId: userId, isLimited: true)]);
    });

    test('resume delegates to repository', () async {
      await case_.resume(userId: userId);
      expect(repo.resumeCalls, [userId]);
    });

    test('cleanupExpired passes UTC calendar todayUtc derived from now', () async {
      final now = DateTime.utc(2026, 11, 30, 23, 59, 59);
      await case_.cleanupExpired(now: now);
      expect(repo.cleanupCalls, [DateTime.utc(2026, 11, 30)]);
    });

    test('fetchByUserIds delegates to repository', () async {
      repo.fetchResult = {
        userId: const UserAvailabilityEntity(userId: userId, isLimited: true),
      };
      final result = await case_.fetchByUserIds({userId});
      expect(result[userId]?.isLimited, isTrue);
      expect(repo.fetchCalls.single, {userId});
    });
  });

  group('InMemoryUserAvailabilityRepository semantics', () {
    test('clear limited preserves active pause', () async {
      final backing = InMemoryUserAvailabilityRepository();
      final availability = UserAvailabilityCase(
        backing,
        env: Env(environment: Environment.test),
        logger: Logger('test'),
      );
      final resumeOn = DateTime.utc(2026, 9, 1);

      await availability.pause(
        userId: userId,
        resumeOn: resumeOn,
        now: DateTime.utc(2026, 8, 1),
      );
      await availability.setLimited(userId: userId, isLimited: true);
      await availability.setLimited(userId: userId, isLimited: false);

      final row = backing.rowFor(userId)!;
      expect(row.isLimited, isFalse);
      expect(row.resumeOn, resumeOn);
      expect(row.effectiveOn(DateTime.utc(2026, 8, 15)), AvailabilityView.paused);
    });

    test('resume on limited+paused falls back to limited', () async {
      final backing = InMemoryUserAvailabilityRepository();
      final availability = UserAvailabilityCase(
        backing,
        env: Env(environment: Environment.test),
        logger: Logger('test'),
      );

      await availability.setLimited(userId: userId, isLimited: true);
      await availability.pause(
        userId: userId,
        resumeOn: DateTime.utc(2026, 9, 1),
        now: DateTime.utc(2026, 8, 1),
      );
      await availability.resume(userId: userId);

      final row = backing.rowFor(userId)!;
      expect(row.isLimited, isTrue);
      expect(row.resumeOn, isNull);
      expect(row.effectiveOn(DateTime.utc(2026, 8, 15)), AvailabilityView.limited);
    });

    test('resume and clear limited on open state are idempotent', () async {
      final backing = InMemoryUserAvailabilityRepository();
      final availability = UserAvailabilityCase(
        backing,
        env: Env(environment: Environment.test),
        logger: Logger('test'),
      );

      await availability.resume(userId: userId);
      await availability.setLimited(userId: userId, isLimited: false);
      expect(backing.rowFor(userId), isNull);

      await availability.resume(userId: userId);
      await availability.setLimited(userId: userId, isLimited: false);
      expect(backing.rowFor(userId), isNull);
    });

    test('cleanupExpired deletes pause-only rows and clears limited stale dates', () async {
      final backing = InMemoryUserAvailabilityRepository();
      final availability = UserAvailabilityCase(
        backing,
        env: Env(environment: Environment.test),
        logger: Logger('test'),
      );
      const pauseOnly = 'UpauseOnly';
      const limitedStale = 'UlimitedStale';

      backing.seed(
        pauseOnly,
        UserAvailabilityEntity(
          userId: pauseOnly,
          resumeOn: DateTime.utc(2026, 8, 1),
        ),
      );
      backing.seed(
        limitedStale,
        UserAvailabilityEntity(
          userId: limitedStale,
          isLimited: true,
          resumeOn: DateTime.utc(2026, 8, 1),
        ),
      );

      await availability.cleanupExpired(now: DateTime.utc(2026, 8, 10));

      expect(backing.rowFor(pauseOnly), isNull);
      final limited = backing.rowFor(limitedStale)!;
      expect(limited.isLimited, isTrue);
      expect(limited.resumeOn, isNull);
    });
  });
}

final class InMemoryUserAvailabilityRepository
    implements UserAvailabilityRepositoryPort {
  final _rows = <String, UserAvailabilityEntity>{};
  final fetchCalls = <Set<String>>[];
  final setLimitedCalls = <({String userId, bool isLimited})>[];
  final pauseCalls = <({String userId, DateTime resumeOn})>[];
  final resumeCalls = <String>[];
  final cleanupCalls = <DateTime>[];

  Map<String, UserAvailabilityEntity> fetchResult = const {};

  UserAvailabilityEntity? rowFor(String userId) => _rows[userId];

  void seed(String userId, UserAvailabilityEntity entity) {
    _rows[userId] = entity;
  }

  @override
  Future<Map<String, UserAvailabilityEntity>> fetchByUserIds(
    Set<String> userIds,
  ) async {
    fetchCalls.add(Set<String>.from(userIds));
    if (fetchResult.isNotEmpty) {
      return fetchResult;
    }
    return {
      for (final id in userIds)
        if (_rows.containsKey(id)) id: _rows[id]!,
    };
  }

  @override
  Future<void> setLimited({
    required String userId,
    required bool isLimited,
  }) async {
    setLimitedCalls.add((userId: userId, isLimited: isLimited));
    if (isLimited) {
      final existing = _rows[userId];
      _rows[userId] = UserAvailabilityEntity(
        userId: userId,
        isLimited: true,
        resumeOn: existing?.resumeOn,
      );
      return;
    }

    final existing = _rows[userId];
    if (existing == null) {
      return;
    }
    final updated = UserAvailabilityEntity(
      userId: userId,
      isLimited: false,
      resumeOn: existing.resumeOn,
    );
    if (!updated.isLimited && updated.resumeOn == null) {
      _rows.remove(userId);
    } else {
      _rows[userId] = updated;
    }
  }

  @override
  Future<void> pause({
    required String userId,
    required DateTime resumeOn,
  }) async {
    pauseCalls.add((userId: userId, resumeOn: resumeOn));
    final existing = _rows[userId];
    _rows[userId] = UserAvailabilityEntity(
      userId: userId,
      isLimited: existing?.isLimited ?? false,
      resumeOn: resumeOn,
    );
  }

  @override
  Future<void> resume({required String userId}) async {
    resumeCalls.add(userId);
    final existing = _rows[userId];
    if (existing == null) {
      return;
    }
    final updated = UserAvailabilityEntity(
      userId: userId,
      isLimited: existing.isLimited,
      resumeOn: null,
    );
    if (!updated.isLimited && updated.resumeOn == null) {
      _rows.remove(userId);
    } else {
      _rows[userId] = updated;
    }
  }

  @override
  Future<void> cleanupExpired(DateTime todayUtc) async {
    cleanupCalls.add(todayUtc);
    final toRemove = <String>[];
    for (final entry in _rows.entries) {
      final resumeOn = entry.value.resumeOn;
      if (resumeOn == null || resumeOn.isAfter(todayUtc)) {
        continue;
      }
      if (!entry.value.isLimited) {
        toRemove.add(entry.key);
        continue;
      }
      _rows[entry.key] = entry.value.copyWith(resumeOn: null);
    }
    for (final id in toRemove) {
      _rows.remove(id);
    }
  }
}
