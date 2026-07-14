import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/features/beacon/domain/exception.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_room/fake_coordination_item_case.dart';
import '../../support/test_realtime_sync.dart';
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
    test(
      'visible People profile change silently refreshes',
      () async {
        final realtime = buildTestRealtimeSync();
        addTearDown(realtime.port.dispose);
        final beaconRepo = TrackingBeaconRepository()
          ..fetchByIdHandler = (_) async => readableBeacon();
        final effects = FakeUiEffectPort();
        final case_ = buildTestBeaconViewCase(
          beaconRepo: beaconRepo,
          realtimeSyncCase: realtime.case_,
        );
        final cubit = BeaconViewCubit(
          id: beaconId,
          myProfile: myProfile,
          beaconViewCase: case_,
          coordinationItemCase: const FakeCoordinationItemCaseForRoom(),
          effects: effects,
        );
        addTearDown(cubit.close);
        await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);

        realtime.port.emitChange(
          const RealtimeEntityChange(
            kind: RealtimeEntityKind.profile,
            aggregateId: 'Uauthor',
            operation: RealtimeOperation.update,
            source: RealtimeChangeSource.serverInvalidation,
          ),
        );
        await pumpUntil(cubit.stream, () => beaconRepo.fetchByIdCalls >= 2);

        expect(effects.emitted, isEmpty);
      },
    );

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

    test('room admission waits for beacon context enrichment', () async {
      final beaconRepo = TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => readableBeacon();
      final case_ = buildTestBeaconViewCase(
        beaconRepo: beaconRepo,
        coordinationRepo: FakeBeaconViewCoordinationRepository(
          enrichmentDelay: const Duration(milliseconds: 500),
          rows: [
            (
              beaconId: beaconId,
              userId: myProfile.id,
              user: myProfile,
              message: 'I can help',
              helpType: null,
              status: 0,
              withdrawReason: null,
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
              responseType: null,
              responseUpdatedAt: null,
              responseAuthorUserId: null,
              roomAccess: RoomAccessBits.admitted,
              admissionAction: null,
              lastDeclineReason: null,
              lastRemoveReason: null,
            ),
          ],
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

      expect(cubit.state.beaconContextLoaded, isFalse);
      expect(cubit.state.isHelpOffered, isFalse);
      expect(cubit.state.canNavigateBeaconRoom, isFalse);

      await pumpUntil(
        cubit.stream,
        () =>
            cubit.state.beaconContextLoaded &&
            cubit.state.isHelpOffered &&
            cubit.state.canNavigateBeaconRoom,
      );
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

    test(
      'surfaces enrichment failure without clearing loaded beacon',
      () async {
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
      },
    );

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

    test(
      'fact card fetch denial does not surface error for loaded beacon',
      () async {
        final effects = FakeUiEffectPort();
        final beaconRepo = TrackingBeaconRepository()
          ..fetchByIdHandler = (_) async => readableBeacon();
        final case_ = buildTestBeaconViewCase(
          beaconRepo: beaconRepo,
          factCardsRepo: FakeBeaconViewFactCardRepository(
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
        expect(cubit.state.factCards, isEmpty);
        expect(effects.emitted.whereType<ShowError>(), isEmpty);
      },
    );

    test(
      'responsibility mark-seen denial does not surface error for loaded beacon',
      () async {
        final effects = FakeUiEffectPort();
        final beaconRepo = TrackingBeaconRepository()
          ..fetchByIdHandler = (_) async => readableBeacon();
        final case_ = buildTestBeaconViewCase(beaconRepo: beaconRepo);
        final cubit = BeaconViewCubit(
          id: beaconId,
          myProfile: myProfile,
          beaconViewCase: case_,
          coordinationItemCase: const FakeCoordinationItemCaseForRoom(
            markItemsSeenException: RemoteApiException(
              'You must be an admitted beacon participant',
            ),
          ),
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
        expect(effects.emitted.whereType<ShowError>(), isEmpty);
      },
    );

    test(
      'matching same-actor invalidation silently replaces beacon truth',
      () async {
        var current = readableBeacon();
        final effects = FakeUiEffectPort();
        final beaconRepo = TrackingBeaconRepository()
          ..fetchByIdHandler = (_) async => current;
        addTearDown(beaconRepo.dispose);
        final cubit = BeaconViewCubit(
          id: beaconId,
          myProfile: myProfile,
          beaconViewCase: buildTestBeaconViewCase(beaconRepo: beaconRepo),
          coordinationItemCase: const FakeCoordinationItemCaseForRoom(),
          effects: effects,
        );
        addTearDown(cubit.close);
        await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);

        current = current.copyWith(title: 'Closed elsewhere');
        beaconRepo.emitInvalidation(beaconId);
        await pumpUntil(
          cubit.stream,
          () => cubit.state.beacon.title == 'Closed elsewhere',
        );

        expect(effects.emitted, isEmpty);
      },
    );

    test('unrelated beacon invalidation does not refetch', () async {
      final beaconRepo = TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => readableBeacon();
      addTearDown(beaconRepo.dispose);
      final cubit = BeaconViewCubit(
        id: beaconId,
        myProfile: myProfile,
        beaconViewCase: buildTestBeaconViewCase(beaconRepo: beaconRepo),
        coordinationItemCase: const FakeCoordinationItemCaseForRoom(),
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);
      await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);
      final calls = beaconRepo.fetchByIdCalls;

      beaconRepo.emitInvalidation('Bother');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(beaconRepo.fetchByIdCalls, calls);
    });

    test('invalidation burst queues at most one full rerun', () async {
      final firstRefresh = Completer<Beacon>();
      final beaconRepo = TrackingBeaconRepository();
      beaconRepo.fetchByIdHandler = (_) {
        if (beaconRepo.fetchByIdCalls == 1) {
          return Future.value(readableBeacon());
        }
        if (beaconRepo.fetchByIdCalls == 2) return firstRefresh.future;
        return Future.value(readableBeacon().copyWith(title: 'Final'));
      };
      addTearDown(beaconRepo.dispose);
      final cubit = BeaconViewCubit(
        id: beaconId,
        myProfile: myProfile,
        beaconViewCase: buildTestBeaconViewCase(beaconRepo: beaconRepo),
        coordinationItemCase: const FakeCoordinationItemCaseForRoom(),
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);
      await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);

      beaconRepo.emitInvalidation(beaconId);
      await pumpUntilCondition(() => beaconRepo.fetchByIdCalls == 2);
      beaconRepo
        ..emitInvalidation(beaconId)
        ..emitInvalidation(beaconId);
      firstRefresh.complete(readableBeacon().copyWith(title: 'Intermediate'));
      await pumpUntil(
        cubit.stream,
        () => cubit.state.beacon.title == 'Final',
      );

      expect(beaconRepo.fetchByIdCalls, 3);
    });

    test('catch-up always performs a full silent snapshot', () async {
      var current = readableBeacon();
      final realtime = buildTestRealtimeSync();
      addTearDown(realtime.port.dispose);
      final beaconRepo = TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => current;
      addTearDown(beaconRepo.dispose);
      final cubit = BeaconViewCubit(
        id: beaconId,
        myProfile: myProfile,
        beaconViewCase: buildTestBeaconViewCase(
          beaconRepo: beaconRepo,
          realtimeSyncCase: realtime.case_,
        ),
        coordinationItemCase: const FakeCoordinationItemCaseForRoom(),
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);
      await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);

      current = current.copyWith(title: 'Caught up');
      realtime.port.emitCatchUp();
      await pumpUntil(
        cubit.stream,
        () => cubit.state.beacon.title == 'Caught up',
      );

      expect(beaconRepo.fetchByIdCalls, 2);
    });

    test(
      'failed background convergence keeps usable state without effect',
      () async {
        final effects = FakeUiEffectPort();
        final beaconRepo = TrackingBeaconRepository()
          ..fetchByIdHandler = (_) async => readableBeacon();
        addTearDown(beaconRepo.dispose);
        final cubit = BeaconViewCubit(
          id: beaconId,
          myProfile: myProfile,
          beaconViewCase: buildTestBeaconViewCase(beaconRepo: beaconRepo),
          coordinationItemCase: const FakeCoordinationItemCaseForRoom(),
          effects: effects,
        );
        addTearDown(cubit.close);
        await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);

        beaconRepo.fetchByIdHandler = (_) async => throw StateError('offline');
        beaconRepo.emitInvalidation(beaconId);
        await pumpUntilCondition(() => beaconRepo.fetchByIdCalls == 2);
        await Future<void>.delayed(Duration.zero);

        expect(cubit.state.beacon.title, 'Mutual friend beacon');
        expect(cubit.state.beaconContentLoaded, isTrue);
        expect(cubit.state.beaconUnavailable, isFalse);
        expect(effects.emitted, isEmpty);
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

Future<void> pumpUntilCondition(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw TimeoutException('Condition not met', timeout);
}
