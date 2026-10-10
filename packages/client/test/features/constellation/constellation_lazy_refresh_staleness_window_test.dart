import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/test_realtime_sync.dart';

/// Global (non-urgent) field invalidations must refresh a visible field at
/// most once per staleness window (5 min) plus the per-account jitter, so a
/// fleet of sessions asks for ~3.3 FULL/s rather than ~33 FULL/s.
///
/// The D8 load model (packages/server/test/perf/constellation_d8_load_model.dart,
/// `D8ClientPolicy.lazySpacingMs`) simulates this same cadence; its test reads
/// the interval from the store source so the two cannot drift apart.
const _stalenessWindow = Duration(minutes: 5);

/// Generous upper bound for the per-account jitter added to the window: small
/// next to the window, so any jitter the store picks stays inside it.
const _jitterAllowance = Duration(seconds: 30);

/// Existing spacing between urgent refreshes and the debounce before one.
const _urgentSpacing = Duration(seconds: 2);
const _debounce = Duration(milliseconds: 220);

final class _CountingRepository implements ConstellationRepositoryPort {
  int fetchCount = 0;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async {
    fetchCount++;
    return ConstellationField(
      loadedAt: DateTime.utc(2026, 10, 5),
      context: '',
      posts: [
        ConstellationPost(
          id: 'on-map',
          authorId: 'ego',
          rootExcerpt: '',
          lastActivityAt: DateTime.utc(2026, 10, 5),
          isPinned: false,
        ),
      ],
    );
  }
}

