import 'package:test/test.dart';
import 'package:tentura_root/domain/availability.dart' as root;
import 'package:tentura_root/domain/enums.dart';
import 'package:tentura_server/domain/entity/user_availability_entity.dart';

DateTime _utcDate(int year, int month, int day) => DateTime.utc(year, month, day);

void main() {
  group('UserAvailabilityEntity', () {
    final todayUtc = _utcDate(2026, 8, 13);

    test('open entity blocks no new requests', () {
      const entity = UserAvailabilityEntity(userId: 'u1');
      expect(entity.effectiveOn(todayUtc), AvailabilityView.open);
      expect(entity.blocksNewRequestsOn(todayUtc), isFalse);
    });

    test('limited does not block new requests', () {
      const entity = UserAvailabilityEntity(userId: 'u1', isLimited: true);
      expect(entity.effectiveOn(todayUtc), AvailabilityView.limited);
      expect(entity.blocksNewRequestsOn(todayUtc), isFalse);
    });

    test('future pause blocks new requests', () {
      final entity = UserAvailabilityEntity(
        userId: 'u1',
        resumeOn: _utcDate(2026, 8, 20),
      );
      expect(entity.effectiveOn(todayUtc), AvailabilityView.paused);
      expect(entity.blocksNewRequestsOn(todayUtc), isTrue);
    });

    test('resume-day equality is available via root helper', () {
      final entity = UserAvailabilityEntity(
        userId: 'u1',
        resumeOn: todayUtc,
      );
      expect(
        root.availabilityViewOn(
          isLimited: entity.isLimited,
          resumeOn: entity.resumeOn,
          todayUtc: todayUtc,
        ),
        AvailabilityView.open,
      );
      expect(entity.blocksNewRequestsOn(todayUtc), isFalse);
    });

    test('past pause is open', () {
      final entity = UserAvailabilityEntity(
        userId: 'u1',
        resumeOn: _utcDate(2026, 8, 10),
      );
      expect(entity.effectiveOn(todayUtc), AvailabilityView.open);
      expect(entity.blocksNewRequestsOn(todayUtc), isFalse);
    });

    test('limited+future pause is paused', () {
      final entity = UserAvailabilityEntity(
        userId: 'u1',
        isLimited: true,
        resumeOn: _utcDate(2026, 8, 20),
      );
      expect(entity.effectiveOn(todayUtc), AvailabilityView.paused);
      expect(entity.blocksNewRequestsOn(todayUtc), isTrue);
    });

    test('limited+past pause falls back to limited', () {
      final entity = UserAvailabilityEntity(
        userId: 'u1',
        isLimited: true,
        resumeOn: _utcDate(2026, 8, 10),
      );
      expect(entity.effectiveOn(todayUtc), AvailabilityView.limited);
      expect(entity.blocksNewRequestsOn(todayUtc), isFalse);
    });

    test('delegates comparison to root helper', () {
      final entity = UserAvailabilityEntity(
        userId: 'u1',
        isLimited: true,
        resumeOn: _utcDate(2026, 8, 20),
      );
      expect(
        entity.effectiveOn(todayUtc),
        root.availabilityViewOn(
          isLimited: entity.isLimited,
          resumeOn: entity.resumeOn,
          todayUtc: todayUtc,
        ),
      );
    });

    test('UTC calendar dates are independent of process local timezone', () {
      final resumeOn = root.utcCalendarDate(DateTime.utc(2026, 8, 20, 23, 59));
      final entity = UserAvailabilityEntity(userId: 'u1', resumeOn: resumeOn);
      expect(root.isUtcCalendarDate(resumeOn), isTrue);
      expect(entity.effectiveOn(todayUtc), AvailabilityView.paused);
    });
  });
}
