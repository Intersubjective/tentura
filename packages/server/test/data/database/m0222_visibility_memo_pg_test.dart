@Tags(['pg', 'mr'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';

/// m0223: the viewer's mutually visible set is computed once per transaction
/// and memoized in a transaction-local setting, in read-only transactions
/// too. It replaced the cross-transaction `person_mutual_visibility_cache`,
/// which read-only transactions (Hasura, constellation) could not fill.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0222_VISIBILITY_MEMO_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0222_vis_memo',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  const viewer = 'Um0222memoV001';
  const peer = 'Um0222memoP001';
  const stranger = 'Um0222memoS001';
  const other = 'Um0222memoO001';

  late DisposablePgWriterSession session;
  late Connection writer;
  late Connection conn;

  Future<void> trust(String subject, String object, {int amount = 1}) =>
      writer.execute('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$subject', '$object', $amount, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''');

  Future<bool> visible(String a, String b, {Connection? on}) async {
    final rows = await (on ?? conn).execute(
      Sql.named(
        "SELECT public.person_are_mutually_visible_cached(@a, @b, '')",
      ),
      parameters: {'a': a, 'b': b},
    );
    return rows.single.single! as bool;
  }

  Future<int> symmetricCalls() async {
    final rows = await writer.execute(
      'SELECT CASE WHEN is_called THEN last_value ELSE 0 END '
      'FROM public._m0222_symmetric_calls',
    );
    return rows.single.single! as int;
  }

  Future<void> resetSymmetricCalls() => writer.execute(
    "SELECT setval('public._m0222_symmetric_calls', 1, false)",
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
    for (final id in [viewer, peer, stranger, other]) {
      await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'pk-$id') ON CONFLICT DO NOTHING
''');
    }
    // Count evaluations of the symmetric set through a wrapper. A sequence is
    // non-transactional, so the count survives the subtransaction rollback of
    // a simulated MeritRank outage; nextval needs a read-write transaction.
    await writer.execute(
      'CREATE SEQUENCE public._m0222_symmetric_calls START 1',
    );
    await writer.execute('''
ALTER FUNCTION public.person_visible_peers_symmetric(text, text)
  RENAME TO _m0222_symmetric_impl
''');
    await writer.execute(r'''
CREATE FUNCTION public.person_visible_peers_symmetric(viewer_id text, ctx text)
RETURNS TABLE(peer_id text) LANGUAGE plpgsql AS $$
BEGIN
  IF current_setting('transaction_read_only') = 'off' THEN
    PERFORM nextval('public._m0222_symmetric_calls');
  END IF;
  IF current_setting('tentura_test.mr_down', true) = 'on' THEN
    RAISE EXCEPTION 'simulated MeritRank outage';
  END IF;
  RETURN QUERY SELECT s.peer_id FROM public._m0222_symmetric_impl(viewer_id, ctx) s;
END;
$$
''');
    await trust(viewer, peer);
    await trust(peer, viewer);
  });

  setUp(resetSymmetricCalls);

  tearDownAll(() async {
    await conn.close();
    await tearDownDisposablePgWriter(session: session);
  });

  test('the memo migration is registered', () {
    expect(migrationsForTesting.map((m) => m.version), contains('0222'));
  });

  test(
    'visibility helpers take no advisory locks and never cache blocks',
    () async {
      for (final fn in [
        'person_are_mutually_visible_cached(text,text,text)',
        'person_are_mutually_visible(text,text,text)',
        'person_visible_peer_ids_tx(text,text)',
      ]) {
        final rows = await writer.execute(
          "SELECT pg_get_functiondef('public.$fn'::regprocedure)",
        );
        final def = rows.single.single! as String;
        expect(def, isNot(contains('advisory')), reason: fn);
        expect(def, isNot(contains('block_hides')), reason: fn);
      }
    },
  );

  test('one transaction computes the viewer set once for many rows', () async {
    await conn.execute('BEGIN');
    try {
      // The reciprocal-trust short-circuit never reaches the set, so ask
      // about people who are not reciprocally trusted.
      for (var i = 0; i < 5; i++) {
        expect(await visible(viewer, stranger), isFalse);
        expect(await visible(viewer, other), isFalse);
      }
      expect(await symmetricCalls(), 1);
    } finally {
      await conn.execute('COMMIT');
    }
  });

  test('read-only transactions memoize and answer correctly', () async {
    await conn.execute('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
    try {
      expect(await visible(viewer, peer), isTrue);
      expect(await visible(viewer, stranger), isFalse);
      final rows = await conn.execute(
        Sql.named(
          "SELECT current_setting('tentura_visibility.p' || md5(@v || chr(31) || ''), true)",
        ),
        parameters: {'v': viewer},
      );
      expect(rows.single.single, isNotNull);
      expect(rows.single.single, isNotEmpty);
    } finally {
      await conn.execute('COMMIT');
    }
  });

  test(
    'a trust write later in the same transaction is not served stale',
    () async {
      await conn.execute('BEGIN');
      try {
        expect(await visible(viewer, stranger), isFalse);
        await conn.execute('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$viewer', '$stranger', 1, now(), now()), ('$stranger', '$viewer', 1, now(), now())
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''');
        // Reciprocal trust answers without the set; the memo must also see it.
        expect(await visible(viewer, stranger), isTrue);
        final rows = await conn.execute(
          Sql.named(
            "SELECT @s = ANY(public.person_visible_peer_ids_tx(@v, ''))",
          ),
          parameters: {'v': viewer, 's': stranger},
        );
        expect(rows.single.single, isTrue);
        expect(await symmetricCalls(), 2);
      } finally {
        await conn.execute('ROLLBACK');
      }
    },
  );

  test('the memo does not outlive its transaction', () async {
    for (var i = 0; i < 3; i++) {
      await conn.execute('BEGIN');
      try {
        expect(await visible(viewer, stranger), isFalse);
      } finally {
        await conn.execute('COMMIT');
      }
    }
    expect(await symmetricCalls(), 3);
  });

  test(
    'MeritRank outage fails closed once per transaction, without errors',
    () async {
      await conn.execute('BEGIN');
      try {
        await conn.execute("SET LOCAL tentura_test.mr_down = 'on'");
        for (var i = 0; i < 4; i++) {
          expect(await visible(viewer, other), isFalse);
        }
        // Reciprocal explicit trust does not depend on MeritRank.
        expect(await visible(viewer, peer), isTrue);
        expect(
          await symmetricCalls(),
          1,
          reason: 'an outage must not be retried (and time out) once per row',
        );
      } finally {
        await conn.execute('ROLLBACK');
      }
    },
  );
}
