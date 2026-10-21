import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/features/beacon/domain/exception.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/closure/domain/entity/beacon_close_result.dart';
import 'package:tentura/features/closure/domain/entity/closure_role.dart';
import 'package:tentura/features/closure/domain/entity/closure_state.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_initial_load_test.dart';

/// Cancel / Close now; [fail] makes the mutation itself fail. While the
/// final check is live it serves a closure snapshot, like the server does.
class _LifecycleClosureRepository extends FakeBeaconViewClosureRepository {
  _LifecycleClosureRepository({this.fail = false});

  final bool fail;
  bool mutated = false;
  int cancelCalls = 0;
  int closeNowCalls = 0;

  @override
  Future<BeaconLifecycleMutationResult> beaconCancel(String beaconId) async {
    cancelCalls++;
    if (fail) throw Exception('cancel failed');
    mutated = true;
    return BeaconLifecycleMutationResult(
      beaconId: beaconId,
      state: BeaconStatus.cancelled.smallintValue,
    );
  }

  @override
  Future<BeaconLifecycleMutationResult> beaconCloseNow(String beaconId) async {
    closeNowCalls++;
    if (fail) throw Exception('close now failed');
    mutated = true;
    return BeaconLifecycleMutationResult(
      beaconId: beaconId,
      state: BeaconStatus.closed.smallintValue,
    );
  }

  @override
  Future<ClosureState> fetchState(String beaconId) async {
    if (mutated) throw const BeaconFetchException();
    return ClosureState(
      epoch: 1,
      status: BeaconStatus.reviewOpen.smallintValue,
      role: ClosureRole.author,
      members: const [],
      closesAt: DateTime.utc(2026, 10, 20),
      canCloseNow: true,
    );
  }
}

/// Mirrors production `BeaconRepository.refreshAndNotify`: it re-reads the
/// Request and emits the update, so a failing read ("database busy") throws.
class _ProdLikeBeaconRepository extends TrackingBeaconRepository {
  @override
  Future<void> refreshAndNotify(String id) async {
    refreshAndNotifyCalls.add(id);
    emitUpdate(await fetchBeaconById(id));
  }
}

/// Production retries a failed Request read once after 300 ms.
const _retrySettle = Duration(milliseconds: 400);

