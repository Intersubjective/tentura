@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/attention_system_settlement_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/trust_evidence_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/review_obligation_backfill_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/fake_user_block_repository.dart';

const _beaconId = 'Broblfbfcn01';
const _authorId = 'Uroblfauth01';
const _reviewer1 = 'Uroblfrevw01';
const _reviewer2 = 'Uroblfrevw02';

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  test('backfill settles pre-closed windows and second run is a no-op', () async {
    await target.recreate();
    final writer = await Connection.open(
      target.databaseEnv.pgEndpoint,
      settings: target.databaseEnv.pgEndpointSettings,
    );
    final database = TenturaDb(target.databaseEnv);
    final logger = Logger('ReviewObligationBackfillPgTest');
    try {
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);
      await _seedClosedWindowFixture(writer);

      final dispatch = AttentionDispatchRepository(database, logger);
      final room = BeaconRoomRepository(database);
      final helpOffers = HelpOfferRepository(database);
      final commitments = CommitmentRepository(database);
      final intents = AttentionIntentCase(
        BeaconRoomNotificationContextRepository(
          room,
          database,
          helpOffers,
          commitments,
        ),
        UserRepository(
          target.databaseEnv,
          database,
          _NoopTrustEvidenceRepository(),
          _NoopInviteGenealogyRepository(),
          InviteSeedPromptRepositoryMock(),
        ),
        BeaconAccessRepository(database),
        FakeUserBlockRepository(),
      );
      await dispatch.record(
        await intents.reviewOpened(
          beaconId: _beaconId,
          beaconTitle: 'Backfill fixture',
          recipientUserIds: {_reviewer1, _reviewer2},
          actorUserId: _authorId,
          sourceEventKey: 'review_opened:Broblffixture',
        ),
      );

      final systemSettlement = AttentionSystemSettlementRepository(database);
      final backfill = ReviewObligationBackfillCase(
        systemSettlement,
        env: target.databaseEnv,
        logger: logger,
      );

      final firstPass = await backfill.run();
      expect(firstPass, 2);

      final kinds = await writer.execute('''
SELECT settlement_kind
FROM public.notification_outbox
WHERE beacon_id = '$_beaconId'
  AND requires_action
ORDER BY account_id
''');
      expect(kinds.map((r) => r[0]), ['expired', 'expired']);

      final secondPass = await backfill.run();
      expect(secondPass, 0);
    } finally {
      await database.close();
      await writer.close();
      await target.drop();
    }
  }, skip: skipReason);
}

Future<void> _seedClosedWindowFixture(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.notification_outbox,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.beacon_review_status,
  public.beacon_review_window,
  public.beacon,
  public."user"
CASCADE
''');

  for (final id in [_authorId, _reviewer1, _reviewer2]) {
    await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'key-$id')
''');
  }

  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (
  '$_beaconId',
  '$_authorId',
  'Backfill beacon',
  'desc',
  ${BeaconStatus.closed.smallintValue}
)
''');

  await writer.execute('''
INSERT INTO public.beacon_review_window (
  beacon_id, opened_at, closes_at, status, extensions_used
) VALUES (
  '$_beaconId',
  now() - interval '2 days',
  now() - interval '1 day',
  1,
  0
)
''');

  for (final uid in [_reviewer1, _reviewer2]) {
    await writer.execute('''
INSERT INTO public.beacon_review_status (beacon_id, user_id, status)
VALUES ('$_beaconId', '$uid', 4)
''');
  }
}

final class _NoopTrustEvidenceRepository extends Fake
    implements TrustEvidenceRepositoryPort {}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}

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
        Platform.environment['TENTURA_REVIEW_OBLIGATION_BACKFILL_TEST_DB'] ??
        'tentura_test_review_obl_bf_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_REVIEW_OBLIGATION_BACKFILL_TEST_DB',
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
