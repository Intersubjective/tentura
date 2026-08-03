@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/domain/invite_genealogy/invite_genealogy_node_key.dart';
import 'package:tentura_server/domain/use_case/block_cascade_case.dart';
import 'package:tentura_server/env.dart';

/// Cascade materialization job — spec §9.3 T-B8/T-B9, §11 X5/X6/X8.
/// (cascade_mode 2 was removed in m0138 — only mode 0/1 remain.)
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
  late UserBlockRepository repo;
  late BlockCascadeCase cascadeJob;

  // Canonical §9.1 ids with `j` infix for parallel-safe pg runs.
  const rootId = 'Ublkjroot0001';
  const aliceId = 'Ublkjalice001';
  const bobId = 'Ublkjbob00001';
  const carolId = 'Ublkjcarol001';
  const daveId = 'Ublkjdave0001';
  const p1Id = 'Ublkjpupp0001';
  const p2Id = 'Ublkjpupp0002';
  const p3Id = 'Ublkjpupp0003';
  const erinId = 'Ublkjerin0001';
  const veraId = 'Ublkjvera0001';
  const p4Id = 'Ublkjpupp0004';

  const hubId = 'Ublkjhub00001';
  final hubChildIds = List.generate(10, (i) => 'Ublkjhubch${i.toString().padLeft(2, '0')}');

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
    p4Id,
    hubId,
    ...hubChildIds,
  ];

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
    DateTime? genealogyCreatedAt,
  }) async {
    final createdClause = genealogyCreatedAt != null
        ? "'${genealogyCreatedAt.toUtc().toIso8601String()}'"
        : 'now()';
    await db.customStatement(
      '''
INSERT INTO public.invite_genealogy (
  descendant_node_key,
  ancestor_node_key,
  descendant_user_id,
  ancestor_user_id,
  ancestor_user_created_at,
  descendant_user_created_at,
  created_at
) VALUES (
  '${keyOf(descendantId)}',
  '${keyOf(ancestorId)}',
  '$descendantId',
  '$ancestorId',
  '${ancestorAt.toUtc().toIso8601String()}',
  '${descendantAt.toUtc().toIso8601String()}',
  $createdClause
)
ON CONFLICT (descendant_node_key) DO UPDATE SET
  descendant_user_id = EXCLUDED.descendant_user_id,
  created_at = EXCLUDED.created_at
''',
    );
  }

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
  }

  Future<void> seedHubFixture() async {
    final tRoot = DateTime.utc(2026);
    final tBranch = DateTime.utc(2026, 2);
    final tChild = DateTime.utc(2026, 3);

    await insertUser(rootId, tRoot);
    await insertUser(aliceId, tBranch);
    await insertUser(hubId, tBranch);
    for (final childId in hubChildIds) {
      await insertUser(childId, tChild);
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
      descendantId: hubId,
      descendantAt: tBranch,
    );
    for (final childId in hubChildIds) {
      await insertGenealogyEdge(
        ancestorId: hubId,
        ancestorAt: tBranch,
        descendantId: childId,
        descendantAt: tChild,
      );
    }
  }

  Future<Set<String>> blockedIdsForAlice() async {
    final rows = await db.customSelect(
      "SELECT blocked_id FROM public.user_block WHERE blocker_id = '$aliceId'",
    ).get();
    return rows.map((r) => r.read<String>('blocked_id')).toSet();
  }

  Future<Set<String>> inheritedIdsForAlice({required String originId}) async {
    final rows = await db.customSelect(
      '''
SELECT blocked_id FROM public.user_block
WHERE blocker_id = '$aliceId'
  AND origin_id = '$originId'
  AND blocked_id <> origin_id
''',
    ).get();
    return rows.map((r) => r.read<String>('blocked_id')).toSet();
  }

  Future<({int status, int materializedCount})> intentRow({
    required String blockerId,
    required String blockedId,
  }) async {
    final row = await db.customSelect(
      '''
SELECT cascade_status, materialized_count
FROM public.user_block_intent
WHERE blocker_id = '$blockerId' AND blocked_id = '$blockedId'
''',
    ).getSingle();
    return (
      status: row.read<int>('cascade_status'),
      materializedCount: row.read<int>('materialized_count'),
    );
  }

  Future<void> runUntilComplete() async {
    for (var i = 0; i < 100; i++) {
      await cascadeJob.runDue();
      final row = await intentRow(blockerId: aliceId, blockedId: bobId);
      if (row.status >= 2) return;
    }
    throw StateError('cascade did not complete for $aliceId -> $bobId');
  }

  Future<void> runUntilHubComplete() async {
    for (var i = 0; i < 100; i++) {
      await cascadeJob.runDue();
      final row = await intentRow(blockerId: aliceId, blockedId: hubId);
      if (row.status >= 2) return;
    }
    throw StateError('cascade did not complete for hub');
  }

  Future<void> cleanup() async {
    final idList = fixtureIds.map((id) => "'$id'").join(', ');
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

  void bindHarness(Env testEnv) {
    env = testEnv;
    db = TenturaDb(env);
    repo = UserBlockRepository(env, db);
    cascadeJob = BlockCascadeCase(
      repo,
      env: env,
      logger: Logger('block_cascade_job_pg_test'),
    );
  }

  if (skipReason == false) {
    tearDown(() async {
      await cleanup();
      await db.close();
    });
  }

  test(
    'T-B8: mode-1 materialization ends done with materialized_count = 3',
    () async {
      bindHarness(_testEnv());
      await seedCanonicalFixture();
      await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 1);
      await runUntilComplete();

      final intent = await intentRow(blockerId: aliceId, blockedId: bobId);
      expect(intent.status, 2);
      expect(intent.materializedCount, 3);
      expect(
        await blockedIdsForAlice(),
        {bobId, p1Id, p2Id, p3Id},
      );
    },
    skip: skipReason,
  );

  test(
    'T-B9: two batched passes yield the same inherited set as one pass',
    () async {
      bindHarness(_testEnv(blockCascadeBatchSize: 2));
      await seedCanonicalFixture();
      await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 1);
      await runUntilComplete();
      final batchedInherited = await inheritedIdsForAlice(originId: bobId);

      await cleanup();
      await db.close();

      bindHarness(_testEnv(blockCascadeBatchSize: 500));
      await seedCanonicalFixture();
      await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 1);
      await runUntilComplete();
      final singleInherited = await inheritedIdsForAlice(originId: bobId);

      expect(batchedInherited, singleInherited);
      expect(batchedInherited, {p1Id, p2Id, p3Id});
    },
    skip: skipReason,
  );

  test(
    'X5: catch-up pass blocks signup that landed after snapshot',
    () async {
      bindHarness(_testEnv(blockCascadeBatchSize: 1));
      await seedCanonicalFixture();
      await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 1);

      final snapshotAt = DateTime.utc(2026, 1, 15);
      await db.customStatement(
        '''
UPDATE public.user_block_intent
SET cascade_snapshot_at = '${snapshotAt.toUtc().toIso8601String()}',
    cascade_status = 1
WHERE blocker_id = '$aliceId' AND blocked_id = '$bobId'
''',
      );

      await repo.materializeCascadeBatch(
        blockerId: aliceId,
        blockedId: bobId,
        limit: 1,
      );

      final tP2 = DateTime.utc(2026, 3);
      final tP4 = DateTime.utc(2026, 5);
      await insertUser(p4Id, tP4);
      await insertGenealogyEdge(
        ancestorId: p2Id,
        ancestorAt: tP2,
        descendantId: p4Id,
        descendantAt: tP4,
        genealogyCreatedAt: DateTime.utc(2026, 4, 1),
      );

      await runUntilComplete();

      final rows = await db.customSelect(
        '''
SELECT 1 FROM public.user_block
WHERE blocker_id = '$aliceId'
  AND blocked_id = '$p4Id'
  AND origin_id = '$bobId'
''',
      ).get();
      expect(rows, isNotEmpty);
    },
    skip: skipReason,
  );

  test(
    'X6: unblock mid-run aborts further inserts without error',
    () async {
      bindHarness(_testEnv(blockCascadeBatchSize: 1));
      await seedCanonicalFixture();
      await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 1);

      await repo.materializeCascadeBatch(
        blockerId: aliceId,
        blockedId: bobId,
        limit: 1,
      );

      final rowsBeforeUnblock = await blockedIdsForAlice();
      expect(rowsBeforeUnblock.length, greaterThan(1));

      await repo.unblock(blockerId: aliceId, blockedId: bobId);
      await cascadeJob.runDue();

      final blocks = await db.customSelect(
        "SELECT 1 FROM public.user_block WHERE blocker_id = '$aliceId'",
      ).get();
      expect(blocks, isEmpty);

      final intents = await db.customSelect(
        "SELECT 1 FROM public.user_block_intent "
        "WHERE blocker_id = '$aliceId' AND blocked_id = '$bobId'",
      ).get();
      expect(intents, isEmpty);
    },
    skip: skipReason,
  );

  test(
    'X8: large cascade caps at BLOCK_CASCADE_MAX_ROWS with status 3',
    () async {
      bindHarness(
        _testEnv(blockCascadeMaxRows: 5, blockCascadeBatchSize: 2),
      );
      await seedHubFixture();
      await repo.block(blockerId: aliceId, blockedId: hubId, cascadeMode: 1);
      await runUntilHubComplete();

      final intent = await intentRow(blockerId: aliceId, blockedId: hubId);
      expect(intent.status, 3);
      expect(intent.materializedCount, 5);
      expect((await inheritedIdsForAlice(originId: hubId)).length, 5);
    },
    skip: skipReason,
  );
}

Env _testEnv({
  int? blockCascadeMaxDepth,
  int? blockCascadeMaxRows,
  int? blockCascadeBatchSize,
}) => Env(
  environment: Environment.test,
  pgHost: Platform.environment['POSTGRES_HOST'] ?? 'localhost',
  pgPort: int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432,
  pgDatabase: Platform.environment['POSTGRES_DBNAME'] ?? 'postgres',
  pgUsername: Platform.environment['POSTGRES_USERNAME'] ?? 'postgres',
  pgPassword: Platform.environment['POSTGRES_PASSWORD'] ?? 'password',
  genealogyNodeKeySecret: 'test-genealogy-secret',
  blockCascadeMaxDepth: blockCascadeMaxDepth,
  blockCascadeMaxRows: blockCascadeMaxRows,
  blockCascadeBatchSize: blockCascadeBatchSize,
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
  AS ok
''',
  ).getSingle();
  return row.read<bool>('ok');
}
