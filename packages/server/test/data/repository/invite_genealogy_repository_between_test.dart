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

/// Forest fixture (descendant created_at must exceed ancestor's — CHECK):
///
///            R (root, 2026-01-01)
///            |
///            A (2026-02-01)              R is also viewer in the seed case
///           / \
///   (V) view   mid B (2026-02-15)
///  2026-03-01      |
///              target T (2026-03-15)
///
///   Separate tree:  R2 (2026-01-01) -> T2 (2026-02-01)
///   Lone user X with no genealogy edges at all.
Future<void> main() async {
  final postgresReachable = await _canConnectPostgres();
  var skipReason = postgresReachable ? false : 'local Postgres not reachable';

  if (postgresReachable) {
    final probe = TenturaDb(_testEnv());
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

  const rootId = 'Ugenbtwroot01';
  const ancId = 'Ugenbtwanc001';
  const viewId = 'Ugenbtwview01';
  const midId = 'Ugenbtwmid001';
  const targetId = 'Ugenbtwtgt001';
  const root2Id = 'Ugenbtwroot02';
  const target2Id = 'Ugenbtwtgt002';
  const loneId = 'Ugenbtwlone01';
  const allIds = [
    rootId,
    ancId,
    viewId,
    midId,
    targetId,
    root2Id,
    target2Id,
    loneId,
  ];

  String keyOf(String id) =>
      InviteGenealogyNodeKey.derive(userId: id, env: env);

  if (skipReason == false) {
    setUpAll(() async {
      env = _testEnv();
      db = TenturaDb(env);
      repo = InviteGenealogyRepository(env, db);

      Future<void> user(String id, DateTime createdAt) async {
        final ts = createdAt.toUtc().toIso8601String();
        await db.customStatement(
          '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', \$1, '$ts', '$ts')
ON CONFLICT (id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  public_key = EXCLUDED.public_key,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at
''',
          ['pk_$id'],
        );
      }

      // Insert edges directly (invitation_id NULL) to avoid the invitation FK.
      Future<void> edge(
        String ancestor,
        DateTime ancestorAt,
        String descendant,
        DateTime descendantAt,
      ) async {
        await db.customStatement(
          '''
INSERT INTO public.invite_genealogy (
  descendant_node_key,
  ancestor_node_key,
  descendant_user_id,
  ancestor_user_id,
  ancestor_user_created_at,
  descendant_user_created_at
) VALUES ('${keyOf(descendant)}', '${keyOf(ancestor)}', '$descendant', '$ancestor', '${ancestorAt.toUtc().toIso8601String()}', '${descendantAt.toUtc().toIso8601String()}')
ON CONFLICT (descendant_node_key) DO NOTHING
''',
        );
      }

      final tRoot = DateTime.utc(2026);
      final tAnc = DateTime.utc(2026, 2);
      final tView = DateTime.utc(2026, 3);
      final tMid = DateTime.utc(2026, 2, 15);
      final tTarget = DateTime.utc(2026, 3, 15);
      final tRoot2 = DateTime.utc(2026);
      final tTarget2 = DateTime.utc(2026, 2);

      await user(rootId, tRoot);
      await user(ancId, tAnc);
      await user(viewId, tView);
      await user(midId, tMid);
      await user(targetId, tTarget);
      await user(root2Id, tRoot2);
      await user(target2Id, tTarget2);
      await user(loneId, DateTime.utc(2026, 4));

      await edge(rootId, tRoot, ancId, tAnc);
      await edge(ancId, tAnc, viewId, tView);
      await edge(ancId, tAnc, midId, tMid);
      await edge(midId, tMid, targetId, tTarget);
      await edge(root2Id, tRoot2, target2Id, tTarget2);
    });

    tearDownAll(() async {
      final idList = allIds.map((e) => "'$e'").join(',');
      await db.customStatement(
        'DELETE FROM public.invite_genealogy '
        'WHERE descendant_user_id IN ($idList) OR ancestor_user_id IN ($idList)',
      );
      await db.customStatement(
        'DELETE FROM public."user" WHERE id IN ($idList)',
      );
      await db.close();
    });
  }

  test('two users meet at the closest common ancestor', () async {
    if (skipReason != false) return;
    final graph = await repo.fetchLineageBetween(
      viewerId: viewId,
      targetId: targetId,
    );
    expect(graph.viewerNodeKey, keyOf(viewId));
    expect(graph.targetNodeKey, keyOf(targetId));
    expect(graph.commonAncestorNodeKey, keyOf(ancId));
    expect(
      graph.nodes.map((n) => n.nodeKey).toSet(),
      {keyOf(viewId), keyOf(ancId), keyOf(rootId), keyOf(midId), keyOf(targetId)},
    );
    // Full Y to the root: V<-A, B<-A, T<-B, A<-R.
    expect(graph.edges, hasLength(4));
  }, skip: skipReason);

  test('viewer is an ancestor of target (LCA == viewer)', () async {
    if (skipReason != false) return;
    final graph = await repo.fetchLineageBetween(
      viewerId: ancId,
      targetId: targetId,
    );
    expect(graph.commonAncestorNodeKey, keyOf(ancId));
    expect(graph.commonAncestorNodeKey, graph.viewerNodeKey);
    expect(
      graph.nodes.map((n) => n.nodeKey).toSet(),
      {keyOf(ancId), keyOf(rootId), keyOf(midId), keyOf(targetId)},
    );
  }, skip: skipReason);

  test('disconnected users return both chains with no common ancestor',
      () async {
    if (skipReason != false) return;
    final graph = await repo.fetchLineageBetween(
      viewerId: viewId,
      targetId: target2Id,
    );
    expect(graph.commonAncestorNodeKey, isNull);
    expect(
      graph.nodes.map((n) => n.nodeKey).toSet(),
      {keyOf(viewId), keyOf(ancId), keyOf(rootId), keyOf(target2Id), keyOf(root2Id)},
    );
  }, skip: skipReason);

  test('seed user with no edges still appears as its own node', () async {
    if (skipReason != false) return;
    final graph = await repo.fetchLineageBetween(
      viewerId: loneId,
      targetId: targetId,
    );
    expect(graph.commonAncestorNodeKey, isNull);
    final lone = graph.nodes.singleWhere((n) => n.nodeKey == keyOf(loneId));
    expect(lone.user, isNotNull);
    expect(lone.user!.id, loneId);
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
