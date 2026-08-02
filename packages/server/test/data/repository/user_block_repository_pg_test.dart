@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/env.dart';

import '../../support/pg_test_public_keys.dart';

/// Direct block repository integration — spec §9.2 Group T-A.
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
      }
    } finally {
      await probe.close();
    }
  }

  late TenturaDb db;
  late UserBlockRepository repo;

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
INSERT INTO public.beacon (id, user_id, title, description, status, created_at, updated_at)
VALUES ('$id', '$authorId', '$id', '', ${BeaconStatus.open.smallintValue},
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
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
      "DELETE FROM public.beacon WHERE id IN ('$aliceBeaconId', '$bobBeaconId')",
    );
    await db.customStatement(
      'DELETE FROM public."user" WHERE id IN ($userList)',
    );
  }

  if (skipReason == false) {
    setUpAll(() async {
      db = TenturaDb(_testEnv());
      repo = UserBlockRepository(db);
    });

    tearDown(() => cleanup());

    tearDownAll(() async {
      await cleanup();
      await db.close();
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

    await db.customStatement('DELETE FROM public."user" WHERE id = \'$bobId\'');

    final blocks = await db.customSelect(
      "SELECT 1 FROM public.user_block WHERE blocker_id = '$aliceId'",
    ).get();
    expect(blocks, isEmpty);

    final intents = await db.customSelect(
      "SELECT 1 FROM public.user_block_intent WHERE blocker_id = '$aliceId'",
    ).get();
    expect(intents, isEmpty);
  }, skip: skipReason);

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
