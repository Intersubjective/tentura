@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/env.dart';

import '../../support/pg_test_public_keys.dart';

/// Postgres integration — skipped when DB or m0100 dedup index is unavailable.
Future<void> main() async {
  final postgresReachable = await _canConnectPostgres();
  var skipReason = postgresReachable ? false : 'local Postgres not reachable';

  if (postgresReachable) {
    final env = _testEnv();
    final probe = TenturaDb(env);
    try {
      if (!await _hasActiveEdgeDedupIndex(probe)) {
        skipReason = 'm0100 schema (bfe_active_unique) missing';
      }
    } finally {
      await probe.close();
    }
  }

  late TenturaDb db;
  late ForwardEdgeRepository repo;

  if (skipReason == false) {
    setUpAll(() async {
      db = TenturaDb(_testEnv());
      repo = ForwardEdgeRepository(db);
    });

    tearDownAll(() async {
      await db.close();
    });

    tearDown(() async {
      await db.customStatement(
        "DELETE FROM public.beacon_forward_edge WHERE beacon_id = 'Bfwdedup01'",
      );
      await db.customStatement(
        "DELETE FROM public.beacon WHERE id = 'Bfwdedup01'",
      );
      await db.customStatement(
        '''DELETE FROM public."user" WHERE id LIKE 'Ufwdedup%' ''',
      );
    });
  }

  Future<void> seedFixture() async {
    final keyA = pgTestPublicKey('fwdedup', 1);
    final keyB = pgTestPublicKey('fwdedup', 2);
    final keyC = pgTestPublicKey('fwdedup', 3);
    final keyD = pgTestPublicKey('fwdedup', 4);
    await db.customStatement(
      r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES
  ('Ufwdedupauth', 'Author', $1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Ufwdedupsend1', 'Sender One', $2, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Ufwdedupsend2', 'Sender Two', $3, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Ufwdeduprecip', 'Recipient', $4, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  public_key = EXCLUDED.public_key
''',
      [keyA, keyB, keyC, keyD],
    );
    await db.customStatement(
      '''
INSERT INTO public.beacon (id, user_id, title, description, created_at, updated_at)
VALUES ('Bfwdedup01', 'Ufwdedupauth', 'Forward dedup test', '', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
    );
  }

  Future<int> countActiveEdges({
    required String senderId,
    required String recipientId,
  }) async {
    final row = await db.customSelect(
      '''
SELECT COUNT(*)::int AS c
FROM public.beacon_forward_edge
WHERE beacon_id = 'Bfwdedup01'
  AND sender_id = '$senderId'
  AND recipient_id = '$recipientId'
  AND cancelled_at IS NULL
''',
    ).getSingle();
    return row.read<int>('c');
  }

  test(
    'createBatch skips duplicate sender/recipient and allows another sender',
    () async {
      await seedFixture();
      const beaconId = 'Bfwdedup01';
      const sender1 = 'Ufwdedupsend1';
      const sender2 = 'Ufwdedupsend2';
      const recipient = 'Ufwdeduprecip';

      final firstInserted = await repo.createBatch(
        beaconId: beaconId,
        senderId: sender1,
        recipientIds: [recipient],
        batchId: 'batch-fwdedup-1',
        noteForRecipient: (_) => 'first note',
      );
      expect(firstInserted, [recipient]);

      final firstEdge = await repo.findActiveEdge(
        beaconId: beaconId,
        senderId: sender1,
        recipientId: recipient,
      );
      expect(firstEdge, isNotNull);
      expect(firstEdge!.note, 'first note');
      expect(firstEdge.batchId, 'batch-fwdedup-1');
      final firstEdgeId = firstEdge.id;

      final secondInserted = await repo.createBatch(
        beaconId: beaconId,
        senderId: sender1,
        recipientIds: [recipient],
        batchId: 'batch-fwdedup-2',
        noteForRecipient: (_) => 'would-be duplicate',
      );
      expect(secondInserted, isEmpty);
      expect(await countActiveEdges(senderId: sender1, recipientId: recipient), 1);

      final unchangedEdge = await repo.findActiveEdge(
        beaconId: beaconId,
        senderId: sender1,
        recipientId: recipient,
      );
      expect(unchangedEdge?.id, firstEdgeId);
      expect(unchangedEdge?.note, 'first note');
      expect(unchangedEdge?.batchId, 'batch-fwdedup-1');

      final thirdPartyInserted = await repo.createBatch(
        beaconId: beaconId,
        senderId: sender2,
        recipientIds: [recipient],
        batchId: 'batch-fwdedup-3',
        noteForRecipient: (_) => 'from sender two',
      );
      expect(thirdPartyInserted, [recipient]);
      expect(await countActiveEdges(senderId: sender2, recipientId: recipient), 1);
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

Future<bool> _hasActiveEdgeDedupIndex(TenturaDb db) async {
  final rows = await db.customSelect(
    '''
SELECT 1 FROM pg_indexes
WHERE schemaname = 'public' AND indexname = 'bfe_active_unique'
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
