@Tags(['pg'])
library;

import 'dart:typed_data';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';

/// Idempotency op log and per-target revision watermark for constellation
/// anchor batches. Sizes are enforced by the schema, not by callers.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_OP_LOG_SCHEMA_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_ca_oplog',
  );

  final migrationTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_OP_LOG_SCHEMA_MIGRATION_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_ca_oplog_mig',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  const viewer = 'Ucaoplogview01';
  const person = 'Ucaoplogpers01';

  late DisposablePgWriterSession session;
  late Connection writer;

  final digest = Uint8List.fromList(List<int>.generate(32, (i) => i));

  Future<void> seedUser(String id) => writer.execute('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''');

  Future<void> insertOp({
    String viewerId = viewer,
    required String opId,
    Uint8List? fingerprint,
    String result = '{"status":"applied"}',
  }) => writer.execute(
    Sql.named('''
INSERT INTO public.constellation_anchor_op_log
  (viewer_id, client_op_id, fingerprint, result, revision, created_at)
VALUES (@v, @op, @fp, @res::jsonb, 1, now())
'''),
    parameters: {
      'v': viewerId,
      'op': opId,
      'fp': fingerprint ?? digest,
      'res': result,
    },
  );

  Future<int> count(String table, String viewerId) async {
    final rows = await writer.execute(
      "SELECT count(*) FROM public.$table WHERE viewer_id = '$viewerId'",
    );
    return rows.single.single! as int;
  }

  group('upgrade from the previous schema version', () {
    late DisposablePgWriterSession upgradeSession;

    setUpAll(() async {
      upgradeSession = await setUpDisposablePgWriter(
        target: migrationTarget,
        lastInclusiveVersion: '0227',
        createPgmer2Extension: true,
      );
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: upgradeSession);
    });

    Future<bool> tableExists(Connection c, String name) async {
      final rows = await c.execute(
        "SELECT to_regclass('public.$name') IS NOT NULL",
      );
      return rows.single.single! as bool;
    }

    test('adds both tables and keeps existing users and anchors', () async {
      final c = upgradeSession.writer;
      expect(await tableExists(c, 'constellation_anchor_op_log'), isFalse);
      expect(
        await tableExists(c, 'constellation_anchor_target_watermark'),
        isFalse,
      );
      await c.execute('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('Ucaoplogupg001', 'u', 'pk-upg1', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
       ('Ucaoplogupg002', 'p', 'pk-upg2', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
''');
      await c.execute('''
INSERT INTO public.constellation_anchor_cursor (viewer_id, revision)
VALUES ('Ucaoplogupg001', 0)
''');
      await c.execute('''
INSERT INTO public.constellation_anchor
  (id, viewer_id, person_id, x_units, y_units, coordinate_space_version,
   revision, placed_at)
VALUES ('Aoplogupg001', 'Ucaoplogupg001', 'Ucaoplogupg002', 0, 0, 1, 1, now())
''');

      await migrateDbSchema(c);

      expect(await tableExists(c, 'constellation_anchor_op_log'), isTrue);
      expect(
        await tableExists(c, 'constellation_anchor_target_watermark'),
        isTrue,
      );
      final anchors = await c.execute(
        "SELECT count(*) FROM public.constellation_anchor "
        "WHERE id = 'Aoplogupg001'",
      );
      expect(anchors.single.single, 1);
    });

    test(
      'upgraded op log enforces sizes and cascades on user delete',
      () async {
        final c = upgradeSession.writer;
        Future<void> insert(String op, Uint8List fp) => c.execute(
          Sql.named('''
INSERT INTO public.constellation_anchor_op_log
  (viewer_id, client_op_id, fingerprint, result, revision, created_at)
VALUES ('Ucaoplogupg001', @op, @fp, '{}'::jsonb, 1, now())
'''),
          parameters: {'op': op, 'fp': fp},
        );

        await expectLater(
          insert('a' * 65, digest),
          throwsA(
            isA<ServerException>().having((e) => e.code, 'code', '22001'),
          ),
        );
        await expectLater(
          insert('short-fp', Uint8List(31)),
          throwsA(
            isA<ServerException>().having((e) => e.code, 'code', '23514'),
          ),
        );
        await insert('ok', digest);
        await c.execute(
          "DELETE FROM public.\"user\" WHERE id = 'Ucaoplogupg001'",
        );
        final rows = await c.execute(
          'SELECT count(*) FROM public.constellation_anchor_op_log',
        );
        expect(rows.single.single, 0);
      },
    );
  });

  setUpAll(() async {
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    writer = session.writer;
    await seedUser(viewer);
    await seedUser(person);
  });

  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session);
  });

  group('constellation anchor op log', () {
    test('primary key rejects a repeated (viewer, client op id)', () async {
      await insertOp(opId: 'op-dup');
      await expectLater(
        insertOp(opId: 'op-dup'),
        throwsA(isA<ServerException>().having((e) => e.code, 'code', '23505')),
      );
    });

    test(
      'client op id of 65 characters violates the varchar(64) limit',
      () async {
        await insertOp(opId: 'a' * 64);
        await expectLater(
          insertOp(opId: 'a' * 65),
          throwsA(
            isA<ServerException>().having((e) => e.code, 'code', '22001'),
          ),
        );
      },
    );

    test('fingerprint must be exactly 32 bytes', () async {
      for (final len in [31, 33]) {
        await expectLater(
          insertOp(opId: 'fp-$len', fingerprint: Uint8List(len)),
          throwsA(
            isA<ServerException>().having((e) => e.code, 'code', '23514'),
          ),
        );
      }
      await insertOp(opId: 'fp-32');
    });

    test(
      'result larger than 256 bytes is rejected, 256 bytes accepted',
      () async {
        String resultOfSize(int bytes) {
          const wrapper = '{"r":""}';
          return '{"r":"${'x' * (bytes - wrapper.length)}"}';
        }

        await insertOp(opId: 'res-256', result: resultOfSize(256));
        await expectLater(
          insertOp(opId: 'res-257', result: resultOfSize(257)),
          throwsA(
            isA<ServerException>().having((e) => e.code, 'code', '23514'),
          ),
        );
      },
    );

    test('has no secondary indexes beyond the primary key', () async {
      final rows = await writer.execute('''
SELECT indexname FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN ('constellation_anchor_op_log',
                    'constellation_anchor_target_watermark')
''');
      expect(
        rows.map((r) => r.single).toSet(),
        {
          'constellation_anchor_op_log_pkey',
          'constellation_anchor_target_watermark_pkey',
        },
      );
    });

    test('deleting the viewer cascades their op log rows only', () async {
      const doomed = 'Ucaoplogdoom01';
      await seedUser(doomed);
      await insertOp(viewerId: doomed, opId: 'cascade-1');
      await insertOp(viewerId: doomed, opId: 'cascade-2');
      await insertOp(opId: 'cascade-keep');
      expect(await count('constellation_anchor_op_log', doomed), 2);

      await writer.execute('DELETE FROM public."user" WHERE id = \'$doomed\'');

      expect(await count('constellation_anchor_op_log', doomed), 0);
      expect(
        await count('constellation_anchor_op_log', viewer),
        greaterThan(0),
      );
    });
  });

  group('constellation anchor target watermark', () {
    Future<void> upsertWatermark(int revision) => writer.execute('''
INSERT INTO public.constellation_anchor_target_watermark
  (viewer_id, target_kind, target_id, revision)
VALUES ('$viewer', 'person', '$person', $revision)
ON CONFLICT (viewer_id, target_kind, target_id)
DO UPDATE SET revision = EXCLUDED.revision
''');

    test('survives deletion of the anchor it describes', () async {
      await writer.execute('''
INSERT INTO public.constellation_anchor_cursor (viewer_id, revision)
VALUES ('$viewer', 0) ON CONFLICT (viewer_id) DO NOTHING
''');
      await writer.execute('''
INSERT INTO public.constellation_anchor
  (id, viewer_id, person_id, x_units, y_units, coordinate_space_version,
   revision, placed_at)
VALUES ('Aoplogwm0001', '$viewer', '$person', 0, 0, 1, 1, now())
''');
      await upsertWatermark(5);

      await writer.execute(
        "DELETE FROM public.constellation_anchor WHERE id = 'Aoplogwm0001'",
      );

      final rows = await writer.execute('''
SELECT revision FROM public.constellation_anchor_target_watermark
WHERE viewer_id = '$viewer' AND target_kind = 'person' AND target_id = '$person'
''');
      expect(rows.single.single, 5);
    });
  });
}
