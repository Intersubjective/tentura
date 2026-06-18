import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_schedule.dart';

void main() {
  final now = DateTime(2026, 6, 15, 12);

  Beacon beacon({
    DateTime? startAt,
    DateTime? endAt,
  }) =>
      Beacon.empty.copyWith(
        startAt: startAt,
        endAt: endAt,
      );

  group('hasScheduleDates', () {
    test('false when neither date set', () {
      expect(beacon().hasScheduleDates, isFalse);
    });

    test('true when start or end set', () {
      expect(
        beacon(startAt: now).hasScheduleDates,
        isTrue,
      );
      expect(
        beacon(endAt: now.add(const Duration(days: 1))).hasScheduleDates,
        isTrue,
      );
    });
  });

  group('schedulePhase', () {
    test('none when no dates', () {
      expect(beacon().schedulePhase(now: now), BeaconSchedulePhase.none);
    });

    test('notStarted before startAt', () {
      final b = beacon(startAt: now.add(const Duration(days: 2)));
      expect(b.schedulePhase(now: now), BeaconSchedulePhase.notStarted);
    });

    test('finished at or after endAt', () {
      final b = beacon(
        startAt: now.subtract(const Duration(days: 2)),
        endAt: now.subtract(const Duration(hours: 1)),
      );
      expect(b.schedulePhase(now: now), BeaconSchedulePhase.finished);
    });

    test('inProgress between start and end', () {
      final b = beacon(
        startAt: now.subtract(const Duration(days: 1)),
        endAt: now.add(const Duration(days: 1)),
      );
      expect(b.schedulePhase(now: now), BeaconSchedulePhase.inProgress);
    });

    test('inProgress with endAt only and before end', () {
      final b = beacon(endAt: now.add(const Duration(days: 3)));
      expect(b.schedulePhase(now: now), BeaconSchedulePhase.inProgress);
    });

    test('inProgress with startAt only after start', () {
      final b = beacon(startAt: now.subtract(const Duration(hours: 2)));
      expect(b.schedulePhase(now: now), BeaconSchedulePhase.inProgress);
    });
  });

  group('scheduleReferenceAt', () {
    test('startAt when not started', () {
      final start = now.add(const Duration(days: 1));
      final b = beacon(startAt: start, endAt: start.add(const Duration(days: 5)));
      expect(b.scheduleReferenceAt(now: now), start);
    });

    test('endAt when in progress', () {
      final end = now.add(const Duration(days: 1));
      final b = beacon(
        startAt: now.subtract(const Duration(days: 1)),
        endAt: end,
      );
      expect(b.scheduleReferenceAt(now: now), end);
    });

    test('endAt when finished', () {
      final end = now.subtract(const Duration(hours: 2));
      final b = beacon(endAt: end);
      expect(b.scheduleReferenceAt(now: now), end);
    });

    test('null when none', () {
      expect(beacon().scheduleReferenceAt(now: now), isNull);
    });

    test('null reference when in progress without endAt', () {
      final b = beacon(startAt: now.subtract(const Duration(hours: 1)));
      expect(b.schedulePhase(now: now), BeaconSchedulePhase.inProgress);
      expect(b.scheduleReferenceAt(now: now), isNull);
    });
  });
}
