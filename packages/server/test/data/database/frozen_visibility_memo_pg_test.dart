@Tags(['pg', 'mr'])
library;

import 'dart:async';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';

/// A transaction that sets the tx-local `tentura_visibility.frozen` flag keeps
/// the first visible-set computation per (viewer, context) for the rest of the
/// transaction, whatever trust other connections commit meanwhile. Without the
/// flag the memo is still invalidated by every stamp change.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FROZEN_VISIBILITY_MEMO_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_frozen_vis_memo',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  const viewer = 'Ufrozenmemo0V01';
  const peer = 'Ufrozenmemo0P01';
  const churnA = 'Ufrozenmemo0A01';
  const churnB = 'Ufrozenmemo0B01';

  late DisposablePgWriterSession session;
  late Connection writer;
  late Connection conn;
  late Connection churn;

  Future<void> trust(
    Connection on,
    String subject,
    String object,
    int amount,
  ) => on.execute('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$subject', '$object', $amount, now(), now())
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount, updated_at = now()
''');

  Future<List<String>> visibleSet(String v, [String ctx = '']) async {
    final rows = await conn.execute(
      Sql.named('SELECT public.person_visible_peer_ids_tx(@v, @c)'),
      parameters: {'v': v, 'c': ctx},
    );
    return (rows.single.single! as List).cast<String>();
  }

  Future<void> freeze() => conn.execute(
    "SELECT set_config('tentura_visibility.frozen', 'on', true)",
  );

  Future<int> symmetricCalls() async {
    final rows = await writer.execute(
      'SELECT CASE WHEN is_called THEN last_value ELSE 0 END '
      'FROM public._frozen_symmetric_calls',
    );
    return rows.single.single! as int;
  }

  Future<void> resetSymmetricCalls() => writer.execute(
    "SELECT setval('public._frozen_symmetric_calls', 1, false)",
  );

  setUpAll(() async {
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    writer = session.writer;
    conn = await Connection.open(
      target.databaseEnv.pgEndpoint,
      settings: target.databaseEnv.pgEndpointSettings,
    );
    churn = await Connection.open(
      target.databaseEnv.pgEndpoint,
      settings: target.databaseEnv.pgEndpointSettings,
    );
    for (final id in [viewer, peer, churnA, churnB]) {
      await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'pk-$id') ON CONFLICT DO NOTHING
''');
    }
    await writer.execute(
      'CREATE SEQUENCE public._frozen_symmetric_calls START 1',
    );
    await writer.execute('''
ALTER FUNCTION public.person_visible_peers_symmetric(text, text)
  RENAME TO _frozen_symmetric_impl
''');
    await writer.execute(r'''
CREATE FUNCTION public.person_visible_peers_symmetric(viewer_id text, ctx text)
RETURNS TABLE(peer_id text) LANGUAGE plpgsql AS $$
BEGIN
  PERFORM nextval('public._frozen_symmetric_calls');
  IF current_setting('tentura_test.mr_down', true) = 'on' THEN
    RAISE EXCEPTION 'simulated MeritRank outage';
  END IF;
  RETURN QUERY SELECT s.peer_id FROM public._frozen_symmetric_impl(viewer_id, ctx) s;
END;
$$
''');
    await trust(writer, viewer, peer, 1);
    await trust(writer, peer, viewer, 1);
  });

  setUp(resetSymmetricCalls);

  tearDownAll(() async {
    await churn.close();
    await conn.close();
    await tearDownDisposablePgWriter(session: session);
  });

  test('the frozen-memo migration is registered after m0229', () {
    expect(
      migrationsForTesting.map((m) => m.version).toList()..sort(),
      contains('0230'),
    );
  });

  test(
    'without the flag a committed trust change invalidates the memo',
    () async {
      await conn.execute('BEGIN');
      try {
        await visibleSet(viewer);
        await trust(churn, churnA, churnB, 1);
        await visibleSet(viewer);
        expect(await symmetricCalls(), 2);
      } finally {
        await conn.execute('ROLLBACK');
      }
    },
  );

  test(
    'a frozen transaction ignores trust committed by another connection',
    () async {
      await conn.execute('BEGIN');
      try {
        await freeze();
        final first = await visibleSet(viewer);
        await trust(churn, churnA, churnB, -1);
        await trust(churn, churnB, churnA, -1);
        final second = await visibleSet(viewer);
        expect(second, first);
        expect(await symmetricCalls(), 1);
      } finally {
        await conn.execute('ROLLBACK');
      }
    },
  );

  test(
    'under continuous trust churn a frozen transaction computes once per '
    'viewer and context',
    () async {
      var stop = false;
      final churner = () async {
        var i = 0;
        while (!stop) {
          await trust(churn, churnA, churnB, (i++).isEven ? -1 : 1);
        }
      }();
      await conn.execute('BEGIN');
      try {
        await freeze();
        for (var i = 0; i < 20; i++) {
          await visibleSet(viewer);
          await visibleSet(viewer, 'ctx-a');
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(await symmetricCalls(), 2);
      } finally {
        await conn.execute('ROLLBACK');
        stop = true;
        await churner;
      }
    },
  );

  test(
    'a transaction that mutates trust is not frozen and invalidates',
    () async {
      await conn.execute('BEGIN');
      try {
        await visibleSet(viewer);
        await trust(conn, churnA, viewer, 1);
        await visibleSet(viewer);
        expect(await symmetricCalls(), 2);
      } finally {
        await conn.execute('ROLLBACK');
      }
    },
  );

  test('a MeritRank failure under the flag still fails closed', () async {
    await conn.execute('BEGIN');
    try {
      await freeze();
      await conn.execute("SET LOCAL tentura_test.mr_down = 'on'");
      expect(await visibleSet(viewer, 'ctx-down'), isEmpty);
      expect(await visibleSet(viewer, 'ctx-down'), isEmpty);
      expect(await symmetricCalls(), 1);
    } finally {
      await conn.execute('ROLLBACK');
    }
  });
}
