import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/my_work_beacon_attention.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/home/domain/work_activity_redesign_gate.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';

import 'my_work_test_support.dart';

AttentionReceipt _receipt({
  required String id,
  required String beaconId,
}) =>
    AttentionReceipt(
      id: id,
      category: 'requestProgress',
      kind: 'commitmentAccepted',
      priority: 'normal',
      title: 'Title',
      body: 'Body',
      actionUrl: '/#/',
      createdAt: DateTime.utc(2026, 8, 5, 10),
      collapsedCount: 1,
      presentationPayloadJson: '{}',
      surface: AttentionSurface.myWork,
      beaconId: beaconId,
    );

void _registerWorkActivityRedesignGate(bool enabled) {
  if (GetIt.I.isRegistered<bool>(instanceName: workActivityRedesignGate)) {
    GetIt.I.unregister<bool>(instanceName: workActivityRedesignGate);
  }
  GetIt.I.registerSingleton<bool>(
    enabled,
    instanceName: workActivityRedesignGate,
  );
}

void main() {
  tearDown(() {
    if (GetIt.I.isRegistered<bool>(instanceName: workActivityRedesignGate)) {
      GetIt.I.unregister<bool>(instanceName: workActivityRedesignGate);
    }
  });

  test('gate off does not call myWorkAttention', () async {
    _registerWorkActivityRedesignGate(false);
    final attentionRepo = StubAttentionRepository();
    final cubit = MyWorkCubit(
      userId: 'user-1',
      myWorkCase: buildTestMyWorkCase(attentionRepository: attentionRepo),
    );

    await cubit.stream.firstWhere((s) => s.isSuccess);
    expect(attentionRepo.myWorkAttentionCallCount, 0);
    expect(cubit.state.attentionLoaded, isFalse);

    await cubit.close();
  });

  test('gate on populates attentionByBeacon and attentionLoaded', () async {
    _registerWorkActivityRedesignGate(true);
    final attentionRepo = StubAttentionRepository()
      ..myWorkAttentionResult = [
        const MyWorkBeaconAttention(
          beaconId: 'b1',
          unseenCount: 2,
        ),
      ];
    final repo = FakeMyWorkRepository()
      ..initResult = (
        authoredNonArchived: [Beacon.empty.copyWith(id: 'b1')],
        helpOfferedNonArchived: const [],
        obligationBeacons: const [],
        archivedCountHint: 0,
      );
    final cubit = MyWorkCubit(
      userId: 'user-1',
      myWorkCase: buildTestMyWorkCase(
        repo: repo,
        attentionRepository: attentionRepo,
      ),
    );

    await cubit.stream.firstWhere((s) => s.attentionLoaded);
    expect(attentionRepo.myWorkAttentionCallCount, 1);
    expect(cubit.state.attentionByBeacon['b1']?.unseenCount, 2);
    expect(cubit.state.nonArchivedCards, isNotEmpty);

    await cubit.close();
  });

  test('stale attention response is dropped', () async {
    _registerWorkActivityRedesignGate(true);
    final attentionRepo = StubAttentionRepository()
      ..myWorkAttentionResult = [
        const MyWorkBeaconAttention(
          beaconId: 'b1',
          unseenCount: 77,
        ),
      ];
    final repo = FakeMyWorkRepository()
      ..initResult = (
        authoredNonArchived: [Beacon.empty.copyWith(id: 'b1')],
        helpOfferedNonArchived: const [],
        obligationBeacons: const [],
        archivedCountHint: 0,
      )
      ..fetchArchivedDelay = const Duration(milliseconds: 120);
    final cubit = MyWorkCubit(
      userId: 'user-1',
      myWorkCase: buildTestMyWorkCase(
        repo: repo,
        attentionRepository: attentionRepo,
      ),
    );
    await cubit.stream.firstWhere((s) => s.attentionLoaded);
    expect(cubit.state.attentionByBeacon['b1']?.unseenCount, 77);

    attentionRepo.myWorkAttentionResult = [
      const MyWorkBeaconAttention(
        beaconId: 'b1',
        unseenCount: 11,
      ),
    ];

    cubit.setFilter(MyWorkFilter.archived);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await cubit.fetch(showLoading: false);
    await cubit.stream.firstWhere((s) => s.attentionLoaded);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(cubit.state.attentionByBeacon['b1']?.unseenCount, 11);
    expect(attentionRepo.myWorkAttentionCallCount, greaterThan(2));

    await cubit.close();
  });

  test('failed attention fetch keeps cards and attentionLoaded false', () async {
    _registerWorkActivityRedesignGate(true);
    final attentionRepo = StubAttentionRepository()
      ..myWorkAttentionError = Exception('attention failed');
    final repo = FakeMyWorkRepository()
      ..initResult = (
        authoredNonArchived: [Beacon.empty.copyWith(id: 'b1')],
        helpOfferedNonArchived: const [],
        obligationBeacons: const [],
        archivedCountHint: 0,
      );
    final cubit = MyWorkCubit(
      userId: 'user-1',
      myWorkCase: buildTestMyWorkCase(
        repo: repo,
        attentionRepository: attentionRepo,
      ),
    );

    await cubit.stream.firstWhere((s) => s.isSuccess);
    expect(cubit.state.nonArchivedCards, isNotEmpty);
    expect(cubit.state.attentionLoaded, isFalse);
    expect(cubit.state.attentionByBeacon, isEmpty);

    await cubit.close();
  });

  test('openedBeacon zeroes unseenCount and calls markSeenForBeacon', () async {
    _registerWorkActivityRedesignGate(true);
    final obligation = _receipt(id: 'r1', beaconId: 'b1');
    final latest = _receipt(id: 'r2', beaconId: 'b1');
    final attentionRepo = StubAttentionRepository()
      ..myWorkAttentionResult = [
        MyWorkBeaconAttention(
          beaconId: 'b1',
          unseenCount: 3,
          latestUnseen: latest,
          liveObligations: [obligation],
        ),
      ];
    final repo = FakeMyWorkRepository()
      ..initResult = (
        authoredNonArchived: [Beacon.empty.copyWith(id: 'b1')],
        helpOfferedNonArchived: const [],
        obligationBeacons: const [],
        archivedCountHint: 0,
      );
    final cubit = MyWorkCubit(
      userId: 'user-1',
      myWorkCase: buildTestMyWorkCase(
        repo: repo,
        attentionRepository: attentionRepo,
      ),
    );
    await cubit.stream.firstWhere((s) => s.attentionLoaded);

    await cubit.openedBeacon('b1');

    final entry = cubit.state.attentionByBeacon['b1']!;
    expect(entry.unseenCount, 0);
    expect(entry.liveObligations, [obligation]);
    expect(entry.latestUnseen, latest);
    expect(attentionRepo.markSeenForBeaconCalls, ['b1']);

    await cubit.close();
  });
}
