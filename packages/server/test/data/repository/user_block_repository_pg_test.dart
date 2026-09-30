@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/domain/use_case/user_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/user_erasure_test_stack.dart';

/// Direct block repository integration — spec §9.2 Group T-A.
Future<void> main() async {
  // Disposable database at the head schema: the ambient database may predate
  // the trust ledger (`trust_project_pair`), which block/unblock now call.
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_USER_BLOCK_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_ubr',
  );
  final postgresReachable = await canReachPostgresAdmin(target);
  final skipReason = postgresReachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';
  final beaconBlockSkipReason = skipReason;

  late DisposablePgWriterSession session;
  late TenturaDb db;
  late UserBlockRepository repo;
  late UserCase userCase;

  const aliceId = 'Ublkalice001';
  const bobId = 'Ublkbob00001';
  const aliceBeaconId = 'Bblkalice001';
  const bobBeaconId = 'Bblkbob00001';
  const allUserIds = [aliceId, bobId];

  Future<void> insertUser(String id, int slot) => db.customStatement(
    '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', '${pgTestPublicKey('ublk', slot)}',
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
  );

  Future<void> insertBeacon({
    required String id,
    required String authorId,
  }) => db.customStatement(
    '''
INSERT INTO public.beacon (
  id, user_id, title, description, status, created_at, updated_at, published_at
)
VALUES ('$id', '$authorId', '$id', '', ${BeaconStatus.open.smallintValue},
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
  );

  Future<void> insertCrossReadForwardEdges() => db.customStatement(
    '''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at
) VALUES
  ('Fblkalice001', '$bobBeaconId', '$bobId', '$aliceId', now()),
  ('Fblkbob00001', '$aliceBeaconId', '$aliceId', '$bobId', now())
