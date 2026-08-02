@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/env.dart';

/// Block filtering on graph readers and mutual friends — spec §3.2, §3.3 / T-H E9–E10.
Future<void> main() async {
  final postgresReachable = await _canConnectPostgres();
  var skipReason = postgresReachable ? false : 'local Postgres not reachable';

  if (postgresReachable) {
    final probe = TenturaDb(_testEnv());
    try {
      if (!await _hasUserBlockSchema(probe)) {
        skipReason = 'm0135 schema (user_block / block_hides) missing';
      } else if (!await _graphIncludesBlockClause(probe)) {
        skipReason = 'm0136 schema (graph block clause) missing';
      } else if (!await _graphEdgesBetweenHasSessionArg(probe)) {
        skipReason =
            'm0136 schema (graph_edges_between hasura_session arg) missing';
      } else if (!await _mutualFriendsIncludesBlockClause(probe)) {
        skipReason = 'm0136 schema (mutual_friends block clause) missing';
      }
    } finally {
      await probe.close();
    }
  }

  late TenturaDb db;

  const viewerId = 'Ublkgview001';
  const peerAId = 'UblkgpeerA01';
  const peerBId = 'UblkgpeerB01';
  const mutualId = 'Ublkgmutual01';
  const allUserIds = [viewerId, peerAId, peerBId, mutualId];

  Future<void> insertUser(String id) => db.customStatement(
    '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
  );

  Future<void> seedTrustEdge(String subject, String object) async {
    await db.customStatement(
      '''
SELECT trust_apply_source_evidence('personal', '$subject', '$object', 'very_good', 1)
''',
    );
    await db.customStatement(
      '''
SELECT trust_rebuild_effective_edge('$subject', '$object')
''',
    );
  }

  Future<void> seedMutualTrust(String a, String b) async {
    await seedTrustEdge(a, b);
    await seedTrustEdge(b, a);
  }

  Future<void> insertDirectBlock(String blockerId, String blockedId) =>
      db.customStatement(
        '''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$blockerId', '$blockedId', '$blockedId')
ON CONFLICT DO NOTHING
''',
      );

  Future<void> cleanup() async {
    final userList = allUserIds.map((id) => "'$id'").join(', ');
    await db.customStatement(
      'DELETE FROM public.user_block WHERE blocker_id IN ($userList) '
      'OR blocked_id IN ($userList)',
    );
    await db.customStatement(
      'DELETE FROM public.user_trust_source_edge '
      'WHERE subject IN ($userList) OR object IN ($userList)',
    );
    await db.customStatement(
      'DELETE FROM public.user_trust_edge '
      'WHERE subject IN ($userList) OR object IN ($userList)',
    );
    await db.customStatement(
      '''DELETE FROM public."user" WHERE id IN ($userList)''',
    );
  }

  if (skipReason == false) {
    setUp(() async {
      db = TenturaDb(_testEnv());
      await cleanup();
      for (final id in allUserIds) {
        await insertUser(id);
      }
    });

    tearDown(() async {
      await cleanup();
      await db.close();
    });
  }

  test(
    'graph() omits edges involving a blocked peer',
    () async {
      await seedMutualTrust(viewerId, peerAId);
      await seedMutualTrust(viewerId, peerBId);

      final session = _sessionJson(viewerId);
      final before = await _queryGraph(
        db,
        focus: viewerId,
        sessionJson: session,
      );
      final peerIdsBefore = before
          .expand((row) => [row.src, row.dst])
          .where((id) => id != viewerId)
          .toSet();
      expect(peerIdsBefore, containsAll([peerAId, peerBId]));

      await insertDirectBlock(viewerId, peerAId);

      final after = await _queryGraph(
        db,
        focus: viewerId,
        sessionJson: session,
      );
      final peerIdsAfter = after
          .expand((row) => [row.src, row.dst])
          .where((id) => id != viewerId)
          .toSet();
      expect(peerIdsAfter, contains(peerBId));
      expect(peerIdsAfter, isNot(contains(peerAId)));
    },
    skip: skipReason,
  );

  test(
    'graph_edges_between() omits edges involving a blocked endpoint',
    () async {
      await db.customStatement(
        '''
INSERT INTO public.user_trust_edge (
  subject, object, anchor_at, prev_sent_weight, created_at, updated_at
) VALUES
  ('$viewerId', '$peerAId', '2026-01-01T00:00:00Z', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('$viewerId', '$peerBId', '2026-01-01T00:00:00Z', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (subject, object) DO UPDATE SET
  prev_sent_weight = EXCLUDED.prev_sent_weight
''',
      );

      final before = await _queryEdgesBetween(
        db,
        [viewerId, peerAId, peerBId],
        viewerId: viewerId,
      );
      expect(before.map((row) => (row.src, row.dst)).toSet(), {
        (viewerId, peerAId),
        (viewerId, peerBId),
      });

      await insertDirectBlock(viewerId, peerAId);

      final after = await _queryEdgesBetween(
        db,
        [viewerId, peerAId, peerBId],
        viewerId: viewerId,
      );
      expect(after.map((row) => (row.src, row.dst)).toSet(), {
        (viewerId, peerBId),
      });
    },
    skip: skipReason,
  );

  test(
    'mutual_friends() is empty when alice and bob are blocked',
    () async {
      await seedMutualTrust(peerAId, mutualId);
      await seedMutualTrust(peerBId, mutualId);
      await insertDirectBlock(peerAId, peerBId);

      final rows = await _queryMutualFriends(db, peerAId, peerBId);
      expect(rows, isEmpty);
    },
    skip: skipReason,
  );

  test(
    'mutual_friends() omits mutual peers alice has blocked',
    () async {
      await seedMutualTrust(peerAId, mutualId);
      await seedMutualTrust(peerBId, mutualId);
      await seedMutualTrust(peerAId, peerBId);
      await insertDirectBlock(peerAId, mutualId);

      final rows = await _queryMutualFriends(db, peerAId, peerBId);
      expect(rows, isEmpty);
    },
    skip: skipReason,
  );
}