/// GitHub #611 (#366 follow-up): Cancel and Close now had the shape Reopen
/// had — a read after the mutation that, when it failed, was shown as an
/// error although the Request was already cancelled / closed.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  const myProfile = Profile(id: 'Uauthor611', displayName: 'Author');
  const beaconId = 'B611lifecycle';

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
    required _LifecycleClosureRepository closureRepo,
    required BeaconStatus initial,
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
    expect(cubit.state.beacon.status, initial);
    return cubit;
  }

  /// After the mutation every read of the Request fails; counts those reads.
  _ProdLikeBeaconRepository failingAfterMutation(
    _LifecycleClosureRepository closureRepo,
    BeaconStatus initial,
    void Function() onReadAfter,
  ) {
    final repo = _ProdLikeBeaconRepository()
      ..fetchByIdHandler = (_) async {
        if (!closureRepo.mutated) return beacon(initial);
        onReadAfter();
        throw const BeaconFetchException();
      };
    addTearDown(repo.dispose);
    return repo;
  }

  group('Issue #611 Cancel shows no false error', () {
    test(
      'a successful Cancel shows the Request cancelled even when the '
      'refresh read fails, with no error claiming the Cancel failed',
      () async {
        final effects = FakeUiEffectPort();
        final closureRepo = _LifecycleClosureRepository();
        var readsAfter = 0;
        final beaconRepo = failingAfterMutation(
          closureRepo,
          BeaconStatus.open,
          () => readsAfter++,
        );
        final cubit = await loadedCubit(
          beaconRepo: beaconRepo,
          closureRepo: closureRepo,
          initial: BeaconStatus.open,
          effects: effects,
        );

        await cubit.cancelBeacon();
        await pumpEventQueue();
        await Future<void>.delayed(_retrySettle);

        expect(closureRepo.cancelCalls, 1);
        expect(cubit.state.beacon.status, BeaconStatus.cancelled);
        expect(cubit.state.isLoading, isFalse);
        expect(
          effects.emitted.whereType<ShowError>(),
          isEmpty,
          reason: 'the Cancel went through; a refresh hiccup is not an error',
        );
        // One refresh read plus its one retry; nothing more.
        expect(readsAfter, 2);
      },
    );

    test('guard: other screens hear the Request is cancelled', () async {
      final closureRepo = _LifecycleClosureRepository();
      final beaconRepo = _ProdLikeBeaconRepository()
        ..fetchByIdHandler = (_) async => beacon(
          closureRepo.mutated ? BeaconStatus.cancelled : BeaconStatus.open,
        );
      addTearDown(beaconRepo.dispose);
      final cubit = await loadedCubit(
        beaconRepo: beaconRepo,
        closureRepo: closureRepo,
        initial: BeaconStatus.open,
      );
      final updates = <Beacon>[];
      final sub = beaconRepo.changes.listen((e) {
        if (e is RepositoryEventUpdate<Beacon>) updates.add(e.value);
      });
      addTearDown(sub.cancel);

      await cubit.cancelBeacon();
      await pumpUntilCondition(
        () => updates.any((b) => b.status == BeaconStatus.cancelled),
      );

      expect(cubit.state.beacon.status, BeaconStatus.cancelled);
    });

    test('guard: a failed Cancel keeps the Request and reports it', () async {
      final effects = FakeUiEffectPort();
      final closureRepo = _LifecycleClosureRepository(fail: true);
      final beaconRepo = _ProdLikeBeaconRepository()
        ..fetchByIdHandler = (_) async => beacon(BeaconStatus.open);
      addTearDown(beaconRepo.dispose);
      final cubit = await loadedCubit(
        beaconRepo: beaconRepo,
        closureRepo: closureRepo,
        initial: BeaconStatus.open,
        effects: effects,
      );

      await cubit.cancelBeacon();
      await pumpEventQueue();

      expect(closureRepo.cancelCalls, 1);
      expect(cubit.state.beacon.status, BeaconStatus.open);
      expect(cubit.state.isLoading, isFalse);
      expect(effects.emitted.whereType<ShowError>(), isNotEmpty);
    });
  });

  group('Issue #611 Close now shows no false error', () {
    test(
      'a successful Close now shows the Request closed even when the '
      'refresh read fails, with no error claiming the close failed',
      () async {
        final effects = FakeUiEffectPort();
        final closureRepo = _LifecycleClosureRepository();
        var readsAfter = 0;
        final beaconRepo = failingAfterMutation(
          closureRepo,
          BeaconStatus.reviewOpen,
          () => readsAfter++,
        );
        final cubit = await loadedCubit(
          beaconRepo: beaconRepo,
          closureRepo: closureRepo,
          initial: BeaconStatus.reviewOpen,
          effects: effects,
        );
        expect(cubit.state.closureState, isNotNull);

        await cubit.closeBeaconNow();
        await pumpEventQueue();
        await Future<void>.delayed(_retrySettle);

        expect(closureRepo.closeNowCalls, 1);
        expect(cubit.state.beacon.status, BeaconStatus.closed);
        expect(cubit.state.isLoading, isFalse);
        // The final-check snapshot belongs to the finished final check.
        expect(cubit.state.closureState, isNull);
        expect(
          effects.emitted.whereType<ShowError>(),
          isEmpty,
          reason:
              'the Close now went through; a refresh hiccup is not an '
              'error',
        );
        expect(readsAfter, 2);
      },
    );

    test('guard: a failed Close now keeps the final check and reports '
        'it', () async {
      final effects = FakeUiEffectPort();
      final closureRepo = _LifecycleClosureRepository(fail: true);
      final beaconRepo = _ProdLikeBeaconRepository()
        ..fetchByIdHandler = (_) async => beacon(BeaconStatus.reviewOpen);
      addTearDown(beaconRepo.dispose);
      final cubit = await loadedCubit(
        beaconRepo: beaconRepo,
        closureRepo: closureRepo,
        initial: BeaconStatus.reviewOpen,
        effects: effects,
      );

      await cubit.closeBeaconNow();
      await pumpEventQueue();

      expect(closureRepo.closeNowCalls, 1);
      expect(cubit.state.beacon.status, BeaconStatus.reviewOpen);
      expect(cubit.state.closureState, isNotNull);
      expect(cubit.state.isLoading, isFalse);
      expect(effects.emitted.whereType<ShowError>(), isNotEmpty);
    });
  });
}
