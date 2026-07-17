@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/repository/invite_genealogy_repository.dart';
import 'package:tentura_server/domain/invite_genealogy/invite_genealogy_node_key.dart';
import 'package:tentura_server/env.dart';

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

  const parentId = 'Ugenchildp001';
  const loneId = 'Ugenchildlone';
  final childIds = [
    for (var i = 0; i < 55; i++) 'Ugenchild${i.toString().padLeft(3, '0')}',
  ];
  final allIds = [parentId, loneId, ...childIds];

  String keyOf(String id) =>
      InviteGenealogyNodeKey.derive(userId: id, env: env);

  DateTime createdAtForIndex(int index) {
    if (index < 3) {
      return DateTime.utc(2026, 2);
    }
    return DateTime.utc(2026, 2, index + 1);
  }

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

      Future<void> edge(String descendant, DateTime descendantAt) async {
        const ancestorAt = '2026-01-01T00:00:00.000Z';
        await db.customStatement(
          '''
INSERT INTO public.invite_genealogy (
  descendant_node_key,
  ancestor_node_key,
  descendant_user_id,
  ancestor_user_id,
  ancestor_user_created_at,
  descendant_user_created_at
) VALUES ('${keyOf(descendant)}', '${keyOf(parentId)}', '$descendant', '$parentId', '$ancestorAt', '${descendantAt.toUtc().toIso8601String()}')
ON CONFLICT (descendant_node_key) DO UPDATE SET
  ancestor_node_key = EXCLUDED.ancestor_node_key,
  descendant_user_id = EXCLUDED.descendant_user_id,
  ancestor_user_id = EXCLUDED.ancestor_user_id,
  ancestor_user_created_at = EXCLUDED.ancestor_user_created_at,
  descendant_user_created_at = EXCLUDED.descendant_user_created_at
''',
        );
      }

      await user(parentId, DateTime.utc(2026));
      await user(loneId, DateTime.utc(2026, 3));
      for (var i = 0; i < childIds.length; i++) {
        final createdAt = createdAtForIndex(i);
        await user(childIds[i], createdAt);
        await edge(childIds[i], createdAt);
      }
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

  test(
    'fetchChildren pages direct children by stable keyset cursor',
    () async {
      if (skipReason != false) return;
      final expected =
          [
            for (var i = 0; i < childIds.length; i++)
              (
                nodeKey: keyOf(childIds[i]),
                createdAt: createdAtForIndex(i),
              ),
          ]..sort((a, b) {
            final created = a.createdAt.compareTo(b.createdAt);
            return created != 0 ? created : a.nodeKey.compareTo(b.nodeKey);
          });

      final first = await repo.fetchChildren(
        nodeKey: keyOf(parentId),
        limit: 2,
      );
      expect(
        first.edges.map((e) => e.descendantNodeKey).toList(),
        expected.take(2).map((e) => e.nodeKey).toList(),
      );

      final lastFirst = first.edges.last;
      final second = await repo.fetchChildren(
        nodeKey: keyOf(parentId),
        afterCreatedAt: lastFirst.descendantUserCreatedAt,
        afterNodeKey: lastFirst.descendantNodeKey,
        limit: 2,
      );
      expect(
        second.edges.map((e) => e.descendantNodeKey).toList(),
        expected.skip(2).take(2).map((e) => e.nodeKey).toList(),
      );
      expect(
        first.edges
            .map((e) => e.descendantNodeKey)
            .toSet()
            .intersection(
              second.edges.map((e) => e.descendantNodeKey).toSet(),
            ),
        isEmpty,
      );
      expect(
        second.nodes.map((n) => n.nodeKey).toSet(),
        containsAll([
          keyOf(parentId),
          ...second.edges.map((e) => e.descendantNodeKey),
        ]),
      );
    },
    skip: skipReason,
  );

  test('fetchChildren clamps oversized limits', () async {
    if (skipReason != false) return;
    final page = await repo.fetchChildren(
      nodeKey: keyOf(parentId),
      limit: 1000,
    );
    expect(page.edges, hasLength(50));
  }, skip: skipReason);

  test(
    'fetchChildren returns an empty page for a node with no children',
    () async {
      if (skipReason != false) return;
      final page = await repo.fetchChildren(
        nodeKey: keyOf(loneId),
        limit: 10,
      );
      expect(page.edges, isEmpty);
      expect(page.nodes, isEmpty);
    },
    skip: skipReason,
  );

  test(
    'fetchChildCounts returns total children for mixed node keys',
    () async {
      if (skipReason != false) return;

      final first = await repo.fetchChildren(
        nodeKey: keyOf(parentId),
        limit: 2,
      );
      final second = await repo.fetchChildren(
        nodeKey: keyOf(parentId),
        afterCreatedAt: first.edges.last.descendantUserCreatedAt,
        afterNodeKey: first.edges.last.descendantNodeKey,
        limit: 2,
      );

      expect(first.edges, hasLength(2));
      expect(second.edges, hasLength(2));

      final missingNodeKey = keyOf('Ugenchildmissing');
      final counts = await repo.fetchChildCounts(
        nodeKeys: [keyOf(parentId), keyOf(loneId), missingNodeKey],
      );

      expect(counts, {
        keyOf(parentId): childIds.length,
        keyOf(loneId): 0,
        missingNodeKey: 0,
      });
    },
    skip: skipReason,
  );

  test(
    'fetchChildCounts for a parent is stable across children pages',
    () async {
      if (skipReason != false) return;

      final parentKey = keyOf(parentId);
      final before = await repo.fetchChildCounts(nodeKeys: [parentKey]);

      final first = await repo.fetchChildren(nodeKey: parentKey, limit: 2);
      final afterPage1 = await repo.fetchChildCounts(nodeKeys: [parentKey]);

      await repo.fetchChildren(
        nodeKey: parentKey,
        afterCreatedAt: first.edges.last.descendantUserCreatedAt,
        afterNodeKey: first.edges.last.descendantNodeKey,
        limit: 2,
      );
      final afterPage2 = await repo.fetchChildCounts(nodeKeys: [parentKey]);

      expect(before[parentKey], childIds.length);
      expect(afterPage1, before);
      expect(afterPage2, before);
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
