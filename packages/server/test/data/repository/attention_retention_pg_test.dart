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

/// Retention must keep durable channel handoffs until they reach a terminal
/// state. Once a receipt has been seen and emailed, m0125 lets retention
/// remove terminal delivery jobs along with their receipt.
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

      await writer.execute('''
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
      'keeps pending and leased handoffs, then removes terminal and no-delivery receipts',
      () async {
        final oldAt = DateTime.parse('2020-01-01T00:00:00Z');

        // A settled, old receipt with no delivery job attached.
        await writer.execute(
          Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at, seen_at, emailed_at,
  source_event_key, destination_kind, presentation_key, access_policy
) VALUES (
  'Nattretlegacy', 'Uattretactor', 'asksOfMe', 'needsMe', 'normal',
  'No delivery', 'No delivery body', '/no-delivery',
  'attention-retention-no-delivery', @oldAt, @oldAt, @oldAt,
  'attention-retention-no-delivery', 'profile', 'invite_accepted', 'profile'
)
'''),
          parameters: {'oldAt': oldAt},
        );
        // Seeing a receipt alone must never discard an unsent digest entry.
        await writer.execute(
          Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at, seen_at,
  source_event_key, destination_kind, presentation_key, access_policy
) VALUES (
  'Nattretunemailed', 'Uattretactor', 'asksOfMe', 'needsMe', 'normal',
  'Unsent digest', 'Unsent digest body', '/unsent-digest',
  'attention-retention-unsent-digest', @oldAt, @oldAt,
  'attention-retention-unsent-digest', 'profile', 'invite_accepted', 'profile'
)
'''),
          parameters: {'oldAt': oldAt},
        );

        Future<String> recordDeliveryBackedReceipt(String suffix) async {
          await unitOfWork.run(
            actorUserId: 'Uattretactor',
            action: () => dispatch.record(
              AttentionDispatchIntent(
                eventType: AttentionEventType.relayReceived,
                sourceEventKey: 'attention-retention-relay-$suffix',
                actorUserId: 'Uattretactor',
                priority: NotificationPriority.normal,
                kind: NotificationKind.newRelay,
                title: 'Forwarded Request',
                body: 'A Request was forwarded to you',
                actionUrl: '/#/view?id=Battret',
                collapseKey: 'attention-retention-relay-$suffix',
                recipients: const [
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
          final receipt = await writer.execute(
            Sql.named('''
SELECT id FROM public.notification_outbox
WHERE dedup_key = @dedupKey
'''),
            parameters: {
              'dedupKey':
                  'Uattretactor|attention-v1|attention-retention-relay-$suffix',
            },
          );
          return receipt.single.single! as String;
        }

        final pendingId = await recordDeliveryBackedReceipt('pending');
        final leasedId = await recordDeliveryBackedReceipt('leased');
        final terminalId = await recordDeliveryBackedReceipt('terminal');
        await writer.execute(
          Sql.named('''
UPDATE public.notification_outbox
SET seen_at = @oldAt, created_at = @oldAt, emailed_at = @oldAt
WHERE id IN (@pendingId, @leasedId, @terminalId)
'''),
          parameters: {
            'oldAt': oldAt,
            'pendingId': pendingId,
            'leasedId': leasedId,
            'terminalId': terminalId,
          },
        );
        await writer.execute(
          Sql.named('''
UPDATE public.attention_channel_delivery
SET status = 'leased', lease_owner = 'retention-test-worker',
    lease_until = @leaseUntil
WHERE receipt_id = @receiptId
'''),
          parameters: {
            'leaseUntil': oldAt.add(const Duration(minutes: 2)),
            'receiptId': leasedId,
          },
        );
        await writer.execute(
          Sql.named('''
UPDATE public.attention_channel_delivery
SET status = 'delivered', delivered_at = @deliveredAt
WHERE receipt_id = @receiptId
'''),
          parameters: {'deliveredAt': oldAt, 'receiptId': terminalId},
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

        expect(await deliveryCountFor(pendingId), 1);
        expect(await deliveryCountFor(leasedId), 1);
        expect(await deliveryCountFor(terminalId), 1);

        final deleted = await outbox.deleteSettledOlderThan(
          const Duration(days: 30),
        );
        expect(deleted, 2);

        final remaining = await writer.execute(
          r'''
SELECT count(*)::int FROM public.notification_outbox
WHERE id IN ('Nattretlegacy', 'Nattretunemailed', $1, $2, $3)
''',
          parameters: [pendingId, leasedId, terminalId],
        );
        expect(remaining.single.single, 3);
        final remainingIds = await writer.execute(
          r'''
SELECT id FROM public.notification_outbox
WHERE id IN ('Nattretunemailed', $1, $2, $3)
ORDER BY id
''',
          parameters: [pendingId, leasedId, terminalId],
        );
        expect(
          remainingIds.map((row) => row.single).toSet(),
          {'Nattretunemailed', pendingId, leasedId},
        );

        // The terminal delivery job cascades away with its receipt (m0125),
        // while pending and leased handoffs remain available to workers.
        expect(await deliveryCountFor(pendingId), 1);
        expect(await deliveryCountFor(leasedId), 1);
        expect(await deliveryCountFor(terminalId), 0);
        final occurrence = await writer.execute('''
SELECT count(*)::int FROM public.attention_occurrence
WHERE source_event_key IN (
  'attention-retention-relay-pending',
  'attention-retention-relay-leased',
  'attention-retention-relay-terminal'
)
''');
        expect(occurrence.single.single, 3);
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
