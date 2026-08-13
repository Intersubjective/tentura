import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/availability.dart';
import 'package:tentura_root/domain/availability.dart' as root;
import 'package:tentura_root/domain/enums.dart';

DateTime _utcDate(int year, int month, int day) => DateTime.utc(year, month, day);

void main() {
  group('Availability', () {
    final todayUtc = _utcDate(2026, 8, 13);

    test('open default blocks no new requests', () {
      final availability = Availability.open();
      expect(availability.effectiveOn(todayUtc), AvailabilityView.open);
      expect(availability.blocksNewRequestsOn(todayUtc), isFalse);
    });

    test('limited does not block new requests', () {
      const availability = Availability(isLimited: true);
      expect(availability.effectiveOn(todayUtc), AvailabilityView.limited);
      expect(availability.blocksNewRequestsOn(todayUtc), isFalse);
    });

    test('future pause blocks new requests', () {
      final availability = Availability(resumeOn: _utcDate(2026, 8, 20));
      expect(availability.effectiveOn(todayUtc), AvailabilityView.paused);
      expect(availability.blocksNewRequestsOn(todayUtc), isTrue);
    });

    test('resume-day equality is available via root helper', () {
      final availability = Availability(resumeOn: todayUtc);
      expect(
        root.availabilityViewOn(
          isLimited: availability.isLimited,
          resumeOn: availability.resumeOn,
          todayUtc: todayUtc,
        ),
        AvailabilityView.open,
      );
      expect(availability.blocksNewRequestsOn(todayUtc), isFalse);
    });

    test('past pause is open', () {
      final availability = Availability(resumeOn: _utcDate(2026, 8, 10));
      expect(availability.effectiveOn(todayUtc), AvailabilityView.open);
      expect(availability.blocksNewRequestsOn(todayUtc), isFalse);
    });

    test('limited+future pause is paused', () {
      final availability = Availability(
        isLimited: true,
        resumeOn: _utcDate(2026, 8, 20),
      );
      expect(availability.effectiveOn(todayUtc), AvailabilityView.paused);
      expect(availability.blocksNewRequestsOn(todayUtc), isTrue);
    });

    test('limited+past pause falls back to limited', () {
      final availability = Availability(
        isLimited: true,
        resumeOn: _utcDate(2026, 8, 10),
      );
      expect(availability.effectiveOn(todayUtc), AvailabilityView.limited);
      expect(availability.blocksNewRequestsOn(todayUtc), isFalse);
    });

    test('delegates comparison to root helper', () {
      final availability = Availability(
        isLimited: true,
        resumeOn: _utcDate(2026, 8, 20),
      );
      expect(
        availability.effectiveOn(todayUtc),
        root.availabilityViewOn(
          isLimited: availability.isLimited,
          resumeOn: availability.resumeOn,
          todayUtc: todayUtc,
        ),
      );
    });

    test('UTC calendar dates are independent of process local timezone', () {
      final resumeOn = root.utcCalendarDate(DateTime.utc(2026, 8, 20, 23, 59));
      final availability = Availability(resumeOn: resumeOn);
      expect(root.isUtcCalendarDate(resumeOn), isTrue);
      expect(availability.effectiveOn(todayUtc), AvailabilityView.paused);
    });
  });
}
