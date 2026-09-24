import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_seen_peer.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';

void main() {
  const myProfile = Profile(id: 'Uviewer', displayName: 'Viewer');
  const beaconId = 'Bseenpeer01';

  Beacon readableBeacon() => Beacon(
    id: beaconId,
    title: 'Peer presence beacon',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    status: BeaconStatus.open,
    canReadContent: true,
    author: const Profile(id: 'Uauthor', displayName: 'Author'),
  );

  group('BeaconViewCubit roomSeenPeer guard', () {
    test('roomSeenPeer room invalidation triggers no beacon refresh', () async {
      final beaconRepo = TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => readableBeacon();
      addTearDown(beaconRepo.dispose);
      final room = FakeBeaconViewRoomRepository();
      addTearDown(room.dispose);
      final cubit = BeaconViewCubit(
        id: beaconId,
        myProfile: myProfile,
        beaconViewCase: buildTestBeaconViewCase(
          beaconRepo: beaconRepo,
          roomRepo: room,
        ),
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);

      await _pumpUntilLoaded(cubit);
      final fetchByIdAfterLoad = beaconRepo.fetchByIdCalls;

      room.emitRoomInvalidation(
        BeaconRoomInvalidation(
          beaconId: beaconId,
          entityType: BeaconRoomEntityType.roomSeenPeer,
          seenPeer: RealtimeSeenPeer(
            userId: 'Upeer00000003',
            lastSeenAt: DateTime.utc(2026, 9, 24, 2),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(
        beaconRepo.fetchByIdCalls,
        fetchByIdAfterLoad,
        reason: 'peer read-presence must not trigger request_detail refresh',
      );
      expect(beaconRepo.refreshAndNotifyCalls, isEmpty);
    });

    test('roomSeenPeer room invalidation triggers no targeted fetch', () async {
      final beaconRepo = TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => readableBeacon();
      addTearDown(beaconRepo.dispose);
      final room = FakeBeaconViewRoomRepository();
      addTearDown(room.dispose);
      final factCards = FakeBeaconViewFactCardRepository();
      final cubit = BeaconViewCubit(
        id: beaconId,
        myProfile: myProfile,
        beaconViewCase: buildTestBeaconViewCase(
          beaconRepo: beaconRepo,
          roomRepo: room,
          factCardsRepo: factCards,
        ),
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);

      await _pumpUntilLoaded(cubit);
      final roomStateCallsAfterLoad = room.fetchBeaconRoomStateCalls;
      final participantCallsAfterLoad = room.fetchParticipantsCalls;
      final factCardCallsAfterLoad = factCards.listCalls;

      room.emitRoomInvalidation(
        BeaconRoomInvalidation(
          beaconId: beaconId,
          entityType: BeaconRoomEntityType.roomSeenPeer,
          seenPeer: RealtimeSeenPeer(
            userId: 'Upeer00000004',
            lastSeenAt: DateTime.utc(2026, 9, 24, 3),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(
        room.fetchBeaconRoomStateCalls,
        roomStateCallsAfterLoad,
        reason: 'peer read-presence must not refetch room state',
      );
      expect(
        room.fetchParticipantsCalls,
        participantCallsAfterLoad,
        reason: 'peer read-presence must not refetch participants',
      );
      expect(
        factCards.listCalls,
        factCardCallsAfterLoad,
        reason: 'peer read-presence must not refetch fact cards',
      );
    });

    test(
      '_fetchForEntityTypes documents roomSeenPeer as presence-only',
      () {
        final source = File(
          'lib/features/beacon_view/ui/bloc/beacon_view_cubit.dart',
        ).readAsStringSync();

        expect(
          source,
          contains('BeaconRoomEntityType.roomSeenPeer'),
          reason:
              'request detail must treat roomSeenPeer like roomSeen: '
              'explicit empty branch beside the existing roomSeen arm',
        );
      },
    );
  });
}

Future<void> _pumpUntilLoaded(BeaconViewCubit cubit) => _pumpUntil(
  cubit.stream,
  () => cubit.state.beaconContextLoaded,
);

Future<void> _pumpUntil(
  Stream<BeaconViewState> stream,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  if (condition()) return;
  await stream.timeout(timeout).firstWhere((_) => condition());
}
