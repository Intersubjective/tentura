@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/coordination_item_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/trust_evidence_repository_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/pg_test_public_keys.dart';

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('room now line write path', () {
    late Connection writer;
    late TenturaDb database;
    late BeaconRoomRepository roomRepo;
    late CoordinationItemRepository items;
    late BeaconRoomCase roomCase;
    late AttentionDispatchRepository dispatch;

    const authorId = 'Unowlineauth1';
    const memberId = 'Unowlinemem01';
    const beaconId = 'Bnowlinebcn01';

    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);
      database = TenturaDb(target.databaseEnv);
      roomRepo = BeaconRoomRepository(database);
      items = CoordinationItemRepository(database);
      dispatch = AttentionDispatchRepository(
        database,
        Logger('room_now_line_pg_test'),
      );
      final unitOfWork = MutatingUnitOfWork(database);
      final attention = TransactionalAttentionCase(unitOfWork, dispatch);
      final attentionIntents = AttentionIntentCase(
        BeaconRoomNotificationContextRepository(
          roomRepo,
          database,
          HelpOfferRepository(database),
          CommitmentRepository(database),
        ),
        UserRepository(
          Env(environment: Environment.test),
          database,
          _NoopTrustEvidenceRepository(),
          _NoopInviteGenealogyRepository(),
          InviteSeedPromptRepositoryMock(),
        ),
        BeaconAccessRepository(database),
        FakeUserBlockRepository(),
      );
      roomCase = BeaconRoomCase(
        roomRepo,
        items,
        _PgFakeFactCards(),
        _PgFakeImages(),
        _PgFakeTasks(),
        _PgFakeRemoteStorage(),
        _PgFakePolling(),
        _PgFakeUploadQuota(),
        FakeUserBlockRepository(),
        unitOfWork,
        FakeBeaconHierarchyRepository(),
        const ProductionDiscussionProductPolicy(),
        attentionIntents: attentionIntents,
        attention: attention,
        env: Env(environment: Environment.test),
        logger: Logger('room_now_line_pg_test'),
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
  public.beacon_room_state,
  public.beacon,
  public."user"
CASCADE
''');
      final authorKey = pgTestPublicKey('nowline', 1);
      final memberKey = pgTestPublicKey('nowline', 2);
      await writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES
  (@authorId, @authorId, @authorKey),
  (@memberId, @memberId, @memberKey)
'''),
        parameters: {
          'authorId': authorId,
          'authorKey': authorKey,
          'memberId': memberId,
          'memberKey': memberKey,
        },
      );
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@beaconId, @authorId, 'NOW test', 'Body', 0)
'''),
        parameters: {'beaconId': beaconId, 'authorId': authorId},
      );
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, status, room_access, created_at, updated_at
) VALUES (
  'Pnowlinemem01', @beaconId, @memberId, 0, 0, @roomAccess,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
'''),
        parameters: {
          'beaconId': beaconId,
          'memberId': memberId,
          'roomAccess': RoomAccessBits.admitted,
        },
      );
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });

    Future<int> publishedPlanCount() async {
      final rows = await writer.execute(
        Sql.named('''
SELECT count(*)::int AS c
FROM public.coordination_item
WHERE beacon_id = @beaconId
  AND kind = @kind
  AND published = true
'''),
        parameters: {
          'beaconId': beaconId,
          'kind': coordinationItemKindPlan,
        },
      );
      return rows.single.first as int;
    }

    test(
      'writes current line without creating a coordination plan item',
      () async {
        expect(await publishedPlanCount(), 0);

        final row = await roomCase.updateRoomNowLine(
          beaconId: beaconId,
          userId: authorId,
          text: '  Fresh NOW line  ',
        );

        expect(row['currentLine'], 'Fresh NOW line');
        expect(await publishedPlanCount(), 0);
        final state = await roomRepo.getBeaconRoomState(beaconId);
        expect(state?.currentLine, 'Fresh NOW line');
      },
      skip: skipReason,
    );

    test(
      'emits coordinationChanged with beacon_room_state source event key',
      () async {
        await roomCase.updateRoomNowLine(
          beaconId: beaconId,
          userId: authorId,
          text: 'Receipt key line',
        );

        final rows = await writer.execute('''
SELECT source_event_key
FROM public.attention_occurrence
ORDER BY id
''');
        expect(rows, hasLength(1));
        final key = rows.single.first as String;
        expect(
          key,
          matches(
            RegExp(
              r'^beacon_room_state:Bnowlinebcn01:now_updated:\d+$',
            ),
          ),
        );
      },
      skip: skipReason,
    );

    test(
      'second identical NOW edit collapses outbox receipts by dedup key',
      () async {
        const line = 'Same NOW twice';
        await roomCase.updateRoomNowLine(
          beaconId: beaconId,
          userId: authorId,
          text: line,
        );
        await roomCase.updateRoomNowLine(
          beaconId: beaconId,
          userId: authorId,
          text: line,
        );

        final occurrenceRows = await writer.execute('''
SELECT count(*)::int AS c FROM public.attention_occurrence
''');
        expect(occurrenceRows.single.first, 2);

        final outboxRows = await writer.execute(
          Sql.named('''
SELECT count(*)::int AS c
FROM public.notification_outbox
WHERE beacon_id = @beaconId
  AND account_id = @memberId
  AND kind = @kind
'''),
          parameters: {
            'beaconId': beaconId,
            'memberId': memberId,
            'kind': NotificationKind.coordinationChanged.name,
          },
        );
        expect(outboxRows.single.first, 1);
      },
      skip: skipReason,
    );
  });
}

Future<bool> _canConnect(Env env) async {
  try {
    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    );
    await connection.close();
    return true;
  } on Object {
    return false;
  }
}

final class _DisposablePgTarget {
  _DisposablePgTarget({
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
        Platform.environment['TENTURA_ROOM_NOW_LINE_TEST_DB'] ??
        'tentura_test_room_now_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_ROOM_NOW_LINE_TEST_DB',
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

final class _NoopTrustEvidenceRepository extends Fake
    implements TrustEvidenceRepositoryPort {}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}

class _PgFakeFactCards extends Fake implements BeaconFactCardRepositoryPort {}

class _PgFakeImages extends Fake implements ImageRepositoryPort {}

class _PgFakeTasks extends Fake implements TaskRepositoryPort {}

class _PgFakeRemoteStorage extends Fake implements RemoteStoragePort {}

class _PgFakePolling extends Fake implements PollingRepositoryPort {}

class _PgFakeUploadQuota extends Fake implements UploadQuotaRepositoryPort {
  @override
  Future<bool> tryReserveDailyBytes({
    required String userId,
    required int bytes,
    required int dailyCapBytes,
  }) async =>
      true;
}
