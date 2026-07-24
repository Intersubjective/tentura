@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/notification_outbox_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/env.dart';

/// Retention FK-safety (Step 4 / m0125): `deleteSettledOlderThan` must remove
/// both a legacy receipt and a delivery-backed canonical receipt in the same
/// sweep without aborting. Before m0125,
/// `attention_channel_delivery.receipt_id` was `ON DELETE RESTRICT`, so a
/// settled canonical receipt still referenced by its delivery job aborted the
/// whole bulk DELETE.
Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('AttentionRetentionRepository deleteSettledOlderThan', () {
    late Connection writer;
    late TenturaDb database;
    late NotificationOutboxRepository outbox;
    late AttentionDispatchRepository dispatch;
    late MutatingUnitOfWork unitOfWork;

    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);

      database = TenturaDb(target.databaseEnv);
      outbox = NotificationOutboxRepository(database);
      dispatch = AttentionDispatchRepository(database);
      unitOfWork = MutatingUnitOfWork(database);

      await writer.execute(r'''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('Uattretactor', 'Retention actor', 'attention-retention-actor-key')
''');
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });

    test(
      'removes both a legacy receipt and a delivery-backed receipt without aborting',
      () async {
        final oldAt = DateTime.parse('2020-01-01T00:00:00Z');

        // Legacy-shape receipt: settled and old, no delivery job attached.
        await writer.execute(
          Sql.named(r'''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at, seen_at
) VALUES (
  'Nattretlegacy', 'Uattretactor', 'asksOfMe', 'needsMe', 'normal',
  'Legacy', 'Legacy body', '/legacy', 'attention-retention-legacy',
  @oldAt, @oldAt
)
'''),
          parameters: {'oldAt': oldAt},
        );

        // Canonical, delivery-backed receipt via the sole creation path.
        await unitOfWork.run(
          actorUserId: 'Uattretactor',
          action: () => dispatch.record(
            const AttentionDispatchIntent(
              eventType: AttentionEventType.relayReceived,
              sourceEventKey: 'attention-retention-relay-1',
              actorUserId: 'Uattretactor',
              priority: NotificationPriority.normal,
              kind: NotificationKind.newRelay,
              title: 'Forwarded Request',
              body: 'A Request was forwarded to you',
              actionUrl: '/#/view?id=Battret',
              collapseKey: 'attention-retention-relay',
              recipients: [
                AttentionRecipientSnapshot(
                  recipientId: 'Uattretactor',
                  reasons: {AttentionRecipientReason.forwardRecipient},
                  role: AttentionRecipientRoleFacts(
                    canReadBeaconContent: true,
                    beaconId: 'Battret',
                    actorUserId: 'Uattretactor',
                  ),
                ),
              ],
              beaconId: 'Battret',
            ),
          ),
        );
        final canonical = await writer.execute(r'''
SELECT id FROM public.notification_outbox
WHERE dedup_key = 'Uattretactor|attention-v1|attention-retention-relay'
''');
        final canonicalId = canonical.single.single! as String;
        await writer.execute(
          Sql.named('''
UPDATE public.notification_outbox
SET seen_at = @oldAt, created_at = @oldAt
WHERE id = @id
'''),
          parameters: {'oldAt': oldAt, 'id': canonicalId},
        );

        Future<int> deliveryCountFor(String receiptId) async {
          final rows = await writer.execute(
            Sql.named('''
SELECT count(*)::int FROM public.attention_channel_delivery
WHERE receipt_id = @receiptId
'''),
            parameters: {'receiptId': receiptId},
          );
          return rows.single.single! as int;
        }

        expect(await deliveryCountFor(canonicalId), 1);

        final deleted = await outbox.deleteSettledOlderThan(
          const Duration(days: 30),
        );
        expect(deleted, 2);

        final remaining = await writer.execute(r'''
SELECT count(*)::int FROM public.notification_outbox
WHERE id IN ('Nattretlegacy', $1)
''', parameters: [canonicalId]);
        expect(remaining.single.single, 0);

        // The delivery job cascades away with its receipt (m0125); the
        // occurrence itself is shared history and stays untouched.
        expect(await deliveryCountFor(canonicalId), 0);
        final occurrence = await writer.execute(r'''
SELECT count(*)::int FROM public.attention_occurrence
WHERE source_event_key = 'attention-retention-relay-1'
''');
        expect(occurrence.single.single, 1);
      },
    );
  }, skip: skipReason);
}

Future<bool> _canConnect(Env env) async {
  try {
    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    ).timeout(const Duration(seconds: 2));
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
        Platform.environment['TENTURA_ATTENTION_RETENTION_TEST_DB'] ??
        'tentura_test_attretn_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_ATTENTION_RETENTION_TEST_DB',
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
      final remaining = await connection.execute(
        r'SELECT count(*)::int FROM pg_database WHERE datname = $1',
        parameters: [databaseName],
      );
      if (remaining.single.single != 0) {
        throw StateError('Disposable database was not dropped: $databaseName');
      }
    } finally {
      await connection.close();
    }
  }
}
