@Tags(['pg', 'mr'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';

/// Block filtering on graph readers and mutual friends — spec §3.2, §3.3 / T-H E9–E10.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_USER_BLOCK_GRAPH_ENFORCEMENT_TEST_DB',
    defaultNamePrefix: 'tentura_test_ub_graph_enf',
  );
  final postgresReachable = await canReachPostgresAdmin(target);
  final skipReason = postgresReachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late Connection writer;
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
INSERT INTO public.user_trust_edge (
  subject, object, prev_sent_weight, trust_w, wall_d, target_w,
  created_at, updated_at
) VALUES (
  '$subject', '$object', 1, 1, 0, 1,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
ON CONFLICT (subject, object) DO UPDATE SET
  prev_sent_weight = EXCLUDED.prev_sent_weight,
  trust_w = EXCLUDED.trust_w,
  target_w = EXCLUDED.target_w,
  updated_at = EXCLUDED.updated_at
''',
    );
  }

  Future<void> seedMutualTrust(String a, String b) async {
    await seedTrustEdge(a, b);
    await seedTrustEdge(b, a);
    await db.customStatement(
      "SELECT mr_put_edge('$a', '$b', 1::double precision, ''::text, 0)",
    );
    await db.customStatement(
      "SELECT mr_put_edge('$b', '$a', 1::double precision, ''::text, 0)",
    );
  }

  Future<void> insertDirectBlock(String blockerId, String blockedId) =>
      db.customStatement(
        '''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$blockerId', '$blockedId', '$blockedId')
ON CONFLICT DO NOTHING
''',
      );

  Future<void> zeroMrEdgesBetween(Iterable<String> ids) async {
    for (final src in ids) {
      for (final dst in ids) {
        if (src == dst) continue;
        await db.customStatement(
          "SELECT mr_put_edge('$src', '$dst', 0::double precision, ''::text, 0)",
        );
      }
    }
  }

  Future<void> cleanup() async {
    final userList = allUserIds.map((id) => "'$id'").join(', ');
    await zeroMrEdgesBetween(allUserIds);
    await db.customStatement(
      'DELETE FROM public.user_block WHERE blocker_id IN ($userList) '
      'OR blocked_id IN ($userList)',
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
    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await writer.execute('CREATE EXTENSION IF NOT EXISTS pgmer2');
      await migrateDbSchema(writer);
      db = TenturaDb(_disposableEnv(target));
    });

    setUp(() async {
      await cleanup();
      for (final id in allUserIds) {
        await insertUser(id);
      }
    });

    tearDown(() async {
      await cleanup();
    });

    tearDownAll(() async {
      await db.close();
      await writer.close();
      await target.drop();
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
  subject, object, prev_sent_weight, trust_w, wall_d, target_w,
  created_at, updated_at
) VALUES
  ('$viewerId', '$peerAId', 1, 1, 0, 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('$viewerId', '$peerBId', 1, 1, 0, 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (subject, object) DO UPDATE SET
  prev_sent_weight = EXCLUDED.prev_sent_weight,
  trust_w = EXCLUDED.trust_w,
  target_w = EXCLUDED.target_w
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

Env _disposableEnv(DisposablePgTarget target) => Env(
  environment: Environment.test,
  pgHost: target.databaseEnv.pgHost,
  pgPort: target.databaseEnv.pgPort,
  pgDatabase: target.databaseEnv.pgDatabase,
  pgUsername: target.databaseEnv.pgUsername,
  pgPassword: target.databaseEnv.pgPassword,
  genealogyNodeKeySecret: 'test-genealogy-secret',
);
