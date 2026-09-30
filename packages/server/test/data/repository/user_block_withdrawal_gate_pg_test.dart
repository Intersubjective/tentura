@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/domain/invite_genealogy/invite_genealogy_node_key.dart';
import 'package:tentura_server/domain/use_case/block_cascade_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';

/// B3 withdrawal gate — spec §9.8 T-G1…T-G8.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_USER_BLOCK_WITHDRAWAL_GATE_TEST_DB',
    defaultNamePrefix: 'tentura_test_ub_withdrawal',
  );
  final postgresReachable = await canReachPostgresAdmin(target);
  final skipReason = postgresReachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late Connection writer;
  late TenturaDb db;
  late Env env;
  late UserBlockRepository repo;
  late BlockCascadeCase cascadeJob;
  late bool hasLegacyTrustLedger;

  // Canonical §9.1 ids with `g` infix for parallel-safe pg runs.
  const rootId = 'Ublkgroot0001';
  const aliceId = 'Ublkgalice001';
  const bobId = 'Ublkgbob00001';
  const carolId = 'Ublkgcarol001';
  const daveId = 'Ublkgdave0001';
  const p1Id = 'Ublkgpupp0001';
  const p2Id = 'Ublkgpupp0002';
  const p3Id = 'Ublkgpupp0003';
  const erinId = 'Ublkgerin0001';
  const veraId = 'Ublkgvera0001';

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

  Future<void> seedHonestTrustEdge({
    required String subject,
    required String object,
    String bin = 'very_good',
    double count = 2,
  }) async {
    final trustW = bin == 'good' ? 0.5 * count : 0.8 * count;
    final weight = trustW.clamp(0.001, 1.0);
    await db.customStatement(
      '''
INSERT INTO public.user_trust_edge (
  subject, object, prev_sent_weight, trust_w, wall_d, target_w,
  created_at, updated_at
) VALUES (
  '$subject', '$object', $weight, $weight, 0, $weight, now(), now()
)
ON CONFLICT (subject, object) DO UPDATE SET
  prev_sent_weight = EXCLUDED.prev_sent_weight,
  trust_w = EXCLUDED.trust_w,
  target_w = EXCLUDED.target_w,
  updated_at = EXCLUDED.updated_at
''',
    );
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
    await seedHonestTrustEdge(
      subject: aliceId,
      object: p1Id,
      bin: 'good',
      count: 1,
    );
    await seedHonestTrustEdge(subject: bobId, object: aliceId);
  }

  Future<List<Map<String, Object?>>> sourceRows({
    required String subject,
    required String object,
  }) async {
    if (!hasLegacyTrustLedger) {
      return [];
    }
    final rows = await db.customSelect(
      '''
SELECT trust_context, subject, object,
       s_very_bad, s_bad, s_no_effect, s_good, s_very_good,
       anchor_at::text AS anchor_at
FROM public.user_trust_source_edge
WHERE subject = '$subject' AND object = '$object'
ORDER BY trust_context
''',
    ).get();
    return rows
        .map(
          (row) => {
            'trust_context': row.read<String>('trust_context'),
            'subject': row.read<String>('subject'),
            'object': row.read<String>('object'),
            's_very_bad': row.read<double>('s_very_bad'),
            's_bad': row.read<double>('s_bad'),
            's_no_effect': row.read<double>('s_no_effect'),
            's_good': row.read<double>('s_good'),
            's_very_good': row.read<double>('s_very_good'),
            'anchor_at': row.read<String>('anchor_at'),
          },
        )
        .toList();
  }

  Future<Map<String, Object?>> trustEdgeProjection({
    required String subject,
    required String object,
  }) async {
    final row = await db.customSelect(
      '''
SELECT trust_w, wall_d, target_w, prev_sent_weight
FROM public.user_trust_edge
WHERE subject = '$subject' AND object = '$object'
''',
    ).getSingle();
    return {
      'trust_w': row.read<double>('trust_w'),
      'wall_d': row.read<double>('wall_d'),
      'target_w': row.read<double>('target_w'),
      'prev_sent_weight': row.read<double>('prev_sent_weight'),
    };
  }

  Future<double> prevSentWeight(String subject, String object) async {
    final row = await db.customSelect(
      '''
SELECT prev_sent_weight
FROM public.user_trust_edge
WHERE subject = '$subject' AND object = '$object'
''',
    ).getSingle();
    return row.read<double>('prev_sent_weight');
  }

  Future<double> rebuildReturnWeight({
    required String subject,
    required String object,
    double? epsilonOverride,
  }) async {
    if (epsilonOverride == -1) {
      final honestRow = await db
          .customSelect(
            r'''
SELECT trust_w AS w, target_w,
  EXISTS (
    SELECT 1 FROM public.user_block b
    WHERE b.blocker_id = $1 AND b.blocked_id = $2
  ) AS blocked
FROM public.user_trust_edge
WHERE subject = $1 AND object = $2
''',
            variables: [
              Variable<String>(subject),
              Variable<String>(object),
            ],
          )
          .getSingleOrNull();
      if (honestRow != null) {
        if (!honestRow.read<bool>('blocked')) {
          await db.customStatement(
            r'''
UPDATE public.user_trust_edge
SET prev_sent_weight = target_w, updated_at = now()
WHERE subject = $1 AND object = $2
''',
            [subject, object],
          );
          await db.customStatement(
            r'''
DELETE FROM public.trust_publish_queue
WHERE subject_user_id = $1 AND object_user_id = $2
''',
            [subject, object],
          );
        }
        return honestRow.read<double>('w');
      }
    }
    if (!hasLegacyTrustLedger) {
      final row = await db
          .customSelect(
            r'''
SELECT trust_w AS w
FROM public.user_trust_edge
WHERE subject = $1 AND object = $2
''',
            variables: [
              Variable<String>(subject),
              Variable<String>(object),
            ],
          )
          .getSingleOrNull();
      return row?.read<double>('w') ?? 0;
    }
    await db.customSelect(
      r'SELECT public.trust_project_pair($1, $2)',
      variables: [
        Variable<String>(subject),
        Variable<String>(object),
      ],
    ).getSingle();
    if (epsilonOverride == -1) {
      await db.customStatement(
        r'''
UPDATE public.user_trust_edge
SET prev_sent_weight = target_w, updated_at = now()
WHERE subject = $1 AND object = $2
''',
        [subject, object],
      );
      await db.customStatement(
        r'''
DELETE FROM public.trust_publish_queue
WHERE subject_user_id = $1 AND object_user_id = $2
''',
        [subject, object],
      );
    }
    final row = await db.customSelect(
      r'''
SELECT trust_w AS w
FROM public.user_trust_edge
WHERE subject = $1 AND object = $2
''',
      variables: [
        Variable<String>(subject),
        Variable<String>(object),
      ],
    ).getSingle();
    return row.read<double>('w');
  }

  Future<int> trustEvidenceEventCount() async {
    if (!hasLegacyTrustLedger) {
      return 0;
    }
    final idList = fixtureIds.map((id) => "'$id'").join(', ');
    final row = await db.customSelect(
      '''
SELECT COUNT(*)::int AS c
FROM public.trust_evidence_event
WHERE subject_user_id IN ($idList) OR object_user_id IN ($idList)
''',
    ).getSingle();
    return row.read<int>('c');
  }

  Future<bool> hasTrustEdge(String subject, String object) => db
      .customSelect(
        '''
SELECT EXISTS (
  SELECT 1 FROM public.user_trust_edge
  WHERE subject = '$subject' AND object = '$object'
) AS ok
''',
      )
      .map((row) => row.read<bool>('ok'))
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
    if (hasLegacyTrustLedger) {
      await db.customStatement(
        'DELETE FROM public.trust_evidence_event '
        'WHERE subject_user_id IN ($idList) OR object_user_id IN ($idList)',
      );
      await db.customStatement(
        'DELETE FROM public.user_trust_source_edge WHERE subject IN ($idList) '
        'OR object IN ($idList)',
      );
    }
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
      logger: Logger('user_block_withdrawal_gate_pg_test.cascade'),
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
      await migrateDbSchema(writer);
      bindHarness(_disposableEnv(target));
      hasLegacyTrustLedger = await _hasLegacyTrustLedger(db);
    });

    setUp(() async {
      await cleanup();
      await seedCanonicalFixture();
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
    'T-G1: block gates publish to zero without touching source evidence',
    () async {
      final sourceBefore = await sourceRows(subject: aliceId, object: bobId);
      final projectionBefore = await trustEdgeProjection(
        subject: aliceId,
        object: bobId,
      );
      final honestPrev = projectionBefore['prev_sent_weight']! as double;
      expect(honestPrev, greaterThan(0));

      await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 0);
      await repo.applyWithdrawal(blockerId: aliceId, blockedId: bobId);

      expect(await prevSentWeight(aliceId, bobId), 0);
      expect(await sourceRows(subject: aliceId, object: bobId), sourceBefore);

      final projectionAfter = await trustEdgeProjection(
        subject: aliceId,
        object: bobId,
      );
      for (final key in ['trust_w', 'wall_d', 'target_w']) {
        expect(
          projectionAfter[key]! as double,
          closeTo(projectionBefore[key]! as double, 0.0001),
        );
      }

      final returned = await rebuildReturnWeight(
        subject: aliceId,
        object: bobId,
        epsilonOverride: -1,
      );
      expect(returned, closeTo(honestPrev, 0.001));
      expect(returned, greaterThan(0));
    },
    skip: skipReason,
  );

  test(
    'T-G2: unblock republishes honest weight exactly',
    () async {
      final honestPrev = await prevSentWeight(aliceId, bobId);
      await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 0);
      await repo.applyWithdrawal(blockerId: aliceId, blockedId: bobId);
      expect(await prevSentWeight(aliceId, bobId), 0);

      await repo.unblock(blockerId: aliceId, blockedId: bobId);

      expect(
        await prevSentWeight(aliceId, bobId),
        closeTo(honestPrev, 0.001),
      );
    },
    skip: skipReason,
  );

  test(
    'T-G3: blocking a stranger with no edge is a publish no-op',
    () async {
      expect(await hasTrustEdge(aliceId, erinId), isFalse);

      await repo.block(blockerId: aliceId, blockedId: erinId, cascadeMode: 0);
      await repo.applyWithdrawal(blockerId: aliceId, blockedId: erinId);

      expect(await hasTrustEdge(aliceId, erinId), isFalse);
    },
    skip: skipReason,
  );

  test(
    'T-G4: reverse edge B→A is untouched when A blocks B',
    () async {
      final reverseBefore = await prevSentWeight(bobId, aliceId);
      expect(reverseBefore, greaterThan(0));

      await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 0);
      await repo.applyWithdrawal(blockerId: aliceId, blockedId: bobId);

      expect(
        await prevSentWeight(bobId, aliceId),
        closeTo(reverseBefore, 0.001),
      );
    },
    skip: skipReason,
  );

  test(
    'T-G5: materializeCascadeBatch gates inherited member edge via effective set',
    () async {
      final honestP1 = await prevSentWeight(aliceId, p1Id);
      expect(honestP1, greaterThan(0));

      await materializeMode1Cascade();

      expect(await prevSentWeight(aliceId, p1Id), 0);
    },
    skip: skipReason,
  );

  test(
    'T-G6: cascade materialization publishes even when |w − prev| < epsilon',
    () async {
      final before = await trustEdgeProjection(subject: aliceId, object: p1Id);
      final stablePrev = before['prev_sent_weight']! as double;
      final stableW = await rebuildReturnWeight(
        subject: aliceId,
        object: p1Id,
      );
      expect((stableW - stablePrev).abs(), lessThan(0.1));

      final prevAfterNoop = await prevSentWeight(aliceId, p1Id);
      await rebuildReturnWeight(subject: aliceId, object: p1Id);
      expect(await prevSentWeight(aliceId, p1Id), closeTo(prevAfterNoop, 1e-9));

      await materializeMode1Cascade();

      expect(await prevSentWeight(aliceId, p1Id), 0);

      await rebuildReturnWeight(
        subject: aliceId,
        object: p1Id,
        epsilonOverride: -1,
      );
      expect(await prevSentWeight(aliceId, p1Id), 0);
    },
    skip: skipReason,
  );

  test(
    'T-G7: block/unblock cycle adds zero trust_evidence_event rows',
    () async {
      final eventsBefore = await trustEvidenceEventCount();

      await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 0);
      await repo.applyWithdrawal(blockerId: aliceId, blockedId: bobId);
      await repo.unblock(blockerId: aliceId, blockedId: bobId);

      expect(await trustEvidenceEventCount(), eventsBefore);
    },
    skip: skipReason,
  );

  test(
    'T-G8: inherited cascade block/unblock cycles recover weight without drift',
    () async {
      final honestP1 = await prevSentWeight(aliceId, p1Id);
      expect(honestP1, greaterThan(0));

      for (var cycle = 0; cycle < 2; cycle++) {
        await materializeMode1Cascade();
        expect(await prevSentWeight(aliceId, p1Id), 0);

        await repo.unblock(blockerId: aliceId, blockedId: bobId);
        expect(
          await prevSentWeight(aliceId, p1Id),
          closeTo(honestP1, 0.001),
        );
      }
    },
    skip: skipReason,
  );

  test(
    'X9: block/unblock churn leaves tables and source evidence unchanged',
    () async {
      const cycles = 30;
      final honestPrev = await prevSentWeight(aliceId, bobId);
      final sourceBefore = await sourceRows(subject: aliceId, object: bobId);

      for (var i = 0; i < cycles; i++) {
        await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 0);
        await repo.applyWithdrawal(blockerId: aliceId, blockedId: bobId);
        await repo.unblock(blockerId: aliceId, blockedId: bobId);
      }

      final blockCount = await db.customSelect(
        '''
SELECT COUNT(*)::int AS c FROM public.user_block
WHERE blocker_id = '$aliceId' OR blocked_id = '$aliceId'
''',
      ).getSingle();
      expect(blockCount.read<int>('c'), 0);

      final intentCount = await db.customSelect(
        '''
SELECT COUNT(*)::int AS c FROM public.user_block_intent
WHERE blocker_id = '$aliceId' OR blocked_id = '$aliceId'
''',
      ).getSingle();
      expect(intentCount.read<int>('c'), 0);

      expect(await sourceRows(subject: aliceId, object: bobId), sourceBefore);
      expect(
        await prevSentWeight(aliceId, bobId),
        closeTo(honestPrev, 0.001),
      );
    },
    skip: skipReason,
  );
}

Future<bool> _hasLegacyTrustLedger(TenturaDb db) async {
  final row = await db.customSelect(
    '''
SELECT to_regclass('public.trust_evidence_event') IS NOT NULL AS ok
''',
  ).getSingle();
  return row.read<bool>('ok');
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
