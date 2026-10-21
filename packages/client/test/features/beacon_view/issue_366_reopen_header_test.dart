import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/domain/exception.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_anchor_status.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/closure/domain/entity/beacon_close_result.dart';
import 'package:tentura/features/closure/domain/entity/closure_role.dart';
import 'package:tentura/features/closure/domain/entity/closure_state.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_initial_load_test.dart';

/// Reopen mutation; [fail] makes the mutation itself fail. While the final
/// check is live it serves a closure snapshot, like the server does.
class _ReopenClosureRepository extends FakeBeaconViewClosureRepository {
  _ReopenClosureRepository({this.fail = false});

  final bool fail;
  bool reopened = false;
  int reopenCalls = 0;

  @override
  Future<BeaconLifecycleMutationResult> beaconReopen(String beaconId) async {
    reopenCalls++;
    if (fail) throw Exception('reopen failed');
    reopened = true;
    return BeaconLifecycleMutationResult(beaconId: beaconId, state: 1);
  }

  @override
  Future<ClosureState> fetchState(String beaconId) async {
    if (reopened) throw const BeaconFetchException();
    return ClosureState(
      epoch: 1,
      status: BeaconStatus.reviewOpen.smallintValue,
      role: ClosureRole.author,
      members: const [],
      closesAt: DateTime.utc(2026, 10, 20),
      canReopen: true,
    );
  }
}

/// Runs the production `ClosureRepository.beaconReopen` sequence (read the
/// epoch, send the reopen) over a fake wire. Like the server, the closure
/// state is gone once reopened: a read answers 1002 "Id not found".
class _WireClosureRepository extends ClosureRepository {
  _WireClosureRepository(super._remoteApiService);

  bool reopened = false;
  int reopenCalls = 0;
  int readsAfterReopen = 0;

  @override
  Future<void> reopen({
    required String beaconId,
    required int expectedEpoch,
  }) async {
    reopenCalls++;
    reopened = true;
  }

  @override
  Future<ClosureState> fetchState(String beaconId) async {
    if (reopened) {
      readsAfterReopen++;
      throw RemoteApiException('Id not found: [$beaconId]', code: '1002');
    }
    return ClosureState(
      epoch: 1,
      status: BeaconStatus.reviewOpen.smallintValue,
      role: ClosureRole.author,
      members: const [],
      closesAt: DateTime.utc(2026, 10, 20),
      canReopen: true,
    );
  }
}

/// Mirrors production `BeaconRepository.refreshAndNotify`: it re-reads the
/// Request and emits the update, so a failing read ("database busy") throws
/// out of `BeaconViewCase.beaconReopen` right after the reopen mutation.
class _ProdLikeBeaconRepository extends TrackingBeaconRepository {
  @override
  Future<void> refreshAndNotify(String id) async {
    refreshAndNotifyCalls.add(id);
    emitUpdate(await fetchBeaconById(id));
  }
}

/// Production retries a failed Request read once after 300 ms
/// (`BeaconViewCubit._fetchBeaconByIdOrRetry`); errors from such a retry
/// land after this window at the latest.
const _retrySettle = Duration(milliseconds: 400);

