@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/invite_genealogy_repository.dart';
import 'package:tentura_server/domain/invite_genealogy/invite_genealogy_node_key.dart';
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
  late InviteGenealogyRepository repo;
  late Env env;

  const ancestorId = 'Ugenanc000001';
  const descendantId = 'Ugendesc00001';
  const invitationId = 'Igen000000001';

  if (skipReason == false) {
    setUpAll(() async {
      env = _testEnv();
      db = TenturaDb(env);
      repo = InviteGenealogyRepository(env, db);
    });

    tearDownAll(() async {
      await db.close();
    });

    tearDown(() async {
      await db.customStatement(
        "DELETE FROM public.invite_genealogy WHERE invitation_id = '$invitationId'",
      );
      await db.customStatement(
        '''DELETE FROM public."user" WHERE id IN ('$ancestorId', '$descendantId')''',
      );
    });
  }

  test('recordSignupEdge persists chronology and survives descendant delete',
      () async {
    if (skipReason != false) {
      return;
    }
    final ancestorKey = '${'a' * 43}1';
    final descendantKey = '${'b' * 43}2';
    await db.customStatement(
      '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES
  ('$ancestorId', 'Ancestor', \$1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('$descendantId', 'Descendant', \$2, '2026-02-01T00:00:00Z', '2026-02-01T00:00:00Z')
ON CONFLICT (id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  public_key = EXCLUDED.public_key,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at
''',
      [ancestorKey, descendantKey],
    );

    await repo.recordSignupEdge(
      ancestorUserId: ancestorId,
      ancestorUserCreatedAt: DateTime.utc(2026, 1, 1),
      descendantUserId: descendantId,
      descendantUserCreatedAt: DateTime.utc(2026, 2, 1),
      invitationId: invitationId,
    );

    await db.customStatement(
      '''DELETE FROM public."user" WHERE id = '$descendantId' ''',
    );

    final graph = await repo.fetchLineage(userId: ancestorId);
    expect(graph.edges, hasLength(1));
    final node = graph.nodes.singleWhere(
      (n) => n.nodeKey == graph.edges.single.descendantNodeKey,
    );
    expect(node.user, isNull);
    expect(node.deletedAt, isNotNull);
    expect(node.userCreatedAt, DateTime.utc(2026, 2, 1));
  }, skip: skipReason);

  test('reverse chronology insert violates CHECK', () async {
    if (skipReason != false) {
      return;
    }
    final ancestorNodeKey = InviteGenealogyNodeKey.derive(
      userId: ancestorId,
      env: env,
    );
    final descendantNodeKey = InviteGenealogyNodeKey.derive(
      userId: descendantId,
      env: env,
    );
    expect(
      () => db.customStatement(
        '''
INSERT INTO public.invite_genealogy (
  descendant_node_key,
  ancestor_node_key,
  ancestor_user_created_at,
  descendant_user_created_at
) VALUES (
  '$descendantNodeKey',
  '$ancestorNodeKey',
  '2026-02-01T00:00:00Z',
  '2026-01-01T00:00:00Z'
)
''',
      ),
      throwsA(isA<Object>()),
    );
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
