@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide ConstellationAnchor, isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_anchor_projection_reader.dart';
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';
import 'package:tentura_server/data/repository/user_availability_repository.dart';
import 'package:tentura_server/data/repository/user_profile_batch_lookup.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/utils/id.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';

const _position = ConstellationAnchorPosition(
  xUnits: 2.5,
  yUnits: -4.25,
  coordinateSpaceVersion: 1,
);

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PLACEHOLDER_PINS_TEST_DB',
    defaultNamePrefix: 'tentura_test_placeholder_pins',
  );
  final skipReason = await pgSkipReason(target);

  group('Pins for people not on Tentura yet', () {
    late DisposablePgWriterSession session;
    late TenturaDb db;
    late ConstellationAnchorRepository repository;
    late _PinFixture pins;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      db = openDisposablePgDatabase(target);
      repository = ConstellationAnchorRepository(db);
      addTearDown(
        () => tearDownDisposablePgWriter(session: session, drift: db),
      );
    });

    setUp(() async {
      pins = _PinFixture(session.writer);
      await pins.insertUser(pins.viewer);
    });

    test(
      'pinning an active owned placeholder stores and returns its placement',
      () async {
        final phantom = await pins.insertPlaceholder(pins.viewer);
        final op = _upsert('place', _placeholderTarget(phantom), _position);
        final result = await repository.applyBatch(
          viewerId: pins.viewer,
          ops: [op],
        );

        _expectPlacement(result.results.single, op);
        expect((await pins.storedTargets()).single, [null, null, phantom]);
      },
    );

    test(
      'a mixed batch returns typed placements for all three kinds',
      () async {
        final person = generateId('U');
        await pins.insertUser(person);
        final beacon = await pins.insertBeacon();
        final phantom = await pins.insertPlaceholder(pins.viewer);
        final ops = [
          _upsert(
            'person',
            ConstellationAnchorTarget.person(person),
            _position,
          ),
          _upsert(
            'beacon',
            ConstellationAnchorTarget.beacon(beacon),
            const ConstellationAnchorPosition(
              xUnits: 5,
              yUnits: -1,
              coordinateSpaceVersion: 1,
            ),
          ),
          _upsert(
            'placeholder',
            _placeholderTarget(phantom),
            const ConstellationAnchorPosition(
              xUnits: -3,
              yUnits: 2,
              coordinateSpaceVersion: 1,
            ),
          ),
        ];
        final result = await repository.applyBatch(
          viewerId: pins.viewer,
          ops: ops,
        );

        expect(result.results, hasLength(ops.length));
        for (final (index, op) in ops.indexed) {
          _expectPlacement(result.results[index], op);
        }
        expect(
          await pins.storedTargets(),
          unorderedEquals([
            [person, null, null],
            [null, beacon, null],
            [null, null, phantom],
          ]),
        );
      },
    );

    for (final unavailable in _UnavailablePlaceholder.values) {
      test(
        'pinning ${unavailable.description} rejects the operation and writes no pin',
        () async {
          final phantom = switch (unavailable) {
            _UnavailablePlaceholder.foreignOwner =>
              await pins.insertForeignPlaceholder(),
            _UnavailablePlaceholder.merged =>
              await pins.insertMergedPlaceholder(),
            _UnavailablePlaceholder.missing => generateId('PH'),
          };
          final op = _upsert('place', _placeholderTarget(phantom), _position);
          final result = await repository.applyBatch(
            viewerId: pins.viewer,
            ops: [op],
          );

          _expectMissingTarget(result.results.single, op);
          expect(await pins.storedTargets(), isEmpty);
        },
      );
    }

    for (final firstAttemptReadCommitted in [false, true]) {
      test(
        firstAttemptReadCommitted
            ? 'a concurrent deletion that violates the placeholder foreign key retries and keeps the other pin'
            : 'a concurrent deletion that invalidates the snapshot retries and keeps the other pin',
        () async {
          final phantom = await pins.insertPlaceholder(pins.viewer);
          final person = generateId('U');
          await pins.insertUser(person);
          final keep = _upsert(
            'keep',
            ConstellationAnchorTarget.person(person),
            _position,
          );
          final removed = _upsert(
            'removed',
            _placeholderTarget(phantom),
            _position,
          );
          final deletion = _DeleteBeforeFlush(
            () => pins.deletePlaceholder(phantom),
            firstAttemptReadCommitted: firstAttemptReadCommitted,
          );
          final racingDb = TenturaDb(
            target.databaseEnv,
            scopeInterceptor: () => deletion,
          );
          addTearDown(racingDb.close);

          final result = await ConstellationAnchorRepository(racingDb)
              .applyBatch(
                viewerId: pins.viewer,
                ops: [keep, removed],
              );

          final firstFlushError = isA<ServerException>().having(
            (error) => error.code,
            'SQLSTATE',
            firstAttemptReadCommitted ? '23503' : '40001',
          );
          expect(
            deletion.firstFlushError,
            firstAttemptReadCommitted
                ? firstFlushError.having(
                    (error) => error.constraintName,
                    'constraint',
                    'constellation_anchor_phantom_id_fkey',
                  )
                : firstFlushError,
          );
          expect(result.results, hasLength(2));
          _expectPlacement(result.results.first, keep);
          _expectMissingTarget(result.results.last, removed);
          expect(await pins.storedTargets(), [
            [person, null, null],
          ]);
        },
      );
    }

    test(
      'the projection keeps ordinary pins alongside active owned placeholder pins',
      () async {
        final person = generateId('U');
        await pins.insertUser(person);
        const personPosition = ConstellationAnchorPosition(
          xUnits: -1.5,
          yUnits: 3,
          coordinateSpaceVersion: 1,
        );
        final personOp = _upsert(
          'person',
          ConstellationAnchorTarget.person(person),
          personPosition,
        );
        final placement = await repository.applyBatch(
          viewerId: pins.viewer,
          ops: [personOp],
        );
        _expectPlacement(placement.results.single, personOp);

        final active = await pins.insertPlaceholder(pins.viewer);
        final merged = await pins.insertPlaceholder(pins.viewer);
        final foreign = await pins.insertForeignPlaceholder();
        await pins.seedPlaceholderPins([active, merged, foreign]);
        await pins.mergePlaceholder(merged);
        expect(
          await pins.storedTargets(),
          unorderedEquals([
            [person, null, null],
            [null, null, active],
            [null, null, merged],
            [null, null, foreign],
          ]),
        );
        expect(await pins.beaconWithId(active), isEmpty);

        final profiles = DriftUserProfileBatchLookup(
          db,
          UserAvailabilityRepository(db),
        );
        final reader = ConstellationAnchorProjectionReader(db, profiles);
        final projection = await db.withReadSnapshot(
          () => reader.readForVisiblePeers(
            viewerId: pins.viewer,
            context: kConstellationContext,
            filters: ConstellationFieldMembershipFilters.defaults,
            visiblePeerIds: [person],
            trustEdges: () async => const [],
            peerProfiles: (ids) async =>
                (await profiles.constellationProfilesByIds(
                  ids,
                )).values.toList(),
          ),
        );

        expect(
          projection.anchors.map(
            (anchor) => (
              anchor.target.kind.wireValue,
              anchor.target.id,
              anchor.position,
            ),
          ),
          unorderedEquals([
            ('PERSON', person, personPosition),
            ('PHANTOM', active, _position),
          ]),
        );
      },
    );
  }, skip: skipReason);
}

