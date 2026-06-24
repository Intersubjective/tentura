import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';

void main() {
  final t0 = DateTime.utc(2020);
  final t1 = DateTime.utc(2020, 1, 2);
  final t2 = DateTime.utc(2020, 1, 3);
  final t3 = DateTime.utc(2020, 1, 4);
  final createdEarly2019 = DateTime.utc(2019, 6);
  final seenLate2019 = DateTime.utc(2019, 12, 20).millisecondsSinceEpoch;
  final forwardBeforeSeen = DateTime.utc(2019, 12, 10);
  final beaconStale = DateTime.utc(2019, 12);

  group('InboxItem.newStuffReasons', () {
    test('new forward only when beacon-side is stale', () {
      final beacon = Beacon(
        createdAt: t0,
        updatedAt: beaconStale,
        id: 'b1',
      );
      final item = InboxItem(
        beaconId: 'b1',
        latestForwardAt: t3,
        forwardCount: 1,
        beacon: beacon,
      );
      expect(
        item.newStuffReasons(seenLate2019),
        [InboxNewStuffReason.newForward],
      );
    });

    test('coordination when newer than updated_at (tie: coordination only)', () {
      final beacon = Beacon(
        createdAt: t0,
        updatedAt: t1,
        id: 'b1',
        status: BeaconStatus.needsMoreHelp,
        statusChangedAt: t1,
      );
      final item = InboxItem(
        beaconId: 'b1',
        latestForwardAt: forwardBeforeSeen,
        beacon: beacon,
      );
      expect(
        item.newStuffReasons(seenLate2019),
        [InboxNewStuffReason.coordinationStatusChanged],
      );
    });

    test('beacon updated when only updated_at exceeds seen', () {
      final beacon = Beacon(
        createdAt: t0,
        updatedAt: t2,
        id: 'b1',
      );
      final item = InboxItem(
        beaconId: 'b1',
        latestForwardAt: forwardBeforeSeen,
        beacon: beacon,
      );
      expect(
        item.newStuffReasons(seenLate2019),
        [InboxNewStuffReason.beaconUpdated],
      );
    });

    test('forward plus beacon updates when all are new', () {
      final beacon = Beacon(
        createdAt: t0,
        updatedAt: t1,
        id: 'b1',
        statusChangedAt: t2,
      );
      final item = InboxItem(
        beaconId: 'b1',
        latestForwardAt: t3,
        forwardCount: 1,
        beacon: beacon,
      );
      expect(
        item.newStuffReasons(seenLate2019),
        [
          InboxNewStuffReason.newForward,
          InboxNewStuffReason.coordinationStatusChanged,
          InboxNewStuffReason.beaconUpdated,
        ],
      );
    });

    test('no new-forward line when forwardCount is zero despite latestForwardAt', () {
      final beacon = Beacon(
        createdAt: t0,
        updatedAt: t3,
        id: 'b1',
      );
      final item = InboxItem(
        beaconId: 'b1',
        latestForwardAt: t3,
        beacon: beacon,
      );
      expect(
        item.newStuffReasons(seenLate2019),
        [InboxNewStuffReason.beaconUpdated],
      );
    });

    test('empty when nothing newer than seen', () {
      final beacon = Beacon(
        createdAt: t0,
        updatedAt: t1,
        id: 'b1',
      );
      final item = InboxItem(
        beaconId: 'b1',
        latestForwardAt: t0,
        beacon: beacon,
      );
      expect(item.newStuffReasons(t2.millisecondsSinceEpoch), isEmpty);
    });
  });
}