/// GitHub #366: after Reopen from the final check the Request is back to
/// coordinating (Open) and the app-bar status line says so at once, with no
/// stale "Wrapping up" / "Final check" left behind.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  const myProfile = Profile(id: 'Uauthor366', displayName: 'Author');
  const beaconId = 'B366reopen';
  final l10n = lookupL10n(const Locale('en'));

  Beacon beacon(BeaconStatus status) => Beacon(
    id: beaconId,
    title: 'Couch to the new flat',
    createdAt: DateTime.utc(2026, 10, 12),
    updatedAt: DateTime.utc(2026, 10, 12),
    status: status,
    author: myProfile,
  );

  Future<BeaconViewCubit> loadedCubit({
    required TrackingBeaconRepository beaconRepo,
    required ClosureRepository closureRepo,
    FakeUiEffectPort? effects,
  }) async {
    final cubit = BeaconViewCubit(
      id: beaconId,
      myProfile: myProfile,
      beaconViewCase: buildTestBeaconViewCase(
        beaconRepo: beaconRepo,
        closureRepo: closureRepo,
      ),
      effects: effects ?? FakeUiEffectPort(),
    );
    addTearDown(cubit.close);
    await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);
    await pumpEventQueue();
    // Precondition: the header reads the final check before Reopen.
    expect(cubit.state.beacon.status, BeaconStatus.reviewOpen);
    expect(cubit.state.closureState, isNotNull);
    expect(
      beaconViewStatusSlots(l10n, cubit.state).displayLine,
      contains(l10n.beaconPhaseWrappingUp),
    );
    return cubit;
  }

  group('Issue #366 Reopen refreshes the header at once', () {
    test(
      'a successful Reopen leaves the final check even when the refresh '
      'read fails, with no error claiming the Reopen failed',
      () async {
        final effects = FakeUiEffectPort();
        final closureRepo = _ReopenClosureRepository();
        var readsAfterReopen = 0;
        final beaconRepo = _ProdLikeBeaconRepository()
          // Like the busy-database replies in the report: once the Request
          // is reopened, every read of it fails.
          ..fetchByIdHandler = (_) async {
            if (!closureRepo.reopened) return beacon(BeaconStatus.reviewOpen);
            readsAfterReopen++;
            throw const BeaconFetchException();
          };
        addTearDown(beaconRepo.dispose);
        final cubit = await loadedCubit(
          beaconRepo: beaconRepo,
          closureRepo: closureRepo,
          effects: effects,
        );

        await cubit.reopenBeacon();
        await pumpEventQueue();
        await Future<void>.delayed(_retrySettle);

        expect(closureRepo.reopenCalls, 1);
        expect(closureRepo.reopened, isTrue);
        // The mutation succeeded: the status is applied locally.
        expect(cubit.state.beacon.status, BeaconStatus.open);
        final line = beaconViewStatusSlots(l10n, cubit.state).displayLine;
        expect(line, isNot(contains(l10n.beaconPhaseWrappingUp)));
        expect(line, isNot(contains(l10n.beaconPhaseNeedsMoreHelp)));
        expect(cubit.state.isLoading, isFalse);
        // The final-check snapshot belongs to the cancelled epoch.
        expect(cubit.state.closureState, isNull);
        expect(
          effects.emitted.whereType<ShowError>(),
          isEmpty,
          reason:
              'the Reopen went through; a refresh hiccup must not read '
              'as "Reopen failed"',
        );
        // One refresh read plus its one retry; nothing more (owner review).
        expect(readsAfterReopen, 2);
      },
    );

    test(
      'the header shows the Request back in coordination as soon as the '
      'Reopen mutation succeeds, before the refresh read answers',
      () async {
        final closureRepo = _ReopenClosureRepository();
        final readGate = Completer<void>();
        addTearDown(() {
          if (!readGate.isCompleted) readGate.complete();
        });
        final beaconRepo = _ProdLikeBeaconRepository()
          ..fetchByIdHandler = (_) async {
            if (!closureRepo.reopened) return beacon(BeaconStatus.reviewOpen);
            // The refresh read hangs (slow network) until released.
            await readGate.future;
            return beacon(BeaconStatus.open);
          };
        addTearDown(beaconRepo.dispose);
        final cubit = await loadedCubit(
          beaconRepo: beaconRepo,
          closureRepo: closureRepo,
        );

        final reopening = cubit.reopenBeacon();
        await pumpUntilCondition(() => closureRepo.reopenCalls == 1);
        await pumpEventQueue();

        expect(readGate.isCompleted, isFalse);
        expect(cubit.state.beacon.status, BeaconStatus.open);
        expect(cubit.state.isLoading, isFalse);
        expect(cubit.state.closureState, isNull);
        final line = beaconViewStatusSlots(l10n, cubit.state).displayLine;
        expect(line, isNot(contains(l10n.beaconPhaseWrappingUp)));
        expect(line, isNot(contains(l10n.beaconPhaseNeedsMoreHelp)));

        readGate.complete();
        await reopening;
      },
    );

    test(
      'after Reopen one refresh read runs; when it fails its one retry '
      'brings the refreshed Request, with no further reads',
      () async {
        final effects = FakeUiEffectPort();
        final closureRepo = _ReopenClosureRepository();
        final refreshed = beacon(BeaconStatus.open).copyWith(
          title: 'Couch to the new flat (van booked)',
          updatedAt: DateTime.utc(2026, 10, 13),
        );
        var readsAfterReopen = 0;
        final beaconRepo = _ProdLikeBeaconRepository()
          ..fetchByIdHandler = (_) async {
            if (!closureRepo.reopened) return beacon(BeaconStatus.reviewOpen);
            readsAfterReopen++;
            // "Database busy" on the first read only.
            if (readsAfterReopen == 1) throw const BeaconFetchException();
            return refreshed;
          };
        addTearDown(beaconRepo.dispose);
        final cubit = await loadedCubit(
          beaconRepo: beaconRepo,
          closureRepo: closureRepo,
          effects: effects,
        );

        await cubit.reopenBeacon();
        await pumpUntilCondition(
          () => cubit.state.beacon.title == refreshed.title,
        );
        // Room for any stray extra read (or its 300 ms retry) to show up.
        await Future<void>.delayed(_retrySettle);
        await pumpEventQueue();

        expect(closureRepo.reopenCalls, 1);
        expect(cubit.state.beacon.status, BeaconStatus.open);
        expect(cubit.state.beacon.title, refreshed.title);
        expect(cubit.state.isLoading, isFalse);
        expect(
          readsAfterReopen,
          2,
          reason: 'one refresh read that failed, then exactly one retry',
        );
        expect(effects.emitted.whereType<ShowError>(), isEmpty);
      },
    );

    test(
      'after Reopen a refresh read that succeeds is the only read',
      () async {
        final closureRepo = _ReopenClosureRepository();
        final refreshed = beacon(BeaconStatus.open).copyWith(
          title: 'Couch to the new flat (van booked)',
        );
        var readsAfterReopen = 0;
        final beaconRepo = _ProdLikeBeaconRepository()
          ..fetchByIdHandler = (_) async {
            if (!closureRepo.reopened) return beacon(BeaconStatus.reviewOpen);
            readsAfterReopen++;
            return refreshed;
          };
        addTearDown(beaconRepo.dispose);
        final cubit = await loadedCubit(
          beaconRepo: beaconRepo,
          closureRepo: closureRepo,
        );

        await cubit.reopenBeacon();
        await pumpUntilCondition(
          () => cubit.state.beacon.title == refreshed.title,
        );
        await Future<void>.delayed(_retrySettle);
        await pumpEventQueue();

        expect(cubit.state.beacon.status, BeaconStatus.open);
        expect(
          readsAfterReopen,
          1,
          reason:
              'no second read from the reopen step, and the screen\'s own '
              'notify must not trigger another full refresh',
        );
      },
    );

    test(
      'guard: other screens hear the Request is Open again after Reopen',
      () async {
        final closureRepo = _ReopenClosureRepository();
        final beaconRepo = _ProdLikeBeaconRepository()
          ..fetchByIdHandler = (_) async => beacon(
            closureRepo.reopened ? BeaconStatus.open : BeaconStatus.reviewOpen,
          );
        addTearDown(beaconRepo.dispose);
        final cubit = await loadedCubit(
          beaconRepo: beaconRepo,
          closureRepo: closureRepo,
        );
        final updates = <Beacon>[];
        final sub = beaconRepo.changes.listen((e) {
          if (e is RepositoryEventUpdate<Beacon>) updates.add(e.value);
        });
        addTearDown(sub.cancel);

        await cubit.reopenBeacon();
        await pumpUntilCondition(
          () => updates.any(
            (b) => b.id == beaconId && b.status == BeaconStatus.open,
          ),
        );

        expect(cubit.state.beacon.status, BeaconStatus.open);
        expect(
          beaconViewStatusSlots(l10n, cubit.state).displayLine,
          isNot(contains(l10n.beaconPhaseWrappingUp)),
        );
      },
    );

    test(
      'Reopen shows no error when the closure state is already gone '
      '(1002 Id not found) right after the reopen',
      () async {
        final effects = FakeUiEffectPort();
        // Never called on the wire: the repository's reads are faked.
        final remote = RemoteApiService(
          const Env(),
          const WebSocketClientRealtimeSocketFactory(),
        );
        addTearDown(remote.close);
        final closureRepo = _WireClosureRepository(remote);
        final beaconRepo = _ProdLikeBeaconRepository()
          ..fetchByIdHandler = (_) async => beacon(
            closureRepo.reopened ? BeaconStatus.open : BeaconStatus.reviewOpen,
          );
        addTearDown(beaconRepo.dispose);
        final cubit = await loadedCubit(
          beaconRepo: beaconRepo,
          closureRepo: closureRepo,
          effects: effects,
        );

        await cubit.reopenBeacon();
        await pumpEventQueue();
        await Future<void>.delayed(_retrySettle);

        expect(closureRepo.reopenCalls, 1);
        expect(
          effects.emitted.whereType<ShowError>(),
          isEmpty,
          reason:
              'no closure epoch after a reopen is the normal state, not an '
              'error to flash',
        );
        expect(cubit.state.beacon.status, BeaconStatus.open);
        expect(cubit.state.isLoading, isFalse);
        expect(cubit.state.closureState, isNull);
        expect(
          beaconViewStatusSlots(l10n, cubit.state).displayLine,
          isNot(contains(l10n.beaconPhaseWrappingUp)),
        );
        expect(closureRepo.readsAfterReopen, 0);
      },
    );

    test(
      'guard: a failed Reopen keeps the final check and reports the error',
      () async {
        final effects = FakeUiEffectPort();
        final closureRepo = _ReopenClosureRepository(fail: true);
        final beaconRepo = _ProdLikeBeaconRepository()
          ..fetchByIdHandler = (_) async => beacon(BeaconStatus.reviewOpen);
        addTearDown(beaconRepo.dispose);
        final cubit = await loadedCubit(
          beaconRepo: beaconRepo,
          closureRepo: closureRepo,
          effects: effects,
        );

        await cubit.reopenBeacon();
        await pumpEventQueue();

        expect(closureRepo.reopenCalls, 1);
        expect(cubit.state.beacon.status, BeaconStatus.reviewOpen);
        expect(
          beaconViewStatusSlots(l10n, cubit.state).displayLine,
          contains(l10n.beaconPhaseWrappingUp),
        );
        expect(cubit.state.isLoading, isFalse);
        expect(effects.emitted.whereType<ShowError>(), isNotEmpty);
      },
    );
  });
}