enum _UnavailablePlaceholder {
  foreignOwner("another owner's placeholder"),
  merged('a merged placeholder'),
  missing('a missing placeholder');

  const _UnavailablePlaceholder(this.description);
  final String description;
}

ConstellationAnchorTarget _placeholderTarget(String id) {
  final target = ConstellationAnchorTarget.tryFromWire(
    kindWire: 'PHANTOM',
    targetId: id,
  );
  expect(
    target?.kind.wireValue,
    'PHANTOM',
    reason: 'PHANTOM must be a valid batch target',
  );
  return target!;
}

AnchorApplyOp _upsert(
  String id,
  ConstellationAnchorTarget target,
  ConstellationAnchorPosition position,
) => AnchorApplyOp(
  clientOpId: id,
  kind: AnchorOpKind.upsert,
  target: target,
  position: position,
);

void _expectPlacement(AnchorApplyOpResult result, AnchorApplyOp op) {
  expect(result.clientOpId, op.clientOpId);
  expect(result.status, AnchorOpStatus.ok, reason: result.reason);
  expect(
    result.anchor,
    isA<ConstellationAnchor>()
        .having((anchor) => anchor.target.kind, 'kind', op.target.kind)
        .having((anchor) => anchor.target.id, 'target id', op.target.id)
        .having((anchor) => anchor.position, 'position', op.position),
  );
}

void _expectMissingTarget(AnchorApplyOpResult result, AnchorApplyOp op) {
  expect(result.clientOpId, op.clientOpId);
  expect(result.status, AnchorOpStatus.rejected);
  expect(result.reason, 'target_not_found');
  expect(result.anchor, isNull);
}

final class _DeleteBeforeFlush extends QueryInterceptor {
  _DeleteBeforeFlush(this.delete, {required this.firstAttemptReadCommitted});

