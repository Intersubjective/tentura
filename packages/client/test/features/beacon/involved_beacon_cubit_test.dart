import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/features/auth/domain/port/auth_local_repository_port.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon/ui/bloc/involved_beacon_cubit.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

class _FakeAuthLocalRepository implements AuthLocalRepositoryPort {
  @override
  Future<String> getCurrentAccountId() async => 'Uviewer';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBeaconRepository implements BeaconRepository {
  _FakeBeaconRepository(this.pages);

  /// Consecutive [fetchInvolvedBeacons] results.
  final List<List<Beacon>> pages;

  var _call = 0;

  @override
  Future<Iterable<Beacon>> fetchInvolvedBeacons({
    required String authorId,
    required String viewerId,
    required int offset,
    int limit = 5,
  }) async => pages[_call++ < pages.length ? _call - 1 : pages.length - 1];

  @override
  Stream<RepositoryEvent<Beacon>> get changes => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Beacon _beacon(String id) => Beacon(
  id: id,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

InvolvedBeaconCubit _cubit(_FakeBeaconRepository repo) => InvolvedBeaconCubit(
  authorId: 'Uauthor',
  beaconRepository: repo,
  authLocalRepository: _FakeAuthLocalRepository(),
  effects: FakeUiEffectPort(),
);

void main() {
  group('InvolvedBeaconCubit first fetch', () {
    // Regression: the initial state holds a const `[]`; a non-reset first
    // fetch used to mutate it in place and throw, showing the error/retry
    // screen instead of the empty placeholder.
    test('empty result lands in success state, not error', () async {
      final cubit = _cubit(_FakeBeaconRepository([[]]));
      addTearDown(cubit.close);

      await cubit.fetch();

      expect(cubit.state.hasError, isFalse);
      expect(cubit.state.beacons, isEmpty);
      expect(cubit.state.hasReachedLast, isTrue);
    });

    test('non-empty result lands in success state, not error', () async {
      final cubit = _cubit(
        _FakeBeaconRepository([
          [_beacon('B1'), _beacon('B2')],
        ]),
      );
      addTearDown(cubit.close);

      await cubit.fetch();

      expect(cubit.state.hasError, isFalse);
      expect(cubit.state.beacons.map((b) => b.id), ['B1', 'B2']);
    });

    test('subsequent fetch appends the next page', () async {
      final cubit = _cubit(
        _FakeBeaconRepository([
          [for (var i = 0; i < 5; i++) _beacon('B$i')],
          [_beacon('B5')],
        ]),
      );
      addTearDown(cubit.close);

      await cubit.fetch();
      await cubit.fetch();

      expect(cubit.state.hasError, isFalse);
      expect(cubit.state.beacons.map((b) => b.id), [
        for (var i = 0; i <= 5; i++) 'B$i',
      ]);
      expect(cubit.state.hasReachedLast, isTrue);
    });
  });
}
