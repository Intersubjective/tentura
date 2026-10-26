import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/constellation_consts.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_tag_magnet.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_tag_magnet_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_tag_magnet_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/test_realtime_sync.dart';

const _ego = Profile(id: 'ego', displayName: 'Ego');

Set<String> _noTags(String personId) => const {};

final class _StubRepository implements ConstellationRepositoryPort {
  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => ConstellationField(
    loadedAt: DateTime.utc(2026, 10, 26),
    context: '',
    peers: const [ConstellationPerson(id: 'ann', displayName: 'Ann')],
    edges: const [
      ConstellationTrustEdgeEntity(src: 'ego', dst: 'ann', tier: 1),
    ],
    directContactIds: const ['ann'],
  );
}

typedef _Upsert = ({
  String tagId,
  double xUnits,
  double yUnits,
  String clientOpId,
});

typedef _Remove = ({String tagId, String clientOpId});

/// The server side of the magnet API, as the repository port sees it.
final class _FakeMagnetRepository
    implements ConstellationTagMagnetRepositoryPort {
  List<ConstellationTagMagnet> stored = [];
  Exception? listFailure;
  Exception? writeFailure;

  /// Holds every write until completed, to observe the optimistic state.
  Completer<void>? writeGate;

  int listCalls = 0;
  final upserts = <_Upsert>[];
  final removes = <_Remove>[];

  @override
  Future<List<ConstellationTagMagnet>> list() async {
    listCalls++;
    if (listFailure case final failure?) throw failure;
    return [...stored];
  }

  @override
  Future<ConstellationTagMagnet> upsert({
    required String tagId,
    required double xUnits,
    required double yUnits,
    required String clientOpId,
  }) async {
    upserts.add(
      (tagId: tagId, xUnits: xUnits, yUnits: yUnits, clientOpId: clientOpId),
    );
    await writeGate?.future;
    if (writeFailure case final failure?) throw failure;
    final magnet = ConstellationTagMagnet(
      tagId: tagId,
      xUnits: xUnits,
      yUnits: yUnits,
      revision: upserts.length,
    );
    stored = [
      for (final m in stored)
        if (m.tagId != tagId) m,
      magnet,
    ];
    return magnet;
  }

  @override
  Future<void> remove({
    required String tagId,
    required String clientOpId,
  }) async {
    removes.add((tagId: tagId, clientOpId: clientOpId));
    await writeGate?.future;
    if (writeFailure case final failure?) throw failure;
    stored = [
      for (final m in stored)
        if (m.tagId != tagId) m,
    ];
  }
}

typedef _Rig = ({
  ConstellationCubit cubit,
  _FakeMagnetRepository repository,
  TestRealtimeSyncPort realtime,
});

Future<_Rig> _open(_FakeMagnetRepository repository) async {
  final realtime = buildTestRealtimeSync();
  addTearDown(realtime.port.dispose);
  final cubit = ConstellationCubit(
    case_: ConstellationStoreFixture(
      _StubRepository(),
      accountId: 'ego',
    ).store,
    viewer: _ego,
    tagMagnetCase: ConstellationTagMagnetCase(
      repository,
      realtime.case_,
      env: const Env(),
      logger: Logger('test'),
    ),
  );
  addTearDown(cubit.close);
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  await pumpEventQueue();
  return (cubit: cubit, repository: repository, realtime: realtime.port);
}

