@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/attention_channel_delivery_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/trust_evidence_repository_port.dart';
import 'package:tentura_server/domain/use_case/user_case.dart';
import 'package:tentura_server/env.dart';

/// FK-safe account erasure (Step 4 / m0125): a user who has received
/// canonical attention (recipient snapshot, channel delivery job, channel
/// throttle lease) must still be deletable end to end through the real
/// `UserCase.deleteById()` path, and every account-scoped attention row for
/// them must be gone afterward. Before m0125 these FKs were `ON DELETE
/// RESTRICT` and aborted `userDelete`.
Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('UserCase.deleteById erases account-scoped attention rows', () {
    late Connection writer;
    late TenturaDb database;
    late UserCase userCase;
    late AttentionDispatchRepository dispatch;
    late AttentionChannelDeliveryRepository delivery;
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
      dispatch = AttentionDispatchRepository(database);
      delivery = AttentionChannelDeliveryRepository(database);
      unitOfWork = MutatingUnitOfWork(database);
      userCase = UserCase(
        _NoopImageRepository(),
        UserRepository(
          Env(environment: Environment.test),
          database,
          _NoopTrustEvidenceRepository(),
          _NoopInviteGenealogyRepository(),
        ),
        _NoopTaskRepository(),
        env: Env(environment: Environment.test),
        logger: Logger('test'),
      );
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });

    test(
      'deletes the account and cascades recipient, delivery, and throttle rows',
      () async {
        const actorId = 'Uattdelactor';
        const targetId = 'Uattdeltarget';
        for (final (id, key) in const [
          (actorId, 'attention-delete-actor-key'),
          (targetId, 'attention-delete-target-key'),
        ]) {
          await writer.execute(
            Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
            parameters: {'id': id, 'key': key},
          );
        }

        await unitOfWork.run(
          actorUserId: actorId,
          action: () => dispatch.record(
            const AttentionDispatchIntent(
              eventType: AttentionEventType.relayReceived,
              sourceEventKey: 'attention-delete-relay-1',
              actorUserId: actorId,
              priority: NotificationPriority.normal,
              kind: NotificationKind.newRelay,
              title: 'Forwarded Request',
              body: 'A Request was forwarded to you',
              actionUrl: '/#/view?id=Battdel',
              collapseKey: 'attention-delete-relay',
              recipients: [
                AttentionRecipientSnapshot(
                  recipientId: targetId,
                  reasons: {AttentionRecipientReason.forwardRecipient},
                  role: AttentionRecipientRoleFacts(
                    canReadBeaconContent: true,
                    beaconId: 'Battdel',
                    actorUserId: actorId,
                  ),
                ),
              ],
              beaconId: 'Battdel',
            ),
          ),
        );

        // Lease the delivery job so a throttle row also exists for the
        // target account (claimDue is the only writer of that table).
        final now = DateTime.timestamp().toUtc();
        final claimed = await delivery.claimDue(
          workerId: 'worker-delete-test',
          now: now,
          limit: 10,
        );
        expect(claimed, hasLength(1));

        Future<int> countFor(String table) async {
          final rows = await writer.execute(
            Sql.named(
              'SELECT count(*)::int FROM public.$table '
              'WHERE account_id = @accountId',
            ),
            parameters: {'accountId': targetId},
          );
          return rows.single.single! as int;
        }

        expect(await countFor('attention_occurrence_recipient'), 1);
        expect(await countFor('attention_channel_delivery'), 1);
        expect(await countFor('attention_channel_throttle'), 1);
        expect(await countFor('notification_outbox'), 1);

        final result = await userCase.deleteById(id: targetId);
        expect(result, isTrue);

        final remainingUser = await writer.execute(
          Sql.named(
            'SELECT count(*)::int FROM public."user" WHERE id = @id',
          ),
          parameters: {'id': targetId},
        );
        expect(remainingUser.single.single, 0);

        expect(await countFor('attention_occurrence_recipient'), 0);
        expect(await countFor('attention_channel_delivery'), 0);
        expect(await countFor('attention_channel_throttle'), 0);
        expect(await countFor('notification_outbox'), 0);

        // Occurrence rows are shared history and stay RESTRICT: they are
        // never bulk-deleted by account erasure.
        final occurrence = await writer.execute(
          Sql.named('''
SELECT count(*)::int FROM public.attention_occurrence
WHERE source_event_key = @sourceEventKey
'''),
          parameters: {'sourceEventKey': 'attention-delete-relay-1'},
        );
        expect(occurrence.single.single, 1);
      },
    );

    test(
      'anonymizes a deleted actor while retaining usable recipient history',
      () async {
        const actorId = 'Uattdelactorerase';
        const actorName = 'Erased Actor';
        const targetId = 'Uattdeltargeterase';
        for (final (id, displayName, key) in const [
          (actorId, actorName, 'attention-delete-actor-erase-key'),
          (targetId, targetId, 'attention-delete-target-erase-key'),
        ]) {
          await writer.execute(
            Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @displayName, @key)
'''),
            parameters: {'id': id, 'displayName': displayName, 'key': key},
          );
        }

        await unitOfWork.run(
          actorUserId: actorId,
          action: () => dispatch.record(
            const AttentionDispatchIntent(
              eventType: AttentionEventType.relayReceived,
              sourceEventKey: 'attention-delete-actor-erase-relay-1',
              actorUserId: actorId,
              priority: NotificationPriority.normal,
              kind: NotificationKind.newRelay,
              title: 'Erased Actor forwarded a Request',
              body: 'Erased Actor shared a private request',
              actionUrl: '/#/profile?id=Uattdelactorerase',
              collapseKey: 'attention-delete-actor-erase',
              recipients: [
                AttentionRecipientSnapshot(
                  recipientId: targetId,
                  reasons: {AttentionRecipientReason.forwardRecipient},
                  role: AttentionRecipientRoleFacts(
                    canReadBeaconContent: true,
                    beaconId: 'Battdelerase',
                    targetEntityId: actorId,
                    actorUserId: actorId,
                  ),
                ),
              ],
              beaconId: 'Battdelerase',
              targetEntityId: actorId,
            ),
          ),
        );

        final now = DateTime.timestamp().toUtc();
        expect(
          await delivery.claimDue(
            workerId: 'worker-delete-actor-test',
            now: now,
            limit: 10,
          ),
          hasLength(1),
        );
        await writer.execute(
          Sql.named('''
UPDATE public.attention_channel_delivery
SET last_error = @lastError
WHERE account_id = @targetId
'''),
          parameters: {
            'lastError': '$actorName ($actorId) delivery failed',
            'targetId': targetId,
          },
        );

        final result = await userCase.deleteById(id: actorId);
        expect(result, isTrue);

        Future<int> countForSource(String table) async {
          final rows = await writer.execute(
            Sql.named('''
SELECT count(*)::int
FROM public.$table
WHERE occurrence_id = (
  SELECT id
  FROM public.attention_occurrence
  WHERE source_event_key = 'erased-actor|' || id
  LIMIT 1
)
'''),
          );
          return rows.single.single! as int;
        }

        final userRows = await writer.execute(
          Sql.named('SELECT count(*)::int FROM public."user" WHERE id = @id'),
          parameters: {'id': actorId},
        );
        expect(userRows.single.single, 0);

        // The occurrence, recipient snapshot, receipt, and delivery all stay
        // available for the other recipient; only actor-bearing data changes.
        expect(await countForSource('attention_occurrence_recipient'), 1);
        expect(await countForSource('notification_outbox'), 1);
        expect(await countForSource('attention_channel_delivery'), 1);

        final scrubbedOccurrences = await writer.execute(
          Sql.named('''
SELECT count(*)::int
FROM public.attention_occurrence
WHERE actor_user_id = @actorId
   OR immutable_payload::text LIKE '%' || @actorId || '%'
   OR immutable_payload::text LIKE '%' || @actorName || '%'
'''),
          parameters: {'actorId': actorId, 'actorName': actorName},
        );
        expect(scrubbedOccurrences.single.single, 0);

        final scrubbedRecipients = await writer.execute(
          Sql.named('''
SELECT count(*)::int
FROM public.attention_occurrence_recipient
WHERE row_to_json(attention_occurrence_recipient)::text LIKE '%' || @actorId || '%'
   OR row_to_json(attention_occurrence_recipient)::text LIKE '%' || @actorName || '%'
'''),
          parameters: {'actorId': actorId, 'actorName': actorName},
        );
        expect(scrubbedRecipients.single.single, 0);

        final scrubbedReceipts = await writer.execute(
          Sql.named('''
SELECT count(*)::int
FROM public.notification_outbox
WHERE actor_user_id = @actorId
   OR row_to_json(notification_outbox)::text LIKE '%' || @actorId || '%'
   OR row_to_json(notification_outbox)::text LIKE '%' || @actorName || '%'
'''),
          parameters: {'actorId': actorId, 'actorName': actorName},
        );
        expect(scrubbedReceipts.single.single, 0);

        final scrubbedDeliveries = await writer.execute(
          Sql.named('''
SELECT count(*)::int
FROM public.attention_channel_delivery
WHERE row_to_json(attention_channel_delivery)::text LIKE '%' || @actorId || '%'
   OR row_to_json(attention_channel_delivery)::text LIKE '%' || @actorName || '%'
'''),
          parameters: {'actorId': actorId, 'actorName': actorName},
        );
        expect(scrubbedDeliveries.single.single, 0);

        final retainedReceipt = await writer.execute(
          Sql.named('''
SELECT title, body, actor_user_id, presentation_payload::text
FROM public.notification_outbox
WHERE account_id = @targetId
  AND source_event_key LIKE 'erased-actor|%'
'''),
          parameters: {'targetId': targetId},
        );
        expect(retainedReceipt, hasLength(1));
        expect(retainedReceipt.single[0], 'Deleted account');
        expect(
          retainedReceipt.single[1],
          'An account involved in this activity was deleted.',
        );
        expect(retainedReceipt.single[2], isNull);
        expect(retainedReceipt.single[3], contains('relayReceived'));

        final retainedDelivery = await writer.execute(
          Sql.named('''
SELECT payload::text
FROM public.attention_channel_delivery
WHERE account_id = @targetId
'''),
          parameters: {'targetId': targetId},
        );
        expect(retainedDelivery, hasLength(1));
        expect(retainedDelivery.single.single, contains('deleted-account'));
      },
    );
  }, skip: skipReason);
}

class _NoopImageRepository implements ImageRepositoryPort {
  @override
  Future<void> deleteAllOf({required String userId}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _NoopTaskRepository implements TaskRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _NoopTrustEvidenceRepository implements TrustEvidenceRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _NoopInviteGenealogyRepository implements InviteGenealogyRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
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
        Platform.environment['TENTURA_USER_DELETE_ATTENTION_TEST_DB'] ??
        'tentura_test_userdel_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_USER_DELETE_ATTENTION_TEST_DB',
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
