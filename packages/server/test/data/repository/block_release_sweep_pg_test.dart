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
import 'package:tentura_server/domain/port/user_block_repository_port.dart';
import 'package:tentura_server/domain/use_case/block_cascade_case.dart';
import 'package:tentura_server/domain/use_case/block_release_sweep_case.dart';
import 'package:tentura_server/env.dart';

/// Release sweep — spec §9.7 T-F1…T-F7, §11 X10, plus cursor advancement.
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
  late BlockReleaseSweepCase releaseJob;

  // Canonical §9.1 ids with `f` infix for parallel-safe pg runs.
  const rootId = 'Ublkfroot0001';
  const aliceId = 'Ublkfalice001';
  const bobId = 'Ublkfbob00001';
  const carolId = 'Ublkfcarol001';
  const daveId = 'Ublkfdave0001';
  const p1Id = 'Ublkfpupp0001';
  const p2Id = 'Ublkfpupp0002';
  const p3Id = 'Ublkfpupp0003';
  const erinId = 'Ublkferin0001';
  const veraId = 'Ublkfvera0001';
  const p5Id = 'Ublkfpupp0005';

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
    p5Id,
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
  descendant_user_id = EXCLUDED.descendant_user_id
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

  Future<void> seedHonestTrustEdge({
    required String subject,
    required String object,
  }) async {
    await db.customStatement(
      '''
SELECT trust_apply_source_evidence(
  'personal', '$subject', '$object', 'good', 1
)
''',
    );
    await db.customSelect(
      "SELECT trust_rebuild_effective_edge('$subject', '$object', -1)",
    ).getSingle();
  }

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

    await seedHonestTrustEdge(subject: aliceId, object: bobId);
    await seedHonestTrustEdge(subject: aliceId, object: p1Id);
    await seedHonestTrustEdge(subject: bobId, object: aliceId);
  }

  Future<bool> blockHides(String a, String b) => db
      .customSelect(
        "SELECT public.block_hides('$a', '$b') AS hidden",
      )
      .map((r) => r.read<bool>('hidden'))
      .getSingle();

  Future<bool> hasInheritedRow({
    required String blockerId,
    required String blockedId,
    required String originId,
  }) => db
      .customSelect(
        '''
SELECT EXISTS (
  SELECT 1 FROM public.user_block
  WHERE blocker_id = '$blockerId'
    AND blocked_id = '$blockedId'
    AND origin_id = '$originId'
) AS ok
''',
      )
      .map((r) => r.read<bool>('ok'))
      .getSingle();

  Future<void> materializeMode1Cascade() async {
    await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 1);
    for (var i = 0; i < 100; i++) {
      await cascadeJob.runDue();
      final row = await db.customSelect(
        '''
SELECT cascade_status FROM public.user_block_intent
WHERE blocker_id = '$aliceId' AND blocked_id = '$bobId'
''',
      ).getSingle();
      if (row.read<int>('cascade_status') >= 2) return;
    }
    throw StateError('mode-1 cascade did not complete');
  }

  Future<void> runFullReleaseSweep() async {
    await releaseJob.runDue();
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
      'DELETE FROM public.user_trust_source_edge WHERE subject IN ($idList) '
      'OR object IN ($idList)',
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
      logger: Logger('block_release_sweep_pg_test.cascade'),
    );
    releaseJob = BlockReleaseSweepCase(
      repo,
      env: env,
      logger: Logger('block_release_sweep_pg_test.release'),
    );
  }

  if (skipReason == false) {
    setUp(() async {
      bindHarness(_testEnv());
      await cleanup();
      await seedCanonicalFixture();
    });

    tearDown(() async {
      await cleanup();
      await db.close();
    });
  }

  test(
    'T-F1: inherited P1 released when P1↔V becomes mutual (V is A-trusted)',
    () async {
      await materializeMode1Cascade();
      expect(await hasInheritedRow(
        blockerId: aliceId,
        blockedId: p1Id,
        originId: bobId,
      ), isTrue);

      await insertMutualVote(p1Id, veraId);
      await runFullReleaseSweep();

      expect(await hasInheritedRow(
        blockerId: aliceId,
        blockedId: p1Id,
        originId: bobId,
      ), isFalse);
      expect(await blockHides(aliceId, p1Id), isFalse);
    },
    skip: skipReason,
  );

  test(
    'T-F2: direct root row is never a release candidate',
    () async {
      await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 0);
      await insertMutualVote(aliceId, bobId);

      await runFullReleaseSweep();

      expect(await hasInheritedRow(
        blockerId: aliceId,
        blockedId: bobId,
        originId: bobId,
      ), isTrue);
      expect(await blockHides(aliceId, bobId), isTrue);
    },
    skip: skipReason,
  );

  test(
    'T-F3: promoted direct row survives; inherited row for same person goes',
    () async {
      await materializeMode1Cascade();
      await repo.promoteToDirect(blockerId: aliceId, blockedId: p2Id);
      await insertMutualVote(p2Id, veraId);

      await runFullReleaseSweep();

      expect(await hasInheritedRow(
        blockerId: aliceId,
        blockedId: p2Id,
        originId: bobId,
      ), isFalse);
      expect(await hasInheritedRow(
        blockerId: aliceId,
        blockedId: p2Id,
        originId: p2Id,
      ), isTrue);
      expect(await blockHides(aliceId, p2Id), isTrue);
    },
    skip: skipReason,
  );

  test(
    'T-F4: mode-2 cascade members are never released',
    () async {
      await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 2);
      for (var i = 0; i < 100; i++) {
        await cascadeJob.runDue();
        final row = await db.customSelect(
          '''
SELECT cascade_status FROM public.user_block_intent
WHERE blocker_id = '$aliceId' AND blocked_id = '$bobId'
''',
        ).getSingle();
        if (row.read<int>('cascade_status') >= 2) break;
      }

      await insertMutualVote(p1Id, veraId);
      await runFullReleaseSweep();

      expect(await hasInheritedRow(
        blockerId: aliceId,
        blockedId: p1Id,
        originId: bobId,
      ), isTrue);
    },
    skip: skipReason,
  );

  test(
    'T-F5: released pair republishes honest trust weight via trust_rebuild',
    () async {
      await materializeMode1Cascade();
      final honestRow = await db.customSelect(
        '''
SELECT prev_sent_weight
FROM public.user_trust_edge
WHERE subject = '$aliceId' AND object = '$p1Id'
''',
      ).getSingle();
      final honestWeight = honestRow.read<double>('prev_sent_weight');
      expect(honestWeight, greaterThan(0));

      await db.customStatement(
        '''
UPDATE public.user_trust_edge
SET prev_sent_weight = 0
WHERE subject = '$aliceId' AND object = '$p1Id'
''',
      );

      await insertMutualVote(p1Id, veraId);
      await runFullReleaseSweep();

      final row = await db.customSelect(
        '''
SELECT prev_sent_weight
FROM public.user_trust_edge
WHERE subject = '$aliceId' AND object = '$p1Id'
''',
      ).getSingle();
      expect(row.read<double>('prev_sent_weight'), closeTo(honestWeight, 0.001));
    },
    skip: skipReason,
  );

  test(
    'T-F6: after release, signup under released person does not inherit block',
    () async {
      await materializeMode1Cascade();
      await insertMutualVote(p1Id, veraId);
      await runFullReleaseSweep();
      expect(await blockHides(aliceId, p1Id), isFalse);

      final tP1 = DateTime.utc(2026, 3);
      final tP5 = DateTime.utc(2026, 6);
      await insertUser(p5Id, tP5);
      await insertGenealogyEdge(
        ancestorId: p1Id,
        ancestorAt: tP1,
        descendantId: p5Id,
        descendantAt: tP5,
        genealogyCreatedAt: DateTime.utc(2026, 6, 1),
      );

      expect(
        await hasInheritedRow(
          blockerId: aliceId,
          blockedId: p5Id,
          originId: bobId,
        ),
        isFalse,
      );
    },
    skip: skipReason,
  );

  test(
    'T-F7: merely-mutual P1↔P2 (not A-trusted) is not released',
    () async {
      await materializeMode1Cascade();
      await runFullReleaseSweep();

      expect(await hasInheritedRow(
        blockerId: aliceId,
        blockedId: p1Id,
        originId: bobId,
      ), isTrue);
      expect(await hasInheritedRow(
        blockerId: aliceId,
        blockedId: p2Id,
        originId: bobId,
      ), isTrue);
    },
    skip: skipReason,
  );

  test(
    'X10: blocking the voucher re-evaluates attachment; Carol stays blocked',
    () async {
      await materializeMode1Cascade();
      await db.customStatement(
        '''
DELETE FROM public.vote_user
WHERE (subject = '$carolId' AND object = '$veraId')
   OR (subject = '$veraId' AND object = '$carolId')
''',
      );
      await db.customStatement(
        '''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$aliceId', '$carolId', '$bobId')
ON CONFLICT DO NOTHING
''',
      );
      await insertMutualVote(carolId, veraId);

      await repo.block(blockerId: aliceId, blockedId: veraId, cascadeMode: 0);
      await runFullReleaseSweep();

      expect(await hasInheritedRow(
        blockerId: aliceId,
        blockedId: carolId,
        originId: bobId,
      ), isTrue);
    },
    skip: skipReason,
  );

  test(
    'cursor: two limit-1 batches examine different candidates (attached rows advance)',
    () async {
      await materializeMode1Cascade();

      final first = await repo.runReleaseSweep(limit: 1, afterCursor: null);
      expect(first.lastExaminedCandidate, isNotNull);
      expect(first.reachedTail, isFalse);

      final second = await repo.runReleaseSweep(
        limit: 1,
        afterCursor: first.lastExaminedCandidate,
      );
      expect(second.lastExaminedCandidate, isNotNull);
      expect(
        second.lastExaminedCandidate,
        isNot(equals(first.lastExaminedCandidate)),
      );
    },
    skip: skipReason,
  );
}

Env _testEnv({
  int? trustSweepBatchSize,
  Duration? trustSweepTimeBudget,
}) => Env(
  environment: Environment.test,
  pgHost: Platform.environment['POSTGRES_HOST'] ?? 'localhost',
  pgPort: int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432,
  pgDatabase: Platform.environment['POSTGRES_DBNAME'] ?? 'postgres',
  pgUsername: Platform.environment['POSTGRES_USERNAME'] ?? 'postgres',
  pgPassword: Platform.environment['POSTGRES_PASSWORD'] ?? 'password',
  genealogyNodeKeySecret: 'test-genealogy-secret',
  trustSweepBatchSize: trustSweepBatchSize,
  trustSweepTimeBudget: trustSweepTimeBudget,
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
  final row = await db
      .customSelect(
        r'''
SELECT EXISTS (
  SELECT 1
  FROM information_schema.tables
  WHERE table_schema = 'public' AND table_name = 'user_block'
) AS ok
''',
      )
      .getSingle();
  return row.read<bool>('ok');
}
