import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/features/favorites/data/repository/favorites_remote_repository.dart';
import 'package:tentura/features/favorites/ui/bloc/favorites_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import '../auth/auth_test_helpers.dart';

class _FakeFavoritesRepository extends Mock
    implements FavoritesRemoteRepository {
  _FakeFavoritesRepository(this._changes);

  final Stream<Beacon> _changes;

  @override
  Stream<Beacon> get changes => _changes;
}

class _Effects implements UiEffectPort {
  @override
  Stream<UiEffect> get effects => const Stream.empty();

  @override
  void emit(UiEffect effect) {}
}

Beacon _pinned(String id, BeaconKind kind) => Beacon(
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  id: id,
  kind: kind,
  isPinned: true,
);

void main() {
  group('FavoritesCubit live pin updates', () {
    late StreamController<Beacon> changes;
    late FavoritesCubit cubit;

    setUp(() {
      changes = StreamController<Beacon>.broadcast();
      final repo = _FakeFavoritesRepository(changes.stream);
      cubit = FavoritesCubit(
        buildTestAuthCase(EmptyAuthLocal(), EmptyAuthRemote()),
        repo,
        _Effects(),
      );
    });

    tearDown(() async {
      await cubit.close();
      await changes.close();
    });

    test('pinning a Request adds it to the list', () async {
      changes.add(_pinned('R1', BeaconKind.request));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.beacons.map((e) => e.id), ['R1']);
    });

    test('a Post pin leaves existing favorites untouched', () async {
      changes.add(_pinned('R1', BeaconKind.request));
      await Future<void>.delayed(Duration.zero);
      changes
        ..add(_pinned('P1', BeaconKind.post))
        ..add(_pinned('R2', BeaconKind.request));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.beacons.map((e) => e.id), ['R2', 'R1']);
    });

    test('a Post unpin leaves existing favorites untouched', () async {
      changes.add(_pinned('R1', BeaconKind.request));
      await Future<void>.delayed(Duration.zero);
      changes.add(_pinned('P1', BeaconKind.post).copyWith(isPinned: false));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.beacons.map((e) => e.id), ['R1']);
    });

    test('pinning a Post does not add it to the list', () async {
      changes.add(_pinned('P1', BeaconKind.post));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.beacons, isEmpty);
    });
  });
}
