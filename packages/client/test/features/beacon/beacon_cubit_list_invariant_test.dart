import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/features/auth/domain/port/auth_local_repository_port.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon/domain/enum.dart';
import 'package:tentura/features/beacon/ui/bloc/beacon_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

class _FakeAuthLocalRepository implements AuthLocalRepositoryPort {
  _FakeAuthLocalRepository(this.accountId);

  final String accountId;

  @override
  Future<String> getCurrentAccountId() async => accountId;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CapturingBeaconRepository implements BeaconRepository {
  List<int>? lastLifecycleStates;

  @override
  Future<Iterable<Beacon>> fetchBeacons({
    required String profileId,
    required int offset,
    required List<int> lifecycleStates,
    int limit = 5,
  }) async {
    lastLifecycleStates = lifecycleStates;
    return [
      Beacon(
        id: 'Breadable1',
        title: 'Readable',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        canReadContent: true,
      ),
      Beacon(
        id: 'Bhidden1',
        title: 'Hidden',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        canReadContent: false,
      ),
    ];
  }

  @override
  Stream<RepositoryEvent<Beacon>> get changes => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('BeaconCubit list invariants', () {
    test('other profile active filter excludes draft lifecycle state', () async {
      final repo = _CapturingBeaconRepository();
      final cubit = BeaconCubit(
        profileId: 'Uauthor',
        beaconRepository: repo,
        authLocalRepository: _FakeAuthLocalRepository('Uviewer'),
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);

      await cubit.fetch(reset: true);

      expect(repo.lastLifecycleStates, isNot(contains(BeaconStatus.draft.smallintValue)));
      expect(cubit.state.beacons, hasLength(1));
      expect(cubit.state.beacons.single.id, 'Breadable1');
      expect(cubit.state.beacons.every((b) => b.canReadContent), isTrue);
    });

    test('own profile active filter still includes draft', () async {
      final repo = _CapturingBeaconRepository();
      final cubit = BeaconCubit(
        profileId: 'Umine',
        beaconRepository: repo,
        authLocalRepository: _FakeAuthLocalRepository('Umine'),
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);

      await cubit.fetch(reset: true);

      expect(repo.lastLifecycleStates, contains(BeaconStatus.draft.smallintValue));
    });
  });

  group('Beacon commit invariant', () {
    test('canCommitAsViewer requires readable open-family beacon', () {
      final readableOpen = Beacon(
        id: 'B1',
        createdAt: _t,
        updatedAt: _t,
        status: BeaconStatus.open,
        canReadContent: true,
      );
      final unreadableOpen = Beacon(
        id: 'B2',
        createdAt: _t,
        updatedAt: _t,
        status: BeaconStatus.open,
        canReadContent: false,
      );
      final readableClosed = Beacon(
        id: 'B3',
        createdAt: _t,
        updatedAt: _t,
        status: BeaconStatus.closed,
        canReadContent: true,
      );

      expect(readableOpen.canOpenAsViewer, isTrue);
      expect(readableOpen.canCommitAsViewer, isTrue);
      expect(unreadableOpen.canOpenAsViewer, isFalse);
      expect(unreadableOpen.canCommitAsViewer, isFalse);
      expect(readableClosed.canOpenAsViewer, isTrue);
      expect(readableClosed.canCommitAsViewer, isFalse);
    });
  });
}

final _t = DateTime.utc(2026);
