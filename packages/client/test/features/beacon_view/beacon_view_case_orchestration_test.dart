import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/realtime/realtime_watch.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/features/beacon_room/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_room/domain/room_read_watermark_store.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';

import '../../support/test_realtime_sync.dart';
import 'beacon_view_case_test_support.dart';

void main() {
  group('BeaconViewCase stream wiring', () {
    test('forwardChanges forwards repository events', () async {
      final forward = FakeBeaconViewForwardRepository();
      addTearDown(forward.dispose);
      final case_ = buildTestBeaconViewCase(forward: forward);

      final ids = <String>[];
      final sub = case_.forwardChanges.listen(ids.add);
      addTearDown(sub.cancel);

      forward.emitForwardCompleted('B1');
      await Future<void>.delayed(Duration.zero);

      expect(ids, ['B1']);
    });

    test('beaconChanges forwards repository invalidations', () async {
      final beacon = TrackingBeaconRepository();
      addTearDown(beacon.dispose);
      final case_ = buildTestBeaconViewCase(beaconRepo: beacon);

      final events = <RepositoryEvent<Beacon>>[];
      final sub = case_.beaconChanges.listen(events.add);
      addTearDown(sub.cancel);

      beacon.emitInvalidation('B1');
      await Future<void>.delayed(Duration.zero);

      expect(events.single.id, 'B1');
      expect(events.single, isA<RepositoryEventInvalidate<Beacon>>());
    });

    test('catchUps forwards the shared realtime recovery signal', () async {
      final realtime = buildTestRealtimeSync();
      final syncCase = realtime.case_;
      addTearDown(syncCase.dispose);
      addTearDown(realtime.port.dispose);
      final case_ = buildTestBeaconViewCase(realtimeSyncCase: syncCase);

      final events = <void>[];
      final sub = case_.catchUps.listen(events.add);
      addTearDown(sub.cancel);

      realtime.port.emitCatchUp();
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
    });

    test('People watch uses the exact fetched subject set', () async {
      final realtime = buildTestRealtimeSync();
      final grants = FakeBeaconViewWatchGrantPort();
      addTearDown(realtime.case_.dispose);
      addTearDown(realtime.port.dispose);
      final case_ = buildTestBeaconViewCase(
        realtimeSyncCase: realtime.case_,
        realtimeWatchGrantPort: grants,
      );

      await case_.replacePeopleWatch(
        beaconId: 'B1',
        subjectIds: {'U-author', 'U-helper', 'B-not-a-user'},
      );

      final descriptor = grants.descriptors.single;
      expect(descriptor.scope, RealtimeWatchScope.people);
      expect(descriptor.beaconId, 'B1');
      expect(descriptor.requestedSubjectIds, {'U-author', 'U-helper'});
      expect(realtime.port.replacedWatches, hasLength(1));
    });

    test(
      'peopleChanges forwards only relationship and profile signals',
      () async {
        final realtime = buildTestRealtimeSync();
        addTearDown(realtime.case_.dispose);
        addTearDown(realtime.port.dispose);
        final case_ = buildTestBeaconViewCase(
          realtimeSyncCase: realtime.case_,
        );
        final changes = <RealtimeEntityChange>[];
        final sub = case_.peopleChanges.listen(changes.add);
        addTearDown(sub.cancel);

        for (final kind in const {
          RealtimeEntityKind.relationship,
          RealtimeEntityKind.profile,
          RealtimeEntityKind.beacon,
        }) {
          realtime.port.emitChange(
            RealtimeEntityChange(
              kind: kind,
              aggregateId: 'U-author',
              operation: RealtimeOperation.update,
              source: RealtimeChangeSource.serverInvalidation,
            ),
          );
        }
        await Future<void>.delayed(Duration.zero);

        expect(
          changes.map((change) => change.kind),
          [RealtimeEntityKind.relationship, RealtimeEntityKind.profile],
        );
      },
    );

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

    test('beaconRoomInvalidations forwards room case events', () async {
      final room = FakeBeaconViewRoomRepository();
      addTearDown(room.dispose);
      final case_ = buildTestBeaconViewCase(roomRepo: room);

      final events = <BeaconRoomInvalidation>[];
      final sub = case_.beaconRoomInvalidations.listen(events.add);
      addTearDown(sub.cancel);

      const inv = BeaconRoomInvalidation(
        beaconId: 'B3',
        entityType: BeaconRoomEntityType.roomMessage,
      );
      room.emitRoomInvalidation(inv);
      await Future<void>.delayed(Duration.zero);

      expect(events, [inv]);
    });

    test(
      'readWatermarkChanges forwards beacon room watermark stream',
      () async {
        final watermark = RoomReadWatermarkStore.testing();
        addTearDown(watermark.dispose);
        final case_ = buildTestBeaconViewCase(watermarkStore: watermark);

        final ids = <String>[];
        final sub = case_.readWatermarkChanges.listen(ids.add);
        addTearDown(sub.cancel);

        watermark.observeReadThrough('B4', DateTime.utc(2026));
        await Future<void>.delayed(Duration.zero);

        expect(ids, ['B4']);
      },
    );
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

    test('setBeaconStatus refreshes beacon after mutation', () async {
      final beacon = TrackingBeaconRepository();
      final coordination = FakeBeaconViewCoordinationRepository();
      final case_ = buildTestBeaconViewCase(
        beaconRepo: beacon,
        coordinationRepo: coordination,
      );

      await case_.setBeaconStatus(beaconId: 'B-status', status: 2);

      expect(coordination.setBeaconStatusCalls, [
        (beaconId: 'B-status', status: 2),
      ]);
      expect(beacon.refreshAndNotifyCalls, ['B-status']);
    });

    test(
      'setCoordinationResponse emits help, participant, and beacon refresh',
      () async {
        final beacon = TrackingBeaconRepository();
        final forward = FakeBeaconViewForwardRepository();
        addTearDown(forward.dispose);
        final coordination = FakeBeaconViewCoordinationRepository();
        final room = FakeBeaconViewRoomRepository();
        addTearDown(room.dispose);
        final case_ = buildTestBeaconViewCase(
          beaconRepo: beacon,
          forward: forward,
          coordinationRepo: coordination,
          roomRepo: room,
        );

        await case_.setCoordinationResponse(
          beaconId: 'B-response',
          offerUserId: 'u-offer',
          responseType: 1,
          inviteToRoom: true,
          removeFromRoom: false,
        );

        expect(coordination.setCoordinationResponseCalls, [
          (
            beaconId: 'B-response',
            offerUserId: 'u-offer',
            responseType: 1,
            inviteToRoom: true,
            removeFromRoom: false,
          ),
        ]);
        expect(
          forward.notifiedHelpOfferEvents.single,
          isA<HelpOfferInvalidated>().having(
            (e) => e.beaconId,
            'beaconId',
            'B-response',
          ),
        );
        expect(room.localChanges, [
          const BeaconRoomInvalidation(
            beaconId: 'B-response',
            entityType: BeaconRoomEntityType.participant,
          ),
        ]);
        expect(beacon.refreshAndNotifyCalls, ['B-response']);
      },
    );

    test(
      'acceptHelpOffer emits help, participant, and beacon refresh',
      () async {
        final beacon = TrackingBeaconRepository();
        final forward = FakeBeaconViewForwardRepository();
        addTearDown(forward.dispose);
        final coordination = FakeBeaconViewCoordinationRepository();
        final room = FakeBeaconViewRoomRepository();
        addTearDown(room.dispose);
        final case_ = buildTestBeaconViewCase(
          beaconRepo: beacon,
          forward: forward,
          coordinationRepo: coordination,
          roomRepo: room,
        );

        await case_.acceptHelpOffer(
          beaconId: 'B-accept',
          offerUserId: 'u-offer',
        );

        expect(coordination.acceptHelpOfferCalls, [
          (beaconId: 'B-accept', offerUserId: 'u-offer'),
        ]);
        expect(
          forward.notifiedHelpOfferEvents.single,
          isA<HelpOfferInvalidated>().having(
            (e) => e.beaconId,
            'beaconId',
            'B-accept',
          ),
        );
        expect(room.localChanges, [
          const BeaconRoomInvalidation(
            beaconId: 'B-accept',
            entityType: BeaconRoomEntityType.participant,
          ),
        ]);
        expect(beacon.refreshAndNotifyCalls, ['B-accept']);
      },
    );

    test(
      'declineHelpOffer emits help, participant, and beacon refresh',
      () async {
        final beacon = TrackingBeaconRepository();
        final forward = FakeBeaconViewForwardRepository();
        addTearDown(forward.dispose);
        final coordination = FakeBeaconViewCoordinationRepository();
        final room = FakeBeaconViewRoomRepository();
        addTearDown(room.dispose);
        final case_ = buildTestBeaconViewCase(
          beaconRepo: beacon,
          forward: forward,
          coordinationRepo: coordination,
          roomRepo: room,
        );

        await case_.declineHelpOffer(
          beaconId: 'B-decline',
          offerUserId: 'u-offer',
          reason: 'not enough context',
        );

        expect(coordination.declineHelpOfferCalls, [
          (
            beaconId: 'B-decline',
            offerUserId: 'u-offer',
            reason: 'not enough context',
          ),
        ]);
        expect(
          forward.notifiedHelpOfferEvents.single,
          isA<HelpOfferInvalidated>().having(
            (e) => e.beaconId,
            'beaconId',
            'B-decline',
          ),
        );
        expect(room.localChanges, [
          const BeaconRoomInvalidation(
            beaconId: 'B-decline',
            entityType: BeaconRoomEntityType.participant,
          ),
        ]);
        expect(beacon.refreshAndNotifyCalls, ['B-decline']);
      },
    );

    test(
      'removeFromRoom emits help, participant, and beacon refresh',
      () async {
        final beacon = TrackingBeaconRepository();
        final forward = FakeBeaconViewForwardRepository();
        addTearDown(forward.dispose);
        final coordination = FakeBeaconViewCoordinationRepository();
        final room = FakeBeaconViewRoomRepository();
        addTearDown(room.dispose);
        final case_ = buildTestBeaconViewCase(
          beaconRepo: beacon,
          forward: forward,
          coordinationRepo: coordination,
          roomRepo: room,
        );

        await case_.removeFromRoom(
          beaconId: 'B-remove',
          offerUserId: 'u-offer',
          reason: 'chat is full',
        );

        expect(coordination.removeFromRoomCalls, [
          (
            beaconId: 'B-remove',
            offerUserId: 'u-offer',
            reason: 'chat is full',
          ),
        ]);
        expect(
          forward.notifiedHelpOfferEvents.single,
          isA<HelpOfferInvalidated>().having(
            (e) => e.beaconId,
            'beaconId',
            'B-remove',
          ),
        );
        expect(room.localChanges, [
          const BeaconRoomInvalidation(
            beaconId: 'B-remove',
            entityType: BeaconRoomEntityType.participant,
          ),
        ]);
        expect(beacon.refreshAndNotifyCalls, ['B-remove']);
      },
    );

    test('publishBeacon publishes draft then refreshes beacon', () async {
      final beacon = TrackingBeaconRepository();
      final case_ = buildTestBeaconViewCase(beaconRepo: beacon);

      await case_.publishBeacon('B6');

      expect(beacon.publishDraftCalls, ['B6']);
      expect(beacon.refreshAndNotifyCalls, ['B6']);
    });
  });
}
