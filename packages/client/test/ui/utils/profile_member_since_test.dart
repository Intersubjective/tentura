import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/util/profile_member_since.dart';

void main() {
  final fixedNow = DateTime.utc(2026, 11, 4, 12);

  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ru');
  });

  group('profileTenureSegment boundaries', () {
    test('0 calendar days on join day', () {
      final joined = DateTime.utc(2026, 11, 4, 8);
      expect(
        profileTenureSegment(joinedAt: joined, now: fixedNow),
        (count: 0, unit: ProfileTenureUnit.days),
      );
    });

    test('1 day', () {
      final joined = DateTime.utc(2026, 11, 3, 8);
      expect(
        profileTenureSegment(joinedAt: joined, now: fixedNow),
        (count: 1, unit: ProfileTenureUnit.days),
      );
    });

    test('29 days stays in days unit', () {
      final joined = DateTime.utc(2026, 10, 6, 8);
      expect(
        profileTenureSegment(joinedAt: joined, now: fixedNow),
        (count: 29, unit: ProfileTenureUnit.days),
      );
    });

    test('30 days before a full calendar month', () {
      final joined = DateTime.utc(2026, 10, 5, 8);
      expect(
        profileTenureSegment(joinedAt: joined, now: fixedNow),
        (count: 30, unit: ProfileTenureUnit.days),
      );
    });

    test('11 months', () {
      final joined = DateTime.utc(2025, 12, 4, 8);
      expect(
        profileTenureSegment(joinedAt: joined, now: fixedNow),
        (count: 11, unit: ProfileTenureUnit.months),
      );
    });

    test('12 months becomes 1 year', () {
      final joined = DateTime.utc(2025, 11, 4, 8);
      expect(
        profileTenureSegment(joinedAt: joined, now: fixedNow),
        (count: 1, unit: ProfileTenureUnit.years),
      );
    });

    test('2+ years', () {
      final joined = DateTime.utc(2024, 11, 4, 8);
      expect(
        profileTenureSegment(joinedAt: joined, now: fixedNow),
        (count: 2, unit: ProfileTenureUnit.years),
      );
    });
  });

  group('profileMemberSinceDisplayLine EN', () {
    final l10n = lookupL10n(const Locale('en'));

    test('join day omits redundant zero-day tenure (#1077)', () {
      final joined = DateTime.utc(2026, 11, 4, 8);
      final line = profileMemberSinceDisplayLine(
        l10n: l10n,
        joinedAt: joined,
        now: fixedNow,
      );
      expect(line, 'On Tentura since Nov 4');
      expect(line.contains('0 days'), isFalse);
    });

    test('full line with months tenure', () {
      final joined = DateTime.utc(2026, 3, 12, 8);
      final line = profileMemberSinceDisplayLine(
        l10n: l10n,
        joinedAt: joined,
        now: fixedNow,
      );
      expect(line, 'On Tentura since Mar 12 · 7 months');
    });

    test('day plurals', () {
      expect(
        profileTenureDurationLabel(
          l10n: l10n,
          joinedAt: DateTime.utc(2026, 11, 3),
          now: fixedNow,
        ),
        '1 day',
      );
      expect(
        profileTenureDurationLabel(
          l10n: l10n,
          joinedAt: DateTime.utc(2026, 11, 2),
          now: fixedNow,
        ),
        '2 days',
      );
    });

    test('month and year plurals', () {
      expect(
        profileTenureDurationLabel(
          l10n: l10n,
          joinedAt: DateTime.utc(2025, 12, 4),
          now: fixedNow,
        ),
        '11 months',
      );
      expect(
        profileTenureDurationLabel(
          l10n: l10n,
          joinedAt: DateTime.utc(2024, 11, 4),
          now: fixedNow,
        ),
        '2 years',
      );
    });
  });

  group('profileMemberSinceDisplayLine RU plurals', () {
    final l10n = lookupL10n(const Locale('ru'));

    test('join day omits redundant zero-day tenure', () {
      final joined = DateTime.utc(2026, 11, 4, 8);
      final line = profileMemberSinceDisplayLine(
        l10n: l10n,
        joinedAt: joined,
        now: fixedNow,
      );
      expect(line.contains('0 дней'), isFalse);
      expect(line.startsWith('В Tentura с'), isTrue);
    });

    test('день/дня/дней', () {
      expect(
        profileTenureDurationLabel(
          l10n: l10n,
          joinedAt: DateTime.utc(2026, 11, 3),
          now: fixedNow,
        ),
        '1 день',
      );
      expect(
        profileTenureDurationLabel(
          l10n: l10n,
          joinedAt: DateTime.utc(2026, 11, 2),
          now: fixedNow,
        ),
        '2 дня',
      );
      expect(
        profileTenureDurationLabel(
          l10n: l10n,
          joinedAt: DateTime.utc(2026, 10, 30),
          now: fixedNow,
        ),
        '5 дней',
      );
    });

    test('месяц/месяца/месяцев and год/года/лет', () {
      expect(
        profileTenureDurationLabel(
          l10n: l10n,
          joinedAt: DateTime.utc(2025, 12, 4),
          now: fixedNow,
        ),
        '11 месяцев',
      );
      expect(
        profileTenureDurationLabel(
          l10n: l10n,
          joinedAt: DateTime.utc(2025, 11, 4),
          now: fixedNow,
        ),
        '1 год',
      );
      expect(
        profileTenureDurationLabel(
          l10n: l10n,
          joinedAt: DateTime.utc(2023, 11, 4),
          now: fixedNow,
        ),
        '3 года',
      );
    });
  });
}
