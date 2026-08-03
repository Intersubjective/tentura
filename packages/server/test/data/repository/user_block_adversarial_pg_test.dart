@Tags(['pg'])
library;

import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/domain/invite_genealogy/invite_genealogy_node_key.dart';
import 'package:tentura_server/domain/use_case/block_cascade_case.dart';
import 'package:tentura_server/env.dart';

/// Adversarial corner cases — spec §11 X1, X7, X12, X13, X15, X16.
///
/// X9 (churn) is covered by `user_block_withdrawal_gate_pg_test.dart`.
Future<void> main() async {
  final postgresReachable = await _canConnectPostgres();
  var skipReason = postgresReachable ? false : 'local Postgres not reachable';
  var beaconBlockSkipReason = skipReason;

  if (postgresReachable) {
    final probe = TenturaDb(_testEnv());
    try {
      if (!await _hasUserBlockSchema(probe)) {
        skipReason = 'm0135 schema (user_block / block_hides) missing';
        beaconBlockSkipReason = skipReason;
      } else if (!await _beaconVisibilityIncludesBlock(probe)) {
        beaconBlockSkipReason =
            'm0136 schema (beacon_can_read_content block clause) missing';
      } else if (!await _hasInheritTrigger(probe)) {
        skipReason =
            'm0136 schema (user_block_inherit_on_invite trigger) missing';
      }
    } finally {
      await probe.close();
    }
  }

  late TenturaDb db;
  late Env env;
  late UserBlockRepository repo;
  late BlockCascadeCase cascadeJob;

  // Canonical §9.1 fixture with `adv` infix for parallel-safe pg runs.
  const rootId = 'Ublkadvroot001';
  const aliceId = 'Ublkadvalice01';
  const bobId = 'Ublkadvbob0001';
  const carolId = 'Ublkadvcarol01';
  const daveId = 'Ublkadvdave001';
  const p1Id = 'Ublkadvpupp001';
  const p2Id = 'Ublkadvpupp002';
  const p3Id = 'Ublkadvpupp003';
  const erinId = 'Ublkadverin001';
  const veraId = 'Ublkadvvera001';

  const launderedId = 'Ublkadvlaund01';
  const reregisterId = 'Ublkadvreg0001';
  const aliceBeaconId = 'Bblkadv000001';
  const carolBeaconId = 'Bblkadv000002';
  const stewardBeaconId = 'Bblkadv000003';

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
    launderedId,
    reregisterId,
  ];
  final beaconIds = [aliceBeaconId, carolBeaconId, stewardBeaconId];

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

  Future<void> insertBeacon({
    required String id,
    required String authorId,
  }) => db.customStatement(
    '''
INSERT INTO public.beacon (id, user_id, title, description, status, created_at, updated_at)
VALUES ('$id', '$authorId', '$id', '', ${BeaconStatus.open.smallintValue},
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
  );

  Future<void> insertOpenHelpOffer({
    required String beaconId,
    required String userId,
  }) => db.customStatement(
    '''
INSERT INTO public.beacon_help_offer (
  beacon_id, user_id, message, status, created_at, updated_at
) VALUES ('$beaconId', '$userId', 'open commitment', 0, now(), now())
ON CONFLICT (beacon_id, user_id) DO UPDATE SET status = 0
''',
  );

  Future<void> insertSteward({
    required String beaconId,
    required String userId,
    required String participantId,
  }) => db.customStatement(
    '''
INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, room_access, created_at, updated_at
) VALUES (
  '$participantId', '$beaconId', '$userId',
  ${BeaconParticipantRoleBits.steward}, ${RoomAccessBits.none}, now(), now()
)
ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role
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

  Future<bool> blockHides(String a, String b) => db
      .customSelect(
        r'SELECT public.block_hides($1, $2) AS hidden',
        variables: [Variable<String>(a), Variable<String>(b)],
      )
      .map((row) => row.read<bool>('hidden'))
      .getSingle();

  Future<bool> beaconCanReadContent(String beaconId, String viewerId) => db
      .customSelect(
        r'SELECT public.beacon_can_read_content($1, $2) AS ok',
        variables: [Variable<String>(beaconId), Variable<String>(viewerId)],
      )
      .map((row) => row.read<bool>('ok'))
      .getSingle();

  Future<bool> hasBlockRow({
    required String blockerId,
    required String blockedId,
    String? originId,
  }) async {
    final originClause = originId == null
        ? ''
        : " AND origin_id = '$originId'";
    final rows = await db.customSelect(
      '''
SELECT 1 FROM public.user_block
WHERE blocker_id = '$blockerId' AND blocked_id = '$blockedId'$originClause
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
    final beaconList = beaconIds.map((id) => "'$id'").join(', ');
    await db.customStatement(
      'DELETE FROM public.beacon_help_offer WHERE beacon_id IN ($beaconList)',
    );
    await db.customStatement(
      'DELETE FROM public.beacon_participant WHERE beacon_id IN ($beaconList)',
    );
    await db.customStatement(
      'DELETE FROM public.user_block WHERE blocker_id IN ($idList) '
      'OR blocked_id IN ($idList)',
    );
    await db.customStatement(
      'DELETE FROM public.user_block_intent WHERE blocker_id IN ($idList) '
      'OR blocked_id IN ($idList)',
    );
    await db.customStatement(
      'DELETE FROM public.beacon WHERE id IN ($beaconList)',
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
      logger: Logger('user_block_adversarial_pg_test.cascade'),
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
    'X1: invite laundering — signup under unblocked friend is not inherited',
    () async {
      // Accepted limitation (design §10.6): cascade tracks the invite tree, not
      // intent. Bob is cascade-blocked; a new account invited by unblocked friend
      // Erin does not inherit Alice's block on Bob — the gap is identity-scoped to
      // genealogy edges, not "who asked whom to invite."
      await materializeMode1Cascade();
      expect(await blockHides(aliceId, bobId), isTrue);
      expect(await blockHides(aliceId, erinId), isFalse);

      final tErin = DateTime.utc(2026, 3);
      final tNew = DateTime.utc(2026, 6);
      await signupUnder(
        newUserId: launderedId,
        inviterId: erinId,
        inviterAt: tErin,
        newUserAt: tNew,
      );

      expect(
        await hasBlockRow(
          blockerId: aliceId,
          blockedId: launderedId,
          originId: bobId,
        ),
        isFalse,
      );
      final rows = await db.customSelect(
        "SELECT 1 FROM public.user_block WHERE blocker_id = '$aliceId' "
        "AND blocked_id = '$launderedId'",
      ).get();
      expect(rows, isEmpty);
    },
    skip: skipReason,
  );

  test(
    'X7: mutual concurrent block — opposite directions complete without deadlock',
    () async {
      await Future.wait([
        repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 0),
        repo.block(blockerId: bobId, blockedId: aliceId, cascadeMode: 0),
      ]);

      expect(
        await hasBlockRow(blockerId: aliceId, blockedId: bobId),
        isTrue,
      );
      expect(
        await hasBlockRow(blockerId: bobId, blockedId: aliceId),
        isTrue,
      );
      expect(await blockHides(aliceId, bobId), isTrue);
    },
    skip: skipReason,
  );

  test(
    'X12: deleting cascade origin removes all origin rows and un-hides descendants',
    () async {
      await materializeMode1Cascade();
      expect(await blockHides(aliceId, p1Id), isTrue);
      expect(await blockHides(aliceId, bobId), isTrue);

      final beforeDelete = await db.customSelect(
        "SELECT COUNT(*)::int AS c FROM public.user_block WHERE origin_id = '$bobId'",
      ).getSingle();
      expect(beforeDelete.read<int>('c'), greaterThan(1));

      await db.customStatement('DELETE FROM public."user" WHERE id = \'$bobId\'');

      final afterDelete = await db.customSelect(
        "SELECT COUNT(*)::int AS c FROM public.user_block WHERE origin_id = '$bobId'",
      ).getSingle();
      expect(afterDelete.read<int>('c'), 0);

      final directRow = await db.customSelect(
        '''
SELECT 1 FROM public.user_block
WHERE blocker_id = '$aliceId' AND blocked_id = '$bobId'
''',
      ).get();
      expect(directRow, isEmpty);

      expect(await blockHides(aliceId, p1Id), isFalse);
      expect(await blockHides(aliceId, p2Id), isFalse);
    },
    skip: skipReason,
  );

  test(
    'X13 direct: open commitment surfaces in preview and direct block ejects',
    () async {
      await insertBeacon(id: aliceBeaconId, authorId: aliceId);
      await insertOpenHelpOffer(beaconId: aliceBeaconId, userId: bobId);
      expect(await beaconCanReadContent(aliceBeaconId, bobId), isTrue);

      final preview = await repo.preview(
        blockerId: aliceId,
        blockedId: bobId,
        cascadeMode: 0,
      );
      expect(preview.openCommitmentCount, 1);

      await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 0);
      expect(await beaconCanReadContent(aliceBeaconId, bobId), isFalse);
      expect(await beaconCanReadContent(aliceBeaconId, aliceId), isTrue);
    },
    skip: beaconBlockSkipReason,
  );

  test(
    'X13 inherited: open commitment is ejected despite spec §7.4 grandfather intent',
    () async {
      // Spec §7.4 wanted inherited-only blocks to keep room access when an open
      // commitment exists; that exception was never built into beacon_can_read_content
      // (block_hides is unconditional). This test pins actual v1 behavior, not the
      // originally-intended one — see journal "manager finding before S23."
      await insertBeacon(id: carolBeaconId, authorId: aliceId);
      await insertOpenHelpOffer(beaconId: carolBeaconId, userId: p1Id);
      expect(await beaconCanReadContent(carolBeaconId, p1Id), isTrue);

      await materializeMode1Cascade();
      expect(await blockHides(aliceId, p1Id), isTrue);
      expect(
        await hasBlockRow(
          blockerId: aliceId,
          blockedId: p1Id,
          originId: bobId,
        ),
        isTrue,
      );

      expect(await beaconCanReadContent(carolBeaconId, p1Id), isFalse);
    },
    skip: beaconBlockSkipReason,
  );

  test(
    'X15: fresh account id is not caught by an existing block',
    () async {
      // Accepted limitation: blocks are identity-scoped, not person-scoped. A user
      // who re-registers under a new id is not covered by prior blocks.
      await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 0);
      expect(await blockHides(aliceId, bobId), isTrue);

      await insertUser(reregisterId, DateTime.utc(2026, 7));
      expect(await blockHides(aliceId, reregisterId), isFalse);
      expect(
        await hasBlockRow(blockerId: aliceId, blockedId: reregisterId),
        isFalse,
      );
    },
    skip: skipReason,
  );

  test(
    'X16: steward role does not override block_hides on author beacon',
    () async {
      // Accepted limitation: block_hides is evaluated before steward/participant
      // branches in beacon_can_read_content. Stewards lose visibility of beacons
      // whose author they blocked — call out in release notes (S24), not a bug.
      await insertBeacon(id: stewardBeaconId, authorId: bobId);
      await insertSteward(
        beaconId: stewardBeaconId,
        userId: aliceId,
        participantId: 'Padvsteward01',
      );
      expect(await beaconCanReadContent(stewardBeaconId, aliceId), isTrue);

      await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 0);
      expect(await beaconCanReadContent(stewardBeaconId, aliceId), isFalse);
    },
    skip: beaconBlockSkipReason,
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

Future<bool> _beaconVisibilityIncludesBlock(TenturaDb db) async {
  final row = await db.customSelect(
    r'''
SELECT prosrc LIKE '%block_hides%' AS ok
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'beacon_can_read_content'
''',
  ).getSingleOrNull();
  return row?.read<bool>('ok') ?? false;
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
