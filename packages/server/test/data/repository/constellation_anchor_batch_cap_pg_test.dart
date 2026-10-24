@Tags(['pg', 'mr'])
library;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:postgres/postgres.dart' show Connection, ServerException;
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide ConstellationAnchor, isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';

/// A full 400-operation anchor batch is one atomic transaction that finishes
/// inside the repository's five-second repeatable-read retry budget.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_ANCHOR_BATCH_CAP_TEST_DB',
    defaultNamePrefix: 'tentura_test_cabcap',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  const viewer = 'Ucabcapviewer01';
  const batchSize = 400;
  final peers = [
    for (var i = 0; i < batchSize; i++)
      'Ucabcap${i.toString().padLeft(8, '0')}',
  ];

  late DisposablePgWriterSession session;
  late Connection backend;
  late TenturaDb db;
  late ConstellationAnchorRepositoryPort repository;

  AnchorApplyOp upsert(String opId, String targetId) => AnchorApplyOp(
    clientOpId: opId,
    kind: AnchorOpKind.upsert,
    target: ConstellationAnchorTarget.person(targetId),
    position: const ConstellationAnchorPosition(
      xUnits: 1,
      yUnits: -1,
      coordinateSpaceVersion: 1,
    ),
  );

  setUpAll(() async {
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    backend = await Connection.open(
      target.databaseEnv.pgEndpoint,
      settings: target.databaseEnv.pgEndpointSettings,
    );
    db = TenturaDb.forTest(
      database: PgDatabase.opened(backend, enableMigrations: false),
    );
    repository = ConstellationAnchorRepository(db);
  });

  tearDownAll(() async {
    await db.close();
    if (backend.isOpen) await backend.close();
    await tearDownDisposablePgWriter(session: session);
  });

  setUp(() async {
    final writer = session.writer;
    await writer.execute('DELETE FROM public.constellation_anchor');
    await writer.execute('DELETE FROM public.constellation_anchor_cursor');
    await writer.execute('DELETE FROM public.constellation_anchor_op_log');
    await writer.execute(
      'DELETE FROM public.constellation_anchor_target_watermark',
    );
    await writer.execute('DELETE FROM public.vote_user');
    await writer.execute('DELETE FROM public."user"');
    for (final id in [viewer, ...peers]) {
      await writer.execute('''
INSERT INTO public."user"
  (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id',
        '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
''');
    }
    await writer.execute('SELECT public.mr_reset()');
    for (final peer in peers) {
      await writer.execute('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$viewer', '$peer', 1, now(), now()),
       ('$peer', '$viewer', 1, now(), now())
''');
      for (final (src, dst) in [(viewer, peer), (peer, viewer)]) {
        await writer.execute('''
SELECT public.mr_put_edge(
  '$src', '$dst', 0.75::double precision, '$kConstellationContext', 0)
''');
      }
    }
    await writer.execute('''
INSERT INTO public.constellation_anchor_cursor (viewer_id, revision)
VALUES ('$viewer', 0)
''');
  });

  group('anchor batch of the maximum size', () {
    test(
      '400 upserts commit atomically in one revision step within the retry '
      'budget',
      () async {
        final clock = Stopwatch()..start();
        final result = await repository.applyBatch(
          viewerId: viewer,
          ops: [
            for (var i = 0; i < batchSize; i++) upsert('cap-$i', peers[i]),
          ],
        );
        clock.stop();

        expect(result.results, hasLength(batchSize));
        expect(
          result.results.map((r) => r.status),
          everyElement(AnchorOpStatus.ok),
        );
        expect(
          result.afterRevision.value - result.beforeRevision.value,
          BigInt.from(batchSize),
        );
        final stored = await session.writer.execute('''
SELECT count(*) FROM public.constellation_anchor WHERE viewer_id = '$viewer'
''');
        expect(stored.single.single, batchSize);
        expect(
          clock.elapsed,
          lessThan(const Duration(seconds: 5)),
          reason: 'The batch must fit the five-second transaction budget.',
        );
      },
    );

    test(
      'a database error on the last of 400 operations leaves no row, log '
      'entry or revision change behind',
      () async {
        final ops = [
          for (var i = 0; i < batchSize; i++) upsert('cap-$i', peers[i]),
        ];
        Future<void> removeFault() async {
          await session.writer.execute('''
DROP TRIGGER IF EXISTS cap_batch_rollback_probe
ON public.constellation_anchor_op_log
''');
          await session.writer.execute(
            'DROP FUNCTION IF EXISTS public.cap_batch_rollback_probe()',
          );
        }

        addTearDown(removeFault);
        // Fires at commit, after all 400 operations have been written.
        await session.writer.execute('''
CREATE FUNCTION public.cap_batch_rollback_probe()
RETURNS trigger LANGUAGE plpgsql AS \$probe\$
BEGIN
  IF NEW.client_op_id = 'cap-${batchSize - 1}' THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001',
      MESSAGE = 'cap_batch_rollback_probe';
  END IF;
  RETURN NEW;
END;
\$probe\$
''');
        await session.writer.execute('''
CREATE CONSTRAINT TRIGGER cap_batch_rollback_probe
AFTER INSERT ON public.constellation_anchor_op_log
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION public.cap_batch_rollback_probe()
''');

        await expectLater(
          repository.applyBatch(viewerId: viewer, ops: ops),
          throwsA(
            isA<ServerException>().having(
              (error) => error.message,
              'fault after 400 writes',
              'cap_batch_rollback_probe',
            ),
          ),
        );

        Future<Object?> count(String table) async =>
            (await session.writer.execute(
              "SELECT count(*) FROM public.$table WHERE viewer_id = '$viewer'",
            )).single.single;
        expect(await count('constellation_anchor'), 0);
        expect(await count('constellation_anchor_op_log'), 0);
        expect(
          await repository.readWatermark(viewer),
          ConstellationAnchorRevision.zero,
        );

        await removeFault();
        final recovered = await repository.applyBatch(
          viewerId: viewer,
          ops: ops,
        );
        expect(
          recovered.results.map((r) => r.status),
          everyElement(AnchorOpStatus.ok),
        );
        expect(await count('constellation_anchor'), batchSize);
      },
    );
  });
}
