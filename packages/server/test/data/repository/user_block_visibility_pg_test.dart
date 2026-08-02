@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/env.dart';

/// Hasura visibility enforcement via computed-field SQL — spec §3.4/§3.5 / T-H E11–E12.
///
/// No Hasura HTTP integration harness exists in this repo; pg tests assert the
/// underlying `user_hidden_for_viewer` / `user_presence_hidden_for_viewer`
/// functions that Hasura permission filters delegate to.
Future<void> main() async {
  final postgresReachable = await _canConnectPostgres();
  var skipReason = postgresReachable ? false : 'local Postgres not reachable';

  if (postgresReachable) {
    final probe = TenturaDb(_testEnv());
    try {
      if (!await _hasUserBlockSchema(probe)) {
        skipReason = 'm0135 schema (user_block / block_hides) missing';
      } else if (!await _hasHiddenForViewerFunctions(probe)) {
        skipReason =
            'm0136 schema (user_hidden_for_viewer / user_presence_hidden_for_viewer) missing';
      }
    } finally {
      await probe.close();
    }
  }

  late TenturaDb db;

  const viewerId = 'Ublkvview001';
  const peerId = 'Ublkvpeer001';
  const allUserIds = [viewerId, peerId];

  Future<void> insertUser(String id) => db.customStatement(
    '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
  );

  Future<void> insertPresence(String userId) => db.customStatement(
    '''
INSERT INTO public.user_presence (user_id, status, last_seen_at)
VALUES ('$userId', 0, '2026-01-01T00:00:00Z')
ON CONFLICT (user_id) DO NOTHING
''',
  );

  Future<void> insertDirectBlock(String blockerId, String blockedId) =>
      db.customStatement(
        '''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$blockerId', '$blockedId', '$blockedId')
ON CONFLICT DO NOTHING
''',
      );

  Future<void> cleanup() async {
    final userList = allUserIds.map((id) => "'$id'").join(', ');
    await db.customStatement(
      'DELETE FROM public.user_block WHERE blocker_id IN ($userList) '
      'OR blocked_id IN ($userList)',
    );
    await db.customStatement(
      'DELETE FROM public.user_presence WHERE user_id IN ($userList)',
    );
    await db.customStatement(
      '''DELETE FROM public."user" WHERE id IN ($userList)''',
    );
  }

  if (skipReason == false) {
    setUp(() async {
      db = TenturaDb(_testEnv());
      await cleanup();
      for (final id in allUserIds) {
        await insertUser(id);
        await insertPresence(id);
      }
    });

    tearDown(() async {
      await cleanup();
      await db.close();
    });
  }

  test(
    'E11: user search omits blocked peers (both directions)',
    () async {
      final session = _sessionJson(viewerId);

      final visibleBefore = await _queryVisibleUserIds(db, session);
      expect(visibleBefore, containsAll([viewerId, peerId]));

      await insertDirectBlock(viewerId, peerId);

      final visibleAfterBlock = await _queryVisibleUserIds(db, session);
      expect(visibleAfterBlock, contains(viewerId));
      expect(visibleAfterBlock, isNot(contains(peerId)));

      await db.customStatement(
        'DELETE FROM public.user_block WHERE blocker_id = \'$viewerId\' '
        'AND blocked_id = \'$peerId\'',
      );
      await insertDirectBlock(peerId, viewerId);

      final visibleAfterReverse = await _queryVisibleUserIds(db, session);
      expect(visibleAfterReverse, contains(viewerId));
      expect(visibleAfterReverse, isNot(contains(peerId)));
    },
    skip: skipReason,
  );

  test(
    'E12: presence rows for blocked peers are hidden (both directions)',
    () async {
      final session = _sessionJson(viewerId);

      final visibleBefore = await _queryVisiblePresenceUserIds(db, session);
      expect(visibleBefore, containsAll([viewerId, peerId]));

      await insertDirectBlock(viewerId, peerId);

      final visibleAfterBlock = await _queryVisiblePresenceUserIds(db, session);
      expect(visibleAfterBlock, contains(viewerId));
      expect(visibleAfterBlock, isNot(contains(peerId)));

      await db.customStatement(
        'DELETE FROM public.user_block WHERE blocker_id = \'$viewerId\' '
        'AND blocked_id = \'$peerId\'',
      );
      await insertDirectBlock(peerId, viewerId);

      final visibleAfterReverse =
          await _queryVisiblePresenceUserIds(db, session);
      expect(visibleAfterReverse, contains(viewerId));
      expect(visibleAfterReverse, isNot(contains(peerId)));
    },
    skip: skipReason,
  );
}

String _sessionJson(String viewerId) => '{"x-hasura-user-id": "$viewerId"}';

Future<Set<String>> _queryVisibleUserIds(
  TenturaDb db,
  String sessionJson,
) async {
  final rows = await db.customSelect(
    '''
SELECT u.id
FROM public."user" u
WHERE NOT public.user_hidden_for_viewer(u, '$sessionJson'::json)
ORDER BY u.id
''',
  ).get();

  return rows.map((row) => row.read<String>('id')).toSet();
}

Future<Set<String>> _queryVisiblePresenceUserIds(
  TenturaDb db,
  String sessionJson,
) async {
  final rows = await db.customSelect(
    '''
SELECT p.user_id
FROM public.user_presence p
WHERE NOT public.user_presence_hidden_for_viewer(p, '$sessionJson'::json)
ORDER BY p.user_id
''',
  ).get();

  return rows.map((row) => row.read<String>('user_id')).toSet();
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
SELECT to_regclass('public.user_block') IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'block_hides'
  ) AS ok
''',
  ).getSingle();
  return row.read<bool>('ok');
}

Future<bool> _hasHiddenForViewerFunctions(TenturaDb db) async {
  final row = await db.customSelect(
    '''
SELECT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'user_hidden_for_viewer'
  )
  AND EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'user_presence_hidden_for_viewer'
  ) AS ok
''',
  ).getSingle();
  return row.read<bool>('ok');
}
