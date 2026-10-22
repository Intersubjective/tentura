@Tags(['pg'])
library;

import 'package:test/test.dart';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide ConstellationAnchor, isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';

import '../../support/constellation_anchor_batch_fixture.dart';
import '../../support/disposable_pg_target.dart';

/// «Arrange in a sector» (#644) on the server: the client sends the arranged
/// people as one batch of upserts based on the revision the user saw. The
/// batch commits whole, stays after a reload, is refused whole when a reset
/// (#251, m0256) came after its base revision, and a reset removes it.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_ANCHOR_SECTOR_TEST_DB',
    defaultNamePrefix: 'tentura_test_anchorsector',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  const viewer = 'Usecviewer001';
  final people = [for (var i = 1; i <= 5; i++) 'Usecperson00$i'];

  late DisposablePgWriterSession session;
  late TenturaDb db;
  late ConstellationAnchorRepository repo;

  Future<Map<String, ({double x, double y})>> stored() async {
    final rows = await db
        .customSelect(
          'SELECT person_id, x_units, y_units '
          'FROM public.constellation_anchor '
          "WHERE viewer_id = '$viewer' AND person_id IS NOT NULL",
        )
        .get();
    return {
      for (final row in rows)
        row.read<String>('person_id'): (
          x: row.read<double>('x_units'),
          y: row.read<double>('y_units'),
        ),
    };
  }

  Future<ConstellationAnchorRevision> cursor() => repo.readWatermark(viewer);

  /// The arrangement: everyone on an arc below the viewer, one batch.
  List<AnchorApplyOp> arrangement(
    String batch, {
    ConstellationAnchorRevision? baseRevision,
  }) => [
    for (var i = 0; i < people.length; i++)
      AnchorApplyOp(
        clientOpId: '$batch-$i',
        kind: AnchorOpKind.upsert,
        target: ConstellationAnchorTarget.person(people[i]),
        position: ConstellationAnchorPosition(
          xUnits: -2 + i + 0.25,
          yUnits: 3.5,
          coordinateSpaceVersion: 1,
        ),
        baseRevision: baseRevision,
      ),
  ];

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    db = openDisposablePgDatabase(target);
    repo = constellationAnchorRepositoryFor(db);
  });

  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: db);
  });

  setUp(() async {
    await db.customStatement(
      'TRUNCATE public.constellation_anchor, public.constellation_anchor_cursor, '
      'public.constellation_anchor_op_log, '
      'public.constellation_anchor_target_watermark CASCADE',
    );
    for (final id in [viewer, ...people]) {
      await db.customStatement('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'pk-$id') ON CONFLICT (id) DO NOTHING
''');
    }
  });

  test('one batch places everyone and stays after a reload', () async {
    final base = await cursor();

    final result = await repo.applyBatch(
      viewerId: viewer,
      ops: arrangement('arrange', baseRevision: base),
    );

    expect(
      result.results.map((r) => r.status),
      everyElement(AnchorOpStatus.ok),
    );
    expect(result.results, hasLength(people.length));
    final positions = await stored();
    expect(positions.keys, unorderedEquals(people));
    for (var i = 0; i < people.length; i++) {
      expect(positions[people[i]]!.x, closeTo(-2 + i + 0.25, 1e-9));
      expect(positions[people[i]]!.y, closeTo(3.5, 1e-9));
    }
    expect((await cursor()).value, result.afterRevision.value);
  });

  test(
    'a batch based on a revision older than a reset is refused whole',
    () async {
      final staleBase = await cursor();
      await repo.resetAll(viewerId: viewer, clientOpId: 'reset-1');

      final result = await repo.applyBatch(
        viewerId: viewer,
        ops: arrangement('late', baseRevision: staleBase),
      );

      expect(result.results, hasLength(people.length));
      for (final op in result.results) {
        expect(op.status, AnchorOpStatus.rejected);
        expect(op.reason, 'reset');
      }
      expect(await stored(), isEmpty);
    },
  );

  test('«Сбросить позиции» removes the arrangement', () async {
    await repo.applyBatch(
      viewerId: viewer,
      ops: arrangement('arrange', baseRevision: await cursor()),
    );
    expect(await stored(), hasLength(people.length));

    final reset = await repo.resetAll(viewerId: viewer, clientOpId: 'reset-2');

    expect(reset.clearedCount, people.length);
    expect(await stored(), isEmpty);
  });

  test('a retried batch is not applied twice', () async {
    final ops = arrangement('arrange', baseRevision: await cursor());
    final first = await repo.applyBatch(viewerId: viewer, ops: ops);
    final retry = await repo.applyBatch(viewerId: viewer, ops: ops);

    expect(retry.results.map((r) => r.replayed), everyElement(isTrue));
    expect((await cursor()).value, first.afterRevision.value);
  });
}
