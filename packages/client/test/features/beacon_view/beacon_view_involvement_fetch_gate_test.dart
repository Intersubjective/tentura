import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';

class _CountingCoordinationRepository
    extends FakeBeaconViewCoordinationRepository {
  int fetchCalls = 0;

  @override
  Future<List<FakeHelpOfferCoordinationRow>> fetchHelpOffersWithCoordination({
    required String beaconId,
  }) {
    fetchCalls++;
    return super.fetchHelpOffersWithCoordination(beaconId: beaconId);
  }
}

class _CountingActivityEventRepository
    extends FakeBeaconViewActivityEventRepository {
  int listCalls = 0;

  @override
  Future<List<BeaconActivityEvent>> list({required String beaconId}) {
    listCalls++;
    return super.list(beaconId: beaconId);
  }
}

class _StubForwardRepository extends FakeBeaconViewForwardRepository {
  _StubForwardRepository(this.edges);

  final List<ForwardEdge> edges;

  @override
  Future<List<ForwardEdge>> fetchEdges({required String beaconId}) async =>
      edges;

  @override
  Future<BeaconInvolvementData> fetchBeaconInvolvement({
    required String beaconId,
  }) async => (
    beacon: Beacon(
      id: beaconId,
      title: '',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      author: const Profile(id: 'Uauthor'),
    ),
    forwardedToIds: const <String>{},
    helpOfferedIds: const <String>{},
    withdrawnIds: const <String>{},
    rejectedIds: const <String>{},
    watchingIds: const <String>{},
    onwardForwarderIds: const <String>{},
    myForwardedRecipientNotes: const <String, String>{},
    myForwardedRecipientEdgeIds: const <String, String>{},
    myForwardedRecipientReadAts: const <String, DateTime?>{},
    myForwardedRecipientHasOnwardChild: const <String, bool>{},
    myForwardedRecipientRejected: const <String, bool>{},
  );

  @override
  Future<Map<String, List<String>>> fetchReasonsByBeacon({
    required String beaconId,
  }) async => {};
}

