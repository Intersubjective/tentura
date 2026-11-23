@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';
import 'package:tentura_server/data/repository/constellation_layout_snapshot_repository.dart';
import 'package:tentura_server/data/repository/owner_graph_unit_of_work.dart';
import 'package:tentura_server/domain/entity/constellation_layout_snapshot.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/domain/port/constellation_layout_snapshot_repository_port.dart';
import 'package:tentura_server/domain/port/owner_graph_transaction_port.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/owner_graph_contention.dart';
import '../../support/pg_test_public_keys.dart';

const _viewer = 'Uownerlayout1';
const _otherViewer = 'Uownerlayout2';
const _person = 'Uownerperson1';
const _secondPerson = 'Uownerperson2';
const _initialPosition = (1.5, -2.25, 1);
const _movedPosition = (-3.25, 4.5, 1);

typedef _ScopedAnchorUpsert =
    Future<void> Function({
      required OwnerGraphScope scope,
      required String viewerId,
      required ConstellationAnchorTarget target,
      required ConstellationAnchorPosition position,
      required Set<ConstellationAnchorTarget> additionalWatermarkTargets,
    });

/// Resolve the new port operation at runtime while the method is absent.
_ScopedAnchorUpsert _scopedAnchorUpsert(
  ConstellationAnchorRepositoryPort repository,
) {
  final Object? method;
  try {
    method = (repository as dynamic).upsertScoped;
    // The test reports an absent production method as an assertion failure.
    // ignore: avoid_catching_errors
  } on NoSuchMethodError {
    fail('Scoped anchor placement is unavailable on the repository port.');
  }
  if (method is! _ScopedAnchorUpsert) {
    fail('upsertScoped does not have the scoped anchor write signature.');
  }
  return method;
}

