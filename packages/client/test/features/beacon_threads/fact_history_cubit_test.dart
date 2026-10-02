// tentura-617.29: FactHistoryCubit — issue #181 plan §14.2 (cubit row) /
// §14.6 (history sheet data flow). A thin single-repository cubit over
// `BeaconFactCardRepository.revisions` / `.restore`; it must never touch
// RoomCubit. `baseRevisionSeq` is fixed at construction time (the revision
// the sheet opened with per plan §14.6), never refetched.

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/domain/entity/beacon_fact_history_entry.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/fact_history_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';

const _kBeaconId = 'b-fact-history-test';
const _kFactCardId = 'fact-history-1';

BeaconFactHistoryEntry _entry({
  required String id,
  required int seq,
  String text = 'text',
}) => BeaconFactHistoryEdited(
  id: id,
  factCardId: _kFactCardId,
  seq: seq,
  factText: text,
  actorId: 'actor-1',
  actorTitle: 'Actor One',
  createdAt: DateTime.utc(2026, 1, 1, seq),
);

/// Records `revisions`/`restore` calls; serves [pages] one per successive
/// `revisions` call (the last page repeats once exhausted).
class _FakeFactHistoryRepository extends Fake
    implements BeaconFactCardRepository {
  List<BeaconFactHistoryPage> pages = const [];

  /// When set, every subsequent `revisions` call throws this instead of
  /// serving a page; set it *after* a successful `load()` to make only a
  /// later `loadMore`/post-restore reload fail.
  Object? revisionsError;

  /// When set, `restore` throws this instead of recording the call.
  Object? restoreError;

  int revisionsCallCount = 0;
  String? lastBefore;

  int restoreCallCount = 0;
  int? lastRestoreFromSeq;
  int? lastRestoreBaseRevisionSeq;

  /// Records `'revisions'`/`'restore'` in call order, so tests can assert
  /// that a reload's `revisions` call happens *after* `restore` returns,
  /// not before it (e.g. `['revisions', 'restore', 'revisions']`).
  final List<String> callLog = [];

  @override
  Future<BeaconFactHistoryPage> revisions({
    required String beaconId,
    required String factCardId,
    String? before,
  }) async {
    callLog.add('revisions');
    revisionsCallCount++;
    lastBefore = before;
    final error = revisionsError;
    if (error != null) {
      if (error is Exception) throw error;
      if (error is Error) throw error;
      throw StateError(error.toString());
    }
    final index = revisionsCallCount - 1;
    return pages[index < pages.length ? index : pages.length - 1];
  }

  @override
  Future<int> restore({
    required String beaconId,
    required String factCardId,
    required int fromSeq,
    required int baseRevisionSeq,
  }) async {
    callLog.add('restore');
    restoreCallCount++;
    lastRestoreFromSeq = fromSeq;
    lastRestoreBaseRevisionSeq = baseRevisionSeq;
    final error = restoreError;
    if (error != null) {
      if (error is Exception) throw error;
      if (error is Error) throw error;
      throw StateError(error.toString());
    }
    return fromSeq;
  }
}

FactHistoryCubit _cubit(
  _FakeFactHistoryRepository repository, {
  int baseRevisionSeq = 5,
}) => FactHistoryCubit(
  beaconId: _kBeaconId,
  factCardId: _kFactCardId,
  baseRevisionSeq: baseRevisionSeq,
  repository: repository,
);

