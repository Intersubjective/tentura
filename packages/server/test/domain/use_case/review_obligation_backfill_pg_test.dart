@Tags(['pg'])
library;


import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/attention_reconciliation_repository.dart';
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/data/repository/attention_system_settlement_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/trust_evidence_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/obligation_reconciliation_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import '../../support/fake_user_block_repository.dart';

import '../../support/disposable_pg_target.dart';

const _beaconId = 'Broblfbfcn01';
const _authorId = 'Uroblfauth01';
const _reviewer1 = 'Uroblfrevw01';
const _reviewer2 = 'Uroblfrevw02';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_REVIEW_OBLIGATION_BACKFILL_TEST_DB',
    defaultNamePrefix: 'tentura_test_review_obl_bf',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late Connection writer;
  late TenturaDb database;
  late ObligationReconciliationCase backfill;

  if (skipReason == false) {
    // Lifecycle lives in setUpAll/tearDownAll, not the test body: recreate and
    // drop wait on the cluster-wide disposable-pg lifecycle lock, which may
    // legitimately exceed the default 30-second test timeout under parallel
    // pg load (tentura-8xf raised that lock's queryTimeout to 15 minutes).
    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);
      await _seedFixture(writer);

      database = TenturaDb(target.databaseEnv);
      final logger = Logger('ReviewObligationBackfillPgTest');
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
      backfill = ObligationReconciliationCase(
        systemSettlement,
        AttentionReconciliationRepository(database),
        AttentionRepository(database),
        TransactionalAttentionCase(MutatingUnitOfWork(database), dispatch),
        intents,
        env: target.databaseEnv,
        logger: logger,
      );
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });
  }

  test(
    'backfill is a no-op on the post-m0203 schema and settles nothing',
    () async {
      // m0203 (A6) dropped the review-window tables and its data step retired
      // every live reviewOpened obligation, so the deployment-time backfill
      // for pre-settlement review windows has no subject left: it must settle
      // nothing and stay idempotent, however often it runs.
      final firstPass = await backfill.run();
      expect(firstPass, 0);

      final kinds = await writer.execute('''
SELECT settlement_kind
FROM public.notification_outbox
WHERE beacon_id = '$_beaconId'
  AND requires_action
ORDER BY account_id
''');
      expect(kinds.map((r) => r[0]), [null, null]);

      final secondPass = await backfill.run();
      expect(secondPass, 0);
    },
    skip: skipReason,
  );
}

Future<void> _seedFixture(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.notification_outbox,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
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
}

final class _NoopTrustEvidenceRepository extends Fake
    implements TrustEvidenceRepositoryPort {}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}