void main() {
  const myProfile = Profile(id: 'Uviewer', displayName: 'Viewer');
  const beaconId = 'Bobserver01';

  Beacon beaconFor({
    required bool canReadInvolvement,
    BeaconAccessLevel? accessLevel,
    bool canReadAdmittedHelpers = true,
  }) => Beacon(
    id: beaconId,
    title: 'Observed request',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    status: BeaconStatus.open,
    canReadContent: true,
    canReadInvolvement: canReadInvolvement,
    canReadAdmittedHelpers: canReadAdmittedHelpers,
    accessLevel: accessLevel,
    author: const Profile(id: 'Uauthor', displayName: 'Author'),
  );

  Future<
    ({
      _CountingCoordinationRepository coordination,
      _CountingActivityEventRepository activity,
      FakeBeaconViewRoomRepository room,
      FakeBeaconViewFactCardRepository factCards,
      TrackingBeaconRepository beaconRepo,
      BeaconViewCubit cubit,
    })
  >
  load({
    required bool canReadInvolvement,
    BeaconAccessLevel? accessLevel,
    bool canReadAdmittedHelpers = true,
  }) async {
    final coordination = _CountingCoordinationRepository();
    final activity = _CountingActivityEventRepository();
    final room = FakeBeaconViewRoomRepository();
    final factCards = FakeBeaconViewFactCardRepository();
    final beaconRepo = TrackingBeaconRepository()
      ..fetchByIdHandler = (_) async => beaconFor(
        canReadInvolvement: canReadInvolvement,
        accessLevel: accessLevel,
        canReadAdmittedHelpers: canReadAdmittedHelpers,
      );
    final cubit = BeaconViewCubit(
      id: beaconId,
      myProfile: myProfile,
      beaconViewCase: buildTestBeaconViewCase(
        beaconRepo: beaconRepo,
        coordinationRepo: coordination,
        activityEventsRepo: activity,
        roomRepo: room,
        factCardsRepo: factCards,
      ),
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);
    await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);
    return (
      coordination: coordination,
      activity: activity,
      room: room,
      factCards: factCards,
      beaconRepo: beaconRepo,
      cubit: cubit,
    );
  }

  group('BeaconViewCubit involvement fetch gate', () {
    test('observer without involvement skips offers and room', () async {
      final r = await load(
        canReadInvolvement: false,
        accessLevel: BeaconAccessLevel.observer,
      );

      expect(r.cubit.state.beaconContentLoaded, isTrue);
      expect(r.cubit.state.beaconUnavailable, isFalse);
      expect(r.cubit.state.beacon.title, 'Observed request');
      expect(r.factCards.listCalls, greaterThan(0));
      expect(r.coordination.fetchCalls, 0);
      expect(r.room.fetchParticipantsCalls, 0);
      expect(r.room.fetchBeaconRoomStateCalls, 0);
      expect(r.activity.listCalls, 0);
      expect(r.beaconRepo.fetchAdmittedHelpersCalls, greaterThan(0));
    });

    test('observer with involvement still skips room, loads offers', () async {
      final r = await load(
        canReadInvolvement: true,
        accessLevel: BeaconAccessLevel.observer,
      );

      expect(r.coordination.fetchCalls, greaterThan(0));
      expect(r.room.fetchParticipantsCalls, 0);
      expect(r.room.fetchBeaconRoomStateCalls, 0);
      expect(r.activity.listCalls, 0);
      expect(r.beaconRepo.fetchAdmittedHelpersCalls, greaterThan(0));
    });

    test('member still fetches involvement and room data', () async {
      final r = await load(
        canReadInvolvement: true,
        accessLevel: BeaconAccessLevel.member,
      );

      expect(r.coordination.fetchCalls, greaterThan(0));
      expect(r.room.fetchParticipantsCalls, greaterThan(0));
      expect(r.room.fetchBeaconRoomStateCalls, greaterThan(0));
      expect(r.activity.listCalls, greaterThan(0));
    });

    test('member demotion to observer clears cached forwards', () async {
      final coordination = _CountingCoordinationRepository();
      final activity = _CountingActivityEventRepository();
      final room = FakeBeaconViewRoomRepository();
      final factCards = FakeBeaconViewFactCardRepository();
      var current = beaconFor(
        canReadInvolvement: true,
        accessLevel: BeaconAccessLevel.member,
      );
      final beaconRepo = TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => current;
      final cubit = BeaconViewCubit(
        id: beaconId,
        myProfile: myProfile,
        beaconViewCase: buildTestBeaconViewCase(
          beaconRepo: beaconRepo,
          coordinationRepo: coordination,
          activityEventsRepo: activity,
          roomRepo: room,
          factCardsRepo: factCards,
          forward: _StubForwardRepository([
            ForwardEdge(
              id: 'e1',
              beaconId: beaconId,
              createdAt: DateTime.utc(2026),
              sender: myProfile,
              recipient: const Profile(id: 'Uother', displayName: 'Other'),
            ),
          ]),
        ),
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);
      await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);
      final memberParticipantCalls = room.fetchParticipantsCalls;
      await cubit.loadForwards();
      expect(cubit.state.forwardsLoaded, isTrue);
      expect(cubit.state.viewerForwardEdges, isNotEmpty);

      current = beaconFor(
        canReadInvolvement: false,
        accessLevel: BeaconAccessLevel.observer,
      );
      await cubit.retryInitialLoad();
      await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);

      expect(cubit.state.forwardsLoaded, isFalse);
      expect(cubit.state.viewerForwardEdges, isEmpty);
      expect(room.fetchParticipantsCalls, memberParticipantCalls);
    });
  });
}

Future<void> pumpUntil(
  Stream<BeaconViewState> stream,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  if (condition()) return;
  await stream.timeout(timeout).firstWhere((_) => condition());
}
