@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/invite_genealogy_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/domain/invite_genealogy/invite_genealogy_node_key.dart';
import 'package:tentura_server/env.dart';

/// Blocked genealogy nodes become deleted-account placeholders (§7.3 E13).
///
/// Forest fixture (descendant created_at must exceed ancestor's — CHECK):
///
///            R (root, 2026-01-01)
///            |
///            A (2026-02-01)  <- middle node anonymized when blocked
///           / \
///   (V) view   mid B (2026-02-15)
///  2026-03-01      |
///              child C (2026-03-15)
///
/// Lone user X with no genealogy edges (target-fallback path).
Future<void> main() async {
  final postgresReachable = await _canConnectPostgres();
  var skipReason = postgresReachable ? false : 'local Postgres not reachable';

  if (postgresReachable) {
    final probe = TenturaDb(_testEnv());
    try {
      if (!await _hasInviteGenealogyTable(probe)) {
        skipReason = 'invite_genealogy table missing';
      } else if (!await _hasUserBlockSchema(probe)) {
        skipReason = 'm0135 schema (user_block / block_hides) missing';
      }
    } finally {
      await probe.close();
    }
  }

  late TenturaDb db;
  late InviteGenealogyRepository repo;
  late UserBlockRepository blockRepo;
  late Env env;

  const rootId = 'Ugenblkroot01';
  const ancId = 'Ugenblkanc001';
  const viewId = 'Ugenblkview01';
  const midId = 'Ugenblkmid001';
  const childId = 'Ugenblkchild01';
  const loneId = 'Ugenblkalone01';
  const allIds = [rootId, ancId, viewId, midId, childId, loneId];

  String keyOf(String id) =>
      InviteGenealogyNodeKey.derive(userId: id, env: env);

  Future<void> blockPair({
    required String blockerId,
    required String blockedId,
  }) async {
    await blockRepo.block(
      blockerId: blockerId,
      blockedId: blockedId,
      cascadeMode: 0,
    );
  }

  Future<void> cleanupBlocks() async {
    final idList = allIds.map((e) => "'$e'").join(',');
    await db.customStatement(
      'DELETE FROM public.user_block WHERE blocker_id IN ($idList) '
      'OR blocked_id IN ($idList)',
    );
    await db.customStatement(
      'DELETE FROM public.user_block_intent WHERE blocker_id IN ($idList) '
      'OR blocked_id IN ($idList)',
    );
  }

  if (skipReason == false) {
    setUpAll(() async {
      env = _testEnv();
      db = TenturaDb(env);
      blockRepo = UserBlockRepository(env, db);
      repo = InviteGenealogyRepository(env, db, blockRepo);

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
      final tChild = DateTime.utc(2026, 3, 15);

      await user(rootId, tRoot);
      await user(ancId, tAnc);
      await user(viewId, tView);
      await user(midId, tMid);
      await user(childId, tChild);
      await user(loneId, DateTime.utc(2026, 4));

      await edge(rootId, tRoot, ancId, tAnc);
      await edge(ancId, tAnc, viewId, tView);
      await edge(ancId, tAnc, midId, tMid);
      await edge(midId, tMid, childId, tChild);
    });

    tearDown(() => cleanupBlocks());

    tearDownAll(() async {
      await cleanupBlocks();
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

  test(
    'fetchLineage anonymizes a blocked middle ancestor without disconnecting edges',
    () async {
      if (skipReason != false) return;

      await blockPair(blockerId: viewId, blockedId: ancId);

      final lineage = await repo.fetchLineage(userId: viewId);
      final ancNode = lineage.nodes.singleWhere((n) => n.nodeKey == keyOf(ancId));

      expect(ancNode.user, isNull);
      expect(ancNode.deletedAt, isNull);
      expect(ancNode.userCreatedAt, DateTime.utc(2026, 2));

      expect(
        lineage.edges.map((e) => e.descendantNodeKey),
        containsAll([keyOf(viewId), keyOf(ancId)]),
      );
      expect(
        lineage.edges.map((e) => e.ancestorNodeKey),
        contains(keyOf(rootId)),
      );
    },
    skip: skipReason,
  );

  test(
    'fetchLineage anonymizes when the middle ancestor blocked the viewer',
    () async {
      if (skipReason != false) return;

      await blockPair(blockerId: ancId, blockedId: viewId);

      final lineage = await repo.fetchLineage(userId: viewId);
      final ancNode = lineage.nodes.singleWhere((n) => n.nodeKey == keyOf(ancId));

      expect(ancNode.user, isNull);
      expect(ancNode.deletedAt, isNull);
      expect(
        lineage.edges.map((e) => e.descendantNodeKey),
        contains(keyOf(ancId)),
      );
    },
    skip: skipReason,
  );

  test(
    'fetchChildren keeps descendants connected when the parent is blocked',
    () async {
      if (skipReason != false) return;

      await blockPair(blockerId: viewId, blockedId: ancId);

      final page = await repo.fetchChildren(
        viewerId: viewId,
        nodeKey: keyOf(ancId),
        limit: 10,
      );

      final ancNode = page.nodes.singleWhere((n) => n.nodeKey == keyOf(ancId));
      expect(ancNode.user, isNull);
      expect(ancNode.deletedAt, isNull);

      expect(
        page.edges.map((e) => e.descendantNodeKey),
        containsAll([keyOf(viewId), keyOf(midId)]),
      );

      final below = await repo.fetchChildren(
        viewerId: viewId,
        nodeKey: keyOf(midId),
        limit: 10,
      );
      expect(
        below.edges.map((e) => e.descendantNodeKey),
        contains(keyOf(childId)),
      );
      final childNode = below.nodes.singleWhere(
        (n) => n.nodeKey == keyOf(childId),
      );
      expect(childNode.user?.id, childId);
    },
    skip: skipReason,
  );

  test(
    'fetchLineageBetween anonymizes blocked nodes while preserving subtree edges',
    () async {
      if (skipReason != false) return;

      await blockPair(blockerId: viewId, blockedId: ancId);

      final graph = await repo.fetchLineageBetween(
        viewerId: viewId,
        targetId: childId,
      );

      final ancNode = graph.nodes.singleWhere((n) => n.nodeKey == keyOf(ancId));
      expect(ancNode.user, isNull);
      expect(ancNode.deletedAt, isNull);

      expect(
        graph.edges.map((e) => e.descendantNodeKey),
        containsAll([keyOf(midId), keyOf(childId), keyOf(ancId), keyOf(viewId)]),
      );
      expect(
        graph.nodes.singleWhere((n) => n.nodeKey == keyOf(childId)).user?.id,
        childId,
      );
    },
    skip: skipReason,
  );

  test(
    'fetchLineageBetween target fallback anonymizes a blocked lone user',
    () async {
      if (skipReason != false) return;

      await blockPair(blockerId: viewId, blockedId: loneId);

      final graph = await repo.fetchLineageBetween(
        viewerId: viewId,
        targetId: loneId,
      );

      final loneNode = graph.nodes.singleWhere((n) => n.nodeKey == keyOf(loneId));
      expect(loneNode.user, isNull);
      expect(loneNode.deletedAt, isNull);
    },
    skip: skipReason,
  );

  test(
    'fetchLineageBetween target fallback anonymizes when target blocked viewer',
    () async {
      if (skipReason != false) return;

      await blockPair(blockerId: loneId, blockedId: viewId);

      final graph = await repo.fetchLineageBetween(
        viewerId: viewId,
        targetId: loneId,
      );

      final loneNode = graph.nodes.singleWhere((n) => n.nodeKey == keyOf(loneId));
      expect(loneNode.user, isNull);
      expect(loneNode.deletedAt, isNull);
    },
    skip: skipReason,
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

Future<bool> _hasUserBlockSchema(TenturaDb db) async {
  final rows = await db.customSelect(
    '''
SELECT 1
FROM information_schema.tables
WHERE table_schema = 'public' AND table_name = 'user_block'
LIMIT 1
''',
  ).getSingleOrNull();
  return rows != null;
}