ON CONFLICT (id) DO NOTHING
''',
  );

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

  Future<void> seedPair() async {
    await insertUser(aliceId, 1);
    await insertUser(bobId, 2);
    await insertBeacon(id: aliceBeaconId, authorId: aliceId);
    await insertBeacon(id: bobBeaconId, authorId: bobId);
    await insertCrossReadForwardEdges();
  }

  Future<void> cleanup() async {
    final userList = allUserIds.map((id) => "'$id'").join(', ');
    await db.customStatement(
      'DELETE FROM public.user_block WHERE blocker_id IN ($userList) '
      'OR blocked_id IN ($userList)',
    );
    await db.customStatement(
      'DELETE FROM public.user_block_intent WHERE blocker_id IN ($userList) '
      'OR blocked_id IN ($userList)',
    );
    await db.customStatement(
      "DELETE FROM public.beacon_forward_edge WHERE id IN "
      "('Fblkalice001', 'Fblkbob00001')",
    );
    await db.customStatement(
      "DELETE FROM public.beacon_hierarchy_events "
      "WHERE source_beacon_id IN ('$aliceBeaconId', '$bobBeaconId')",
    );
    await db.customStatement(
      "DELETE FROM public.beacon WHERE id IN ('$aliceBeaconId', '$bobBeaconId')",
    );
    await db.customStatement(
      'DELETE FROM public."user" WHERE id IN ($userList)',
    );
  }

  UserCase buildAccountErasureUserCase(UserRepository users) {
    final env = _testEnv(target);
    final log = Logger('user_block_repository_pg_test');
    final dispatch = AttentionDispatchRepository(db, log);
    final unitOfWork = MutatingUnitOfWork(db);
    final outbox = BeaconHierarchyOutboxRepository(db);
    final lifecycleEffects = BeaconLifecycleEffectsCase(
      outbox,
      env: env,
      logger: log,
    );
    final attention = TransactionalAttentionCase(unitOfWork, dispatch);
    return buildUserErasureTestStack(
      db: db,
      userRepository: users,
      lifecycleEffects: lifecycleEffects,
      attention: attention,
      logger: log,
    ).userCase;
  }

  if (skipReason == false) {
    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      db = openDisposablePgDatabase(target);
      repo = UserBlockRepository(_testEnv(target), db);
      userCase = buildAccountErasureUserCase(buildDefaultUserRepository(db));
    });

    tearDown(() => cleanup());

    tearDownAll(() async {
      await cleanup();
      await db.close();
      await tearDownDisposablePgWriter(session: session);
    });
  }

  test('T-A1: direct block creates intent and effective row', () async {
    await seedPair();
    await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 0);

    final blocks = await db.customSelect(
      "SELECT blocker_id, blocked_id, origin_id FROM public.user_block "
      "WHERE blocker_id = '$aliceId'",
    ).get();
    expect(blocks, hasLength(1));
    expect(blocks.single.read<String>('blocked_id'), bobId);
    expect(blocks.single.read<String>('origin_id'), bobId);

    final intents = await db.customSelect(
      "SELECT cascade_mode FROM public.user_block_intent "
      "WHERE blocker_id = '$aliceId' AND blocked_id = '$bobId'",
    ).get();
    expect(intents, hasLength(1));
    expect(intents.single.read<int>('cascade_mode'), 0);
  }, skip: skipReason);

  test('T-A2: block_hides is symmetric after direct block', () async {
    await seedPair();
    await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 0);

    expect(await blockHides(aliceId, bobId), isTrue);
    expect(await blockHides(bobId, aliceId), isTrue);
  }, skip: skipReason);

  test(
    'T-A3: beacon_can_read_content denies cross-view after direct block',
    () async {
      await seedPair();
      await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 0);

      expect(await beaconCanReadContent(bobBeaconId, aliceId), isFalse);
      expect(await beaconCanReadContent(aliceBeaconId, bobId), isFalse);
    },
    skip: beaconBlockSkipReason,
  );

  test('T-A4: unblock clears rows and block_hides', () async {
    await seedPair();
    await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 0);
    await repo.unblock(blockerId: aliceId, blockedId: bobId);

    final blocks = await db.customSelect(
      "SELECT 1 FROM public.user_block WHERE blocker_id = '$aliceId'",
    ).get();
    expect(blocks, isEmpty);

    final intents = await db.customSelect(
      "SELECT 1 FROM public.user_block_intent "
      "WHERE blocker_id = '$aliceId' AND blocked_id = '$bobId'",
    ).get();
    expect(intents, isEmpty);

    expect(await blockHides(aliceId, bobId), isFalse);
    expect(await blockHides(bobId, aliceId), isFalse);
  }, skip: skipReason);

  test(
    'T-A4b: unblock restores beacon readability when visibility wall is live',
    () async {
      await seedPair();
      await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 0);
      await repo.unblock(blockerId: aliceId, blockedId: bobId);

      expect(await beaconCanReadContent(bobBeaconId, aliceId), isTrue);
      expect(await beaconCanReadContent(aliceBeaconId, bobId), isTrue);
    },
    skip: beaconBlockSkipReason,
  );

  test('T-A5: self-block is rejected by the database CHECK', () async {
    await insertUser(aliceId, 1);

    await expectLater(
      repo.block(blockerId: aliceId, blockedId: aliceId, cascadeMode: 0),
      throwsA(anything),
    );

    final blocks = await db.customSelect(
      "SELECT 1 FROM public.user_block WHERE blocker_id = '$aliceId'",
    ).get();
    expect(blocks, isEmpty);
  }, skip: skipReason);

  test('T-A6: repeat block is idempotent', () async {
    await seedPair();
    await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 0);
    await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 1);

    final blocks = await db.customSelect(
      "SELECT 1 FROM public.user_block WHERE blocker_id = '$aliceId'",
    ).get();
    expect(blocks, hasLength(1));

    final intent = await db.customSelect(
      "SELECT cascade_mode FROM public.user_block_intent "
      "WHERE blocker_id = '$aliceId' AND blocked_id = '$bobId'",
    ).getSingle();
    expect(intent.read<int>('cascade_mode'), 1);
  }, skip: skipReason);

  test('T-A7: deleting blocked user cascades block rows', () async {
    await seedPair();
    await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 0);

    expect(await userCase.deleteById(id: bobId), isTrue);

    final blocks = await db.customSelect(
      "SELECT 1 FROM public.user_block WHERE blocker_id = '$aliceId'",
    ).get();
    expect(blocks, isEmpty);

    final intents = await db.customSelect(
      "SELECT 1 FROM public.user_block_intent WHERE blocker_id = '$aliceId'",
    ).get();
    expect(intents, isEmpty);
  }, skip: skipReason);

  test(
    'T-A7b: raw user delete without erasure violates beacon_owner_or_deleted_ck',
    () async {
      await seedPair();
      await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 0);

      await expectLater(
        db.customStatement('DELETE FROM public."user" WHERE id = \'$bobId\''),
        throwsA(anything),
      );

      final blocks = await db.customSelect(
        "SELECT 1 FROM public.user_block WHERE blocker_id = '$aliceId'",
      ).get();
      expect(blocks, hasLength(1));
    },
    skip: skipReason,
  );

  test(
    'T-A7c: failed account erasure rolls back block rows and owned beacon',
    () async {
      final env = _testEnv(target);
      final failingUsers = _FailingUserRepository(
        env,
        db,
        _NoopInviteGenealogyRepository(),
        InviteSeedPromptRepositoryMock(),
      );
      failingUsers.failOnDelete = true;
      final failingCase = buildAccountErasureUserCase(failingUsers);

      await seedPair();
      await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 0);

      await expectLater(
        failingCase.deleteById(id: bobId),
        throwsA(isA<StateError>()),
      );

      final blocks = await db.customSelect(
        "SELECT 1 FROM public.user_block WHERE blocker_id = '$aliceId'",
      ).get();
      expect(blocks, hasLength(1));

      final bobBeacon = await db.customSelect(
        "SELECT user_id, status FROM public.beacon WHERE id = '$bobBeaconId'",
      ).getSingle();
      expect(bobBeacon.read<String>('user_id'), bobId);
      expect(
        bobBeacon.read<int>('status'),
        BeaconStatus.open.smallintValue,
      );
    },
    skip: skipReason,
  );

  test('T-A8: mutual direct blocks are independent', () async {
    await seedPair();
    await repo.block(blockerId: bobId, blockedId: aliceId, cascadeMode: 0);
    await repo.block(blockerId: aliceId, blockedId: bobId, cascadeMode: 0);

    expect(await blockHides(aliceId, bobId), isTrue);

    await repo.unblock(blockerId: aliceId, blockedId: bobId);

    expect(await blockHides(aliceId, bobId), isTrue);
    expect(await blockHides(bobId, aliceId), isTrue);

    final remaining = await db.customSelect(
      "SELECT blocker_id, blocked_id FROM public.user_block "
      "WHERE blocker_id = '$bobId' AND blocked_id = '$aliceId'",
    ).get();
    expect(remaining, hasLength(1));
  }, skip: skipReason);
}

Env _testEnv(DisposablePgTarget target) => Env(
  environment: Environment.test,
  pgHost: target.databaseEnv.pgHost,
  pgPort: target.databaseEnv.pgPort,
  pgDatabase: target.databaseName,
  pgUsername: target.databaseEnv.pgUsername,
  pgPassword: target.databaseEnv.pgPassword,
  genealogyNodeKeySecret: 'test-genealogy-secret',
);

final class _FailingUserRepository extends UserRepository {
  _FailingUserRepository(
    super.env,
    super.database,
    super.inviteGenealogyRepository,
    super.inviteSeedPrompt,
  );

  var failOnDelete = false;

  @override
  Future<void> deleteById({required String id}) async {
    if (failOnDelete) {
      throw StateError('injected user delete failure');
    }
    return super.deleteById(id: id);
  }
}


final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}
