import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_schedule.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/beacon_schedule_presenter.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  final l10n = lookupL10n(const Locale('en'));
  final now = DateTime(2026, 6, 15, 12);

  Beacon beacon({
    DateTime? startAt,
    DateTime? endAt,
    BeaconStatus status = BeaconStatus.open,
  }) =>
      Beacon.empty.copyWith(
        startAt: startAt,
        endAt: endAt,
        status: status,
      );

  BeaconSchedulePresentation present(Beacon b) =>
      beaconSchedulePresentation(beacon: b, l10n: l10n, now: now)!;

  test('returns null when no schedule dates', () {
    expect(
      beaconSchedulePresentation(beacon: beacon(), l10n: l10n, now: now),
      isNull,
    );
  });

  group('event', () {
    test('upcoming beyond threshold shows absolute date, not urgent', () {
      final p = present(beacon(startAt: now.add(const Duration(days: 5))));
      expect(p.phase, BeaconSchedulePhase.notStarted);
      expect(p.visibleText, 'Jun 20');
      expect(p.urgent, isFalse);
      expect(p.semanticsLabel, l10n.beaconCardScheduleScheduledFor('Jun 20'));
    });

    test('upcoming window beyond threshold shows absolute range', () {
      final p = present(beacon(
        startAt: now.add(const Duration(days: 5)),
        endAt: now.add(const Duration(days: 8)),
      ));
      expect(p.visibleText, 'Jun 20 – Jun 23');
      expect(p.urgent, isFalse);
    });

    test('starting within threshold (>24h) shows countdown, not urgent', () {
      final p = present(beacon(startAt: now.add(const Duration(days: 2))));
      expect(p.phase, BeaconSchedulePhase.notStarted);
      expect(p.visibleText, l10n.beaconCardScheduleStartsIn('2d 0h'));
      expect(p.urgent, isFalse);
    });

    test('starting under 24h is urgent', () {
      final p = present(beacon(startAt: now.add(const Duration(hours: 5))));
      expect(p.visibleText, l10n.beaconCardScheduleStartsIn('5h 0m'));
      expect(p.urgent, isTrue);
    });

    test('in progress with far end shows "until" absolute date', () {
      final p = present(beacon(
        startAt: now.subtract(const Duration(days: 1)),
        endAt: now.add(const Duration(days: 5)),
      ));
      expect(p.phase, BeaconSchedulePhase.inProgress);
      expect(p.visibleText, l10n.beaconCardScheduleUntil('Jun 20'));
      expect(p.urgent, isFalse);
    });

    test('in progress ending within threshold shows countdown', () {
      final p = present(beacon(
        startAt: now.subtract(const Duration(days: 1)),
        endAt: now.add(const Duration(days: 2, hours: 3)),
      ));
      expect(p.visibleText, l10n.beaconCardScheduleEndsIn('2d 3h'));
      expect(p.urgent, isFalse);
    });

    test('in progress without end shows "happening now"', () {
      final p = present(beacon(startAt: now.subtract(const Duration(hours: 1))));
      expect(p.visibleText, l10n.beaconCardScheduleHappeningNow);
      expect(p.urgent, isFalse);
    });

    test('finished event is quiet absolute date, never overdue', () {
      final p = present(beacon(
        startAt: now.subtract(const Duration(days: 5)),
        endAt: now.subtract(const Duration(hours: 3)),
      ));
      expect(p.phase, BeaconSchedulePhase.finished);
      expect(p.visibleText, 'Jun 10 – Jun 15');
      expect(p.urgent, isFalse);
      expect(p.semanticsLabel, l10n.beaconCardScheduleEndedOn('Jun 10 – Jun 15'));
    });
  });

  group('deadline (endAt only)', () {
    test('beyond threshold shows "by {date}", not urgent', () {
      final p = present(beacon(endAt: now.add(const Duration(days: 5))));
      expect(p.phase, BeaconSchedulePhase.inProgress);
      expect(p.visibleText, l10n.beaconCardScheduleDeadlineBy('Jun 20'));
      expect(p.urgent, isFalse);
    });

    test('within threshold (>24h) shows "due in", not urgent', () {
      final p = present(beacon(endAt: now.add(const Duration(days: 2))));
      expect(p.visibleText, l10n.beaconCardScheduleDueIn('2d 0h'));
      expect(p.urgent, isFalse);
    });

    test('under 24h is urgent', () {
      final p = present(beacon(endAt: now.add(const Duration(hours: 5))));
      expect(p.visibleText, l10n.beaconCardScheduleDueIn('5h 0m'));
      expect(p.urgent, isTrue);
    });

    test('passed deadline is overdue and urgent', () {
      final p = present(beacon(endAt: now.subtract(const Duration(hours: 3))));
      expect(p.phase, BeaconSchedulePhase.finished);
      expect(p.visibleText, l10n.beaconCardScheduleOverdue);
      expect(p.urgent, isTrue);
    });
  });

  group('hand-off to STATUS axis', () {
    test('reviewOpen renders quiet date with no countdown / no urgency', () {
      final b = beacon(
        startAt: now.subtract(const Duration(days: 5)),
        endAt: now.subtract(const Duration(hours: 3)),
        status: BeaconStatus.reviewOpen,
      );
      final p = present(b);
      expect(p.visibleText, 'Jun 10 – Jun 15');
      expect(p.urgent, isFalse);
      expect(p.phase, BeaconSchedulePhase.finished);
      expect(beaconScheduleNeedsLiveTimer(b, now: now), isFalse);
    });

    test('closed lifecycle hands off even with a future deadline', () {
      final b = beacon(
        endAt: now.add(const Duration(days: 5)),
        status: BeaconStatus.closed,
      );
      final p = present(b);
      expect(p.urgent, isFalse);
      expect(beaconScheduleNeedsLiveTimer(b, now: now), isFalse);
    });
  });

  group('beaconScheduleNeedsLiveTimer', () {
    test('true only for live countdowns', () {
      expect(
        beaconScheduleNeedsLiveTimer(
          beacon(startAt: now.add(const Duration(hours: 5))),
          now: now,
        ),
        isTrue,
      );
      // Absolute date (beyond threshold) → no timer.
      expect(
        beaconScheduleNeedsLiveTimer(
          beacon(startAt: now.add(const Duration(days: 5))),
          now: now,
        ),
        isFalse,
      );
      // Overdue / finished → no timer.
      expect(
        beaconScheduleNeedsLiveTimer(
          beacon(endAt: now.subtract(const Duration(hours: 3))),
          now: now,
        ),
        isFalse,
      );
    });
  });
}
