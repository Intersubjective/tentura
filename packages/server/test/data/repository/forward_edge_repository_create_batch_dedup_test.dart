@Tags(['pg'])
library;

import 'dart:async';
import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/domain/entity/forward_batch_create_result.dart';
import 'package:tentura_server/domain/entity/forward_edge_created.dart';
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
      } else if (!await _hasUserAvailabilityTable(probe)) {
        skipReason = 'm0148 schema (user_availability) missing';
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
      expect(firstInserted.createdEdges.length, 1);
      expect(firstInserted.createdEdges.single.recipientId, recipient);

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
      expect(
        secondInserted,
        const ForwardBatchCreateResult(
          createdEdges: [],
          availabilitySkippedRecipientIds: [],
        ),
      );
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
      expect(thirdPartyInserted.createdEdges.length, 1);
      expect(thirdPartyInserted.createdEdges.single.recipientId, recipient);
      expect(await countActiveEdges(senderId: sender2, recipientId: recipient), 1);
    },
    skip: skipReason,
  );

  group('createBatch — disposable Postgres', () {
    final target = _DisposablePgTarget.fromEnvironment();
    final disposableSkip = postgresReachable
        ? false
        : 'Postgres admin database not reachable for disposable test target';

    late Connection writer;
    late TenturaDb db;
    late ForwardEdgeRepository repo;

    setUpAll(() async {
      if (disposableSkip != false) {
        return;
      }
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);

      db = TenturaDb(target.databaseEnv);
      repo = ForwardEdgeRepository(db);
    });

    tearDown(() async {
      if (disposableSkip != false) {
        return;
      }
      await writer.execute(
        "DELETE FROM public.beacon_forward_edge WHERE beacon_id = 'Bfwdedup02'",
      );
      await writer.execute(
        "DELETE FROM public.user_availability WHERE user_id LIKE 'Ufwdedup%'",
      );
      await writer.execute(
        "DELETE FROM public.beacon WHERE id = 'Bfwdedup02'",
      );
      await writer.execute(
        '''DELETE FROM public."user" WHERE id LIKE 'Ufwdedup%' ''',
      );
    });

    tearDownAll(() async {
      if (disposableSkip != false) {
        return;
      }
      await db.close();
      await writer.close();
      await target.drop();
    });

    Future<void> seedDisposableFixture() async {
      final keyA = pgTestPublicKey('fwdedup', 1);
      final keyB = pgTestPublicKey('fwdedup', 2);
      final keyC = pgTestPublicKey('fwdedup', 3);
      await writer.execute(
        Sql.named(r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES
  ('Ufwdedupauth', 'Author', @keyA, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Ufwdedupsend1', 'Sender One', @keyB, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Ufwdeduprecip', 'Recipient', @keyC, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  public_key = EXCLUDED.public_key
'''),
        parameters: {
          'keyA': keyA,
          'keyB': keyB,
          'keyC': keyC,
        },
      );
      await writer.execute(r'''
INSERT INTO public.beacon (id, user_id, title, description, created_at, updated_at)
VALUES ('Bfwdedup02', 'Ufwdedupauth', 'Forward dedup disposable', '', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''');
    }

    test(
      'concurrent createBatch for same active edge completes without unique violation',
      () async {
        await seedDisposableFixture();
        const beaconId = 'Bfwdedup02';
        const sender = 'Ufwdedupsend1';
        const recipient = 'Ufwdeduprecip';

        final db1 = TenturaDb(target.databaseEnv);
        final db2 = TenturaDb(target.databaseEnv);
        final repo1 = ForwardEdgeRepository(db1);
        final repo2 = ForwardEdgeRepository(db2);

        try {
          final results = await Future.wait([
            repo1.createBatch(
              beaconId: beaconId,
              senderId: sender,
              recipientIds: [recipient],
              batchId: 'batch-fwdedup-conc-1',
              noteForRecipient: (_) => 'concurrent one',
            ),
            repo2.createBatch(
              beaconId: beaconId,
              senderId: sender,
              recipientIds: [recipient],
              batchId: 'batch-fwdedup-conc-2',
              noteForRecipient: (_) => 'concurrent two',
            ),
          ]);

          final createdCount = results
              .map((result) => result.createdEdges.length)
              .fold<int>(0, (sum, count) => sum + count);
          expect(createdCount, 1);
          for (final result in results) {
            expect(result.availabilitySkippedRecipientIds, isEmpty);
          }

          final countRows = await writer.execute(r'''
SELECT COUNT(*)::int
FROM public.beacon_forward_edge
WHERE beacon_id = 'Bfwdedup02'
  AND sender_id = 'Ufwdedupsend1'
  AND recipient_id = 'Ufwdeduprecip'
  AND cancelled_at IS NULL
''');
          expect(countRows.single.single, 1);
        } finally {
          await db1.close();
          await db2.close();
        }
      },
      skip: disposableSkip,
    );

    test(
      'paused recipient is availability skipped and leaves no active edge',
      () async {
        await seedDisposableFixture();
        await writer.execute(r'''
INSERT INTO public.user_availability (user_id, is_limited, resume_on, updated_at)
VALUES (
  'Ufwdeduprecip',
  false,
  ((CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::date + 7),
  CURRENT_TIMESTAMP
)
ON CONFLICT (user_id) DO UPDATE SET
  is_limited = EXCLUDED.is_limited,
  resume_on = EXCLUDED.resume_on,
  updated_at = EXCLUDED.updated_at
''');

        const beaconId = 'Bfwdedup02';
        const sender = 'Ufwdedupsend1';
        const recipient = 'Ufwdeduprecip';

        final result = await repo.createBatch(
          beaconId: beaconId,
          senderId: sender,
          recipientIds: [recipient],
          batchId: 'batch-fwdedup-paused',
          noteForRecipient: (_) => 'should not insert',
        );

        expect(
          result,
          const ForwardBatchCreateResult(
            createdEdges: [],
            availabilitySkippedRecipientIds: ['Ufwdeduprecip'],
          ),
        );

        final countRows = await writer.execute(r'''
SELECT COUNT(*)::int
FROM public.beacon_forward_edge
WHERE beacon_id = 'Bfwdedup02'
  AND sender_id = 'Ufwdedupsend1'
  AND recipient_id = 'Ufwdeduprecip'
  AND cancelled_at IS NULL
''');
        expect(countRows.single.single, 0);
      },
      skip: disposableSkip,
    );
  });
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

Future<bool> _hasUserAvailabilityTable(TenturaDb db) async {
  final rows = await db.customSelect(
    '''
SELECT 1
FROM information_schema.tables
WHERE table_schema = 'public' AND table_name = 'user_availability'
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
        Platform.environment['TENTURA_FORWARD_EDGE_DEDUP_TEST_DB'] ??
        'tentura_test_fwdedup_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_FORWARD_EDGE_DEDUP_TEST_DB',
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
