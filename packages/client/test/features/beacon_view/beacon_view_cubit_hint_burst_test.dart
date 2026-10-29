import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';

const _beaconId = 'Bhintburst01';

Beacon _readableBeacon(String title) => Beacon(
  id: _beaconId,
  title: title,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  author: const Profile(id: 'Uauthor', displayName: 'Author'),
);

class _TrackingCoordinationRepository
    extends FakeBeaconViewCoordinationRepository {
  int fetchHelpOffersCalls = 0;

  @override
  Future<List<FakeHelpOfferCoordinationRow>> fetchHelpOffersWithCoordination({
    required String beaconId,
  }) {
    fetchHelpOffersCalls++;
    return super.fetchHelpOffersWithCoordination(beaconId: beaconId);
  }
}

class _Harness {
  _Harness() {
    beaconRepo.fetchByIdHandler = (_) async => _readableBeacon('Initial title');
    cubit = BeaconViewCubit(
      id: _beaconId,
      myProfile: const Profile(id: 'Uviewer', displayName: 'Viewer'),
      beaconViewCase: buildTestBeaconViewCase(
        beaconRepo: beaconRepo,
        forward: forward,
        roomRepo: room,
        coordinationRepo: coordination,
      ),
      effects: FakeUiEffectPort(),
    );
  }

  final beaconRepo = TrackingBeaconRepository();
  final forward = FakeBeaconViewForwardRepository();
  final room = FakeBeaconViewRoomRepository();
  final coordination = _TrackingCoordinationRepository();
  late final BeaconViewCubit cubit;

  void invalidateRoom(BeaconRoomEntityType type) => room.emitRoomInvalidation(
    BeaconRoomInvalidation(beaconId: _beaconId, entityType: type),
  );

  Future<void> dispose() async {
    await cubit.close();
    await beaconRepo.dispose();
    await forward.dispose();
    await room.dispose();
  }
}

void main() {
  group('Request detail realtime refresh', () {
    test(
      'one hint burst refreshes detail and offers once and a later participant '
      'hint refreshes them once more',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        if (!h.cubit.state.beaconContextLoaded) {
          await h.cubit.stream
              .firstWhere((state) => state.beaconContextLoaded)
              .timeout(const Duration(seconds: 2));
        }
        await pumpEventQueue(times: 30);
        expect(h.cubit.state.beacon.title, 'Initial title');
        final detailAfterLoad = h.beaconRepo.fetchByIdCalls;
        final offersAfterLoad = h.coordination.fetchHelpOffersCalls;

        final heldFetch = Completer<Beacon>();
        final fetchStarted = Completer<void>();
        addTearDown(() {
          if (!heldFetch.isCompleted) {
            heldFetch.complete(_readableBeacon('Burst title'));
          }
        });
        h.beaconRepo.fetchByIdHandler = (_) {
          if (!fetchStarted.isCompleted) fetchStarted.complete();
          return heldFetch.future;
        };

        // Observe delivery on the same broadcast streams the cubit already
        // subscribes to, rather than assuming add() means delivery finished.
        final delivered = <String>[];
        final allHintsDelivered = Completer<void>();
        void recordDelivery(String hint) {
          delivered.add(hint);
          if (delivered.length == 5) allHintsDelivered.complete();
        }

        final beaconDelivery = h.beaconRepo.changes.listen(
          (_) => recordDelivery('beacon'),
        );
        final offerDelivery = h.forward.helpOfferChanges.listen(
          (_) => recordDelivery('offer'),
        );
        final roomDelivery = h.room.beaconRoomInvalidations.listen(
          (hint) => recordDelivery(hint.entityType.name),
        );
        addTearDown(() async {
          await beaconDelivery.cancel();
          await offerDelivery.cancel();
          await roomDelivery.cancel();
        });

        // No await between these hints: one invalidation buffer flush delivers
        // the beacon, offer and room hints in the same event-loop turn.
        h.beaconRepo.emitInvalidation(_beaconId);
        h.forward.emitHelpOfferChange(const HelpOfferInvalidated(_beaconId));
        h
          ..invalidateRoom(BeaconRoomEntityType.participant)
          ..invalidateRoom(BeaconRoomEntityType.helpOffer)
          ..invalidateRoom(BeaconRoomEntityType.coordinationItem);
        await allHintsDelivered.future.timeout(const Duration(seconds: 2));
        await fetchStarted.future.timeout(const Duration(seconds: 2));
        // Flush the streams and chained cubit callbacks while the first read
        // is still blocked. Every hint must have reached its listener here.
        await pumpEventQueue(times: 30);
        expect(
          delivered,
          unorderedEquals([
            'beacon',
            'offer',
            'participant',
            'helpOffer',
            'coordinationItem',
          ]),
        );
        expect(heldFetch.isCompleted, isFalse);
        expect(h.cubit.state.beacon.title, 'Initial title');
        expect(
          h.beaconRepo.fetchByIdCalls,
          detailAfterLoad + 1,
          reason:
              'All five hints have been delivered while the first fetch is '
              'held; none may start another detail read.',
        );

        heldFetch.complete(_readableBeacon('Burst title'));
        // Drain the full refresh and any queued follow-up before counting.
        await pumpEventQueue(times: 30);
        expect(h.cubit.state.beacon.title, 'Burst title');
        final burstReads = (
          detail: h.beaconRepo.fetchByIdCalls - detailAfterLoad,
          offers: h.coordination.fetchHelpOffersCalls - offersAfterLoad,
        );
        expect(
          burstReads,
          (detail: 1, offers: 1),
          reason:
              'Releasing the held read must finish exactly one full refresh, '
              'without a queued duplicate from the same burst.',
        );

        h.beaconRepo.fetchByIdHandler = (_) async =>
            _readableBeacon('Later participant title');
        h.invalidateRoom(BeaconRoomEntityType.participant);
        await pumpEventQueue(times: 30);
        expect(h.cubit.state.beacon.title, 'Later participant title');

        expect(
          (
            detail: h.beaconRepo.fetchByIdCalls - detailAfterLoad,
            offers: h.coordination.fetchHelpOffersCalls - offersAfterLoad,
          ),
          (detail: 2, offers: 2),
          reason:
              'Hints from one burst must share one full refresh; a later '
              'participant hint must still fetch fresh detail and offers.',
        );
      },
    );
  });
}
