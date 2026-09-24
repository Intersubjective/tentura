@Tags(['pg', 'mr'])
library;


import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;

import '../../support/disposable_pg_target.dart';

typedef TrustEdge = ({String src, String dst, int tier});

/// Live Postgres proof of m0163 constellation_trust_edges (D1/D6/§9.1).
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_TRUST_EDGES_TEST_DB',
    defaultNamePrefix: 'tentura_test_cte',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late Connection writer;
  late TenturaDb db;

  const egoId = 'Ucteego00001';
  const peerAId = 'Uctepeera001';
  const peerBId = 'Uctepeerb001';
  const peerCId = 'Uctepeerc001';
  const outsiderId = 'Ucteoutsid01';
  const ctx = '';

  final allUserIds = [
    egoId,
    peerAId,
    peerBId,
    peerCId,
    outsiderId,
  ];

  Future<void> insertUser(String id) => db.customStatement(
    '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
  );

  Future<void> voteEdge(
    String subject,
    String object, {
    int amount = 1,
  }) =>
      db.customStatement(
        '''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$subject', '$object', $amount, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''',
      );

  Future<void> trustEdge(
    String subject,
    String object, {
    double prevSentWeight = 1,
  }) =>
      db.customStatement(
        '''
INSERT INTO public.user_trust_edge (
  subject, object, anchor_at, prev_sent_weight, created_at, updated_at
) VALUES (
  '$subject', '$object', '2026-01-01T00:00:00Z', $prevSentWeight,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
ON CONFLICT (subject, object) DO UPDATE SET
  prev_sent_weight = EXCLUDED.prev_sent_weight,
  updated_at = EXCLUDED.updated_at
''',
      );

  Future<void> seedReciprocalTrust(String aId, String bId) async {
    await voteEdge(aId, bId);
    await voteEdge(bId, aId);
  }

  Future<void> insertBlock(String blockerId, String blockedId) =>
      db.customStatement(
        '''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$blockerId', '$blockedId', '$blockedId')
ON CONFLICT DO NOTHING
''',
      );

  Future<List<TrustEdge>> callTrustEdges(
    String viewerId,
    List<String> nodeIds, {
    String context = ctx,
  }) async {
    final arrayLiteral = nodeIds.isEmpty
        ? 'ARRAY[]::text[]'
        : 'ARRAY[${nodeIds.map((id) => "'$id'").join(', ')}]::text[]';
    final rows = await db
        .customSelect(
          '''
SELECT src, dst, tier
FROM public.constellation_trust_edges('$viewerId', '$context', $arrayLiteral)
ORDER BY src, dst, tier
''',
        )
        .get();
    return [
      for (final row in rows)
        (
          src: row.read<String>('src'),
          dst: row.read<String>('dst'),
          tier: row.read<int>('tier'),
        ),
    ];
  }

  Future<String> functionDefinition() async {
    final row = await db
        .customSelect(
          r'''
SELECT pg_get_functiondef(
  'public.constellation_trust_edges(text,text,text[])'::regprocedure) AS def
''',
        )
        .getSingle();
    return row.read<String>('def');
  }

  Future<List<String>> functionReturnColumns() async {
    final row = await db
        .customSelect(
          r'''
SELECT pg_get_function_result(p.oid) AS result_type
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'constellation_trust_edges'
LIMIT 1
''',
        )
        .getSingleOrNull();
    final resultType = row?.read<String>('result_type') ?? '';
    final match = RegExp(r'TABLE\((.*)\)').firstMatch(resultType);
    if (match == null) {
      return [];
    }
    return match
        .group(1)!
        .split(',')
        .map((part) => part.trim().split(RegExp(r'\s+')).first)
        .toList();
  }

  Future<void> cleanup() async {
    final idList = allUserIds.map((id) => "'$id'").join(', ');
    await db.customStatement(
      'DELETE FROM public.user_block WHERE blocker_id IN ($idList) '
      'OR blocked_id IN ($idList)',
    );
    await db.customStatement(
      'DELETE FROM public.vote_user WHERE subject IN ($idList) OR object IN ($idList)',
    );
    await db.customStatement(
      'DELETE FROM public.user_trust_edge WHERE subject IN ($idList) '
      'OR object IN ($idList)',
    );
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
    'the function returns only src, dst, tier — no weight or score columns',
    () async {
      expect(await functionReturnColumns(), ['src', 'dst', 'tier']);
      // Read the installed definition rather than a migration file: the
      // migration that introduced this is inside the squashed baseline.
      final definition = await functionDefinition();
      expect(
        definition,
        contains('RETURNS TABLE(src text, dst text, tier smallint)'),
      );
      expect(
        RegExp(r'SELECT\s+t1\.src,\s+t1\.dst,\s+1::smallint', multiLine: true)
            .hasMatch(definition),
        isTrue,
      );
      expect(
        RegExp(r'SELECT\s+t2\.src,\s+t2\.dst,\s+2::smallint', multiLine: true)
            .hasMatch(definition),
        isTrue,
      );
    },
    skip: skipReason,
  );

  test(
    'containment: endpoint outside {ego} ∪ V is never returned even when in node_ids',
    () async {
      await seedReciprocalTrust(egoId, peerAId);
      await voteEdge(peerAId, outsiderId);
      await trustEdge(peerAId, outsiderId);

      final edges = await callTrustEdges(
        egoId,
        [egoId, peerAId, outsiderId],
      );

      expect(
        edges.where(
          (e) => e.src == outsiderId || e.dst == outsiderId,
        ),
        isEmpty,
      );
    },
    skip: skipReason,
  );

  test(
    'tier preference: pair in vote_user and user_trust_edge returns once at tier 1',
    () async {
      await seedReciprocalTrust(egoId, peerAId);
      await seedReciprocalTrust(egoId, peerBId);
      await voteEdge(peerAId, peerBId);
      await trustEdge(peerAId, peerBId);

      final edges = await callTrustEdges(
        egoId,
        [egoId, peerAId, peerBId],
      );

      final ab = edges.where((e) => e.src == peerAId && e.dst == peerBId);
      expect(ab, [(src: peerAId, dst: peerBId, tier: 1)]);
      expect(ab.length, 1);
    },
    skip: skipReason,
  );

  test(
    'positive only: amount <= 0 and prev_sent_weight <= 0 never appear',
    () async {
      await seedReciprocalTrust(egoId, peerAId);
      await seedReciprocalTrust(egoId, peerBId);
      await seedReciprocalTrust(egoId, peerCId);
      await voteEdge(peerAId, peerBId, amount: 0);
      await voteEdge(peerBId, peerCId, amount: -1);
      await trustEdge(peerAId, peerCId, prevSentWeight: 0);
      await trustEdge(peerBId, peerCId, prevSentWeight: -0.5);

      final edges = await callTrustEdges(
        egoId,
        [egoId, peerAId, peerBId, peerCId],
      );

      expect(edges.where((e) => e.src == peerAId && e.dst == peerBId), isEmpty);
      expect(edges.where((e) => e.src == peerBId && e.dst == peerCId), isEmpty);
      expect(edges.where((e) => e.src == peerAId && e.dst == peerCId), isEmpty);
    },
    skip: skipReason,
  );

  test(
    'viewer blocks: edges touching a blocked peer are absent',
    () async {
      await seedReciprocalTrust(egoId, peerAId);
      await seedReciprocalTrust(egoId, peerBId);
      await voteEdge(peerAId, peerBId);
      await trustEdge(peerAId, peerBId);

      final before = await callTrustEdges(
        egoId,
        [egoId, peerAId, peerBId],
      );
      expect(
        before.where((e) => e.src == peerAId || e.dst == peerAId),
        isNotEmpty,
      );

      await insertBlock(egoId, peerAId);

      final after = await callTrustEdges(
        egoId,
        [egoId, peerAId, peerBId],
      );
      expect(
        after.where((e) => e.src == peerAId || e.dst == peerAId),
        isEmpty,
      );
    },
    skip: skipReason,
  );

  test(
    'viewer blocks: edges touching a peer who blocks the viewer are absent',
    () async {
      await seedReciprocalTrust(egoId, peerAId);
      await seedReciprocalTrust(egoId, peerBId);
      await voteEdge(peerAId, peerBId);
      await trustEdge(peerAId, peerBId);

      await insertBlock(peerAId, egoId);

      final edges = await callTrustEdges(
        egoId,
        [egoId, peerAId, peerBId],
      );
      expect(
        edges.where((e) => e.src == peerAId || e.dst == peerAId),
        isEmpty,
      );
    },
    skip: skipReason,
  );

  test(
    'peer↔peer blocks: tier-1 vote_user edge is absent when A blocks B',
    () async {
      await seedReciprocalTrust(egoId, peerAId);
      await seedReciprocalTrust(egoId, peerBId);
      await seedReciprocalTrust(peerAId, peerBId);
      await voteEdge(peerAId, peerBId);
      await trustEdge(peerAId, peerBId, prevSentWeight: 0);

      await insertBlock(peerAId, peerBId);

      final edges = await callTrustEdges(
        egoId,
        [egoId, peerAId, peerBId],
      );

      expect(
        edges.where((e) => e.src == peerAId && e.dst == peerBId),
        isEmpty,
        reason: 'tier-1 vote_user must be filtered by peer↔peer block_hides',
      );
    },
    skip: skipReason,
  );

  test(
    'peer↔peer blocks: neither tier-1 nor tier-2 A→B edge when A blocks B',
    () async {
      await seedReciprocalTrust(egoId, peerAId);
      await seedReciprocalTrust(egoId, peerBId);
      await seedReciprocalTrust(peerAId, peerBId);
      await voteEdge(peerAId, peerBId);
      await trustEdge(peerAId, peerBId);

      await insertBlock(peerAId, peerBId);

      final edges = await callTrustEdges(
        egoId,
        [egoId, peerAId, peerBId],
      );

      expect(
        edges.where((e) => e.src == peerAId && e.dst == peerBId),
        isEmpty,
      );
    },
    skip: skipReason,
  );

  test(
    'wire hygiene: SELECT exposes exactly src, dst, tier',
    () async {
      await seedReciprocalTrust(egoId, peerAId);
      await seedReciprocalTrust(egoId, peerBId);
      await seedReciprocalTrust(egoId, peerCId);
      await voteEdge(peerAId, peerBId);
      await trustEdge(peerCId, peerBId);

      final edges = await callTrustEdges(
        egoId,
        [egoId, peerAId, peerBId, peerCId],
      );

      expect(edges, isNotEmpty);
      for (final edge in edges) {
        expect(edge.src, isNotEmpty);
        expect(edge.dst, isNotEmpty);
        expect(edge.tier, anyOf(1, 2));
      }
      expect(await functionReturnColumns(), ['src', 'dst', 'tier']);
    },
    skip: skipReason,
  );

  test(
    'empty viewer yields empty result without error',
    () async {
      await voteEdge(peerAId, peerBId);
      expect(await callTrustEdges('', [egoId, peerAId, peerBId]), isEmpty);
      expect(await callTrustEdges('   ', [egoId, peerAId, peerBId]), isEmpty);
    },
    skip: skipReason,
  );

  test(
    'empty node_ids array yields empty result without error',
    () async {
      await seedReciprocalTrust(egoId, peerAId);
      await voteEdge(peerAId, peerBId);
      expect(await callTrustEdges(egoId, []), isEmpty);
    },
    skip: skipReason,
  );
}

