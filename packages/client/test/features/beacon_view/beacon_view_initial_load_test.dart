import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/features/beacon/domain/exception.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_room/fake_coordination_item_case.dart';
import 'beacon_view_case_test_support.dart';

void main() {
  const myProfile = Profile(id: 'Uviewer', displayName: 'Viewer');
  const beaconId = 'Bmutual01';

  Beacon readableBeacon() => Beacon(
    id: beaconId,
    title: 'Mutual friend beacon',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    status: BeaconStatus.open,
    canReadContent: true,
    author: const Profile(id: 'Uauthor', displayName: 'Author'),
  );

  group('BeaconViewCubit initial load', () {
    test('shows beacon content before enrichment completes', () async {
      final beaconRepo = TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => readableBeacon();
      final case_ = buildTestBeaconViewCase(
        beaconRepo: beaconRepo,
        coordinationRepo: FakeBeaconViewCoordinationRepository(
          enrichmentDelay: const Duration(milliseconds: 500),
        ),
      );
      final cubit = BeaconViewCubit(
        id: beaconId,
        myProfile: myProfile,
        beaconViewCase: case_,
        coordinationItemCase: const FakeCoordinationItemCaseForRoom(),
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);

      await pumpUntil(
        cubit.stream,
        () => cubit.state.beaconContentLoaded,
      );

      expect(cubit.state.beaconUnavailable, isFalse);
      expect(cubit.state.beacon.id, beaconId);
      expect(cubit.state.beacon.title, 'Mutual friend beacon');
    });

    test('retries once when first fetch returns unavailable', () async {
      final beaconRepo = TrackingBeaconRepository();
      beaconRepo.fetchByIdHandler = (_) async {
        if (beaconRepo.fetchByIdCalls == 1) {
          throw BeaconFetchException(beaconId);
        }
        return readableBeacon();
      };
      final case_ = buildTestBeaconViewCase(beaconRepo: beaconRepo);
      final cubit = BeaconViewCubit(
        id: beaconId,
        myProfile: myProfile,
        beaconViewCase: case_,
        coordinationItemCase: const FakeCoordinationItemCaseForRoom(),
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);

      await pumpUntil(
        cubit.stream,
        () => cubit.state.beaconContentLoaded,
      );

      expect(beaconRepo.fetchByIdCalls, 2);
      expect(cubit.state.beaconUnavailable, isFalse);
    });

    test('surfaces enrichment failure without clearing loaded beacon', () async {
      final effects = FakeUiEffectPort();
      final beaconRepo = TrackingBeaconRepository();
      beaconRepo.fetchByIdHandler = (_) async => readableBeacon();
      final case_ = buildTestBeaconViewCase(
        beaconRepo: beaconRepo,
        coordinationRepo: FakeBeaconViewCoordinationRepository(
          enrichmentError: StateError('coordination timeout'),
        ),
      );
      final cubit = BeaconViewCubit(
        id: beaconId,
        myProfile: myProfile,
        beaconViewCase: case_,
        coordinationItemCase: const FakeCoordinationItemCaseForRoom(),
        effects: effects,
      );
      addTearDown(cubit.close);

      await pumpUntil(
        cubit.stream,
        () => cubit.state.beaconContentLoaded,
      );
      await pumpUntilEffects(
        () => effects.emitted.any((e) => e is ShowError),
      );

      expect(cubit.state.beacon.id, beaconId);
      expect(cubit.state.beaconContentLoaded, isTrue);
      expect(cubit.state.status, isA<StateIsSuccess>());
    });

    test(
      'room activity fetch denial does not surface error for loaded beacon',
      () async {
        final effects = FakeUiEffectPort();
        final beaconRepo = TrackingBeaconRepository()
          ..fetchByIdHandler = (_) async => readableBeacon();
        final case_ = buildTestBeaconViewCase(
          beaconRepo: beaconRepo,
          activityEventsRepo: FakeBeaconViewActivityEventRepository(
            listError: const RemoteApiException('Room access required'),
          ),
        );
        final cubit = BeaconViewCubit(
          id: beaconId,
          myProfile: myProfile,
          beaconViewCase: case_,
          coordinationItemCase: const FakeCoordinationItemCaseForRoom(),
          effects: effects,
        );
        addTearDown(cubit.close);

        await pumpUntil(
          cubit.stream,
          () => cubit.state.beaconContentLoaded,
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(cubit.state.beacon.id, beaconId);
        expect(cubit.state.beaconContentLoaded, isTrue);
        expect(cubit.state.status, isA<StateIsSuccess>());
        expect(cubit.state.roomActivityEvents, isEmpty);
        expect(effects.emitted.whereType<ShowError>(), isEmpty);
      },
    );
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

Future<void> pumpUntilEffects(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw TimeoutException('Effect condition not met', timeout);
}
