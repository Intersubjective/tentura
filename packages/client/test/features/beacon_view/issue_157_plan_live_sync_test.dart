import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_hud_derivation.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_initial_load_test.dart';

/// GitHub #157 — Plan / What's next on the NOW surface must track live
/// `beacon_room_state.current_line` without a full page reload.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  const myProfile = Profile(id: 'Uviewer', displayName: 'Viewer');
  const beaconId = 'B157plan';
  final l10n = lookupL10n(const Locale('en'));

  Beacon readableBeacon({BeaconStatus status = BeaconStatus.open}) => Beacon(
    id: beaconId,
    title: 'Plan live sync proof',
    createdAt: DateTime.utc(2026, 9, 15),
    updatedAt: DateTime.utc(2026, 9, 15),
    status: status,
    canReadContent: true,
    author: const Profile(id: 'Uauthor', displayName: 'Author'),
  );

  BeaconRoomState roomWithPlan(String line) => BeaconRoomState(
    beaconId: beaconId,
    updatedAt: DateTime.utc(2026, 9, 15, 12),
    currentLine: line,
  );

  group('Issue #157 plan / NOW line live sync', () {
    test(
      'coordination_item invalidation refetches room cue for NOW plan (regression)',
      () async {
        final room = FakeBeaconViewRoomRepository(
          roomState: roomWithPlan('Plan from client A'),
        );
        addTearDown(room.dispose);
        final beaconRepo = TrackingBeaconRepository()
          ..fetchByIdHandler = (_) async => readableBeacon();
        addTearDown(beaconRepo.dispose);
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
        await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);

        expect(beaconHudNowLine(l10n, cubit.state), 'Plan from client A');
        final fetchesAfterLoad = room.fetchBeaconRoomStateCalls;

        room.roomState = roomWithPlan('Plan edited remotely');
        room.emitRoomInvalidation(
          const BeaconRoomInvalidation(
            beaconId: beaconId,
            entityType: BeaconRoomEntityType.coordinationItem,
          ),
        );
        await pumpUntil(
          cubit.stream,
          () => room.fetchBeaconRoomStateCalls > fetchesAfterLoad,
        );

        expect(
          cubit.state.beaconRoomCue?.currentLine,
          'Plan edited remotely',
        );
        expect(beaconHudNowLine(l10n, cubit.state), 'Plan edited remotely');
      },
    );

    test(
      'beacon RepositoryEventUpdate refetches room cue for NOW plan (regression)',
      () async {
        var roomLine = 'Initial plan';
        final room = FakeBeaconViewRoomRepository(
          roomState: roomWithPlan(roomLine),
        );
        addTearDown(room.dispose);
        var beacon = readableBeacon();
        final beaconRepo = TrackingBeaconRepository()
          ..fetchByIdHandler = (_) async => beacon;
        addTearDown(beaconRepo.dispose);
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
        await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);

        roomLine = 'Plan after beacon refresh';
        room.roomState = roomWithPlan(roomLine);
        beacon = readableBeacon().copyWith(
          updatedAt: DateTime.utc(2026, 9, 15, 13),
        );
        beaconRepo.emitUpdate(beacon);
        await pumpUntil(
          cubit.stream,
          () => cubit.state.beaconRoomCue?.currentLine == roomLine,
        );

        expect(beaconHudNowLine(l10n, cubit.state), roomLine);
      },
    );

    test(
      'activityEvent room invalidation refreshes NOW plan without reload',
      () async {
        final room = FakeBeaconViewRoomRepository(
          roomState: roomWithPlan('Stale plan on NOW'),
        );
        addTearDown(room.dispose);
        final beaconRepo = TrackingBeaconRepository()
          ..fetchByIdHandler = (_) async => readableBeacon();
        addTearDown(beaconRepo.dispose);
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
        await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);

        room.roomState = roomWithPlan('Plan from coordinationChanged feed');
        room.emitRoomInvalidation(
          const BeaconRoomInvalidation(
            beaconId: beaconId,
            entityType: BeaconRoomEntityType.activityEvent,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 120));

        expect(
          cubit.state.beaconRoomCue?.currentLine,
          'Plan from coordinationChanged feed',
        );
        expect(
          beaconHudNowLine(l10n, cubit.state),
          'Plan from coordinationChanged feed',
        );
      },
    );

    test(
      'room_message invalidation refreshes NOW plan when chat updates plan text',
      () async {
        final room = FakeBeaconViewRoomRepository(
          roomState: roomWithPlan('Before chat-driven plan edit'),
        );
        addTearDown(room.dispose);
        final beaconRepo = TrackingBeaconRepository()
          ..fetchByIdHandler = (_) async => readableBeacon();
        addTearDown(beaconRepo.dispose);
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
        await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);

        room.roomState = roomWithPlan('After chat-driven plan edit');
        room.emitRoomInvalidation(
          const BeaconRoomInvalidation(
            beaconId: beaconId,
            entityType: BeaconRoomEntityType.roomMessage,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 120));

        expect(
          cubit.state.beaconRoomCue?.currentLine,
          'After chat-driven plan edit',
        );
      },
    );
  });
}