  final Future<void> Function() delete;
  final bool firstAttemptReadCommitted;
  var _deleted = false;
  ServerException? firstFlushError;

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    // The real FK sees the committed deletion at READ COMMITTED. Under
    // REPEATABLE READ the stale row instead produces a serialization failure.
    // Change only the first attempt of the test covering the FK retry.
    if (firstAttemptReadCommitted &&
        !_deleted &&
        statement ==
            'SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ WRITE') {
      return super.runCustom(
        executor,
        'SET TRANSACTION ISOLATION LEVEL READ COMMITTED READ WRITE',
        args,
      );
    }
    return super.runCustom(executor, statement, args);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (_deleted ||
        !statement.contains('public.constellation_anchor_apply_ops(')) {
      return super.runSelect(executor, statement, args);
    }
    _deleted = true;
    // applyBatch has validated and selected its writes before issuing this
    // statement. Commit the deletion on a separate session before the flush.
    await delete();
    try {
      return await super.runSelect(executor, statement, args);
    } on ServerException catch (error) {
      firstFlushError = error;
      rethrow;
    }
  }
}

final class _PinFixture {
  _PinFixture(this.writer);

  final Connection writer;
  final viewer = generateId('U');

  Future<void> insertUser(String id) => writer.execute(
    Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
    parameters: {'id': id, 'key': 'pk-$id'},
  );

  Future<String> insertBeacon() async {
    final id = generateId('B');
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status, published_at)
VALUES (@id, @viewer, 'Request to pin', 'Description', 0, now())
'''),
      parameters: {'id': id, 'viewer': viewer},
    );
    return id;
  }

  Future<Result> beaconWithId(String id) => writer.execute(
    Sql.named('SELECT id FROM public.beacon WHERE id = @id'),
    parameters: {'id': id},
  );

  Future<String> insertPlaceholder(String owner) async {
    final id = generateId('PH');
    await writer.executeWithOwnerScopes(
      [owner],
      Sql.named('''
INSERT INTO public.phantom (id, owner_id, display_name)
VALUES (@id, @owner, 'Anna')
'''),
      parameters: {'id': id, 'owner': owner},
    );
    return id;
  }

  Future<String> insertForeignPlaceholder() async {
    final owner = generateId('U');
    await insertUser(owner);
    return insertPlaceholder(owner);
  }

  Future<String> insertMergedPlaceholder() async {
    final id = await insertPlaceholder(viewer);
    await mergePlaceholder(id);
    return id;
  }

  Future<void> mergePlaceholder(String id) async {
    final user = generateId('U');
    final merge = generateId('PM');
    await insertUser(user);
    await withPgOwnerScopes(writer, [viewer], (tx) async {
      await tx.execute(
        Sql.named('''
INSERT INTO public.phantom_merge
  (id, phantom_id, owner_id, user_id, origin, created_at, undo)
VALUES (@merge, @id, @viewer, @user, 2, now(), '{}'::jsonb)
'''),
        parameters: {'merge': merge, 'id': id, 'viewer': viewer, 'user': user},
      );
      final updated = await tx.execute(
        Sql.named('''
UPDATE public.phantom
SET merged_user_id = @user, current_merge_id = @merge,
    merged_at = now(), merge_origin = 2
WHERE id = @id AND owner_id = @viewer
RETURNING id
'''),
        parameters: {'merge': merge, 'id': id, 'viewer': viewer, 'user': user},
      );
      expect(updated.single.single, id);
    });
  }

  Future<void> deletePlaceholder(String id) async {
    final deleted = await writer.executeWithOwnerScopes(
      [viewer],
      Sql.named('DELETE FROM public.phantom WHERE id = @id RETURNING id'),
      parameters: {'id': id},
    );
    expect(deleted.single.single, id);
  }

  Future<List<List<Object?>>> storedTargets() async => [
    for (final row in await writer.execute(
      Sql.named('''
SELECT person_id, beacon_id, phantom_id
FROM public.constellation_anchor WHERE viewer_id = @viewer
'''),
      parameters: {'viewer': viewer},
    ))
      row.toList(),
  ];

  Future<void> seedPlaceholderPins(List<String> ids) =>
      withPgOwnerScopes(writer, [viewer], (tx) async {
        await tx.execute(
          Sql.named('''
INSERT INTO public.constellation_anchor_cursor (viewer_id) VALUES (@viewer)
ON CONFLICT (viewer_id) DO NOTHING
'''),
          parameters: {'viewer': viewer},
        );
        for (final id in ids) {
          await tx.execute(
            Sql.named('''
INSERT INTO public.constellation_anchor (
  id, viewer_id, phantom_id, x_units, y_units,
  coordinate_space_version, revision, placed_at
) VALUES (@anchor, @viewer, @phantom, @x, @y, @version, 0, 'epoch')
'''),
            parameters: {
              'anchor': generateId('CA'),
              'viewer': viewer,
              'phantom': id,
              'x': _position.xUnits,
              'y': _position.yUnits,
              'version': _position.coordinateSpaceVersion,
            },
          );
        }
      });
}
