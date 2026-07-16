import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/digest_cadence.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_preferences_entity.dart';
import 'package:tentura_server/domain/port/notification_preference_repository_port.dart';
import 'package:tentura_server/domain/use_case/notification_preference_case.dart';

void main() {
  const accountId = 'a1';

  NotificationPreferencesEntity baseline() =>
      NotificationPreferencesEntity.defaults(accountId);

  group('NotificationPreferenceCase.update', () {
    test('parses valid push and email category names', () async {
      final repo = _FakePrefs(baseline());
      final case_ = NotificationPreferenceCase(repo);

      final next = await case_.update(
        accountId: accountId,
        pushCategories: const ['asksOfMe', 'coordination'],
        emailCategories: const ['unblocksMe'],
      );

      expect(
        next.pushCategories,
        {NotificationCategory.asksOfMe, NotificationCategory.coordination},
      );
      expect(next.emailCategories, {NotificationCategory.unblocksMe});
      expect(repo.lastUpsert, next);
    });

    test('silently drops invalid category strings', () async {
      final repo = _FakePrefs(baseline());
      final case_ = NotificationPreferenceCase(repo);

      final next = await case_.update(
        accountId: accountId,
        pushCategories: const ['asksOfMe', 'not_a_category', ''],
        emailCategories: const ['bogus'],
      );

      expect(next.pushCategories, {NotificationCategory.asksOfMe});
      expect(next.emailCategories, isEmpty);
    });

    test('null category lists leave current categories untouched', () async {
      final current = baseline().copyWith(
        pushCategories: const {NotificationCategory.ambient},
        emailCategories: const {NotificationCategory.coordination},
      );
      final repo = _FakePrefs(current);
      final case_ = NotificationPreferenceCase(repo);

      final next = await case_.update(accountId: accountId);

      expect(next.pushCategories, current.pushCategories);
      expect(next.emailCategories, current.emailCategories);
    });

    test('empty category list clears that channel', () async {
      final repo = _FakePrefs(baseline());
      final case_ = NotificationPreferenceCase(repo);

      final next = await case_.update(
        accountId: accountId,
        pushCategories: const [],
        emailCategories: const [],
      );

      expect(next.pushCategories, isEmpty);
      expect(next.emailCategories, isEmpty);
    });

    group('quiet hours', () {
      test('accepts valid minute-of-day values', () async {
        final repo = _FakePrefs(baseline());
        final case_ = NotificationPreferenceCase(repo);

        final next = await case_.update(
          accountId: accountId,
          quietHoursStartMinute: 22 * 60,
          quietHoursEndMinute: 7 * 60,
        );

        expect(next.quietHoursStartMinute, 22 * 60);
        expect(next.quietHoursEndMinute, 7 * 60);
      });

      test('rejects minute below zero', () async {
        final repo = _FakePrefs(baseline());
        final case_ = NotificationPreferenceCase(repo);

        expect(
          () => case_.update(
            accountId: accountId,
            quietHoursStartMinute: -1,
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('quiet-hours minute must be in [0, 1440)'),
            ),
          ),
        );
        expect(repo.lastUpsert, isNull);
      });

      test('rejects minute at or above 1440', () async {
        final repo = _FakePrefs(baseline());
        final case_ = NotificationPreferenceCase(repo);

        expect(
          () => case_.update(
            accountId: accountId,
            quietHoursEndMinute: 1440,
          ),
          throwsA(isA<ArgumentError>()),
        );
        expect(repo.lastUpsert, isNull);
      });

      test('clearQuietHours nulls both endpoints', () async {
        final current = baseline().copyWith(
          quietHoursStartMinute: 22 * 60,
          quietHoursEndMinute: 7 * 60,
        );
        final repo = _FakePrefs(current);
        final case_ = NotificationPreferenceCase(repo);

        final next = await case_.update(
          accountId: accountId,
          clearQuietHours: true,
        );

        expect(next.quietHoursStartMinute, isNull);
        expect(next.quietHoursEndMinute, isNull);
      });
    });

    group('snooze', () {
      final snoozeUntil = DateTime.utc(2026, 6, 25, 18);

      test('sets snoozeUntil', () async {
        final repo = _FakePrefs(baseline());
        final case_ = NotificationPreferenceCase(repo);

        final next = await case_.update(
          accountId: accountId,
          snoozeUntil: snoozeUntil,
        );

        expect(next.snoozeUntil, snoozeUntil);
      });

      test('clearSnooze nulls snoozeUntil', () async {
        final current = baseline().copyWith(snoozeUntil: snoozeUntil);
        final repo = _FakePrefs(current);
        final case_ = NotificationPreferenceCase(repo);

        final next = await case_.update(
          accountId: accountId,
          clearSnooze: true,
        );

        expect(next.snoozeUntil, isNull);
      });

      test('null snoozeUntil leaves current value', () async {
        final current = baseline().copyWith(snoozeUntil: snoozeUntil);
        final repo = _FakePrefs(current);
        final case_ = NotificationPreferenceCase(repo);

        final next = await case_.update(accountId: accountId);

        expect(next.snoozeUntil, snoozeUntil);
      });
    });

    test('parses email digest cadence; unknown falls back to off', () async {
      final repo = _FakePrefs(
        baseline().copyWith(emailDigest: DigestCadence.daily),
      );
      final case_ = NotificationPreferenceCase(repo);

      final weekly = await case_.update(
        accountId: accountId,
        emailDigest: 'weekly',
      );
      expect(weekly.emailDigest, DigestCadence.weekly);

      final off = await case_.update(
        accountId: accountId,
        emailDigest: 'not_a_cadence',
      );
      expect(off.emailDigest, DigestCadence.off);
    });

    test('updates tz offset, lock screen safe, and locale', () async {
      final repo = _FakePrefs(baseline());
      final case_ = NotificationPreferenceCase(repo);

      final next = await case_.update(
        accountId: accountId,
        tzOffsetMinutes: 180,
        lockScreenSafe: true,
        locale: 'ru',
      );

      expect(next.tzOffsetMinutes, 180);
      expect(next.lockScreenSafe, isTrue);
      expect(next.locale, 'ru');
    });

    test('updates only contract-owned muteable in-app classes', () async {
      final repo = _FakePrefs(baseline());
      final case_ = NotificationPreferenceCase(repo);

      final next = await case_.update(
        accountId: accountId,
        mutedInAppEventClasses: const [
          'coordination_churn',
          'request_progress',
        ],
      );

      expect(next.mutedInAppEventClasses, {
        'coordination_churn',
        'request_progress',
      });
    });

    test('rejects unknown or non-muteable in-app classes', () async {
      final repo = _FakePrefs(baseline());
      final case_ = NotificationPreferenceCase(repo);

      await expectLater(
        case_.update(
          accountId: accountId,
          mutedInAppEventClasses: const ['blocker_opened'],
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(repo.lastUpsert, isNull);
    });
  });
}

class _FakePrefs implements NotificationPreferenceRepositoryPort {
  _FakePrefs(this._prefs);

  NotificationPreferencesEntity _prefs;
  NotificationPreferencesEntity? lastUpsert;

  @override
  Future<NotificationPreferencesEntity> getForAccount(String accountId) async =>
      _prefs;

  @override
  Future<void> upsert(NotificationPreferencesEntity prefs) async {
    lastUpsert = prefs;
    _prefs = prefs;
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}
