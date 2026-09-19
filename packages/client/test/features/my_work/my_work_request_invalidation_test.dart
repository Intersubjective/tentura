import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/attention/entity/my_work_beacon_attention.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';

import 'my_work_test_support.dart';
import '../../support/test_realtime_sync.dart';

void main() {
  test('a surface move refreshes the desk without a manual reload', () async {
    final realtime = buildTestRealtimeSync();
    final attentionRepo = StubAttentionRepository()
      ..myWorkAttentionResult = [
        const MyWorkBeaconAttention(beaconId: 'moved', unseenCount: 1),
      ];
    final repo = FakeMyWorkRepository()
      ..initResult = (
        authoredNonArchived: [Beacon.empty.copyWith(id: 'moved')],
        helpOfferedNonArchived: const [],
        obligationBeacons: const [],
        archivedCountHint: 0,
      );
    final cubit = MyWorkCubit(
      userId: 'user-1',
      myWorkCase: buildTestMyWorkCase(
        repo: repo,
        attentionRepository: attentionRepo,
        realtimeSyncCase: realtime.case_,
      ),
    );
    await cubit.stream.firstWhere((s) => s.attentionLoaded);
    expect(
      cubit.state.nonArchivedCards.map((c) => c.beaconId),
      ['moved'],
    );
    final fetchesBefore = repo.fetchInitCallCount;

    // Every state the desk passes through while the Request leaves it. The
    // endpoints are the easy part; the interleaving is where a Request shows
    // up twice or vanishes from both places (U13c).
    final seen = <List<MyWorkCardViewModel>>[];
    final sub = cubit.stream.listen(
      (s) => seen.add([...s.nonArchivedCards, ...s.archivedCards]),
    );
    addTearDown(sub.cancel);

    // The Request changed hands: it is no longer the viewer's desk work.
    repo.initResult = (
      authoredNonArchived: const <Beacon>[],
      helpOfferedNonArchived: const [],
      obligationBeacons: const [],
      archivedCountHint: 0,
    );
    attentionRepo.myWorkAttentionResult = const [];

    realtime.port.emitChange(
      const RealtimeEntityChange(
        kind: RealtimeEntityKind.beacon,
        operation: RealtimeOperation.update,
        source: RealtimeChangeSource.serverInvalidation,
        aggregateId: 'moved',
      ),
    );

    await cubit.stream.firstWhere((s) => s.nonArchivedCards.isEmpty);

    expect(repo.fetchInitCallCount, greaterThan(fetchesBefore));
    expect(cubit.state.nonArchivedCards, isEmpty);
    expect(cubit.state.archivedCards, isEmpty);

    // Never on two surfaces at once, and never announced as gone and back.
    var left = false;
    for (final cards in seen) {
      final ids = cards.map((c) => c.beaconId).toList();
      expect(ids.length, ids.toSet().length, reason: 'duplicated: $ids');
      if (ids.contains('moved')) {
        expect(left, isFalse, reason: 'came back after leaving: $seen');
      } else {
        left = true;
      }
    }
    expect(left, isTrue);

    await cubit.close();
  });

  test('an invalidation for a Request the desk does not hold is harmless', () async {
    final realtime = buildTestRealtimeSync();
    final repo = FakeMyWorkRepository()
      ..initResult = (
        authoredNonArchived: [Beacon.empty.copyWith(id: 'mine')],
        helpOfferedNonArchived: const [],
        obligationBeacons: const [],
        archivedCountHint: 0,
      );
    final cubit = MyWorkCubit(
      userId: 'user-1',
      myWorkCase: buildTestMyWorkCase(
        repo: repo,
        attentionRepository: StubAttentionRepository(),
        realtimeSyncCase: realtime.case_,
      ),
    );
    await cubit.stream.firstWhere((s) => s.attentionLoaded);

    realtime.port.emitChange(
      const RealtimeEntityChange(
        kind: RealtimeEntityKind.beacon,
        operation: RealtimeOperation.update,
        source: RealtimeChangeSource.serverInvalidation,
        aggregateId: 'someone-elses',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(cubit.state.nonArchivedCards.map((c) => c.beaconId), ['mine']);
    expect(cubit.state.loadError, isNull);

    await cubit.close();
  });
}
