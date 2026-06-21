import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/duration_format.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  final l10n = lookupL10n(const Locale('en'));

  test('less than minute', () {
    expect(
      formatCompactDurationRemaining(Duration.zero, l10n),
      '<1m',
    );
  });

  test('minutes only', () {
    expect(
      formatCompactDurationRemaining(const Duration(minutes: 45), l10n),
      '45m',
    );
  });

  test('hours and minutes', () {
    expect(
      formatCompactDurationRemaining(const Duration(hours: 2, minutes: 15), l10n),
      '2h 15m',
    );
  });

  test('days and hours', () {
    expect(
      formatCompactDurationRemaining(const Duration(days: 3, hours: 5), l10n),
      '3d 5h',
    );
  });

  test('lifecycle ended same day shows time only', () {
    final endedAt = DateTime(2026, 6, 20, 9, 15);
    final now = DateTime(2026, 6, 20, 12);
    expect(
      formatBeaconLifecycleEndedAt(
        endedAt: endedAt,
        now: now,
        localeName: l10n.localeName,
      ),
      '09:15',
    );
  });

  test('lifecycle ended other day shows date and time', () {
    final endedAt = DateTime(2026, 6, 15, 14, 30);
    final now = DateTime(2026, 6, 20, 12);
    expect(
      formatBeaconLifecycleEndedAt(
        endedAt: endedAt,
        now: now,
        localeName: l10n.localeName,
      ),
      'Jun 15, 2026, 14:30',
    );
  });
}