void main() {
  late ({RealtimeSyncCase case_, TestRealtimeSyncPort port}) sync;
  late _CountingRepository repository;
  late ConstellationCubit cubit;
  late ConstellationStoreFixture fixture;

  void emit(RealtimeEntityKind kind, String aggregateId) =>
      sync.port.emitChange(
        RealtimeEntityChange(
          kind: kind,
          aggregateId: aggregateId,
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );

  void build(FakeAsync async) {
    sync = buildTestRealtimeSync();
    repository = _CountingRepository();
    fixture = ConstellationStoreFixture(
      repository,
      accountId: 'ego',
      realtime: sync.case_,
      now: () => DateTime.utc(2026, 10, 5).add(async.elapsed),
    );
    async.flushMicrotasks();
    cubit = fixture.createCubit(viewer: const Profile(id: 'ego'));
    cubit.load();
    async.flushMicrotasks();
    expect(repository.fetchCount, 1, reason: 'initial load');
  }

  void tearDownCubit(FakeAsync async) {
    cubit.close();
    fixture.store.dispose();
    fixture.account.close();
    sync.port.dispose();
    async.flushMicrotasks();
  }

  test('lazy refresh interval is the five-minute staleness window', () {
    expect(kLazyFieldRefreshInterval, _stalenessWindow);
  });

  test(
    'a global hint does not trigger a second FULL within the staleness window',
    () {
      fakeAsync((async) {
        build(async);

        emit(RealtimeEntityKind.roomMessage, 'elsewhere');
        async.elapse(_stalenessWindow - const Duration(seconds: 1));

        expect(repository.fetchCount, 1);
        tearDownCubit(async);
      });
    },
  );

  test('a global hint refreshes once the window plus jitter has passed', () {
    fakeAsync((async) {
      build(async);

      emit(RealtimeEntityKind.roomMessage, 'elsewhere');
      async.elapse(
        _stalenessWindow + _jitterAllowance + const Duration(seconds: 1),
      );

      expect(repository.fetchCount, 2);
      tearDownCubit(async);
    });
  });

  test('a steady stream of global hints refreshes once per window', () {
    fakeAsync((async) {
      build(async);

      for (var i = 0; i < 29; i++) {
        emit(RealtimeEntityKind.roomMessage, 'elsewhere-$i');
        async.elapse(const Duration(seconds: 10));
      }
      expect(
        repository.fetchCount,
        1,
        reason: 'no refresh inside the first five minutes of hints',
      );

      for (var i = 0; i < 30; i++) {
        emit(RealtimeEntityKind.roomMessage, 'elsewhere-late-$i');
        async.elapse(const Duration(seconds: 10));
      }
      expect(
        repository.fetchCount,
        2,
        reason: 'one refresh, not one per old 30 s interval',
      );
      tearDownCubit(async);
    });
  });

  test('returning to the tab refreshes at once despite the window', () {
    fakeAsync((async) {
      build(async);
      cubit.setVisible(false);
      emit(RealtimeEntityKind.roomMessage, 'elsewhere');
      async.elapse(const Duration(minutes: 1));
      expect(repository.fetchCount, 1);

      cubit.setVisible(true);
      async.flushMicrotasks();

      expect(repository.fetchCount, 2);
      tearDownCubit(async);
    });
  });

  test('a global hint after returning to the tab waits for the window', () {
    fakeAsync((async) {
      build(async);
      cubit.setVisible(false);
      emit(RealtimeEntityKind.roomMessage, 'elsewhere');
      async.elapse(const Duration(minutes: 1));
      cubit.setVisible(true);
      async.flushMicrotasks();
      expect(repository.fetchCount, 2);

      emit(RealtimeEntityKind.roomMessage, 'elsewhere-again');
      async.elapse(const Duration(minutes: 4));
      expect(repository.fetchCount, 2, reason: 'inside the window');

      async.elapse(
        const Duration(minutes: 1) + _jitterAllowance + _debounce,
      );
      expect(repository.fetchCount, 3, reason: 'after the window');
      tearDownCubit(async);
    });
  });

  test('a hidden field stays paused beyond the staleness window', () {
    fakeAsync((async) {
      build(async);
      cubit.setVisible(false);

      emit(RealtimeEntityKind.roomMessage, 'elsewhere');
      async.elapse(_stalenessWindow * 2);

      expect(repository.fetchCount, 1);
      tearDownCubit(async);
    });
  });

  test('a global hint refreshes within the window plus a jitter allowance', () {
    fakeAsync((async) {
      build(async);

      emit(RealtimeEntityKind.roomMessage, 'elsewhere');
      const step = Duration(milliseconds: 100);
      var elapsed = Duration.zero;
      while (repository.fetchCount < 2 &&
          elapsed <= _stalenessWindow + _jitterAllowance) {
        async.elapse(step);
        elapsed += step;
      }

      expect(repository.fetchCount, 2, reason: 'refreshed within allowance');
      expect(elapsed, greaterThanOrEqualTo(_stalenessWindow));
      tearDownCubit(async);
    });
  });

  test(
    'opening the field refreshes at once while a global hint is pending',
    () {
      fakeAsync((async) {
        build(async);
        emit(RealtimeEntityKind.roomMessage, 'elsewhere');
        async.elapse(const Duration(minutes: 1));
        expect(repository.fetchCount, 1, reason: 'hint is still inside window');

        cubit.load();
        async.flushMicrotasks();

        expect(repository.fetchCount, 2);
        tearDownCubit(async);
      });
    },
  );

  test('an urgent hint refreshes after the urgent spacing, not the window', () {
    fakeAsync((async) {
      build(async);

      emit(RealtimeEntityKind.beacon, 'on-map');
      async.elapse(_urgentSpacing - const Duration(milliseconds: 1));
      expect(repository.fetchCount, 1, reason: 'just before urgent spacing');

      async.elapse(const Duration(milliseconds: 1));
      expect(repository.fetchCount, 2, reason: 'at urgent spacing');
      tearDownCubit(async);
    });
  });

  test('an urgent hint overtakes a pending global refresh', () {
    fakeAsync((async) {
      build(async);
      emit(RealtimeEntityKind.roomMessage, 'elsewhere');
      async.elapse(const Duration(seconds: 30));
      expect(repository.fetchCount, 1);

      emit(RealtimeEntityKind.beacon, 'on-map');
      async.elapse(_debounce - const Duration(milliseconds: 1));
      expect(repository.fetchCount, 1, reason: 'just before the debounce');

      async.elapse(const Duration(milliseconds: 1));
      expect(repository.fetchCount, 2, reason: 'at the debounce');
      tearDownCubit(async);
    });
  });
}
