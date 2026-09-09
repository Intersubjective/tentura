@Tags(['pg'])
library;

import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/env.dart';

/// Live Postgres proof of m0163a discoverability visibility cache (GATE-14.1).
Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late Connection writer;
  late TenturaDb db;

  const viewerId = 'Udiscvcache01';
  const peerId = 'Udiscvcache02';
  const peerBId = 'Udiscvcache03';
  const batchPeerA = 'Udiscvcache04';
  const batchPeerB = 'Udiscvcache05';
  const ctx = '';

  final allUserIds = [
    viewerId,
    peerId,
    peerBId,
    batchPeerA,
    batchPeerB,
  ];

  Future<void> insertUser(String id) => db.customStatement(
    '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
  );

  Future<void> trustEdge(String subject, String object, {int amount = 1}) =>
      db.customStatement(
        '''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$subject', '$object', $amount, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''',
      );

  Future<void> deleteTrustEdge(String subject, String object) =>
      db.customStatement(
        '''
DELETE FROM public.vote_user
WHERE subject = '$subject' AND object = '$object'
''',
      );

  Future<void> mrEdge(String subject, String object) => db.customStatement(
    "SELECT mr_put_edge('$subject', '$object', 0.75::double precision, ''::text, 0)",
  );

  Future<void> clearMrEdge(String subject, String object) => db.customStatement(
    "SELECT mr_put_edge('$subject', '$object', 0::double precision, ''::text, 0)",
  );

  Future<bool> callCached(
    String aId,
    String bId, {
    String context = ctx,
    Connection? connection,
  }) async {
    if (connection != null) {
      final rows = await connection.execute(
        Sql.named(
          r'''
SELECT public.person_are_mutually_visible_cached(@a, @b, @ctx) AS mutual
''',
        ),
        parameters: {'a': aId, 'b': bId, 'ctx': context},
      );
      return rows.single.first! as bool;
    }
    final row = await db
        .customSelect(
          r'''
SELECT public.person_are_mutually_visible_cached($1, $2, $3) AS mutual
''',
          variables: [
            Variable<String>(aId),
            Variable<String>(bId),
            Variable<String>(context),
          ],
        )
        .getSingle();
    return row.read<bool>('mutual');
  }

  Future<int> cacheRowCount() async {
    final row = await db
        .customSelect(
          r'SELECT count(*)::int AS c FROM public.person_mutual_visibility_cache',
        )
        .getSingle();
    return row.read<int>('c');
  }

  Future<Map<String, Object?>> cacheRowForPair(
    String aId,
    String bId, {
    String context = ctx,
  }) async {
    final lo = aId.compareTo(bId) <= 0 ? aId : bId;
    final hi = aId.compareTo(bId) <= 0 ? bId : aId;
    final row = await db
        .customSelect(
          r'''
SELECT person_lo, person_hi, ctx, is_mutually_visible, mr_epoch, trust_version, computed_at
FROM public.person_mutual_visibility_cache
WHERE person_lo = $1 AND person_hi = $2 AND ctx = $3
''',
          variables: [
            Variable<String>(lo),
            Variable<String>(hi),
            Variable<String>(context),
          ],
        )
        .getSingleOrNull();
    if (row == null) {
      return {};
    }
    return {
      'person_lo': row.read<String>('person_lo'),
      'person_hi': row.read<String>('person_hi'),
      'ctx': row.read<String>('ctx'),
      'is_mutually_visible': row.read<bool>('is_mutually_visible'),
      'mr_epoch': row.read<BigInt>('mr_epoch'),
      'trust_version': row.read<BigInt>('trust_version'),
      'computed_at': row.read<String>('computed_at'),
    };
  }

  Future<BigInt> readMrEpoch() async {
    final row = await db
        .customSelect(
          r'SELECT epoch FROM public.mr_publish_epoch WHERE id = true',
        )
        .getSingle();
    return row.read<BigInt>('epoch');
  }

  Future<BigInt> readTrustVersion() async {
    final row = await db
        .customSelect(
          r'SELECT public.direct_trust_current_version() AS v',
        )
        .getSingle();
    return row.read<BigInt>('v');
  }

  Future<void> restorePamvUncachedBody() async {
    await db.customStatement(r'''
CREATE OR REPLACE FUNCTION public.person_are_mutually_visible_uncached(
  a_id text, b_id text, ctx text
) RETURNS boolean LANGUAGE sql STABLE AS $$
SELECT CASE
  WHEN nullif(trim(coalesce(a_id, '')), '') IS NULL THEN false
  WHEN nullif(trim(coalesce(b_id, '')), '') IS NULL THEN false
  WHEN a_id = b_id THEN false
  WHEN public.person_reciprocal_explicit_trust(a_id, b_id) THEN true
  WHEN public.person_is_mutually_visible(a_id, b_id, coalesce(ctx, '')) THEN true
  ELSE public.person_is_mutually_visible(b_id, a_id, coalesce(ctx, ''))
END;
$$;
''');
  }

  Future<void> installPamvCallCounter({double sleepSeconds = 0}) async {
    await db.customStatement('''
CREATE TABLE IF NOT EXISTS public._discoverability_cache_test_pamv_calls (
  id int PRIMARY KEY DEFAULT 1,
  n bigint NOT NULL DEFAULT 0
)
''');
    await db.customStatement('''
INSERT INTO public._discoverability_cache_test_pamv_calls (id, n)
VALUES (1, 0)
ON CONFLICT (id) DO NOTHING
''');
    await db.customStatement(r'''
DO $$
BEGIN
  IF to_regprocedure('public.person_are_mutually_visible_uncached(text,text,text)') IS NULL
     AND to_regprocedure('public.person_are_mutually_visible(text,text,text)') IS NOT NULL THEN
    ALTER FUNCTION public.person_are_mutually_visible(text, text, text)
      RENAME TO person_are_mutually_visible_uncached;
  END IF;
END;
$$;
''');
    final sleepLiteral = sleepSeconds.toString();
    await db.customStatement('''
CREATE OR REPLACE FUNCTION public.person_are_mutually_visible(
  a_id text, b_id text, ctx text
) RETURNS boolean LANGUAGE plpgsql AS \$\$
BEGIN
  UPDATE public._discoverability_cache_test_pamv_calls
    SET n = n + 1
    WHERE id = 1;
  IF $sleepLiteral::double precision > 0 THEN
    PERFORM pg_sleep($sleepLiteral);
  END IF;
  RETURN public.person_are_mutually_visible_uncached(a_id, b_id, ctx);
END;
\$\$;
''');
  }

  Future<void> resetPamvCallCounter() async {
    await db.customStatement(
      'UPDATE public._discoverability_cache_test_pamv_calls SET n = 0 WHERE id = 1',
    );
  }

  Future<int> readPamvCallCount() async {
    final row = await db
        .customSelect(
          r'SELECT n FROM public._discoverability_cache_test_pamv_calls WHERE id = 1',
        )
        .getSingleOrNull();
    return row?.read<int>('n') ?? 0;
  }

  Future<void> truncateCache() => db.customStatement(
    'TRUNCATE public.person_mutual_visibility_cache',
  );

  Future<void> seedReciprocalTrust(String aId, String bId) async {
    await trustEdge(aId, bId);
    await trustEdge(bId, aId);
  }

  Future<void> cleanup() async {
    await truncateCache();
    await resetPamvCallCounter();
    final idList = allUserIds.map((id) => "'$id'").join(', ');
    await db.customStatement(
      'DELETE FROM public.vote_user WHERE subject IN ($idList) OR object IN ($idList)',
    );
    for (final otherId in allUserIds) {
      if (otherId == viewerId) continue;
      await clearMrEdge(viewerId, otherId);
      await clearMrEdge(otherId, viewerId);
    }
    await db.customStatement(
      '''DELETE FROM public."user" WHERE id IN ($idList)''',
    );
  }

  if (skipReason == false) {
    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await writer.execute('CREATE EXTENSION IF NOT EXISTS pgmer2');
      await migrateDbSchema(writer);
      db = TenturaDb(target.databaseEnv);
      await installPamvCallCounter();
    });

    setUp(() async {
      await cleanup();
      for (final id in allUserIds) {
        await insertUser(id);
      }
    });

    tearDownAll(() async {
      await db.close();
      await writer.close();
      await target.drop();
    });
  }

  test(
    'm0163a migration body never references block_hides',
    () {
      final migrationSource = File(
        'lib/data/database/migration/m0163a.dart',
      ).readAsStringSync();
      expect(migrationSource.contains('block_hides'), isFalse);
    },
    skip: skipReason,
  );

  test(
    'cache miss computes and stores; identical follow-up call is a hit',
    () async {
      await seedReciprocalTrust(viewerId, peerId);

      expect(await readPamvCallCount(), 0);
      expect(await callCached(viewerId, peerId), isTrue);
      expect(await readPamvCallCount(), 1);
      expect(await cacheRowCount(), 1);

      final row = await cacheRowForPair(viewerId, peerId);
      expect(row['is_mutually_visible'], isTrue);
      expect(row['mr_epoch'], await readMrEpoch());
      expect(row['trust_version'], await readTrustVersion());

      expect(await callCached(viewerId, peerId), isTrue);
      expect(await readPamvCallCount(), 1, reason: 'second call must be a cache hit');
    },
    skip: skipReason,
  );

  test(
    'mr_bump_publish_epoch invalidates every existing cache entry',
    () async {
      await seedReciprocalTrust(viewerId, peerId);
      expect(await callCached(viewerId, peerId), isTrue);
      expect(await readPamvCallCount(), 1);

      final epochBefore = await readMrEpoch();
      await db.customStatement('SELECT public.mr_bump_publish_epoch()');
      expect(await readMrEpoch(), greaterThan(epochBefore));

      expect(await callCached(viewerId, peerId), isTrue);
      expect(await readPamvCallCount(), 2, reason: 'epoch bump must force rebuild');

      final row = await cacheRowForPair(viewerId, peerId);
      expect(row['mr_epoch'], await readMrEpoch());
    },
    skip: skipReason,
  );

  test(
    'single vote_user insert invalidates existing cache entries',
    () async {
      await seedReciprocalTrust(viewerId, peerId);
      expect(await callCached(viewerId, peerId), isTrue);
      expect(await readPamvCallCount(), 1);

      final trustBefore = await readTrustVersion();
      await trustEdge(viewerId, peerBId);
      expect(await readTrustVersion(), greaterThan(trustBefore));

      expect(await callCached(viewerId, peerId), isTrue);
      expect(await readPamvCallCount(), 2, reason: 'vote_user write must force rebuild');
    },
    skip: skipReason,
  );

  test(
    'vote_user update invalidates existing cache entries',
    () async {
      await seedReciprocalTrust(viewerId, peerId);
      expect(await callCached(viewerId, peerId), isTrue);
      expect(await readPamvCallCount(), 1);

      await trustEdge(viewerId, peerBId, amount: 1);
      await resetPamvCallCounter();
      expect(await callCached(viewerId, peerId), isTrue);
      expect(await readPamvCallCount(), 1);

      await trustEdge(viewerId, peerBId, amount: -1);
      expect(await callCached(viewerId, peerId), isTrue);
      expect(await readPamvCallCount(), 2, reason: 'vote_user update must force rebuild');
    },
    skip: skipReason,
  );

  test(
    'vote_user delete invalidates existing cache entries',
    () async {
      await seedReciprocalTrust(viewerId, peerId);
      await trustEdge(viewerId, peerBId);
      expect(await callCached(viewerId, peerId), isTrue);
      expect(await readPamvCallCount(), 1);

      await deleteTrustEdge(viewerId, peerBId);
      expect(await callCached(viewerId, peerId), isTrue);
      expect(await readPamvCallCount(), 2, reason: 'vote_user delete must force rebuild');
    },
    skip: skipReason,
  );

  test(
    'statement-level vote_user trigger invalidates on a batch write',
    () async {
      await seedReciprocalTrust(viewerId, peerId);
      expect(await callCached(viewerId, peerId), isTrue);
      expect(await readPamvCallCount(), 1);

      await db.customStatement('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES
  ('$viewerId', '$batchPeerA', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('$viewerId', '$batchPeerB', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''');

      expect(await callCached(viewerId, peerId), isTrue);
      expect(
        await readPamvCallCount(),
        2,
        reason: 'batch vote_user write must invalidate cached entries',
      );
    },
    skip: skipReason,
  );

  test(
    'TTL-expired entry is a miss even when epoch and trust version are unchanged',
    () async {
      await seedReciprocalTrust(viewerId, peerId);
      expect(await callCached(viewerId, peerId), isTrue);
      expect(await readPamvCallCount(), 1);

      final epoch = await readMrEpoch();
      final trust = await readTrustVersion();
      await db.customStatement('''
UPDATE public.person_mutual_visibility_cache
SET computed_at = now() - interval '120 seconds',
    mr_epoch = $epoch,
    trust_version = $trust
WHERE person_lo = LEAST('$viewerId', '$peerId')
  AND person_hi = GREATEST('$viewerId', '$peerId')
  AND ctx = ''
''');

      expect(await callCached(viewerId, peerId), isTrue);
      expect(await readPamvCallCount(), 2, reason: 'expired TTL must force rebuild');
    },
    skip: skipReason,
  );

  test(
    '(a,b) and (b,a) share one normalized cache row',
    () async {
      await seedReciprocalTrust(viewerId, peerId);

      expect(await callCached(viewerId, peerId), isTrue);
      expect(await cacheRowCount(), 1);
      expect(await readPamvCallCount(), 1);

      final lo = viewerId.compareTo(peerId) <= 0 ? viewerId : peerId;
      final hi = viewerId.compareTo(peerId) <= 0 ? peerId : viewerId;
      final row = await cacheRowForPair(viewerId, peerId);
      expect(row['person_lo'], lo);
      expect(row['person_hi'], hi);

      expect(await callCached(peerId, viewerId), isTrue);
      expect(await cacheRowCount(), 1);
      expect(await readPamvCallCount(), 1, reason: 'reversed argument order must hit cache');
    },
    skip: skipReason,
  );

  test(
    'concurrent misses on the same key rebuild once, not twice',
    () async {
      await seedReciprocalTrust(viewerId, peerId);
      await truncateCache();
      await resetPamvCallCounter();
      await installPamvCallCounter(sleepSeconds: 0.4);

      final env = target.databaseEnv;
      final conn1 = await Connection.open(
        env.pgEndpoint,
        settings: env.pgEndpointSettings,
      );
      final conn2 = await Connection.open(
        env.pgEndpoint,
        settings: env.pgEndpointSettings,
      );
      try {
        final results = await Future.wait<bool>([
          callCached(viewerId, peerId, connection: conn1),
          callCached(viewerId, peerId, connection: conn2),
        ]);
        expect(results, everyElement(isTrue));
        expect(
          await readPamvCallCount(),
          1,
          reason: 'single-flight must dedupe concurrent rebuilds',
        );
        expect(await cacheRowCount(), 1);
      } finally {
        await conn1.close();
        await conn2.close();
        await installPamvCallCounter();
      }
    },
    skip: skipReason,
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'MeritRank-unavailable miss fails closed without caching a positive',
    () async {
      await trustEdge(viewerId, peerId);
      await mrEdge(peerId, viewerId);
      await truncateCache();

      await db.customStatement('''
CREATE OR REPLACE FUNCTION public.person_are_mutually_visible_uncached(
  a_id text, b_id text, ctx text
) RETURNS boolean LANGUAGE plpgsql AS \$\$
BEGIN
  RAISE EXCEPTION 'simulated MeritRank outage';
END;
\$\$;
''');

      bool? result;
      Object? thrown;
      try {
        result = await callCached(viewerId, peerId);
      } on Object catch (error) {
        thrown = error;
      } finally {
        await restorePamvUncachedBody();
        await installPamvCallCounter();
      }

      expect(thrown, isNull, reason: 'cached wrapper must swallow underlying errors');
      expect(result, isFalse);
      expect(await cacheRowForPair(viewerId, peerId), isEmpty);
      expect(await cacheRowCount(), 0);
    },
    skip: skipReason,
  );
}

Future<bool> _canConnect(Env env) async {
  try {
    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    );
    await connection.close();
    return true;
  } on Object {
    return false;
  }
}

final class _DisposablePgTarget {
  _DisposablePgTarget({
    required this.adminEnv,
    required this.databaseEnv,
    required this.databaseName,
  });

  factory _DisposablePgTarget.fromEnvironment() {
    final host = Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1';
    final port =
        int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432;
    final username = Platform.environment['POSTGRES_USERNAME'] ?? 'postgres';
    final password = Platform.environment['POSTGRES_PASSWORD'] ?? 'password';
    final adminDatabase =
        Platform.environment['POSTGRES_ADMIN_DBNAME'] ?? 'postgres';
    final databaseName =
        Platform.environment['TENTURA_DISCOVERABILITY_CACHE_TEST_DB'] ??
        'tentura_test_discov_cache_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';

    Env envFor(String database) => Env(
      environment: Environment.test,
      pgHost: host,
      pgPort: port,
      pgDatabase: database,
      pgUsername: username,
      pgPassword: password,
      printEnv: false,
      isDebugModeOn: false,
    );
    return _DisposablePgTarget(
      adminEnv: envFor(adminDatabase),
      databaseEnv: envFor(databaseName),
      databaseName: databaseName,
    );
  }

  final Env adminEnv;
  final Env databaseEnv;
  final String databaseName;

  Future<void> recreate() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
      await connection.execute('CREATE DATABASE "$databaseName"');
    } finally {
      await connection.close();
    }
  }

  Future<void> drop() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
    } finally {
      await connection.close();
    }
  }
}
