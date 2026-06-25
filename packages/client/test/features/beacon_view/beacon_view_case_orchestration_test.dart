import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/beacon_room/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_room/domain/room_read_watermark_store.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';

import 'beacon_view_case_test_support.dart';

void main() {
  group('BeaconViewCase stream wiring', () {
    test('forwardCompleted forwards repository events', () async {
      final forward = FakeBeaconViewForwardRepository();
      addTearDown(forward.dispose);
      final case_ = buildTestBeaconViewCase(forward: forward);

      final ids = <String>[];
      final sub = case_.forwardCompleted.listen(ids.add);
      addTearDown(sub.cancel);

      forward.emitForwardCompleted('B1');
      await Future<void>.delayed(Duration.zero);

      expect(ids, ['B1']);
    });

    test('helpOfferChanges forwards repository events', () async {
      final forward = FakeBeaconViewForwardRepository();
      addTearDown(forward.dispose);
      final case_ = buildTestBeaconViewCase(forward: forward);

      final events = <HelpOfferEvent>[];
      final sub = case_.helpOfferChanges.listen(events.add);
      addTearDown(sub.cancel);

      const event = HelpOfferInvalidated('B2');
      forward.emitHelpOfferChange(event);
      await Future<void>.delayed(Duration.zero);

      expect(events, [event]);
    });

    test('beaconRoomInvalidations forwards invalidation service events', () async {
      final invalidation = FakeInvalidationService();
      addTearDown(invalidation.dispose);
      final case_ = buildTestBeaconViewCase(invalidation: invalidation);

      final events = <BeaconRoomInvalidation>[];
      final sub = case_.beaconRoomInvalidations.listen(events.add);
      addTearDown(sub.cancel);

      const inv = BeaconRoomInvalidation(
        beaconId: 'B3',
        entityType: BeaconRoomEntityType.roomMessage,
      );
      invalidation.emitRoomInvalidation(inv);
      await Future<void>.delayed(Duration.zero);

      expect(events, [inv]);
    });

    test('readWatermarkChanges forwards beacon room watermark stream', () async {
      final watermark = RoomReadWatermarkStore.testing();
      addTearDown(watermark.dispose);
      final case_ = buildTestBeaconViewCase(watermarkStore: watermark);

      final ids = <String>[];
      final sub = case_.readWatermarkChanges.listen(ids.add);
      addTearDown(sub.cancel);

      watermark.observeReadThrough('B4', DateTime.utc(2026));
      await Future<void>.delayed(Duration.zero);

      expect(ids, ['B4']);
    });
  });

  group('BeaconViewCase refetch after lifecycle mutations', () {
    test('beaconClose refreshes beacon after evaluation', () async {
      final beacon = TrackingBeaconRepository();
      final case_ = buildTestBeaconViewCase(beaconRepo: beacon);

      await case_.beaconClose(
        beaconId: 'B1',
        expectedRequiresReviewWindow: false,
      );

      expect(beacon.refreshAndNotifyCalls, ['B1']);
    });

    test('beaconCancel refreshes beacon after evaluation', () async {
      final beacon = TrackingBeaconRepository();
      final case_ = buildTestBeaconViewCase(beaconRepo: beacon);

      await case_.beaconCancel('B2');

      expect(beacon.refreshAndNotifyCalls, ['B2']);
    });

    test('beaconExtendReview refreshes beacon after evaluation', () async {
      final beacon = TrackingBeaconRepository();
      final case_ = buildTestBeaconViewCase(beaconRepo: beacon);

      await case_.beaconExtendReview('B3');

      expect(beacon.refreshAndNotifyCalls, ['B3']);
    });

    test('beaconReopen refreshes beacon after evaluation', () async {
      final beacon = TrackingBeaconRepository();
      final case_ = buildTestBeaconViewCase(beaconRepo: beacon);

      await case_.beaconReopen('B4');

      expect(beacon.refreshAndNotifyCalls, ['B4']);
    });

    test('beaconCloseNow refreshes beacon after evaluation', () async {
      final beacon = TrackingBeaconRepository();
      final case_ = buildTestBeaconViewCase(beaconRepo: beacon);

      await case_.beaconCloseNow('B5');

      expect(beacon.refreshAndNotifyCalls, ['B5']);
    });

    test('publishBeacon publishes draft then refreshes beacon', () async {
      final beacon = TrackingBeaconRepository();
      final case_ = buildTestBeaconViewCase(beaconRepo: beacon);

      await case_.publishBeacon('B6');

      expect(beacon.publishDraftCalls, ['B6']);
      expect(beacon.refreshAndNotifyCalls, ['B6']);
    });
  });
}
