@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/invite_genealogy_repository.dart';
import 'package:tentura_server/data/repository/mock/user_trust_edge_repository_mock.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/env.dart';

Future<void> main() async {
  final postgresReachable = await _canConnectPostgres();
  var skipReason = postgresReachable ? false : 'local Postgres not reachable';

  if (postgresReachable) {
    final env = _testEnv();
    final probe = TenturaDb(env);
    try {
      if (!await _hasInviteGenealogyTable(probe)) {
        skipReason = 'invite_genealogy table missing';
      }
    } finally {
      await probe.close();
    }
  }

  late TenturaDb db;
  late UserRepository repo;
  late Env env;

  const ancestorId = 'Usigngeneanc01';
  const invitationId = 'Isigngene001';
  const ancestorPublicKey = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const descendantPublicKey = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

  String? descendantId;

  if (skipReason == false) {
    setUpAll(() async {
      env = _testEnv();
      db = TenturaDb(env);
      repo = UserRepository(
        env,
        db,
        const UserTrustEdgeRepositoryMock(),
        InviteGenealogyRepository(env, db),
      );
    });

    tearDownAll(() async {
      await db.close();
    });

    setUp(() async {
      await db.customStatement(
        '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES (
  '$ancestorId',
  'Ancestor',
  '$ancestorPublicKey',
  '2026-01-01T00:00:00Z',
  '2026-01-01T00:00:00Z'
)
ON CONFLICT (id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  public_key = EXCLUDED.public_key,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at
''',
      );
      await db.customStatement(
        '''
INSERT INTO public.invitation (
  id,
  user_id,
  addressee_name,
  created_at,
  updated_at
) VALUES (
  '$invitationId',
  '$ancestorId',
  'Invitee',
  now(),
  now()
)
ON CONFLICT (id) DO UPDATE SET
  user_id = EXCLUDED.user_id,
  invited_id = NULL,
  addressee_name = EXCLUDED.addressee_name,
  created_at = now(),
  updated_at = now()
''',
      );
    });

    tearDown(() async {
      await db.customStatement(
        "DELETE FROM public.invite_genealogy WHERE invitation_id = '$invitationId'",
      );
      if (descendantId != null) {
        await db.customStatement(
          '''DELETE FROM public.vote_user WHERE subject IN ('$descendantId', '$ancestorId') OR object IN ('$descendantId', '$ancestorId')''',
        );
        await db.customStatement(
          '''DELETE FROM public.user_contact WHERE viewer_id = '$ancestorId' AND subject_id = '$descendantId' ''',
        );
        await db.customStatement(
          '''DELETE FROM public.account_credential WHERE account_id = '$descendantId' ''',
        );
        await db.customStatement(
          '''DELETE FROM public."user" WHERE id = '$descendantId' ''',
        );
        descendantId = null;
      }
      await db.customStatement(
        "DELETE FROM public.invitation WHERE id = '$invitationId'",
      );
      await db.customStatement(
        '''DELETE FROM public."user" WHERE id = '$ancestorId' ''',
      );
    });
  }

  test('createInvited appends invite_genealogy row in same transaction', () async {
    if (skipReason != false) {
      return;
    }
    final descendant = await repo.createInvited(
      invitationId: invitationId,
      publicKey: descendantPublicKey,
      displayName: 'Descendant',
    );
    descendantId = descendant.id;

    final rows = await db.customSelect(
      '''
SELECT ancestor_user_id, descendant_user_id, invitation_id
FROM public.invite_genealogy
WHERE invitation_id = '$invitationId'
''',
    ).get();

    expect(rows, hasLength(1));
    expect(rows.single.read<String>('ancestor_user_id'), ancestorId);
    expect(rows.single.read<String>('descendant_user_id'), descendantId);
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

Future<bool> _hasInviteGenealogyTable(TenturaDb db) async {
  final rows = await db.customSelect(
    '''
SELECT 1
FROM information_schema.tables
WHERE table_schema = 'public' AND table_name = 'invite_genealogy'
LIMIT 1
''',
  ).getSingleOrNull();
  return rows != null;
}
