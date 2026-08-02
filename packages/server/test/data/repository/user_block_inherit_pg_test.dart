@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/domain/invite_genealogy/invite_genealogy_node_key.dart';
import 'package:tentura_server/env.dart';

/// Signup inheritance trigger — spec §9.5 Group T-D.
Future<void> main() async {
  final postgresReachable = await _canConnectPostgres();
  var skipReason = postgresReachable ? false : 'local Postgres not reachable';

  if (postgresReachable) {
    final probe = TenturaDb(_testEnv());
    try {
      if (!await _hasUserBlockSchema(probe)) {
        skipReason = 'm0135 schema (user_block / block_hides) missing';
      } else if (!await _hasInheritTrigger(probe)) {
        skipReason =
            'm0136 schema (user_block_inherit_on_invite trigger) missing';
      }
    } finally {
      await probe.close();
    }
  }

  late TenturaDb db;
  late UserBlockRepository repo;
  late Env env;

  // Canonical fixture ids (§9.1) with `d` infix for parallel-safe pg runs.
  const rootId = 'Ublkdroot0001';
  const aliceId = 'Ublkdalice001';
  const bobId = 'Ublkdbob00001';
  const carolId = 'Ublkdcarol001';
  const daveId = 'Ublkddave0001';
  const p1Id = 'Ublkdpupp0001';
  const p2Id = 'Ublkdpupp0002';
  const p3Id = 'Ublkdpupp0003';
  const erinId = 'Ublkderin0001';
  const veraId = 'Ublkdvera0001';

  const p4Id = 'Ublkdpupp0004';
  const xId = 'Ublkdxinherit1';
  const yId = 'Ublkdyinherit2';
  const zId = 'Ublkdzinherit3';
  const wId = 'Ublkdwinherit4';

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
    p4Id,
    xId,
    yId,
    zId,
    wId,
  ];

  String keyOf(String userId) =>
      InviteGenealogyNodeKey.derive(userId: userId, env: env);

  Future<void> insertUser(String id, DateTime createdAt) =>
      db.customStatement(
        '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '${createdAt.toUtc().toIso8601String()}',
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
ON CONFLICT (descendant_node_key) DO NOTHING
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

  Future<void> seedCanonicalFixture() async {
    final tRoot = DateTime.utc(2026);
    final tBranch = DateTime.utc(2026, 2);
    final tBobChild = DateTime.utc(2026, 3);
    final tDeep = DateTime.utc(2026, 4);

    await insertUser(rootId, tRoot);
    await insertUser(aliceId, tBranch);
    await insertUser(bobId, tBranch);
    await insertUser(veraId, tBranch);
    await insertUser(carolId, tBobChild);
    await insertUser(p1Id, tBobChild);
    await insertUser(p2Id, tBobChild);
    await insertUser(erinId, tBobChild);
    await insertUser(daveId, tDeep);
    await insertUser(p3Id, tDeep);

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
  }

  Future<void> blockAliceOnBobMode1WithCascadeRows() async {
    await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 1);
    for (final descendantId in [p1Id, p2Id, p3Id]) {
      await db.customStatement(
        r'''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ($1, $2, $3)
ON CONFLICT DO NOTHING
''',
        [aliceId, descendantId, bobId],
      );
    }
    await db.customStatement(
      r'''
UPDATE public.user_block_intent
SET cascade_status = 2, materialized_count = 3, updated_at = now()
WHERE blocker_id = $1 AND blocked_id = $2
''',
      [aliceId, bobId],
    );
  }

  Future<bool> hasBlockRow({
    required String blockerId,
    required String blockedId,
    required String originId,
  }) async {
    final rows = await db.customSelect(
      '''
SELECT 1 FROM public.user_block
WHERE blocker_id = '$blockerId'
  AND blocked_id = '$blockedId'
  AND origin_id = '$originId'
''',
    ).get();
    return rows.isNotEmpty;
  }

  Future<void> signupUnder({
    required String newUserId,
    required String inviterId,
    required DateTime inviterAt,
    required DateTime newUserAt,
  }) async {
    await insertUser(newUserId, newUserAt);
    await insertGenealogyEdge(
      ancestorId: inviterId,
      ancestorAt: inviterAt,
      descendantId: newUserId,
      descendantAt: newUserAt,
    );
  }

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
      'DELETE FROM public.invite_genealogy '
      'WHERE descendant_user_id IN ($idList) OR ancestor_user_id IN ($idList)',
    );
    await db.customStatement(
      'DELETE FROM public.vote_user WHERE subject IN ($idList) OR object IN ($idList)',
    );
    await db.customStatement(
      'DELETE FROM public."user" WHERE id IN ($idList)',
    );
  }

  if (skipReason == false) {
    setUpAll(() async {
      env = _testEnv();
      db = TenturaDb(env);
      repo = UserBlockRepository(env, db);
    });

    tearDown(() => cleanup());

    tearDownAll(() async {
      await cleanup();
      await db.close();
    });
  }

  test(
    'T-D1: signup under materialized blocked descendant inherits block',
    () async {
      await seedCanonicalFixture();
      await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 1);
      await blockAliceOnBobMode1WithCascadeRows();

      final tP2 = DateTime.utc(2026, 3);
      final tP4 = DateTime.utc(2026, 5);
      await signupUnder(
        newUserId: p4Id,
        inviterId: p2Id,
        inviterAt: tP2,
        newUserAt: tP4,
      );

      expect(
        await hasBlockRow(blockerId: aliceId, blockedId: p4Id, originId: bobId),
        isTrue,
      );
    },
    skip: skipReason,
  );

  test(
    'T-D2: signup under attached non-blocked ancestor does not inherit',
    () async {
      await seedCanonicalFixture();
      await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 1);
      await blockAliceOnBobMode1WithCascadeRows();

      final tCarol = DateTime.utc(2026, 3);
      final tX = DateTime.utc(2026, 5);
      await signupUnder(
        newUserId: xId,
        inviterId: carolId,
        inviterAt: tCarol,
        newUserAt: tX,
      );

      expect(
        await hasBlockRow(blockerId: aliceId, blockedId: xId, originId: bobId),
        isFalse,
      );
      final rows = await db.customSelect(
        "SELECT 1 FROM public.user_block WHERE blocker_id = '$aliceId' "
        "AND blocked_id = '$xId'",
      ).get();
      expect(rows, isEmpty);
    },
    skip: skipReason,
  );

  test(
    'T-D3: signup under directly blocked ancestor inherits block',
    () async {
      await seedCanonicalFixture();
      await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 1);

      final tBob = DateTime.utc(2026, 2);
      final tY = DateTime.utc(2026, 5);
      await signupUnder(
        newUserId: yId,
        inviterId: bobId,
        inviterAt: tBob,
        newUserAt: tY,
      );

      expect(
        await hasBlockRow(blockerId: aliceId, blockedId: yId, originId: bobId),
        isTrue,
      );
    },
    skip: skipReason,
  );

  test(
    'T-D4: mode-0 block does not inherit on signup',
    () async {
      await seedCanonicalFixture();
      await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 0);

      final tBob = DateTime.utc(2026, 2);
      final tZ = DateTime.utc(2026, 5);
      await signupUnder(
        newUserId: zId,
        inviterId: bobId,
        inviterAt: tBob,
        newUserAt: tZ,
      );

      final rows = await db.customSelect(
        "SELECT 1 FROM public.user_block WHERE blocker_id = '$aliceId' "
        "AND blocked_id = '$zId'",
      ).get();
      expect(rows, isEmpty);
    },
    skip: skipReason,
  );

  test(
    'T-D5: two independent blockers both inherit on signup under blocked root',
    () async {
      await seedCanonicalFixture();
      await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 1);
      await repo.block(blockerId: veraId, blockedId: bobId, cascadeMode: 1);

      final tBob = DateTime.utc(2026, 2);
      final tW = DateTime.utc(2026, 5);
      await signupUnder(
        newUserId: wId,
        inviterId: bobId,
        inviterAt: tBob,
        newUserAt: tW,
      );

      expect(
        await hasBlockRow(blockerId: aliceId, blockedId: wId, originId: bobId),
        isTrue,
      );
      expect(
        await hasBlockRow(blockerId: veraId, blockedId: wId, originId: bobId),
        isTrue,
      );
    },
    skip: skipReason,
  );

  test(
    'T-D6: NULL descendant_user_id signup row does not error trigger',
    () async {
      await seedCanonicalFixture();
      await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 1);

      final ghostKey = '${'z' * 43}9';
      final tBob = DateTime.utc(2026, 2);
      final tGhost = DateTime.utc(2026, 5);

      await db.customStatement(
        '''
INSERT INTO public.invite_genealogy (
  descendant_node_key,
  ancestor_node_key,
  descendant_user_id,
  ancestor_user_id,
  ancestor_user_created_at,
  descendant_user_created_at
) VALUES (
  '$ghostKey',
  '${keyOf(bobId)}',
  NULL,
  '$bobId',
  '${tBob.toUtc().toIso8601String()}',
  '${tGhost.toUtc().toIso8601String()}'
)
''',
      );

      final rows = await db.customSelect(
        "SELECT 1 FROM public.invite_genealogy WHERE descendant_node_key = '$ghostKey'",
      ).get();
      expect(rows, hasLength(1));

      await db.customStatement(
        "DELETE FROM public.invite_genealogy WHERE descendant_node_key = '$ghostKey'",
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
  AND (SELECT count(*) FROM pg_proc WHERE proname = 'block_hides') > 0
  AS ok
''',
  ).getSingle();
  return row.read<bool>('ok');
}

Future<bool> _hasInheritTrigger(TenturaDb db) async {
  final row = await db.customSelect(
    '''
SELECT count(*)::int AS n
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_proc p ON p.oid = t.tgfoid
WHERE c.relname = 'invite_genealogy'
  AND p.proname = 'user_block_inherit_on_invite'
  AND NOT t.tgisinternal
''',
  ).getSingle();
  return row.read<int>('n') > 0;
}
