@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';

/// m0223: all existing data is brought into the default context, without
/// firing user triggers (no `updated_at` bump, no realtime hints).
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0223_FLATTEN_CONTEXTS_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0223_ctx',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  const author = 'Um0223ctxA001';
  const witness = 'Um0223ctxW001';
  const named = 'Bm0223ctxN001';
  const plain = 'Bm0223ctxP001';
  final stamp = DateTime.utc(2025, 10, 15, 12);

  late DisposablePgWriterSession session;
  late Connection writer;

  Future<Object?> one(String sql) async =>
      (await writer.execute(sql)).single.single;

  Future<void> applyM0223() async {
    for (final statement in m0223.statements) {
      await writer.execute(statement);
    }
  }

  setUpAll(() async {
    session = await setUpDisposablePgWriter(
      target: target,
      lastInclusiveVersion: '0222',
    );
    writer = session.writer;
    for (final id in [author, witness]) {
      await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'pk-$id') ON CONFLICT DO NOTHING
''');
    }
    for (final (id, context) in [(named, "'Fatum'"), (plain, 'NULL')]) {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, context,
                           created_at, updated_at)
VALUES ('$id', '$author', 't', 'd', $context, @stamp, @stamp)
'''),
        parameters: {'stamp': stamp},
      );
    }
    await writer.execute('''
INSERT INTO public.user_context (user_id, context_name)
VALUES ('$author', 'Fatum'), ('$author', 'QuestForGlory')
''');
    await writer.execute('''
INSERT INTO public.ego_witness_window
  (ego_user_id, context, witness_user_id, m, admitted, mr_epoch)
VALUES ('$author', 'Fatum', '$witness', 0.5, true, 1),
       ('$author', '', '$witness', 0.7, true, 1)
''');
    await applyM0223();
  });

  tearDownAll(() => tearDownDisposablePgWriter(session: session));

  test('named Request contexts become the default (NULL)', () async {
    expect(
      await one(
        'SELECT count(*) FROM public.beacon WHERE context IS NOT NULL',
      ),
      0,
    );
  });

  test(
    'flattening does not bump updated_at (user triggers disabled)',
    () async {
      final rows = await writer.execute(
        "SELECT updated_at FROM public.beacon WHERE id IN ('$named', '$plain')",
      );
      for (final row in rows) {
        expect((row.single! as DateTime).toUtc(), stamp);
      }
    },
  );

  test('user triggers on the touched tables are enabled again', () async {
    expect(
      await one('''
SELECT count(*) FROM pg_trigger
WHERE NOT tgisinternal AND tgenabled = 'D'
  AND tgrelid IN ('public.beacon'::regclass,
                  'public.beacon_forward_edge'::regclass,
                  'public.inbox_item'::regclass)
'''),
      0,
    );
  });

  test('named witness windows are dropped, the default one is kept', () async {
    final rows = await writer.execute(
      "SELECT context, m FROM public.ego_witness_window "
      "WHERE ego_user_id = '$author'",
    );
    expect(rows.map((r) => r[0]).toList(), ['']);
    expect(rows.single[1], 0.7);
  });

  test('context definitions stay (contexts remain a schema element)', () async {
    expect(await one('SELECT count(*) FROM public.user_context'), 2);
  });

  test('re-running the migration is a no-op', () async {
    await applyM0223();
    expect(
      await one(
        'SELECT count(*) FROM public.beacon WHERE context IS NOT NULL',
      ),
      0,
    );
    expect(await one('SELECT count(*) FROM public.ego_witness_window'), 1);
  });
}
