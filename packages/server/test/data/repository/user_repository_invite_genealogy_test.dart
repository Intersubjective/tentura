@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/invite_genealogy_repository.dart';
import 'package:tentura_server/data/repository/invite_seed_prompt_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/mock/trust_evidence_repository_mock.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/env.dart';

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late Connection writer;
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
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);
      env = target.databaseEnv;
      db = TenturaDb(env);
      repo = UserRepository(
        env,
        db,
        const TrustEvidenceRepositoryMock(),
        InviteGenealogyRepository(env, db, UserBlockRepository(env, db)),
        InviteSeedPromptRepository(db),
      );
    });

    tearDownAll(() async {
      await db.close();
      await writer.close();
      await target.drop();
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

Future<bool> _canConnect(Env env) async {
  try {
    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    );
    await connection.close();
    return true;
  } on Object {
    return false;
  }
}

class _DisposablePgTarget {
  const _DisposablePgTarget({
    required this.adminEnv,
    required this.databaseEnv,
    required this.databaseName,
  });

  factory _DisposablePgTarget.fromEnvironment() {
    final host = Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1';
    final port =
        int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432;
    final username = Platform.environment['POSTGRES_USERNAME'] ?? 'postgres';
    final password = Platform.environment['POSTGRES_PASSWORD'] ?? 'password';
    final adminDatabase =
        Platform.environment['POSTGRES_ADMIN_DBNAME'] ?? 'postgres';
    final databaseName =
        Platform.environment['TENTURA_INVITE_GENEALOGY_TEST_DB'] ??
        'tentura_test_invite_genealogy_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_INVITE_GENEALOGY_TEST_DB',
        'must match tentura_test_[a-z0-9_]+ and be at most 63 characters',
      );
    }

    Env envFor(String database) => Env(
      environment: Environment.test,
      pgHost: host,
      pgPort: port,
      pgDatabase: database,
      pgUsername: username,
      pgPassword: password,
      printEnv: false,
      isDebugModeOn: false,
      genealogyNodeKeySecret: 'test-genealogy-secret',
    );

    return _DisposablePgTarget(
      adminEnv: envFor(adminDatabase),
      databaseEnv: envFor(databaseName),
      databaseName: databaseName,
    );
  }

  final Env adminEnv;
  final Env databaseEnv;
  final String databaseName;

  Future<void> recreate() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
      await connection.execute('CREATE DATABASE "$databaseName"');
    } finally {
      await connection.close();
    }
  }

  Future<void> drop() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
    } finally {
      await connection.close();
    }
  }
}
