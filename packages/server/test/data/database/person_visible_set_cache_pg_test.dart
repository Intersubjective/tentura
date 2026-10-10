@Tags(['pg', 'mr'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';

/// The viewer's visible set is stored across transactions in
/// `person_visible_set_cache`, keyed by (viewer, context, MeritRank publish
/// epoch, trust generation). `person_visible_peer_ids_tx` consults the row
/// under the request's snapshot and fills it on a miss; a trust or block
/// change committed by anyone makes the next read a miss, and a degraded
/// (MeritRank failure) result is never stored.
///
/// A read is a hit or a miss by whether it made a MeritRank RPC
/// (`mr_rpc_attempts()` delta on the reading backend), the same measure the
/// warm-FULL perf gate uses; results are compared with
/// `person_visible_peers_symmetric`, the uncached computation. The only
/// implementation seam is the MeritRank-outage injection of the
/// 'degraded results' group (see there). The table name and its columns are
/// those of ARCH §7.4a (`docs/plans/issue-235-constellation-interactive-
/// architecture.md`), which is binding.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PERSON_VISIBLE_SET_CACHE_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_vis_set_cache',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  const viewer = 'Uvissetcache0V001';
  const peer = 'Uvissetcache0P001';
  const joiner = 'Uvissetcache0L001';
  const oneWay = 'Uvissetcache0O001';
  const stranger = 'Uvissetcache0S001';
  const otherCtx = 'ctx-a';

  late DisposablePgWriterSession session;
  late Connection writer;
  late Connection conn;
  late Connection churn;

  Future<void> trust(
    Connection on,
    String subject,
    String object, {
    int amount = 1,
  }) => on.execute('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$subject', '$object', $amount, now(), now())
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount, updated_at = now()
''');

  Future<void> trustBothWays(Connection on, String a, String b) async {
    await trust(on, a, b);
    await trust(on, b, a);
  }

  Future<void> revokeBothWays(Connection on, String a, String b) async {
    await trust(on, a, b, amount: -1);
    await trust(on, b, a, amount: -1);
  }

  Future<void> block(String blocker, String blocked) => writer.execute('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$blocker', '$blocked', '$blocker')
''');

  Future<void> bumpMrEpoch() => writer.execute(
    'UPDATE public.mr_publish_epoch SET epoch = epoch + 1 WHERE id = true',
  );

  Future<List<String>> visibleSet(
    Connection on,
    String v, [
    String ctx = '',
  ]) async {
    final rows = await on.execute(
      Sql.named('SELECT public.person_visible_peer_ids_tx(@v, @c)'),
      parameters: {'v': v, 'c': ctx},
    );
    return ((rows.single.single! as List).cast<String>())..sort();
  }

  /// What the visible set is when nothing is cached.
  Future<List<String>> uncachedSet(String v, [String ctx = '']) async {
    final rows = await writer.execute(
      Sql.named(
        'SELECT coalesce(array_agg(s.peer_id ORDER BY s.peer_id), '
        "'{}'::text[]) FROM public.person_visible_peers_symmetric(@v, @c) s",
      ),
      parameters: {'v': v, 'c': ctx},
    );
    return (rows.single.single! as List).cast<String>();
  }

  Future<List<({String ctx, int mrEpoch, int trustGen, List<String> peerIds})>>
  cacheRows(String v) async {
    final rows = await writer.execute(
      Sql.named(
        'SELECT ctx, mr_epoch, trust_gen, peer_ids '
        'FROM public.person_visible_set_cache WHERE viewer_id = @v '
        'ORDER BY ctx',
      ),
      parameters: {'v': v},
    );
    return [
      for (final r in rows)
        (
          ctx: r[0]! as String,
          mrEpoch: r[1]! as int,
          trustGen: r[2]! as int,
          peerIds: (r[3]! as List).cast<String>(),
        ),
    ];
  }

  Future<int> mrEpoch() async {
    final rows = await writer.execute(
      'SELECT epoch FROM public.mr_publish_epoch WHERE id = true',
    );
    return rows.single.single! as int;
  }

  Future<int> mrRpcAttempts(Connection on) async {
    final rows = await on.execute('SELECT public.mr_rpc_attempts()');
    return rows.single.single! as int;
  }

  /// One committed read-write transaction on [on] that reads the visible set
  /// of [v], with the MeritRank RPCs it made. Zero RPCs means the set was
  /// served from the cache.
  Future<({List<String> set, int rpcs})> read(
    String v, {
    String ctx = '',
    Connection? on,
  }) async {
    final c = on ?? conn;
    await c.execute('BEGIN');
    try {
      final before = await mrRpcAttempts(c);
      final set = await visibleSet(c, v, ctx);
      return (set: set, rpcs: await mrRpcAttempts(c) - before);
    } finally {
      await c.execute('COMMIT');
    }
  }

  /// Fills the cache for [v] and shows the next transaction is served from
  /// it, so a following invalidation check is a miss against a real hit.
  Future<List<String>> primeCache(String v, [String ctx = '']) async {
    final first = await read(v, ctx: ctx);
    final second = await read(v, ctx: ctx);
    expect(second.set, first.set);
    expect(second.rpcs, 0, reason: 'priming must leave a stored set');
    return first.set;
  }

  /// The rows stored for [v] and [ctx] under the current MeritRank epoch,
  /// with their peers sorted. How the implementation keeps rows of older
  /// epochs or trust generations is its own business.
  Future<List<List<String>>> storedSets(String v, [String ctx = '']) async {
    final epoch = await mrEpoch();
    return [
      for (final r in await cacheRows(v))
        if (r.ctx == ctx && r.mrEpoch == epoch) ([...r.peerIds]..sort()),
    ];
  }

  /// The trust generation the next fill of [v]'s set is stored under: the
  /// MeritRank epoch is bumped so the read is a miss and stores a fresh row,
  /// which carries the generation the transactional counter has now.
  Future<int> trustGenerationNow(String v) async {
    await bumpMrEpoch();
    await read(v);
    final epoch = await mrEpoch();
    final rows = (await cacheRows(v)).where((r) => r.mrEpoch == epoch);
    expect(rows, isNotEmpty, reason: 'the read must store a row');
    return rows.map((r) => r.trustGen).reduce((a, b) => a > b ? a : b);
  }

  void expectMiss(({List<String> set, int rpcs}) r, List<String> expected) {
    expect(r.set, expected);
    expect(r.rpcs, greaterThan(0), reason: 'the stored set must not be served');
  }

  void expectHit(({List<String> set, int rpcs}) r, List<String> expected) {
    expect(r.set, expected);
    expect(r.rpcs, 0, reason: 'the stored set must be served');
  }

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
    for (final id in [viewer, peer, joiner, oneWay, stranger]) {
      await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'pk-$id') ON CONFLICT DO NOTHING
''');
    }
  });

  setUp(() async {
    await writer.execute('DELETE FROM public.user_block');
    await writer.execute('DELETE FROM public.vote_user');
    await trustBothWays(writer, viewer, peer);
    // Every test starts cold. The table comes from the migration under test.
    await writer.execute(r'''
DO $$
BEGIN
  IF to_regclass('public.person_visible_set_cache') IS NOT NULL THEN
    DELETE FROM public.person_visible_set_cache;
  END IF;
END
$$
''');
  });

  tearDownAll(() async {
    await churn.close();
    await conn.close();
    await tearDownDisposablePgWriter(session: session);
  });

  group('cache storage', () {
    // ARCH §7.4a names the table and these columns: the key is
    // (viewer_id, ctx, mr_epoch, trust_gen), the payload peer_ids text[].
    test('the cache table has the columns of the design', () async {
      final rows = await writer.execute('''
SELECT column_name FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'person_visible_set_cache'
''');
      expect(
        rows.map((r) => r.single! as String),
        containsAll([
          'viewer_id',
          'ctx',
          'mr_epoch',
          'trust_gen',
          'peer_ids',
          'computed_at',
        ]),
      );
    });

    test(
      'a computed set is stored under the current MeritRank epoch',
      () async {
        expectMiss(await read(viewer), [peer]);
        expect(await storedSets(viewer), [
          [peer],
        ]);
      },
    );

    test('a later transaction is served the stored set without a '
        'MeritRank RPC', () async {
      await read(viewer);
      expectHit(await read(viewer), [peer]);
    });

    test('a read-only snapshot transaction is served from the stored set, '
        'without a MeritRank RPC', () async {
      await read(viewer);
      await conn.execute('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
      try {
        final before = await mrRpcAttempts(conn);
        expect(await visibleSet(conn, viewer), [peer]);
        expect(await mrRpcAttempts(conn) - before, 0);
      } finally {
        await conn.execute('COMMIT');
      }
    });

    test('each context has its own stored set', () async {
      await read(viewer);
      await read(viewer, ctx: otherCtx);
      expect(
        (await cacheRows(viewer)).map((r) => r.ctx),
        containsAll(['', otherCtx]),
      );
      expectHit(await read(viewer), [peer]);
      expectHit(await read(viewer, ctx: otherCtx), await uncachedSet(viewer));
    });
  });

  group('parity with the uncached visibility', () {
    Future<void> fixtures() async {
      await trustBothWays(writer, viewer, joiner);
      await trust(writer, viewer, oneWay);
      await trust(writer, stranger, viewer, amount: -1);
    }

    final viewers = [viewer, peer, joiner, oneWay, stranger];

    test('the first, computing read equals the uncached set', () async {
      await fixtures();
      for (final v in viewers) {
        for (final ctx in ['', otherCtx]) {
          expect(
            (await read(v, ctx: ctx)).set,
            await uncachedSet(v, ctx),
            reason: '$v/$ctx',
          );
        }
      }
    });

    test('a read served from the stored set equals the uncached set', () async {
      await fixtures();
      for (final v in viewers) {
        await read(v);
      }
      for (final v in viewers) {
        final uncached = await uncachedSet(v);
        final again = await read(v);
        expect(again.set, uncached, reason: v);
        if (uncached.isNotEmpty) {
          expect(again.rpcs, 0, reason: '$v must be a hit');
        }
      }
      expect(
        await uncachedSet(viewer),
        containsAll([peer, joiner]),
        reason: 'the fixtures give the viewer a non-trivial set',
      );
    });
  });

  group('invalidation', () {
    test(
      'an uncommitted trust change does not disturb a read, and no stale set '
      'is served once it commits',
      () async {
        expect(await primeCache(viewer), [peer]);

        await churn.execute('BEGIN');
        try {
          await trustBothWays(churn, viewer, joiner);
          // The change is invisible to others, so the stored set is still
          // right, and reading it must not wait for the writer. If it does,
          // the server gives up and the test fails, rather than leaving the
          // connection stuck on the lock.
          await conn.execute("SET lock_timeout = '3s'");
          await conn.execute("SET statement_timeout = '8s'");
          try {
            expectHit(await read(viewer), [peer]);
          } finally {
            await conn.execute('RESET lock_timeout');
            await conn.execute('RESET statement_timeout');
          }
        } finally {
          await churn.execute('COMMIT');
        }

        expectMiss(await read(viewer), [joiner, peer]);
      },
    );

    test(
      'a reader on an older snapshot cannot store its set for the newer '
      'trust generation',
      () async {
        await conn.execute('BEGIN ISOLATION LEVEL REPEATABLE READ');
        try {
          await conn.execute('SELECT count(*) FROM public.vote_user');
          await trustBothWays(churn, viewer, joiner);
          // Computed from the snapshot that predates the commit.
          expect(await visibleSet(conn, viewer), [peer]);
        } finally {
          await conn.execute('COMMIT');
        }

        expect((await read(viewer)).set, [joiner, peer]);
        expectHit(await read(viewer), [joiner, peer]);
      },
    );

    test('a rolled-back trust change leaves the stored set valid', () async {
      await primeCache(viewer);
      await churn.execute('BEGIN');
      await trustBothWays(churn, viewer, joiner);
      await churn.execute('ROLLBACK');

      expectHit(await read(viewer), [peer]);
    });

    test('a committed trust change by the viewer is a miss', () async {
      await primeCache(viewer);
      await trustBothWays(writer, viewer, joiner);
      expectMiss(await read(viewer), [joiner, peer]);
    });

    test(
      'a committed trust change between two other people is a miss',
      () async {
        await primeCache(viewer);
        // Neither end is the viewer. Whether it moves the viewer's set depends
        // on the MeritRank graph, which the cache cannot tell, so a trust
        // change by anyone ends the stored set.
        await trustBothWays(writer, peer, joiner);
        final expected = await uncachedSet(viewer);
        expectMiss(await read(viewer), expected);
        expectHit(await read(viewer), expected);
      },
    );

    test('a trust change that is rolled back does not advance the trust '
        'generation, and a committed one does', () async {
      final before = await trustGenerationNow(viewer);

      await churn.execute('BEGIN');
      await trustBothWays(churn, viewer, joiner);
      await churn.execute('ROLLBACK');
      expect(
        await trustGenerationNow(viewer),
        before,
        reason: 'a rolled-back change is no change',
      );

      await trustBothWays(writer, viewer, joiner);
      expect(
        await trustGenerationNow(viewer),
        greaterThan(before),
        reason: 'a committed change is a new generation',
      );
    });

    test('revoking trust is a miss', () async {
      await primeCache(viewer);
      await revokeBothWays(writer, viewer, peer);
      final after = await read(viewer);
      expect(after.set, await uncachedSet(viewer));
      expect(after.rpcs, greaterThan(0));
    });

    group('in the transaction that fills the cache', () {
      /// Adds trust, reads the transaction's own (uncommitted) set, and ends
      /// the transaction by [finish].
      Future<List<String>> addTrustReadThen(String finish) async {
        await conn.execute('BEGIN');
        try {
          await trustBothWays(conn, viewer, joiner);
          return await visibleSet(conn, viewer);
        } finally {
          await conn.execute(finish);
        }
      }

      Future<List<String>> revokeTrustReadThen(String finish) async {
        await conn.execute('BEGIN');
        try {
          await revokeBothWays(conn, viewer, peer);
          return await visibleSet(conn, viewer);
        } finally {
          await conn.execute(finish);
        }
      }

      test('added trust that is rolled back is never served to the next '
          'reader', () async {
        expect(await addTrustReadThen('ROLLBACK'), [joiner, peer]);

        expect(
          (await read(viewer, on: churn)).set,
          [peer],
          reason: 'the next committed reader sees the committed trust only',
        );
        for (final row in await cacheRows(viewer)) {
          expect(row.peerIds, isNot(contains(joiner)));
        }
        expectHit(await read(viewer, on: churn), [peer]);
      });

      test(
        'added trust that is rolled back does not replace a stored set',
        () async {
          await primeCache(viewer);
          expect(await addTrustReadThen('ROLLBACK'), [joiner, peer]);

          expectHit(await read(viewer, on: churn), [peer]);
        },
      );

      test('revoked trust that is rolled back is never served to the next '
          'reader', () async {
        expect(await revokeTrustReadThen('ROLLBACK'), isNot(contains(peer)));

        expect((await read(viewer, on: churn)).set, [peer]);
        for (final row in await cacheRows(viewer)) {
          expect(row.peerIds, contains(peer));
        }
        expectHit(await read(viewer, on: churn), [peer]);
      });

      test(
        'revoked trust that is rolled back does not replace a stored set',
        () async {
          await primeCache(viewer);
          expect(await revokeTrustReadThen('ROLLBACK'), isNot(contains(peer)));

          expectHit(await read(viewer, on: churn), [peer]);
        },
      );

      test(
        'added trust that is committed is served to the next reader',
        () async {
          expect(await addTrustReadThen('COMMIT'), [joiner, peer]);

          expect((await read(viewer, on: churn)).set, [joiner, peer]);
          expectHit(await read(viewer, on: churn), [joiner, peer]);
        },
      );

      test(
        'revoked trust that is committed is served to the next reader',
        () async {
          // The viewer keeps another trusted person, so the set after the
          // revocation is not empty.
          await trustBothWays(writer, viewer, joiner);
          await primeCache(viewer);
          expect(await revokeTrustReadThen('COMMIT'), isNot(contains(peer)));

          final expected = await uncachedSet(viewer);
          expect(expected, [joiner]);
          final next = await read(viewer, on: churn);
          expect(next.set, expected);
          expect(next.set, isNot(contains(peer)));
          expectHit(await read(viewer, on: churn), expected);
        },
      );

      test('a set read before and after a trust change in one transaction '
          'leaves the committed set', () async {
        await conn.execute('BEGIN');
        try {
          expect(await visibleSet(conn, viewer), [peer]);
          await trustBothWays(conn, viewer, joiner);
          expect(await visibleSet(conn, viewer), [joiner, peer]);
        } finally {
          await conn.execute('COMMIT');
        }

        expect((await read(viewer, on: churn)).set, [joiner, peer]);
        expectHit(await read(viewer, on: churn), [joiner, peer]);
      });

      test('a set read before a rolled-back trust change in one transaction '
          'leaves the committed set', () async {
        await conn.execute('BEGIN');
        try {
          expect(await visibleSet(conn, viewer), [peer]);
          await trustBothWays(conn, viewer, joiner);
          expect(await visibleSet(conn, viewer), [joiner, peer]);
        } finally {
          await conn.execute('ROLLBACK');
        }

        expect((await read(viewer, on: churn)).set, [peer]);
        for (final row in await cacheRows(viewer)) {
          expect(row.peerIds, isNot(contains(joiner)));
        }
      });
    });

    test('a block placed by the viewer is a miss', () async {
      await primeCache(viewer);
      await block(viewer, peer);
      final after = await read(viewer);
      expect(after.set, await uncachedSet(viewer));
      expect(after.rpcs, greaterThan(0));
    });

    test('a block placed on the viewer by the peer is a miss', () async {
      await primeCache(viewer);
      await block(peer, viewer);
      final after = await read(viewer);
      expect(after.set, await uncachedSet(viewer));
      expect(after.rpcs, greaterThan(0));
    });

    test('lifting a block is a miss', () async {
      await block(viewer, peer);
      await primeCache(viewer);
      await writer.execute('DELETE FROM public.user_block');
      final after = await read(viewer);
      expect(after.set, await uncachedSet(viewer));
      expect(after.rpcs, greaterThan(0));
    });

    test('a MeritRank publish epoch bump is a miss', () async {
      await primeCache(viewer);
      await bumpMrEpoch();
      expectMiss(await read(viewer), [peer]);
      expect(await storedSets(viewer), [
        [peer],
      ]);
      expectHit(await read(viewer), [peer]);
    });
  });

  group('degraded results', () {
    // There is no way to make MeritRank fail on demand from a session, so the
    // uncached computation is wrapped: while `tentura_test.mr_down` is on, it
    // raises, which `person_visible_peer_ids_tx` turns into its empty,
    // fail-closed fallback. This is the one test seam that assumes the cache
    // computes through `person_visible_peers_symmetric`, as m0222/m0230 do
    // (the same seam as `m0222_visibility_memo_pg_test.dart`).
    setUpAll(() async {
      await writer.execute('''
ALTER FUNCTION public.person_visible_peers_symmetric(text, text)
  RENAME TO _vis_cache_symmetric_impl
''');
      await writer.execute(r'''
CREATE FUNCTION public.person_visible_peers_symmetric(viewer_id text, ctx text)
RETURNS TABLE(peer_id text) LANGUAGE plpgsql AS $$
BEGIN
  IF current_setting('tentura_test.mr_down', true) = 'on' THEN
    RAISE EXCEPTION 'simulated MeritRank outage';
  END IF;
  RETURN QUERY SELECT s.peer_id FROM public._vis_cache_symmetric_impl(viewer_id, ctx) s;
END;
$$
''');
    });

    tearDownAll(() async {
      await writer.execute(
        'DROP FUNCTION public.person_visible_peers_symmetric(text, text)',
      );
      await writer.execute('''
ALTER FUNCTION public._vis_cache_symmetric_impl(text, text)
  RENAME TO person_visible_peers_symmetric
''');
    });

    Future<List<String>> readDuringOutage(String v) async {
      await conn.execute('BEGIN');
      try {
        await conn.execute("SET LOCAL tentura_test.mr_down = 'on'");
        return await visibleSet(conn, v);
      } finally {
        await conn.execute('COMMIT');
      }
    }

    test('a MeritRank failure writes no row', () async {
      // Fails closed to the empty set, as without the cache.
      expect(await readDuringOutage(viewer), isEmpty);
      expect(await cacheRows(viewer), isEmpty);
    });

    test(
      'a failure does not poison the read after MeritRank recovers',
      () async {
        await readDuringOutage(viewer);

        expectMiss(await read(viewer), [peer]);
        expect(await storedSets(viewer), [
          [peer],
        ]);
        expectHit(await read(viewer), [peer]);
      },
    );

    test('a failure does not overwrite an earlier row', () async {
      await primeCache(viewer);
      await bumpMrEpoch();

      expect(await readDuringOutage(viewer), isEmpty);

      expect(
        await storedSets(viewer),
        isEmpty,
        reason: 'nothing is stored for the epoch the failed read ran under',
      );
      for (final row in await cacheRows(viewer)) {
        expect(
          row.peerIds,
          [peer],
          reason: 'no empty set was stored over the previous one',
        );
      }
    });
  });
}