void main() {
  group('FactHistoryCubit.load (tentura-617.29)', () {
    test('emits the first page of entries', () async {
      final repo = _FakeFactHistoryRepository()
        ..pages = [
          (entries: [_entry(id: 'e2', seq: 2), _entry(id: 'e1', seq: 1)], nextCursor: null),
        ];
      final cubit = _cubit(repo);
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.entries, hasLength(2));
      expect(
        cubit.state.entries.map((e) => e.id),
        ['e2', 'e1'],
      );
      expect(cubit.state.status, isA<StateIsSuccess>());
      expect(cubit.state.loadError, isNull);
      expect(repo.revisionsCallCount, 1);
      expect(
        repo.lastBefore,
        isNull,
        reason: 'the first page must not pass a cursor',
      );
    });
  });

  group('FactHistoryCubit.loadMore (tentura-617.29)', () {
    test(
      'passes the previous nextCursor and appends via a new list instance',
      () async {
        final repo = _FakeFactHistoryRepository()
          ..pages = [
            (entries: [_entry(id: 'e2', seq: 2)], nextCursor: 'cursor-2'),
            (entries: [_entry(id: 'e1', seq: 1)], nextCursor: null),
          ];
        final cubit = _cubit(repo);
        addTearDown(cubit.close);

        await cubit.load();
        final firstPageEntries = cubit.state.entries;
        expect(firstPageEntries, hasLength(1));

        await cubit.loadMore();

        expect(repo.revisionsCallCount, 2);
        expect(repo.lastBefore, 'cursor-2');
        expect(
          identical(cubit.state.entries, firstPageEntries),
          isFalse,
          reason: 'loadMore must emit a new List instance, not mutate it',
        );
        expect(
          cubit.state.entries.map((e) => e.id),
          ['e2', 'e1'],
        );
        expect(cubit.state.nextCursor, isNull);
      },
    );

    test('does nothing when nextCursor is null', () async {
      final repo = _FakeFactHistoryRepository()
        ..pages = [
          (entries: [_entry(id: 'e1', seq: 1)], nextCursor: null),
        ];
      final cubit = _cubit(repo);
      addTearDown(cubit.close);

      await cubit.load();
      expect(repo.revisionsCallCount, 1);
      final entriesBefore = cubit.state.entries;
      final stateBefore = cubit.state;

      await cubit.loadMore();

      expect(
        repo.revisionsCallCount,
        1,
        reason: 'loadMore must no-op when there is no next page',
      );
      expect(
        identical(cubit.state.entries, entriesBefore),
        isTrue,
        reason: 'a no-op loadMore must not replace the entries list',
      );
      expect(cubit.state.nextCursor, stateBefore.nextCursor);
      expect(cubit.state.loadError, stateBefore.loadError);
      expect(cubit.state.status, isA<StateIsSuccess>());
      expect(cubit.state.entries, hasLength(1));
    });
  });

  group('FactHistoryCubit.restore (tentura-617.29)', () {
    test(
      'calls repository.restore(fromSeq, baseRevisionSeq) then reloads the '
      'first page, not the loadMore cursor',
      () async {
        final repo = _FakeFactHistoryRepository()
          ..pages = [
            // load(): page 1, has more.
            (entries: [_entry(id: 'e2', seq: 2)], nextCursor: 'cursor-2'),
            // loadMore(): page 2, before: 'cursor-2'.
            (entries: [_entry(id: 'e1', seq: 1)], nextCursor: null),
            // restore()'s reload must go back to before: null, not
            // continue from the exhausted 'cursor-2'.
            (entries: [_entry(id: 'e3', seq: 3)], nextCursor: null),
          ];
        final cubit = _cubit(repo, baseRevisionSeq: 5);
        addTearDown(cubit.close);

        await cubit.load();
        await cubit.loadMore();
        expect(repo.revisionsCallCount, 2);
        expect(repo.callLog, ['revisions', 'revisions']);
        expect(cubit.state.entries, hasLength(2));

        await cubit.restore(1);

        expect(repo.restoreCallCount, 1);
        expect(repo.lastRestoreFromSeq, 1);
        expect(
          repo.lastRestoreBaseRevisionSeq,
          5,
          reason:
              'baseRevisionSeq is fixed at sheet-open time, not the '
              'current head seq',
        );
        expect(
          repo.revisionsCallCount,
          3,
          reason: 'restore must reload the timeline afterwards',
        );
        expect(
          repo.callLog,
          ['revisions', 'revisions', 'restore', 'revisions'],
          reason:
              'restore() must call repository.restore then reload, not '
              'reload first or reload without ever restoring',
        );
        expect(
          repo.lastBefore,
          isNull,
          reason:
              'the post-restore reload must refetch the first page, not '
              'continue pagination from the loadMore cursor',
        );
        expect(cubit.state.entries.map((e) => e.id), ['e3']);
      },
    );
  });

  group('FactHistoryCubit.loadMore error handling (tentura-617.29)', () {
    test(
      'a repository error on loadMore lands in the error state without '
      'dropping already-loaded entries',
      () async {
        final repo = _FakeFactHistoryRepository()
          ..pages = [
            (entries: [_entry(id: 'e1', seq: 1)], nextCursor: 'cursor-2'),
          ];
        final cubit = _cubit(repo);
        addTearDown(cubit.close);

        await cubit.load();
        expect(cubit.state.entries, hasLength(1));

        repo.revisionsError = StateError('loadMore boom');
        await cubit.loadMore();

        expect(cubit.state.loadError, isNotNull);
        expect(
          cubit.state.status,
          isA<StateIsSuccess>(),
          reason: 'a failed loadMore must land in a terminal status',
        );
        expect(
          cubit.state.entries.map((e) => e.id),
          ['e1'],
          reason: 'a failed loadMore must not drop already-loaded entries',
        );
      },
    );
  });

  group('FactHistoryCubit.restore error handling (tentura-617.29)', () {
    test(
      'a repository error from restore() lands in the error state without '
      'reloading',
      () async {
        final repo = _FakeFactHistoryRepository()
          ..pages = [
            (entries: [_entry(id: 'e1', seq: 1)], nextCursor: null),
          ]
          ..restoreError = StateError('restore boom');
        final cubit = _cubit(repo);
        addTearDown(cubit.close);

        await cubit.load();
        expect(repo.revisionsCallCount, 1);

        await cubit.restore(1);

        expect(repo.restoreCallCount, 1);
        expect(cubit.state.loadError, isNotNull);
        expect(cubit.state.status, isA<StateIsSuccess>());
        expect(
          repo.revisionsCallCount,
          1,
          reason: 'a failed restore must not trigger a reload',
        );
        expect(cubit.state.entries.map((e) => e.id), ['e1']);
      },
    );

    test(
      'a repository error from the post-restore reload lands in the '
      'error state',
      () async {
        final repo = _FakeFactHistoryRepository()
          ..pages = [
            (entries: [_entry(id: 'e1', seq: 1)], nextCursor: null),
          ];
        final cubit = _cubit(repo);
        addTearDown(cubit.close);

        await cubit.load();
        repo.revisionsError = StateError('reload boom');

        await cubit.restore(1);

        expect(
          repo.restoreCallCount,
          1,
          reason: 'restore itself must still be called before the reload',
        );
        expect(cubit.state.loadError, isNotNull);
        expect(cubit.state.status, isA<StateIsSuccess>());
      },
    );
  });

  group('FactHistoryCubit error handling (tentura-617.29)', () {
    test('a repository error lands in the error state', () async {
      final repo = _FakeFactHistoryRepository()
        ..revisionsError = StateError('boom');
      final cubit = _cubit(repo);
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.loadError, isNotNull);
      expect(cubit.state.entries, isEmpty);
      expect(
        cubit.state.status,
        isA<StateIsSuccess>(),
        reason:
            'a failed load must land in a terminal status with loadError '
            'set (ThreadsCubit convention), not stay stuck on '
            'StateIsLoading',
      );
    });
  });
}
