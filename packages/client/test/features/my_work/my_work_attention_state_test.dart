import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/my_work_beacon_attention.dart';
import 'package:tentura/domain/entity/beacon.dart';
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

void main() {
  test('populates attentionByBeacon and attentionLoaded', () async {
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

  // U17a. Opening a Request is a **clear** gesture (§4), applied by the detail
  // host after the Request displays. My Desk only zeroes the badge
  // optimistically; marking read here was the read axis standing in for the
  // clear axis (D02), and it fired before navigation, so even a forbidden
  // open burned the badge.
  test('openedBeacon zeroes unseenCount and marks nothing read', () async {
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
    expect(attentionRepo.markSeenForBeaconCalls, isEmpty);
    // It is not a clear either: the desk never clears before navigation.
    expect(attentionRepo.clearSnapshotCalls, isEmpty);

    await cubit.close();
  });

  // U15 (was: CHANGES IN U07b). There is no generic settlement path left to
  // test. What the desk can do to a Request from the card is clear one
  // **optional** event; obligations end through their source transitions
  // only (D04), and the server refuses the mutation that used to back Done
  // (U07b2).
  test('clearOptionalEvent writes the clear axis and never settles', () async {
    final optional = _receipt(id: 'r-opt', beaconId: 'b1');
    final obligation = _receipt(id: 'r-ob', beaconId: 'b1');
    final attentionRepo = StubAttentionRepository()
      ..myWorkAttentionResult = [
        MyWorkBeaconAttention(
          beaconId: 'b1',
          unseenCount: 2,
          latestUnseen: optional,
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

    await cubit.clearOptionalEvent('b1', 'r-opt');

    final entry = cubit.state.attentionByBeacon['b1']!;
    expect(entry.unseenCount, 1);
    expect(entry.latestUnseen, isNull);
    // The obligation is untouched: clearing an optional event says nothing
    // about a responsibility.
    expect(entry.liveObligations.map((r) => r.id), ['r-ob']);
    expect(attentionRepo.clearSnapshotCalls, ['r-opt']);
    expect(attentionRepo.clearCalls, hasLength(1));
    expect(attentionRepo.settleCalls, isEmpty);
    expect(attentionRepo.markSeenForBeaconCalls, isEmpty);

    await cubit.close();
  });

  test('clearOptionalEvent refuses to touch a live obligation', () async {
    final obligation = _receipt(id: 'r-ob', beaconId: 'b1');
    final attentionRepo = StubAttentionRepository()
      ..myWorkAttentionResult = [
        MyWorkBeaconAttention(
          beaconId: 'b1',
          unseenCount: 0,
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

    await cubit.clearOptionalEvent('b1', 'r-ob');

    expect(
      cubit.state.attentionByBeacon['b1']!.liveObligations.map((r) => r.id),
      ['r-ob'],
    );
    expect(attentionRepo.clearSnapshotCalls, isEmpty);
    expect(attentionRepo.clearCalls, isEmpty);
    expect(attentionRepo.settleCalls, isEmpty);

    await cubit.close();
  });
}
