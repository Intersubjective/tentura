import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';

void main() {
  final t0 = DateTime.utc(2020);
  final t1 = DateTime.utc(2020, 1, 2);
  final t2 = DateTime.utc(2020, 1, 3);
  final t3 = DateTime.utc(2020, 1, 4);
  final createdEarly2019 = DateTime.utc(2019, 6);
  final seenLate2019 = DateTime.utc(2019, 12, 20).millisecondsSinceEpoch;
  final forwardBeforeSeen = DateTime.utc(2019, 12, 10);
  final beaconStale = DateTime.utc(2019, 12);
  /// Before [seenLate2019] so beacon row does not count as "new" in isolation.
  final beaconUpdatedBeforeSeen = DateTime.utc(2019, 12, 15);

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
        coordinationStatus: BeaconCoordinationStatus.moreOrDifferentHelpNeeded,
        coordinationStatusUpdatedAt: t1,
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
        coordinationStatusUpdatedAt: t2,
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

  group('MyWorkCardViewModel.newStuffReasons', () {
    Beacon baseBeacon({
      DateTime? createdAt,
      DateTime? updatedAt,
      DateTime? coordinationStatusUpdatedAt,
    }) =>
        Beacon(
          createdAt: createdAt ?? t0,
          updatedAt: updatedAt ?? t1,
          id: 'b1',
          coordinationStatusUpdatedAt: coordinationStatusUpdatedAt,
        );

    test('new beacon also lists beacon row when created equals updated', () {
      final vm = MyWorkCardViewModel(
        beaconId: 'b1',
        role: MyWorkCardRole.authored,
        kind: MyWorkCardKind.authoredActive,
        beacon: baseBeacon(createdAt: t2, updatedAt: t2),
      );
      expect(
        vm.newStuffReasons(seenLate2019),
        [
          MyWorkNewStuffReason.newBeacon,
          MyWorkNewStuffReason.beaconUpdated,
        ],
      );
    });

    test('author response wins tie with commitment row', () {
      final vm = MyWorkCardViewModel(
        beaconId: 'b1',
        role: MyWorkCardRole.committed,
        kind: MyWorkCardKind.committedActive,
        beacon: baseBeacon(
          createdAt: createdEarly2019,
          updatedAt: beaconUpdatedBeforeSeen,
        ),
        commitmentRowUpdatedAt: t2,
        authorCoordinationUpdatedAt: t2,
      );
      expect(
        vm.newStuffReasons(seenLate2019),
        [MyWorkNewStuffReason.authorResponseChanged],
      );
    });

    test('commitment row when strictly newer than author response', () {
      final vm = MyWorkCardViewModel(
        beaconId: 'b1',
        role: MyWorkCardRole.committed,
        kind: MyWorkCardKind.committedActive,
        beacon: baseBeacon(
          createdAt: createdEarly2019,
          updatedAt: beaconUpdatedBeforeSeen,
        ),
        commitmentRowUpdatedAt: t3,
        authorCoordinationUpdatedAt: t2,
      );
      expect(
        vm.newStuffReasons(seenLate2019),
        [
          MyWorkNewStuffReason.authorResponseChanged,
          MyWorkNewStuffReason.commitmentUpdated,
        ],
      );
    });

    test('coordination status when max activity', () {
      final vm = MyWorkCardViewModel(
        beaconId: 'b1',
        role: MyWorkCardRole.authored,
        kind: MyWorkCardKind.authoredActive,
        beacon: baseBeacon(
          createdAt: createdEarly2019,
          updatedAt: t3,
          coordinationStatusUpdatedAt: t3,
        ),
      );
      expect(
        vm.newStuffReasons(seenLate2019),
        [MyWorkNewStuffReason.coordinationStatusChanged],
      );
    });

    test('beacon updated fallback', () {
      final vm = MyWorkCardViewModel(
        beaconId: 'b1',
        role: MyWorkCardRole.authored,
        kind: MyWorkCardKind.authoredActive,
        beacon: baseBeacon(createdAt: createdEarly2019, updatedAt: t3),
      );
      expect(
        vm.newStuffReasons(seenLate2019),
        [MyWorkNewStuffReason.beaconUpdated],
      );
    });
  });
}
