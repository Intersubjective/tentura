@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/domain/invite_genealogy/invite_genealogy_node_key.dart';
import 'package:tentura_server/env.dart';

/// `block_cascade_candidates` / `block_cascade_unattached` — spec §9.3 T-B,
/// §9.4 T-C, §11 X2/X3/X4/X11.
///
/// Canonical fixture (§9.1) with `c` infix for parallel-safe pg runs:
///
///            R
///           / \
///          A   V
///          |
///          B
///        / | \ \
///       C P1 P2 E
///       |    |
///       D    P3
Future<void> main() async {
  final postgresReachable = await _canConnectPostgres();
  var skipReason = postgresReachable ? false : 'local Postgres not reachable';

  if (postgresReachable) {
    final probe = TenturaDb(_testEnv());
    try {
      if (!await _hasUserBlockSchema(probe)) {
        skipReason = 'm0135 schema (user_block / block_hides) missing';
      }
    } finally {
      await probe.close();
    }
  }

  late TenturaDb db;
  late Env env;

  const rootId = 'Ublkcroot0001';
  const aliceId = 'Ublkcalice001';
  const bobId = 'Ublkcbob00001';
  const carolId = 'Ublkccarol001';
  const daveId = 'Ublkcdave0001';
  const p1Id = 'Ublkcpupp0001';
  const p2Id = 'Ublkcpupp0002';
  const p3Id = 'Ublkcpupp0003';
  const erinId = 'Ublkcerin0001';
  const veraId = 'Ublkcvera0001';

  const b2Id = 'Ublkcb2root01';
  const xId = 'Ublkcxvouch01';
  const aChildId = 'Ublkcachild01';

  final fixtureIds = [
    rootId,
    aliceId,
    bobId,
    carolId,
    daveId,
    p1Id,
    p2Id,
    p3Id,
    erinId,
    veraId,
  ];
  final allIds = [
    ...fixtureIds,
    b2Id,
    xId,
    aChildId,
  ];

  const defaultMaxDepth = 6;
  const defaultLimit = 5000;

  String keyOf(String userId) =>
      InviteGenealogyNodeKey.derive(userId: userId, env: env);

  Future<void> insertUser(String id, DateTime createdAt) => db.customStatement(
    '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id',
  '${createdAt.toUtc().toIso8601String()}',
  '${createdAt.toUtc().toIso8601String()}')
ON CONFLICT (id) DO UPDATE SET
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at
''',
  );

  Future<void> insertGenealogyEdge({
    required String ancestorId,
    required DateTime ancestorAt,
    required String descendantId,
    required DateTime descendantAt,
  }) => db.customStatement(
    '''
INSERT INTO public.invite_genealogy (
  descendant_node_key,
  ancestor_node_key,
  descendant_user_id,
  ancestor_user_id,
  ancestor_user_created_at,
  descendant_user_created_at
) VALUES (
  '${keyOf(descendantId)}',
  '${keyOf(ancestorId)}',
  '$descendantId',
  '$ancestorId',
  '${ancestorAt.toUtc().toIso8601String()}',
  '${descendantAt.toUtc().toIso8601String()}'
)
ON CONFLICT (descendant_node_key) DO UPDATE SET
  descendant_user_id = EXCLUDED.descendant_user_id
''',
  );

  Future<void> insertMutualVote(String a, String b) => db.customStatement(
    '''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES
  ('$a', '$b', 1, now(), now()),
  ('$b', '$a', 1, now(), now())
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''',
  );

  Future<void> insertDirectedVote(String subject, String object) =>
      db.customStatement(
        '''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$subject', '$object', 1, now(), now())
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''',
      );

  Future<void> insertTrustEdge({
    required String subject,
    required String object,
    required double prevSentWeight,
  }) => db.customStatement(
    '''
INSERT INTO public.user_trust_edge (
  subject, object, anchor_at, prev_sent_weight, created_at, updated_at
) VALUES (
  '$subject', '$object', '2026-01-01T00:00:00Z', $prevSentWeight,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
ON CONFLICT (subject, object) DO UPDATE SET
  prev_sent_weight = EXCLUDED.prev_sent_weight
''',
  );

  Future<void> insertUserBlock({
    required String blockerId,
    required String blockedId,
  }) => db.customStatement(
    '''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$blockerId', '$blockedId', '$blockedId')
ON CONFLICT DO NOTHING
''',
  );

  Future<void> seedCanonicalFixture() async {
    final tRoot = DateTime.utc(2026);
    final tBranch = DateTime.utc(2026, 2);
    final tBobChild = DateTime.utc(2026, 3);
    final tDeep = DateTime.utc(2026, 4);

    for (final id in fixtureIds) {
      await insertUser(id, tRoot);
    }

    await insertGenealogyEdge(
      ancestorId: rootId,
      ancestorAt: tRoot,
      descendantId: aliceId,
      descendantAt: tBranch,
    );
    await insertGenealogyEdge(
      ancestorId: rootId,
      ancestorAt: tRoot,
      descendantId: bobId,
      descendantAt: tBranch,
    );
    await insertGenealogyEdge(
      ancestorId: rootId,
      ancestorAt: tRoot,
      descendantId: veraId,
      descendantAt: tBranch,
    );
    await insertGenealogyEdge(
      ancestorId: bobId,
      ancestorAt: tBranch,
      descendantId: carolId,
      descendantAt: tBobChild,
    );
    await insertGenealogyEdge(
      ancestorId: bobId,
      ancestorAt: tBranch,
      descendantId: p1Id,
      descendantAt: tBobChild,
    );
    await insertGenealogyEdge(
      ancestorId: bobId,
      ancestorAt: tBranch,
      descendantId: p2Id,
      descendantAt: tBobChild,
    );
    await insertGenealogyEdge(
      ancestorId: bobId,
      ancestorAt: tBranch,
      descendantId: erinId,
      descendantAt: tBobChild,
    );
    await insertGenealogyEdge(
      ancestorId: carolId,
      ancestorAt: tBobChild,
      descendantId: daveId,
      descendantAt: tDeep,
    );
    await insertGenealogyEdge(
      ancestorId: p2Id,
      ancestorAt: tBobChild,
      descendantId: p3Id,
      descendantAt: tDeep,
    );

    await insertMutualVote(aliceId, veraId);
    await insertMutualVote(aliceId, erinId);
    await insertMutualVote(carolId, veraId);
    await insertMutualVote(p1Id, p2Id);

    await insertTrustEdge(subject: aliceId, object: bobId, prevSentWeight: 0.60);
    await insertTrustEdge(subject: aliceId, object: p1Id, prevSentWeight: 0.20);
    await insertTrustEdge(subject: bobId, object: aliceId, prevSentWeight: 0.50);
  }

  Future<Set<String>> cascadeCandidateIds({
    required String blocker,
    required String root,
    required int mode,
    int maxDepth = defaultMaxDepth,
    int limit = defaultLimit,
  }) async {
    final rows = await db
        .customSelect(
          r'''
SELECT user_id
FROM public.block_cascade_candidates(
  $1, $2, $3::smallint, $4::integer, $5::integer
)
''',
          variables: [
            Variable<String>(blocker),
            Variable<String>(root),
            Variable<int>(mode),
            Variable<int>(maxDepth),
            Variable<int>(limit),
          ],
        )
        .get();
    return rows.map((row) => row.read<String>('user_id')).toSet();
  }

  Future<bool> cascadeUnattached(
    String blocker,
    String root,
    String candidate,
  ) => db
      .customSelect(
        r'''
SELECT public.block_cascade_unattached($1, $2, $3) AS unattached
''',
        variables: [
          Variable<String>(blocker),
          Variable<String>(root),
          Variable<String>(candidate),
        ],
      )
      .map((row) => row.read<bool>('unattached'))
      .getSingle();

  Future<void> cleanup() async {
    final idList = allIds.map((id) => "'$id'").join(', ');
    await db.customStatement(
      'DELETE FROM public.user_block WHERE blocker_id IN ($idList) '
      'OR blocked_id IN ($idList)',
    );
    await db.customStatement(
      'DELETE FROM public.user_block_intent WHERE blocker_id IN ($idList) '
      'OR blocked_id IN ($idList)',
    );
    await db.customStatement(
      'DELETE FROM public.user_trust_edge WHERE subject IN ($idList) '
      'OR object IN ($idList)',
    );
    await db.customStatement(
      'DELETE FROM public.vote_user WHERE subject IN ($idList) OR object IN ($idList)',
    );
    await db.customStatement(
      'DELETE FROM public.invite_genealogy '
      'WHERE descendant_user_id IN ($idList) OR ancestor_user_id IN ($idList)',
    );
    await db.customStatement(
      "DELETE FROM public.invite_genealogy WHERE descendant_node_key = '${keyOf(carolId)}'",
    );
    await db.customStatement(
      'DELETE FROM public."user" WHERE id IN ($idList)',
    );
  }

  if (skipReason == false) {
    setUpAll(() async {
      env = _testEnv();
      db = TenturaDb(env);
    });

    tearDown(cleanup);

    tearDownAll(() async {
      await cleanup();
      await db.close();
    });
  }

  test(
    'T-B1: mode-1 candidates are exactly P1, P2, P3 (root B is not a row)',
    () async {
      await seedCanonicalFixture();

      final candidates = await cascadeCandidateIds(
        blocker: aliceId,
        root: bobId,
        mode: 1,
      );

      expect(candidates, {p1Id, p2Id, p3Id});
      expect(candidates, isNot(contains(bobId)));
      expect(candidates.intersection({carolId, daveId, erinId, veraId}), isEmpty);
    },
    skip: skipReason,
  );

  test(
    'T-B2: unattached predicate matches who the mode-1 candidate set includes',
    () async {
      await seedCanonicalFixture();

      expect(await cascadeUnattached(aliceId, bobId, p1Id), isTrue);
      expect(await cascadeUnattached(aliceId, bobId, p2Id), isTrue);
      expect(await cascadeUnattached(aliceId, bobId, p3Id), isTrue);
      expect(await cascadeUnattached(aliceId, bobId, erinId), isFalse);
      expect(await cascadeUnattached(aliceId, bobId, carolId), isFalse);
      expect(await cascadeUnattached(aliceId, bobId, daveId), isTrue);
    },
    skip: skipReason,
  );

  test(
    'T-B3: E excluded via clause (a) — direct mutual trust with blocker',
    () async {
      await seedCanonicalFixture();

      expect(await cascadeUnattached(aliceId, bobId, erinId), isFalse);
      expect(
        await cascadeCandidateIds(blocker: aliceId, root: bobId, mode: 1),
        isNot(contains(erinId)),
      );
    },
    skip: skipReason,
  );

  test(
    'T-B4: C excluded via clause (b) — mutual peer V vouches for C',
    () async {
      await seedCanonicalFixture();

      expect(await cascadeUnattached(aliceId, bobId, carolId), isFalse);
      expect(
        await cascadeCandidateIds(blocker: aliceId, root: bobId, mode: 1),
        isNot(contains(carolId)),
      );
    },
    skip: skipReason,
  );

  test(
    'T-B5: D excluded by guarded descent even though unattached in isolation',
    () async {
      await seedCanonicalFixture();

      expect(await cascadeUnattached(aliceId, bobId, daveId), isTrue);
      expect(
        await cascadeCandidateIds(blocker: aliceId, root: bobId, mode: 1),
        isNot(contains(daveId)),
      );
    },
    skip: skipReason,
  );

  test(
    'T-B6: P3 included — descent continues through unattached P2',
    () async {
      await seedCanonicalFixture();

      expect(
        await cascadeCandidateIds(blocker: aliceId, root: bobId, mode: 1),
        contains(p3Id),
      );
    },
    skip: skipReason,
  );

  test(
    'T-B7: puppet mutual votes do not attach P1 or P2 to blocker',
    () async {
      await seedCanonicalFixture();

      expect(await cascadeUnattached(aliceId, bobId, p1Id), isTrue);
      expect(await cascadeUnattached(aliceId, bobId, p2Id), isTrue);
      expect(
        await cascadeCandidateIds(blocker: aliceId, root: bobId, mode: 1),
        containsAll([p1Id, p2Id]),
      );
    },
    skip: skipReason,
  );

  test(
    'T-C1: cascade_mode 2 ("all descendants, standing ignored") is rejected '
    'by the DB — removed from the design (m0138), only 0/1 remain',
    () async {
      await seedCanonicalFixture();

      await expectLater(
        db.customStatement(
          '''
INSERT INTO public.user_block_intent (blocker_id, blocked_id, cascade_mode)
VALUES ('$aliceId', '$bobId', 2)
''',
        ),
        throwsA(anything),
      );

      final rows = await db.customSelect(
        "SELECT 1 FROM public.user_block_intent "
        "WHERE blocker_id = '$aliceId' AND blocked_id = '$bobId'",
      ).get();
      expect(rows, isEmpty);
    },
    skip: skipReason,
  );

  test(
    'T-C2: block_cascade_candidates(mode=1) always applies the standing '
    'filter — no unconditional-descent bypass remains for any mode value',
    () async {
      await seedCanonicalFixture();

      final candidates = await cascadeCandidateIds(
        blocker: aliceId,
        root: bobId,
        mode: 1,
      );

      expect(candidates, containsAll([p1Id, p2Id, p3Id]));
      expect(candidates, isNot(contains(bobId)));
    },
    skip: skipReason,
  );

  test(
    'X2: self-vote on P1 does not attach P1 via clause (b)',
    () async {
      await seedCanonicalFixture();
      await insertDirectedVote(p1Id, p1Id);

      expect(await cascadeUnattached(aliceId, bobId, p1Id), isTrue);
      expect(
        await cascadeCandidateIds(blocker: aliceId, root: bobId, mode: 1),
        contains(p1Id),
      );
    },
    skip: skipReason,
  );

  test(
    'X3: blocking own ancestor excludes blocker and their invite subtree',
    () async {
      await seedCanonicalFixture();

      final tBranch = DateTime.utc(2026, 2);
      final tAChild = DateTime.utc(2026, 2, 20);
      await insertUser(aChildId, tAChild);
      await insertGenealogyEdge(
        ancestorId: aliceId,
        ancestorAt: tBranch,
        descendantId: aChildId,
        descendantAt: tAChild,
      );

      for (final mode in [1, 2]) {
        final candidates = await cascadeCandidateIds(
          blocker: aliceId,
          root: rootId,
          mode: mode,
        );
        expect(candidates, isNot(contains(aliceId)));
        expect(candidates, isNot(contains(aChildId)));
      }

      expect(await cascadeUnattached(aliceId, rootId, aliceId), isFalse);
    },
    skip: skipReason,
  );

  test(
    'X4: deleted mid-tree node still allows descent to evaluate D',
    () async {
      await seedCanonicalFixture();

      await db.customStatement(
        'UPDATE public.invite_genealogy SET descendant_user_id = NULL '
        "WHERE descendant_node_key = '${keyOf(carolId)}'",
      );
      await db.customStatement(
        "DELETE FROM public.\"user\" WHERE id = '$carolId'",
      );

      expect(
        await cascadeCandidateIds(blocker: aliceId, root: bobId, mode: 1),
        contains(daveId),
      );
    },
    skip: skipReason,
  );

  test(
    'X11: blocked cross-root voucher cannot attach a descendant',
    () async {
      await seedCanonicalFixture();

      final tBranch = DateTime.utc(2026, 2);
      final tB2Child = DateTime.utc(2026, 3, 5);
      await insertUser(b2Id, tBranch);
      await insertUser(xId, tB2Child);
      await insertGenealogyEdge(
        ancestorId: rootId,
        ancestorAt: DateTime.utc(2026),
        descendantId: b2Id,
        descendantAt: tBranch,
      );
      await insertGenealogyEdge(
        ancestorId: b2Id,
        ancestorAt: tBranch,
        descendantId: xId,
        descendantAt: tB2Child,
      );
      await insertMutualVote(b2Id, xId);
      await insertUserBlock(blockerId: aliceId, blockedId: b2Id);

      expect(await cascadeUnattached(aliceId, b2Id, xId), isTrue);
      expect(
        await cascadeCandidateIds(blocker: aliceId, root: b2Id, mode: 1),
        contains(xId),
      );
    },
    skip: skipReason,
  );
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
SELECT
  to_regclass('public.user_block') IS NOT NULL
  AND to_regclass('public.user_block_intent') IS NOT NULL
  AND (SELECT count(*) FROM pg_proc WHERE proname = 'block_cascade_candidates') > 0
  AND (SELECT count(*) FROM pg_proc WHERE proname = 'block_cascade_unattached') > 0
  AS ok
''',
  ).getSingle();
  return row.read<bool>('ok');
}
