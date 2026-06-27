@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/person_capability_event_repository.dart';
import 'package:tentura_server/env.dart';

/// Postgres integration — fetchFriendContextsBatch gates viewer involvement by
/// beacon_can_read_content (sender-only forward edges must not count).
Future<void> main() async {
  final postgresReachable = await _canConnectPostgres();
  var skipReason = postgresReachable ? false : 'local Postgres not reachable';

  if (postgresReachable) {
    final env = _testEnv();
    final probe = TenturaDb(env);
    try {
      if (!await _hasVisibilityFunctions(probe)) {
        skipReason = 'm0098 schema (beacon_can_read_content) missing';
      }
    } finally {
      await probe.close();
    }
  }

  late TenturaDb db;
  late PersonCapabilityEventRepository repo;

  const viewerId = 'Ufcbatchview1';
  const friendId = 'Ufcbatchfrnd1';
  const authorId = 'Ufcbatchauth1';
  const beaconId = 'Bfcbatchtest1';
  const edgeId = 'Ffcbatchtest1';

  if (skipReason == false) {
    setUpAll(() async {
      db = TenturaDb(_testEnv());
      repo = PersonCapabilityEventRepository(db);
    });

    tearDownAll(() async {
      await db.close();
    });

    tearDown(() async {
      await db.customStatement(
        "DELETE FROM public.beacon_forward_edge WHERE beacon_id = '$beaconId'",
      );
      await db.customStatement(
        "DELETE FROM public.beacon WHERE id = '$beaconId'",
      );
      await db.customStatement(
        '''DELETE FROM public."user" WHERE id IN ('$viewerId', '$friendId', '$authorId')''',
      );
    });
  }

  Future<void> seedFixture() async {
    final viewerKey = '${'h' * 43}1';
    final friendKey = '${'i' * 43}2';
    final authorKey = '${'j' * 43}3';
    await db.customStatement(
      '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES
  ('$viewerId', 'Viewer', \$1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('$friendId', 'Friend', \$2, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('$authorId', 'Author', \$3, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  public_key = EXCLUDED.public_key
''',
      [viewerKey, friendKey, authorKey],
    );

    await db.customStatement(
      '''
INSERT INTO public.beacon (id, user_id, title, description, status, created_at, updated_at)
VALUES (
  '$beaconId', '$authorId', 'Shared beacon', '', ${BeaconStatus.open.smallintValue},
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
ON CONFLICT (id) DO UPDATE SET status = EXCLUDED.status
''',
    );

    // Viewer forwarded to friend but is sender-only (no read access).
    await db.customStatement(
      '''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at
) VALUES (
  '$edgeId', '$beaconId', '$viewerId', '$friendId', now()
)
ON CONFLICT (id) DO NOTHING
''',
    );
  }

  test(
    'sender-only forward edge does not count in coInvolvedBeaconsCount',
    () async {
      await seedFixture();

      final rows = await repo.fetchFriendContextsBatch(
        viewerId: viewerId,
        friendIds: [friendId],
      );

      expect(rows, hasLength(1));
      expect(rows.single.friendId, friendId);
      expect(rows.single.coInvolvedBeaconsCount, 0);
      expect(rows.single.activeForwardsToCount, 0);
    },
    skip: skipReason,
  );
}

Env _testEnv() => Env(
      environment: Environment.test,
      pgHost: Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1',
      pgPort: int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432,
      pgPassword: Platform.environment['POSTGRES_PASSWORD'] ?? 'password',
      printEnv: false,
      isDebugModeOn: false,
    );

Future<bool> _hasVisibilityFunctions(TenturaDb db) async {
  final rows = await db.customSelect(
    '''
SELECT 1 FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'beacon_can_read_content'
LIMIT 1
''',
  ).get();
  return rows.isNotEmpty;
}

Future<bool> _canConnectPostgres() async {
  try {
    final db = TenturaDb(_testEnv());
    await db.customSelect('SELECT 1').getSingle();
    await db.close();
    return true;
  } on Object {
    return false;
  }
}
