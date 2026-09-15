import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_anchor_status.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_initial_load_test.dart';

/// GitHub #149 — request app-bar / header lifecycle status must track live
/// server state without a full page reload.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
  });
  const myProfile = Profile(id: 'Uauthor', displayName: 'Author');
  const beaconId = 'B149header';
  final l10n = lookupL10n(const Locale('en'));

  Beacon readableBeacon({BeaconStatus status = BeaconStatus.open}) => Beacon(
    id: beaconId,
    title: 'Lifecycle header proof',
    createdAt: DateTime.utc(2026, 9, 14),
    updatedAt: DateTime.utc(2026, 9, 14),
    status: status,
    canReadContent: true,
    author: myProfile,
  );

  group('Issue #149 header status live sync', () {
    test(
      'beacon RepositoryEventUpdate refreshes lifecycle for app-bar slots',
      () async {
        var current = readableBeacon();
        final beaconRepo = TrackingBeaconRepository()
          ..fetchByIdHandler = (_) async => current;
        addTearDown(beaconRepo.dispose);
        final cubit = BeaconViewCubit(
          id: beaconId,
          myProfile: myProfile,
          beaconViewCase: buildTestBeaconViewCase(beaconRepo: beaconRepo),
          effects: FakeUiEffectPort(),
        );
        addTearDown(cubit.close);
        await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);

        final before = beaconViewStatusSlots(l10n, cubit.state);
        expect(before.displayLine, contains(l10n.beaconPhaseLookingForHelpers));

        current = readableBeacon(status: BeaconStatus.enoughHelp);
        beaconRepo.emitUpdate(current);
        await Future<void>.delayed(const Duration(milliseconds: 80));

        expect(cubit.state.beacon.status, BeaconStatus.enoughHelp);
        final after = beaconViewStatusSlots(l10n, cubit.state);
        expect(
          after.displayLine,
          contains(l10n.beaconPhaseEnoughHelpInMotion),
        );
      },
    );

    test(
      'coordination_item room invalidation refetches beacon lifecycle for header',
      () async {
        var current = readableBeacon();
        final beaconRepo = TrackingBeaconRepository()
          ..fetchByIdHandler = (_) async => current;
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
        await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);
        final fetchesAfterLoad = beaconRepo.fetchByIdCalls;

        current = readableBeacon(status: BeaconStatus.closed);
        room.emitRoomInvalidation(
          const BeaconRoomInvalidation(
            beaconId: beaconId,
            entityType: BeaconRoomEntityType.coordinationItem,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 80));

        expect(beaconRepo.fetchByIdCalls, greaterThan(fetchesAfterLoad));
        expect(cubit.state.beacon.status, BeaconStatus.closed);
        final slots = beaconViewStatusSlots(l10n, cubit.state);
        expect(slots.displayLine, contains(l10n.beaconPhaseClosed));
      },
    );

    test(
      'help_offer invalidation keeps header lifecycle in sync (control)',
      () async {
        var current = readableBeacon();
        final forward = FakeBeaconViewForwardRepository();
        addTearDown(forward.dispose);
        final beaconRepo = TrackingBeaconRepository()
          ..fetchByIdHandler = (_) async => current;
        addTearDown(beaconRepo.dispose);
        final cubit = BeaconViewCubit(
          id: beaconId,
          myProfile: myProfile,
          beaconViewCase: buildTestBeaconViewCase(
            beaconRepo: beaconRepo,
            forward: forward,
          ),
          effects: FakeUiEffectPort(),
        );
        addTearDown(cubit.close);
        await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);

        current = readableBeacon(status: BeaconStatus.enoughHelp);
        forward.emitHelpOfferChange(const HelpOfferInvalidated(beaconId));
        await pumpUntil(
          cubit.stream,
          () => cubit.state.beacon.status == BeaconStatus.enoughHelp,
        );

        final slots = beaconViewStatusSlots(l10n, cubit.state);
        expect(slots.displayLine, contains(l10n.beaconPhaseEnoughHelpInMotion));
      },
    );
  });
}
