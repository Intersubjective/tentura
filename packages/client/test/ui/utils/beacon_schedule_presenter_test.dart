import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_schedule.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/beacon_schedule_presenter.dart';
import 'package:tentura/ui/utils/duration_format.dart';

void main() {
  final l10n = lookupL10n(const Locale('en'));
  final now = DateTime(2026, 6, 15, 12);

  Beacon beacon({
    DateTime? startAt,
    DateTime? endAt,
  }) =>
      Beacon.empty.copyWith(startAt: startAt, endAt: endAt);

  test('returns null when no schedule dates', () {
    expect(
      beaconSchedulePresentation(beacon: beacon(), l10n: l10n, now: now),
      isNull,
    );
  });

  test('notStarted shows countdown and urgent under 24h', () {
    final b = beacon(startAt: now.add(const Duration(hours: 5)));
    final p = beaconSchedulePresentation(beacon: b, l10n: l10n, now: now)!;
    expect(p.phase, BeaconSchedulePhase.notStarted);
    expect(p.visibleText, '5h 0m');
    expect(p.urgent, isTrue);
    expect(p.semanticsLabel, l10n.beaconCardScheduleStartsIn('5h 0m'));
  });

  test('inProgress shows countdown to endAt', () {
    final b = beacon(
      startAt: now.subtract(const Duration(days: 1)),
      endAt: now.add(const Duration(days: 2, hours: 3)),
    );
    final p = beaconSchedulePresentation(beacon: b, l10n: l10n, now: now)!;
    expect(p.phase, BeaconSchedulePhase.inProgress);
    expect(p.visibleText, '2d 3h');
    expect(p.urgent, isFalse);
    expect(p.semanticsLabel, l10n.beaconCardScheduleEndsIn('2d 3h'));
  });

  test('inProgress without endAt is icon-only semantics', () {
    final b = beacon(startAt: now.subtract(const Duration(hours: 1)));
    final p = beaconSchedulePresentation(beacon: b, l10n: l10n, now: now)!;
    expect(p.visibleText, isEmpty);
    expect(p.semanticsLabel, l10n.beaconCardScheduleInProgress);
  });

  test('finished shows ago text', () {
    final b = beacon(endAt: now.subtract(const Duration(hours: 3)));
    final p = beaconSchedulePresentation(beacon: b, l10n: l10n, now: now)!;
    expect(p.phase, BeaconSchedulePhase.finished);
    expect(p.visibleText, '3h ago');
    expect(p.semanticsLabel, l10n.beaconCardScheduleEndedAgo('3h ago'));
  });

  test('formatCompactDurationRemaining matches days hours', () {
    expect(
      formatCompactDurationRemaining(const Duration(days: 1, hours: 2), l10n),
      '1d 2h',
    );
  });
}