ConstellationAnchorPosition _anchorPosition((double, double, int) position) {
  final (x, y, version) = position;
  return ConstellationAnchorPosition(
    xUnits: x,
    yUnits: y,
    coordinateSpaceVersion: version,
  );
}

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_OWNER_SCOPE_TEST_DB',
    defaultNamePrefix: 'tentura_test_constellation_owner_scope',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  late DisposablePgWriterSession session;
  late TenturaDb holderDb;
  late TenturaDb db;
  late OwnerGraphTransactionPort ownerGraph;
  late ConstellationAnchorRepositoryPort anchors;
  late ConstellationLayoutSnapshotRepositoryPort snapshots;

  setUpAll(() async {
    final previous = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(
      () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = previous,
    );
    session = await setUpDisposablePgWriter(target: target);
    addTearDown(() => tearDownDisposablePgWriter(session: session));
    holderDb = openDisposablePgDatabase(target);
    addTearDown(holderDb.close);
    ownerGraph = OwnerGraphUnitOfWork(holderDb);
    for (final (index, id) in [
      _viewer,
      _otherViewer,
      _person,
      _secondPerson,
    ].indexed) {
      await session.writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
        parameters: {'id': id, 'key': pgTestPublicKey('ownsco', index + 1)},
      );
    }
  });

  setUp(() async {
    await session.writer.execute('''
TRUNCATE public.constellation_anchor, public.constellation_anchor_cursor,
  public.constellation_anchor_op_log, public.constellation_anchor_target_watermark,
  public.constellation_layout_snapshot
''');
    db = openDisposablePgDatabase(target);
    addTearDown(db.close);
    anchors = ConstellationAnchorRepository(db);
    snapshots = ConstellationLayoutSnapshotRepository(db);
  });

  Future<AnchorApplyOpResult> pin(
    String viewer,
    String opId,
    (double, double, int) position, {
    ConstellationAnchorRepositoryPort? repository,
    String person = _person,
  }) async {
    final result = await (repository ?? anchors).applyBatch(
      viewerId: viewer,
      ops: [
        AnchorApplyOp(
          clientOpId: opId,
          kind: AnchorOpKind.upsert,
          target: ConstellationAnchorTarget.person(person),
          position: _anchorPosition(position),
        ),
      ],
    );
    expect(result.results.single.status, AnchorOpStatus.ok);
    return result.results.single;
  }

  Future<ConstellationLayoutSnapshot> save(
    String opId, {
    ConstellationLayoutSnapshotKind kind =
        ConstellationLayoutSnapshotKind.history,
    ConstellationLayoutSnapshotRepositoryPort? repository,
  }) => (repository ?? snapshots).save(
    viewerId: _viewer,
    kind: kind,
    reason: ConstellationLayoutSnapshotReason.manual,
    clientOpId: opId,
  );

  Future<Map<String, (double, double, int)>> positions(String viewer) async {
    final rows = await session.writer.execute(
      Sql.named('''
SELECT target_id, x_units, y_units, coordinate_space_version
FROM public.constellation_anchor
WHERE viewer_id = @viewer AND tombstone_at IS NULL
'''),
      parameters: {'viewer': viewer},
    );
    return {
      for (final row in rows)
        row[0]! as String: (
          row[1]! as double,
          row[2]! as double,
          row[3]! as int,
        ),
    };
  }

  Map<String, (double, double, int)> savedPositions(
    ConstellationLayoutSnapshot snapshot,
  ) => {
    for (final anchor in snapshot.anchors)
      anchor.targetId: (anchor.x, anchor.y, anchor.coordinateSpaceVersion),
  };

  Future<(T, bool)> afterOwnerScope<T>(
    Future<T> Function() write, {
    Future<void> Function()? beforeCommit,
  }) async {
    late Future<T> operation;
    final waited = await whileOwnerGraphScopeHeld(
      ownerGraph,
      _viewer,
      () {
        operation = write().timeout(ownerGraphWriteLimit)..ignore();
        return waitsForOwnerGraphScope(session.writer, _viewer, operation);
      },
      beforeCommit: beforeCommit,
    );
    return (await operation, waited);
  }

  void expectWaited({required bool waited}) {
    expect(
      waited,
      isTrue,
      reason: 'The write completed while its owner scope was held.',
    );
  }

  group('Constellation writes under owner scope contention', () {
    test(
      'anchor batches wait for their own viewer and let another viewer commit',
      () async {
        late Future<AnchorApplyOpResult> sameViewer;
        final (waited, visibleBeforeRelease) = await whileOwnerGraphScopeHeld(
          ownerGraph,
          _viewer,
          () async {
            await pin(
              _otherViewer,
              'other-viewer-pin',
              _movedPosition,
            ).timeout(ownerGraphWriteLimit);
            expect(await positions(_otherViewer), {_person: _movedPosition});

            sameViewer = pin(
              _viewer,
              'same-viewer-pin',
              _initialPosition,
            ).timeout(ownerGraphWriteLimit)..ignore();
            final waited = await waitsForOwnerGraphScope(
              session.writer,
              _viewer,
              sameViewer,
            );
            return (waited, await positions(_viewer));
          },
        );
        final result = await sameViewer;
        expect(result.clientOpId, 'same-viewer-pin');
        expect(await positions(_viewer), {_person: _initialPosition});
        expect(
          visibleBeforeRelease,
          isEmpty,
          reason: 'The anchor committed before its owner scope was released.',
        );
        expect(waited, isTrue);
      },
    );

    test(
      'snapshot save captures the layout committed by the owner it waited for',
      () async {
        await pin(_viewer, 'initial-pin', _initialPosition);

        final (saved, waited) = await afterOwnerScope(
          () => save('save-after-release'),
          beforeCommit: () => holderDb.customStatement(
            r'''
UPDATE public.constellation_anchor SET x_units = $1, y_units = $2
WHERE viewer_id = $3 AND person_id = $4
''',
            [_movedPosition.$1, _movedPosition.$2, _viewer, _person],
          ),
        );

        final listed = await snapshots.list(_viewer);
        expect(listed.single.id, saved.id);
        expect(await positions(_viewer), {_person: _movedPosition});
        expectWaited(waited: waited);
        expect(savedPositions(listed.single), {_person: _movedPosition});
      },
    );

    test(
      'snapshot restore waits and restores the saved anchor position',
      () async {
        await pin(_viewer, 'initial-pin', _initialPosition);
        final saved = await save('save-before-move');
        await pin(_viewer, 'move-pin', _movedPosition);

        final (restored, waited) = await afterOwnerScope(
          () => snapshots.restore(
            viewerId: _viewer,
            snapshotId: saved.id,
            clientOpId: 'restore-after-release',
          ),
        );

        expect(restored.id, saved.id);
        expect(await positions(_viewer), {_person: _initialPosition});
        expectWaited(waited: waited);
      },
    );

    test(
      'restoring the current favourite waits and restores its live positions',
      () async {
        await pin(_viewer, 'initial-pin', _initialPosition);
        final favourite = await save(
          'save-favourite-before-move',
          kind: ConstellationLayoutSnapshotKind.favourite,
        );
        await pin(_viewer, 'move-pin', _movedPosition);
        expect(savedPositions(favourite), {_person: _initialPosition});
        expect(await positions(_viewer), {_person: _movedPosition});

        final (_, waited) = await afterOwnerScope(
          () => snapshots.restoreFavourite(
            viewerId: _viewer,
            snapshotId: favourite.id,
            clientOpId: 'restore-favourite-after-release',
          ),
        );

        expect(await positions(_viewer), savedPositions(favourite));
        expectWaited(waited: waited);
      },
    );

    test(
      'anchor reset waits and clears the live anchors after release',
      () async {
        await pin(_viewer, 'initial-pin', _initialPosition);

        final (reset, waited) = await afterOwnerScope(
          () => anchors.resetAll(
            viewerId: _viewer,
            clientOpId: 'reset-after-release',
          ),
        );

        expect(reset.clearedCount, 1);
        expect(await positions(_viewer), isEmpty);
        expectWaited(waited: waited);
      },
    );
  });

  group('Anchor placement inside a read-committed owner scope', () {
    final positionedTarget = ConstellationAnchorTarget.person(_person);
    final secondTarget = ConstellationAnchorTarget.person(_secondPerson);
    late OwnerGraphTransactionPort transactions;

    setUp(() {
      transactions = OwnerGraphUnitOfWork(db);
    });

    Future<void> Function(OwnerGraphScope) scopedPlacement({
      String viewer = _viewer,
    }) {
      final upsert = _scopedAnchorUpsert(anchors);
      return (scope) => upsert(
        scope: scope,
        viewerId: viewer,
        target: positionedTarget,
        position: _anchorPosition(_movedPosition),
        additionalWatermarkTargets: {secondTarget},
      );
    }

    Future<Map<String, BigInt>> watermarks(String viewer) async {
      final rows = await db
          .customSelect(
            r'''
SELECT target_id, revision
FROM public.constellation_anchor_target_watermark
WHERE viewer_id = $1 AND target_kind = 'PERSON'
''',
            variables: [Variable.withString(viewer)],
          )
          .get();
      return {
        for (final row in rows)
          row.read<String>('target_id'): row.read<BigInt>('revision'),
      };
    }

    Future<int> positionedRowCount() async {
      final row = await db
          .customSelect(
            r'''
SELECT count(*)::int AS count FROM public.constellation_anchor
WHERE viewer_id = $1 AND target_kind = 'PERSON' AND target_id = $2
''',
            variables: [
              Variable.withString(_viewer),
              Variable.withString(_person),
            ],
          )
          .getSingle();
      return row.read<int>('count');
    }

    test('commits the exact position with the owner transaction', () async {
      await transactions.run({_viewer}, _viewer, (scope) async {
        await scopedPlacement()(scope);
        expect(await positionedRowCount(), 1);
        expect(
          await positions(_viewer),
          isEmpty,
          reason:
              'The new anchor must be invisible to other sessions before commit.',
        );
      });

      expect(await positions(_viewer), {_person: _movedPosition});
    });

    test(
      'advances all named targets and rejects stale conditional writes',
      () async {
        await pin(_viewer, 'positioned-target-pin', _initialPosition);
        await pin(
          _viewer,
          'second-target-pin',
          _initialPosition,
          person: _secondPerson,
        );
        final before = await watermarks(_viewer);
        expect(before.keys, unorderedEquals([_person, _secondPerson]));

        await transactions.run(
          {_viewer},
          _viewer,
          (scope) => scopedPlacement()(scope),
        );

        final committed = await watermarks(_viewer);
        final positionsAfterWrite = {
          _person: _movedPosition,
          _secondPerson: _initialPosition,
        };
        expect(await positions(_viewer), positionsAfterWrite);
        final cursor = await anchors.readWatermark(_viewer);
        for (final target in [positionedTarget, secondTarget]) {
          final targetId = target.id;
          expect(committed[targetId], greaterThan(before[targetId]!));
          final rejected = await anchors.applyBatch(
            viewerId: _viewer,
            ops: [
              AnchorApplyOp(
                clientOpId: 'stale-$targetId',
                kind: AnchorOpKind.upsert,
                target: target,
                position: _anchorPosition((7.25, -9.5, 1)),
                ifRevision: ConstellationAnchorRevision(before[targetId]!),
              ),
            ],
          );
          expect(rejected.results.single.status, AnchorOpStatus.rejected);
          expect(rejected.results.single.reason, 'conflict');
          expect(rejected.afterRevision, cursor);
          expect(await positions(_viewer), positionsAfterWrite);
          expect(await watermarks(_viewer), committed);
        }
      },
    );

    test(
      'rolls back the inserted anchor and every named watermark on failure',
      () async {
        await pin(_viewer, 'pin-before-reset', _initialPosition);
        await anchors.resetAll(
          viewerId: _viewer,
          clientOpId: 'reset-before-write',
        );
        await pin(
          _viewer,
          'second-target-pin',
          _initialPosition,
          person: _secondPerson,
        );
        final before = await watermarks(_viewer);
        expect(before.keys, unorderedEquals([_person, _secondPerson]));
        expect(await positionedRowCount(), 0);
        final place = scopedPlacement();
        final abort = StateError(
          'Abort the owner transaction after the anchor write',
        );

        await expectLater(
          transactions.run({_viewer}, _viewer, (scope) async {
            await place(scope);
            expect(await positionedRowCount(), 1);
            final inTransaction = await watermarks(_viewer);
            expect(inTransaction[_person], greaterThan(before[_person]!));
            expect(
              inTransaction[_secondPerson],
              greaterThan(before[_secondPerson]!),
            );
            throw abort;
          }),
          throwsA(same(abort)),
        );

        expect(await positionedRowCount(), 0);
        expect(await positions(_viewer), {_secondPerson: _initialPosition});
        expect(await watermarks(_viewer), before);
      },
    );

    test(
      'rejects a viewer outside the held scope before changing their graph',
      () async {
        await pin(_otherViewer, 'outside-viewer-pin', _initialPosition);
        await pin(
          _otherViewer,
          'outside-viewer-second-pin',
          _initialPosition,
          person: _secondPerson,
        );
        final beforePositions = await positions(_otherViewer);
        final beforeWatermarks = await watermarks(_otherViewer);

        await transactions.run({_viewer}, _otherViewer, (scope) async {
          final place = scopedPlacement(viewer: _otherViewer);
          // Catch the rejection inside run so a write followed by a throw
          // would still commit and be detectable.
          await expectLater(
            () => place(scope),
            throwsA(anyOf(isA<StateError>(), isA<ArgumentError>())),
          );
        });

        expect(await positions(_otherViewer), beforePositions);
        expect(await watermarks(_otherViewer), beforeWatermarks);
        expect(await positions(_viewer), isEmpty);
        expect(await watermarks(_viewer), isEmpty);
      },
    );
  });

  test(
    'anchor placement, layout changes and reset persist with database defaults',
    () async {
      final pinned = await pin(_viewer, 'place-pin', _initialPosition);
      expect(await positions(_viewer), {_person: _initialPosition});
      expect(
        await anchors.readWatermark(_viewer),
        pinned.resultingTargetRevision,
      );

      final original = await save('save-layout');
      expect(savedPositions(original), {_person: _initialPosition});
      await pin(_viewer, 'move-pin', _movedPosition);
      await save(
        'set-favourite',
        kind: ConstellationLayoutSnapshotKind.favourite,
      );
      await snapshots.restoreFavourite(
        viewerId: _viewer,
        snapshotId: original.id,
        clientOpId: 'restore-favourite',
      );
      final favourite = (await snapshots.list(_viewer)).singleWhere(
        (snapshot) =>
            snapshot.kind == ConstellationLayoutSnapshotKind.favourite,
      );
      expect(savedPositions(favourite), {_person: _initialPosition});
      expect(await positions(_viewer), {_person: _movedPosition});

      await snapshots.restore(
        viewerId: _viewer,
        snapshotId: original.id,
        clientOpId: 'restore-layout',
      );
      expect(await positions(_viewer), {_person: _initialPosition});

      final reset = await anchors.resetAll(
        viewerId: _viewer,
        clientOpId: 'reset-layout',
        saveHistory: true,
      );
      expect(reset.clearedCount, 1);
      expect(await positions(_viewer), isEmpty);
      final undo = (await snapshots.list(_viewer)).singleWhere(
        (snapshot) =>
            snapshot.reason == ConstellationLayoutSnapshotReason.reset,
      );
      expect(savedPositions(undo), {_person: _initialPosition});

      await expectDefaultOwnerScopeEnforcement(db);
    },
  );

  group('Constellation writes with owner scope enforcement enabled', () {
    Future<TenturaDb> enforcedDatabase() async {
      await enforceOwnerScope(session);
      final enforced = openDisposablePgDatabase(target);
      addTearDown(enforced.close);
      return enforced;
    }

    Future<List<Object?>> receipts() async {
      final rows = await session.writer.execute(
        Sql.named('''
SELECT client_op_id FROM public.constellation_anchor_op_log
WHERE viewer_id = @viewer ORDER BY revision
'''),
        parameters: {'viewer': _viewer},
      );
      return [for (final row in rows) row.single];
    }

    Future<int> targetRevision() async {
      final rows = await session.writer.execute(
        Sql.named('''
SELECT revision::int FROM public.constellation_anchor_target_watermark
WHERE viewer_id = @viewer AND target_kind = 'PERSON' AND target_id = @person
'''),
        parameters: {'viewer': _viewer, 'person': _person},
      );
      return rows.single.single! as int;
    }

    test('anchor batch commits its position, revision and receipt', () async {
      final repository = ConstellationAnchorRepository(
        await enforcedDatabase(),
      );
      final result = await pin(
        _viewer,
        'enforced-pin',
        _initialPosition,
        repository: repository,
      );

      expect(await positions(_viewer), {_person: _initialPosition});
      expect(await receipts(), ['enforced-pin']);
      final cursor = await repository.readWatermark(_viewer);
      expect(cursor, result.resultingTargetRevision);
      expect(BigInt.from(await targetRevision()), cursor.value);
    });

    test('snapshot save commits the current layout', () async {
      await pin(_viewer, 'initial-pin', _initialPosition);
      final repository = ConstellationLayoutSnapshotRepository(
        await enforcedDatabase(),
      );
      final saved = await save('enforced-save', repository: repository);

      final listed = (await repository.list(_viewer)).single;
      expect(listed.id, saved.id);
      expect(savedPositions(listed), {_person: _initialPosition});
    });

    test(
      'snapshot restore commits the saved layout and records undo history',
      () async {
        await pin(_viewer, 'initial-pin', _initialPosition);
        final saved = await save('save-before-move');
        await pin(_viewer, 'move-pin', _movedPosition);
        final revisionBefore = await targetRevision();
        final repository = ConstellationLayoutSnapshotRepository(
          await enforcedDatabase(),
        );

        await repository.restore(
          viewerId: _viewer,
          snapshotId: saved.id,
          clientOpId: 'enforced-restore',
        );

        expect(await positions(_viewer), {_person: _initialPosition});
        expect(await targetRevision(), greaterThan(revisionBefore));
        final undo = (await repository.list(_viewer)).singleWhere(
          (item) => item.reason == ConstellationLayoutSnapshotReason.restore,
        );
        expect(savedPositions(undo), {_person: _movedPosition});
      },
    );

    test(
      'favourite restore commits both the old favourite and undo history',
      () async {
        await pin(_viewer, 'initial-pin', _initialPosition);
        final saved = await save('save-before-move');
        await pin(_viewer, 'move-pin', _movedPosition);
        await save(
          'save-new-favourite',
          kind: ConstellationLayoutSnapshotKind.favourite,
        );
        final repository = ConstellationLayoutSnapshotRepository(
          await enforcedDatabase(),
        );

        await repository.restoreFavourite(
          viewerId: _viewer,
          snapshotId: saved.id,
          clientOpId: 'enforced-restore-favourite',
        );

        final listed = await repository.list(_viewer);
        final favourite = listed.singleWhere(
          (item) => item.kind == ConstellationLayoutSnapshotKind.favourite,
        );
        expect(savedPositions(favourite), {_person: _initialPosition});
        final undo = listed.singleWhere(
          (item) =>
              item.kind == ConstellationLayoutSnapshotKind.history &&
              item.reason == ConstellationLayoutSnapshotReason.restore,
        );
        expect(savedPositions(undo), {_person: _movedPosition});
        expect(await positions(_viewer), {_person: _movedPosition});
      },
    );

    test(
      'anchor reset commits its cleared count, revision, receipt and undo history',
      () async {
        await pin(_viewer, 'initial-pin', _initialPosition);
        final enforced = await enforcedDatabase();
        final repository = ConstellationAnchorRepository(enforced);
        final revisionBefore = await targetRevision();

        final reset = await repository.resetAll(
          viewerId: _viewer,
          clientOpId: 'enforced-reset',
          saveHistory: true,
        );

        expect(reset.clearedCount, 1);
        expect(await positions(_viewer), isEmpty);
        expect(await repository.readWatermark(_viewer), reset.afterRevision);
        expect(await targetRevision(), greaterThan(revisionBefore));
        expect(await receipts(), ['initial-pin', 'enforced-reset']);
        final undo = (await ConstellationLayoutSnapshotRepository(
          enforced,
        ).list(_viewer)).single;
        expect(undo.reason, ConstellationLayoutSnapshotReason.reset);
        expect(savedPositions(undo), {_person: _initialPosition});
      },
    );
  });
}
