import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';

import '../../support/test_realtime_sync.dart';

/// #234: realtime-driven FULL refetches were issued for every room event of
/// any Request, every 220 ms, also while the tab was hidden.
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

  void emit(RealtimeEntityKind kind, String beaconId) => sync.port.emitChange(
    RealtimeEntityChange(
      kind: kind,
      aggregateId: beaconId,
      operation: RealtimeOperation.update,
      source: RealtimeChangeSource.serverInvalidation,
    ),
  );

  void build(FakeAsync async) {
    sync = buildTestRealtimeSync();
    repository = _CountingRepository();
    cubit = ConstellationCubit(
      case_: ConstellationFieldCase(
        repository,
        env: const Env.fromEnvironment(),
        logger: Logger('ConstellationRealtimeRefreshTest'),
        realtimeSyncCase: sync.case_,
      ),
      viewer: const Profile(id: 'ego'),
      now: () => DateTime.utc(2026, 10, 5).add(async.elapsed),
    );
    async.flushMicrotasks();
    expect(repository.fetchCount, 1, reason: 'initial load');
  }

  void tearDownCubit(FakeAsync async) {
    cubit.close();
    sync.port.dispose();
    async.flushMicrotasks();
  }

  test('a hidden field does not refetch; showing it refetches once', () {
    fakeAsync((async) {
      build(async);
      cubit.setVisible(false);
      for (var i = 0; i < 10; i++) {
        emit(RealtimeEntityKind.beacon, 'b$i');
        async.elapse(const Duration(seconds: 1));
      }
      expect(repository.fetchCount, 1);

      cubit.setVisible(true);
      async.elapse(const Duration(seconds: 3));
      expect(repository.fetchCount, 2);
      tearDownCubit(async);
    });
  });

  test('a steady event stream refreshes at most every 2 s', () {
    fakeAsync((async) {
      build(async);
      // One event every 100 ms for 10 s used to reset a 220 ms debounce
      // (never firing) or, spaced wider, fire once per event.
      for (var i = 0; i < 100; i++) {
        emit(RealtimeEntityKind.beacon, 'on-map');
        async.elapse(const Duration(milliseconds: 100));
      }
      async.elapse(const Duration(seconds: 3));
      expect(repository.fetchCount, inInclusiveRange(5, 7));
      tearDownCubit(async);
    });
  });

  test('room traffic of a Request not on the map refreshes lazily', () {
    fakeAsync((async) {
      build(async);
      emit(RealtimeEntityKind.roomMessage, 'elsewhere');
      async.elapse(const Duration(seconds: 5));
      expect(repository.fetchCount, 1);

      async.elapse(kLazyFieldRefreshInterval);
      expect(repository.fetchCount, 2);

      emit(RealtimeEntityKind.roomMessage, 'on-map');
      async.elapse(const Duration(seconds: 3));
      expect(repository.fetchCount, 3);
      tearDownCubit(async);
    });
  });

  test('an explicit load absorbs a pending realtime refresh', () {
    fakeAsync((async) {
      build(async);
      emit(RealtimeEntityKind.beacon, 'on-map');
      async.flushMicrotasks();
      cubit.load();
      async.elapse(const Duration(seconds: 5));
      expect(repository.fetchCount, 2);
      tearDownCubit(async);
    });
  });
}