typedef _GraphRow = ({String src, String dst});

typedef _EdgeRow = ({String src, String dst});

String _sessionJson(String viewerId) =>
    '{"x-hasura-user-id": "$viewerId"}';

Future<List<_GraphRow>> _queryGraph(
  TenturaDb db, {
  required String focus,
  required String sessionJson,
}) async {
  final rows = await db.customSelect(
    '''
SELECT src, dst
FROM public.graph('$focus', '', true, '$sessionJson'::json)
ORDER BY src, dst
''',
  ).get();

  return [
    for (final row in rows)
      (
        src: row.read<String>('src'),
        dst: row.read<String>('dst'),
      ),
  ];
}

Future<List<_EdgeRow>> _queryEdgesBetween(
  TenturaDb db,
  List<String> nodeIds, {
  required String viewerId,
}) async {
  final arrayLiteral =
      'ARRAY[${nodeIds.map((id) => "'$id'").join(', ')}]::text[]';
  final sessionJson = _sessionJson(viewerId);
  final rows = await db.customSelect(
    '''
SELECT src, dst
FROM public.graph_edges_between($arrayLiteral, true, '$sessionJson'::json)
ORDER BY src, dst
''',
  ).get();

  return [
    for (final row in rows)
      (
        src: row.read<String>('src'),
        dst: row.read<String>('dst'),
      ),
  ];
}

Future<List<String>> _queryMutualFriends(
  TenturaDb db,
  String aliceId,
  String bobId,
) async {
  final rows = await db.customSelect(
    '''
SELECT id
FROM public.mutual_friends('$aliceId', '$bobId', '')
ORDER BY id
''',
  ).get();

  return [for (final row in rows) row.read<String>('id')];
}

Env _testEnv() => Env(
  environment: Environment.test,
  pgHost: Platform.environment['POSTGRES_HOST'] ?? 'localhost',
  pgPort: int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432,
  pgDatabase: Platform.environment['POSTGRES_DBNAME'] ?? 'postgres',
  pgUsername: Platform.environment['POSTGRES_USERNAME'] ?? 'postgres',
  pgPassword: Platform.environment['POSTGRES_PASSWORD'] ?? 'password',
  genealogyNodeKeySecret: 'test-genealogy-secret',
);

Future<bool> _canConnectPostgres() async {
  try {
    final db = TenturaDb(_testEnv());
    await db.customSelect('SELECT 1').getSingle();
    await db.close();
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> _hasUserBlockSchema(TenturaDb db) async {
  final row = await db.customSelect(
    '''
SELECT to_regclass('public.user_block') IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'block_hides'
  ) AS ok
''',
  ).getSingle();
  return row.read<bool>('ok');
}

Future<bool> _graphIncludesBlockClause(TenturaDb db) async {
  final row = await db.customSelect(
    '''
SELECT pg_get_functiondef(p.oid) LIKE '%block_hides%' AS ok
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'graph'
LIMIT 1
''',
  ).getSingleOrNull();
  return row?.read<bool>('ok') ?? false;
}

Future<bool> _graphEdgesBetweenHasSessionArg(TenturaDb db) async {
  final row = await db.customSelect(
    '''
SELECT 1
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'graph_edges_between'
  AND p.pronargs = 3
LIMIT 1
''',
  ).getSingleOrNull();
  return row != null;
}

Future<bool> _mutualFriendsIncludesBlockClause(TenturaDb db) async {
  final row = await db.customSelect(
    '''
SELECT pg_get_functiondef(p.oid) LIKE '%block_hides%' AS ok
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'mutual_friends'
LIMIT 1
''',
  ).getSingleOrNull();
  return row?.read<bool>('ok') ?? false;
}