/// Polls instead of pumping a fixed number of turns, so a debounced hint
/// handler or a slow write does not make the test depend on its timing.
Future<void> _until(bool Function() done, {String? reason}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      fail(reason ?? 'condition not reached within 3 s');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

const _centre = kConstellationCanvasCentre;
const _here = Offset(_centre + 150, _centre - 90);
const _there = Offset(_centre - 210, _centre + 120);

({double xUnits, double yUnits}) _unitsOf(Offset scene) {
  final anchor = constellationPointToV1Anchor((x: scene.dx, y: scene.dy));
  return (xUnits: anchor.xUnits, yUnits: anchor.yUnits);
}

void _expectAt(Offset? actual, Offset expected, {String? reason}) {
  expect(actual, isNotNull, reason: reason);
  expect((actual! - expected).distance, lessThan(1e-6), reason: reason);
}

ConstellationTagMagnet _saved(String tagId, Offset scene, {int revision = 1}) {
  final units = _unitsOf(scene);
  return ConstellationTagMagnet(
    tagId: tagId,
    xUnits: units.xUnits,
    yUnits: units.yUnits,
    revision: revision,
  );
}

RealtimeEntityChange _personTagHint(int revision) => RealtimeEntityChange(
  kind: RealtimeEntityKind.personTag,
  aggregateId: 'ego',
  operation: RealtimeOperation.update,
  source: RealtimeChangeSource.serverInvalidation,
  revision: BigInt.from(revision),
);

void main() {
  late _FakeMagnetRepository repository;

  setUp(() => repository = _FakeMagnetRepository());

  group('saving tag magnets through the server API', () {
    test('placing a magnet saves it at the placed position', () async {
      final rig = await _open(repository);

      rig.cubit.placeTagMagnet(
        tagId: 'T-workshop',
        position: _here,
        tagsOfPerson: _noTags,
      );
      await _until(() => repository.upserts.isNotEmpty);

      final saved = repository.upserts.single;
      final units = _unitsOf(_here);
      expect(saved.tagId, 'T-workshop');
      expect(saved.xUnits, closeTo(units.xUnits, 1e-9));
      expect(saved.yUnits, closeTo(units.yUnits, 1e-9));
      expect(saved.clientOpId, isNotEmpty);
      expect(repository.removes, isEmpty);
      _expectAt(rig.cubit.tagMagnets['T-workshop'], _here);
    });

    test('the magnet shows before the server has answered', () async {
      repository.writeGate = Completer<void>();
      final rig = await _open(repository);

      rig.cubit.placeTagMagnet(
        tagId: 'T-workshop',
        position: _here,
        tagsOfPerson: _noTags,
      );
      await _until(() => repository.upserts.isNotEmpty);

      _expectAt(
        rig.cubit.tagMagnets['T-workshop'],
        _here,
        reason: 'the optimistic magnet is visible while the save is in flight',
      );
      repository.writeGate!.complete();
      await pumpEventQueue();
      _expectAt(rig.cubit.tagMagnets['T-workshop'], _here);
    });

    test('moving a magnet saves its new position as a new operation', () async {
      final rig = await _open(repository);
      rig.cubit.placeTagMagnet(
        tagId: 'T-workshop',
        position: _here,
        tagsOfPerson: _noTags,
      );
      await _until(() => repository.upserts.length == 1);

      rig.cubit.placeTagMagnet(
        tagId: 'T-workshop',
        position: _there,
        tagsOfPerson: _noTags,
      );
      await _until(() => repository.upserts.length == 2);

      final moved = repository.upserts.last;
      final units = _unitsOf(_there);
      expect(moved.tagId, 'T-workshop');
      expect(moved.xUnits, closeTo(units.xUnits, 1e-9));
      expect(moved.yUnits, closeTo(units.yUnits, 1e-9));
      expect(
        moved.clientOpId,
        isNot(repository.upserts.first.clientOpId),
        reason: 'a move is a new write, not a replay of the placement',
      );
      _expectAt(rig.cubit.tagMagnets['T-workshop'], _there);
    });

    test('removing a magnet deletes it on the server', () async {
      final rig = await _open(repository);
      rig.cubit.placeTagMagnet(
        tagId: 'T-workshop',
        position: _here,
        tagsOfPerson: _noTags,
      );
      await _until(() => repository.upserts.isNotEmpty);

      rig.cubit.removeTagMagnet('T-workshop');
      await _until(() => repository.removes.isNotEmpty);

      expect(repository.removes.single.tagId, 'T-workshop');
      expect(repository.removes.single.clientOpId, isNotEmpty);
      expect(rig.cubit.tagMagnets, isEmpty);
      await pumpEventQueue();
      expect(repository.stored, isEmpty);
    });

    test(
      'removing a magnet that is not there does not call the server',
      () async {
        final rig = await _open(repository);

        rig.cubit.removeTagMagnet('T-workshop');
        await pumpEventQueue();

        expect(repository.removes, isEmpty);
      },
    );
  });

  group('magnets are loaded with the Field', () {
    test('a new cubit shows the magnets the server holds', () async {
      repository.stored = [
        _saved('T-workshop', _here),
        _saved('T-garden', _there),
      ];

      final rig = await _open(repository);
      await _until(() => rig.cubit.tagMagnets.length == 2);

      _expectAt(rig.cubit.tagMagnets['T-workshop'], _here);
      _expectAt(rig.cubit.tagMagnets['T-garden'], _there);
      expect(repository.listCalls, greaterThanOrEqualTo(1));
    });

    test(
      'a magnet placed in one session is there when the Field reopens',
      () async {
        final first = await _open(repository);
        first.cubit.placeTagMagnet(
          tagId: 'T-workshop',
          position: _here,
          tagsOfPerson: _noTags,
        );
        await _until(() => repository.upserts.isNotEmpty);
        await pumpEventQueue();
        await first.cubit.close();
        final callsBeforeReopen = repository.listCalls;

        final second = await _open(repository);
        await _until(() => second.cubit.tagMagnets.isNotEmpty);

        expect(
          repository.listCalls,
          greaterThan(callsBeforeReopen),
          reason: 'the reopened Field reads the magnets from the server',
        );
        _expectAt(second.cubit.tagMagnets['T-workshop'], _here);
      },
    );

    test(
      'reloading the Field after an account change reads the magnets again',
      () async {
        repository.stored = [_saved('T-workshop', _here)];
        final rig = await _open(repository);
        await _until(() => rig.cubit.tagMagnets.isNotEmpty);
        final callsBefore = repository.listCalls;

        await rig.cubit.onAccountChanged();
        await rig.cubit.load();
        await _until(() => repository.listCalls > callsBefore);
        await _until(() => rig.cubit.tagMagnets.isNotEmpty);

        _expectAt(rig.cubit.tagMagnets['T-workshop'], _here);
      },
    );

    test('a failed magnet read still leaves the Field loaded', () async {
      repository.listFailure = Exception('offline');

      final rig = await _open(repository);

      expect(rig.cubit.state.status, isA<StateIsSuccess>());
      expect(rig.cubit.state.field, isNotNull);
      expect(rig.cubit.tagMagnets, isEmpty);
    });
  });

  group('a failed magnet save is rolled back', () {
    test('a placement that fails leaves no magnet', () async {
      final rig = await _open(repository);
      repository
        ..writeGate = Completer<void>()
        ..writeFailure = Exception('offline');

      rig.cubit.placeTagMagnet(
        tagId: 'T-workshop',
        position: _here,
        tagsOfPerson: _noTags,
      );
      await _until(() => repository.upserts.isNotEmpty);
      _expectAt(
        rig.cubit.tagMagnets['T-workshop'],
        _here,
        reason: 'the magnet is shown while the save is pending',
      );

      repository.writeGate!.complete();
      await _until(
        () => rig.cubit.tagMagnets.isEmpty,
        reason: 'the failed placement is rolled back',
      );
    });

    test('a move that fails puts the magnet back where it was', () async {
      final rig = await _open(repository);
      rig.cubit.placeTagMagnet(
        tagId: 'T-workshop',
        position: _here,
        tagsOfPerson: _noTags,
      );
      await _until(() => repository.upserts.length == 1);
      await pumpEventQueue();
      repository
        ..writeGate = Completer<void>()
        ..writeFailure = Exception('offline');

      rig.cubit.placeTagMagnet(
        tagId: 'T-workshop',
        position: _there,
        tagsOfPerson: _noTags,
      );
      await _until(() => repository.upserts.length == 2);
      _expectAt(
        rig.cubit.tagMagnets['T-workshop'],
        _there,
        reason: 'the magnet is at its new position while the save is pending',
      );

      repository.writeGate!.complete();
      await _until(
        () => (rig.cubit.tagMagnets['T-workshop'] ?? _there) != _there,
        reason: 'the failed move is reverted',
      );
      _expectAt(rig.cubit.tagMagnets['T-workshop'], _here);
    });

    test('a removal that fails brings the magnet back', () async {
      repository.stored = [_saved('T-workshop', _here)];
      final rig = await _open(repository);
      await _until(() => rig.cubit.tagMagnets.isNotEmpty);
      repository
        ..writeGate = Completer<void>()
        ..writeFailure = Exception('offline');

      rig.cubit.removeTagMagnet('T-workshop');
      await _until(() => repository.removes.isNotEmpty);
      expect(
        rig.cubit.tagMagnets,
        isEmpty,
        reason: 'the magnet is gone while the removal is pending',
      );

      repository.writeGate!.complete();
      await _until(
        () => rig.cubit.tagMagnets.isNotEmpty,
        reason: 'the failed removal is rolled back',
      );
      _expectAt(rig.cubit.tagMagnets['T-workshop'], _here);
    });
  });

  group('a people-tags hint reloads the magnets', () {
    test('a magnet saved from another device appears', () async {
      final rig = await _open(repository);
      expect(rig.cubit.tagMagnets, isEmpty);
      final callsBefore = repository.listCalls;

      repository.stored = [_saved('T-garden', _there)];
      rig.realtime.emitChange(_personTagHint(5));
      await _until(() => repository.listCalls > callsBefore);
      await _until(() => rig.cubit.tagMagnets.isNotEmpty);

      _expectAt(rig.cubit.tagMagnets['T-garden'], _there);
    });

    test('a magnet moved or removed from another device follows', () async {
      repository.stored = [
        _saved('T-workshop', _here),
        _saved('T-garden', _there),
      ];
      final rig = await _open(repository);
      await _until(() => rig.cubit.tagMagnets.length == 2);

      repository.stored = [_saved('T-workshop', _there, revision: 2)];
      rig.realtime.emitChange(_personTagHint(6));
      await _until(() => rig.cubit.tagMagnets.length == 1);

      expect(rig.cubit.tagMagnets.keys, ['T-workshop']);
      _expectAt(rig.cubit.tagMagnets['T-workshop'], _there);
    });

    test('a hint of another kind does not read the magnets', () async {
      final rig = await _open(repository);
      final callsBefore = repository.listCalls;

      rig.realtime.emitChange(
        RealtimeEntityChange(
          kind: RealtimeEntityKind.relationship,
          aggregateId: 'ann',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
          revision: BigInt.one,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(repository.listCalls, callsBefore);
    });
  });
}
