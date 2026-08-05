@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/coordination_item_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/trust_evidence_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/accept_ask_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/fake_user_block_repository.dart';
import '../../../support/pg_test_public_keys.dart';

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('commitment attention producers', () {
    late Connection writer;
    late TenturaDb database;
    late CoordinationItemRepository items;
    late AttentionDispatchRepository dispatch;
    late MutatingUnitOfWork unitOfWork;
    late TransactionalAttentionCase attention;
    late AttentionIntentCase attentionIntents;
    late AcceptAskCase acceptAsk;

    const creatorId = 'Ucommitauth01';
    const targetId = 'Ucommittgt01';
    const beaconId = 'Bcommitbcn01';
    const itemId = 'Icommitask01';

    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);
      database = TenturaDb(target.databaseEnv);
      items = CoordinationItemRepository(database);
      dispatch = AttentionDispatchRepository(database, Logger('commitment_attention_pg_test'));
      unitOfWork = MutatingUnitOfWork(database);
      attention = TransactionalAttentionCase(unitOfWork, dispatch);
      final room = BeaconRoomRepository(database);
      attentionIntents = AttentionIntentCase(
        BeaconRoomNotificationContextRepository(room, database),
        UserRepository(
          Env(environment: Environment.test),
          database,
          _NoopTrustEvidenceRepository(),
          _NoopInviteGenealogyRepository(),
        ),
        BeaconAccessRepository(database),
        FakeUserBlockRepository(),
      );
      acceptAsk = AcceptAskCase(
        items,
        attentionIntents: attentionIntents,
        attention: attention,
        env: Env(environment: Environment.test),
        logger: Logger('commitment_attention_pg_test'),
      );
    });

    setUp(() async {
      await writer.execute('''
TRUNCATE TABLE
  public.attention_channel_delivery,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.notification_outbox,
  public.coordination_item,
  public.beacon,
  public."user"
CASCADE
''');
      final creatorKey = pgTestPublicKey('commit', 1);
      final targetKey = pgTestPublicKey('commit', 2);
      await writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES
  (@creatorId, @creatorId, @creatorKey),
  (@targetId, @targetId, @targetKey)
'''),
        parameters: {
          'creatorId': creatorId,
          'targetId': targetId,
          'creatorKey': creatorKey,
          'targetKey': targetKey,
        },
      );
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@beaconId, @creatorId, 'Commitment test', 'Body', 0)
'''),
        parameters: {'beaconId': beaconId, 'creatorId': creatorId},
      );
      await writer.execute(
        Sql.named('''
INSERT INTO public.coordination_item (
  id, beacon_id, kind, status, title, body, creator_id, target_person_id,
  published, source, ordering, created_at, updated_at, published_at
) VALUES (
  @itemId, @beaconId, @kind, @status, 'Need help', '', @creatorId, @targetId,
  true, 0, 0, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
'''),
        parameters: {
          'itemId': itemId,
          'beaconId': beaconId,
          'kind': coordinationItemKindAsk,
          'status': coordinationItemStatusOpen,
          'creatorId': creatorId,
          'targetId': targetId,
        },
      );
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });

    test(
      'accepting an ask writes a creator receipt with beacon and item ids',
      () async {
        await acceptAsk.call(userId: targetId, itemId: itemId);

        final rows = await writer.execute(
          Sql.named('''
SELECT account_id, beacon_id, coordination_item_id, kind
FROM public.notification_outbox
WHERE account_id = @creatorId
'''),
          parameters: {'creatorId': creatorId},
        );
        expect(rows, hasLength(1));
        expect(rows.single[1], beaconId);
        expect(rows.single[2], itemId);
        expect(rows.single[3], NotificationKind.commitmentAccepted.name);
      },
      skip: skipReason,
    );

    test(
      'replaying the same accepted transition source key is idempotent',
      () async {
        final updated = await acceptAsk.call(userId: targetId, itemId: itemId);
        final sourceEventKey =
            'coordination_item:${updated.id}:accepted:'
            '${updated.updatedAt.toUtc().microsecondsSinceEpoch}';
        final intent = await attentionIntents.commitmentChanged(
          beaconId: updated.beaconId,
          actorUserId: targetId,
          transition: 'accepted',
          excerpt: updated.title,
          targetPersonId: updated.creatorId,
          coordinationItemId: updated.id,
          sourceEventKey: sourceEventKey,
        );

        await unitOfWork.run(
          actorUserId: targetId,
          action: () => dispatch.record(intent),
        );

        final count = await writer.execute('''
SELECT count(*)::int FROM public.notification_outbox
''');
        expect(count.single.single, 1);
      },
      skip: skipReason,
    );
  });
}

class _NoopTrustEvidenceRepository implements TrustEvidenceRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopInviteGenealogyRepository implements InviteGenealogyRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
        Platform.environment['TENTURA_COMMITMENT_TEST_DB'] ??
        'tentura_test_commitment_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_COMMITMENT_TEST_DB',
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
