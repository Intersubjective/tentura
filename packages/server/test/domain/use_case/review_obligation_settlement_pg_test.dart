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
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/data/repository/attention_system_settlement_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/trust_evidence_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/attention_settlement_case.dart';

import '../../support/fake_user_block_repository.dart';

import '../../support/disposable_pg_target.dart';

const _beaconId = 'Broblgbcn001';
const _authorId = 'Uroblgauth01';
const _reviewer1 = 'Uroblgrevw01';
const _reviewer2 = 'Uroblgrevw02';
const _subjectId = 'Uroblgsubj01';

/// m0203 (A6) dropped the review-era tables and its data step retired every
/// live `reviewOpened` obligation, so the review-window settlement tests that
/// used to live here no longer have a subject. What remains is the live
/// help-offer settlement surface plus the user-settle guard.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_REVIEW_OBLIGATION_TEST_DB',
    defaultNamePrefix: 'tentura_test_review_obl',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('obligation system settlement', () {
    late Connection writer;
    late TenturaDb database;
    late AttentionDispatchRepository dispatch;
    late AttentionIntentCase intents;
    late AttentionSystemSettlementRepository systemSettlement;

    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);

      database = TenturaDb(target.databaseEnv);
      final logger = Logger('ReviewObligationSettlementPgTest');
      dispatch = AttentionDispatchRepository(database, logger);
      final room = BeaconRoomRepository(database);
      final helpOffers = HelpOfferRepository(database);
      final commitments = CommitmentRepository(database);
      intents = AttentionIntentCase(
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
      systemSettlement = AttentionSystemSettlementRepository(database);
    });

    setUp(() async => _resetFixture(writer));

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });

    test('user settle of a live obligation throws and leaves receipt live',
        () async {
      await dispatch.record(
        await intents.helpOfferSubmitted(
          beaconId: _beaconId,
          helpOffererId: _reviewer2,
          authorId: _authorId,
          sourceEventKey: 'help_offer:Broblgguard',
        ),
      );
      final receiptId = await _liveReceiptId(writer, _authorId);
      expect(receiptId, isNotNull);

      final settlementCase = AttentionSettlementCase(
        AttentionSettlementRepository(database),
        env: target.databaseEnv,
        logger: Logger('ReviewObligationSettlementPgTest'),
      );

      expect(
        () => settlementCase.settle(
          accountId: _authorId,
          receiptId: receiptId!,
          kind: AttentionSettlementKind.resolved,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(await _settlementKind(writer, _authorId), isNull);
    }, skip: skipReason);

    test('settleAuthorHelpOfferSubmitted resolves author help-offer obligation',
        () async {
      await dispatch.record(
        await intents.helpOfferSubmitted(
          beaconId: _beaconId,
          helpOffererId: _reviewer2,
          authorId: _authorId,
          sourceEventKey: 'help_offer:admit',
        ),
      );

      final updated = await systemSettlement.settleAuthorHelpOfferSubmitted(
        beaconId: _beaconId,
        authorAccountId: _authorId,
        helpOffererUserId: _reviewer2,
      );
      expect(updated, 1);

      final helpRows = await writer.execute('''
SELECT settlement_kind, seen_at
FROM public.notification_outbox outbox
JOIN public.attention_occurrence occ ON occ.id = outbox.occurrence_id
WHERE outbox.beacon_id = '$_beaconId'
  AND outbox.account_id = '$_authorId'
  AND occ.event_type = 'helpOfferSubmitted'
''');
      expect(helpRows.single[0], 'resolved');
      expect(helpRows.single[1], isNotNull);
    }, skip: skipReason);

    test(
        'settleAuthorHelpOfferSubmitted preserves prior seen_at and leaves other offerers',
        () async {
      await dispatch.record(
        await intents.helpOfferSubmitted(
          beaconId: _beaconId,
          helpOffererId: _reviewer1,
          authorId: _authorId,
          sourceEventKey: 'help_offer:other',
        ),
      );
      await dispatch.record(
        await intents.helpOfferSubmitted(
          beaconId: _beaconId,
          helpOffererId: _reviewer2,
          authorId: _authorId,
          sourceEventKey: 'help_offer:target',
        ),
      );
      await writer.execute('''
UPDATE public.notification_outbox AS outbox
SET seen_at = '2026-07-17T10:00:00Z'::timestamptz
FROM public.attention_occurrence AS occ
WHERE outbox.occurrence_id = occ.id
  AND occ.event_type = 'helpOfferSubmitted'
  AND outbox.beacon_id = '$_beaconId'
  AND outbox.account_id = '$_authorId'
  AND outbox.target_entity_id = '$_reviewer2'
''');

      final updated = await systemSettlement.settleAuthorHelpOfferSubmitted(
        beaconId: _beaconId,
        authorAccountId: _authorId,
        helpOffererUserId: _reviewer2,
      );
      expect(updated, 1);

      final targetRows = await writer.execute('''
SELECT settlement_kind, seen_at
FROM public.notification_outbox outbox
JOIN public.attention_occurrence occ ON occ.id = outbox.occurrence_id
WHERE outbox.beacon_id = '$_beaconId'
  AND outbox.account_id = '$_authorId'
  AND outbox.target_entity_id = '$_reviewer2'
  AND occ.event_type = 'helpOfferSubmitted'
''');
      expect(targetRows.single[0], 'resolved');
      expect(
        DateTime.parse(targetRows.single[1]!.toString()).toUtc(),
        DateTime.utc(2026, 7, 17, 10),
      );

      final otherRows = await writer.execute('''
SELECT settlement_kind, seen_at
FROM public.notification_outbox outbox
JOIN public.attention_occurrence occ ON occ.id = outbox.occurrence_id
WHERE outbox.beacon_id = '$_beaconId'
  AND outbox.account_id = '$_authorId'
  AND outbox.target_entity_id = '$_reviewer1'
  AND occ.event_type = 'helpOfferSubmitted'
''');
      expect(otherRows.single[0], isNull);
      expect(otherRows.single[1], isNull);
    }, skip: skipReason);

    test(
        'settleAuthorHelpOfferSubmitted marks already-settled unseen receipt seen',
        () async {
      await dispatch.record(
        await intents.helpOfferSubmitted(
          beaconId: _beaconId,
          helpOffererId: _reviewer2,
          authorId: _authorId,
          sourceEventKey: 'help_offer:presettle',
        ),
      );
      await writer.execute('''
UPDATE public.notification_outbox AS outbox
SET
  settlement_kind = 'resolved',
  settled_at = '2026-07-17T09:00:00Z'::timestamptz
FROM public.attention_occurrence AS occ
WHERE outbox.occurrence_id = occ.id
  AND occ.event_type = 'helpOfferSubmitted'
  AND outbox.beacon_id = '$_beaconId'
  AND outbox.account_id = '$_authorId'
  AND outbox.target_entity_id = '$_reviewer2'
''');

      final updated = await systemSettlement.settleAuthorHelpOfferSubmitted(
        beaconId: _beaconId,
        authorAccountId: _authorId,
        helpOffererUserId: _reviewer2,
      );
      expect(updated, 1);

      final helpRows = await writer.execute('''
SELECT settlement_kind, settled_at, seen_at
FROM public.notification_outbox outbox
JOIN public.attention_occurrence occ ON occ.id = outbox.occurrence_id
WHERE outbox.beacon_id = '$_beaconId'
  AND outbox.account_id = '$_authorId'
  AND outbox.target_entity_id = '$_reviewer2'
  AND occ.event_type = 'helpOfferSubmitted'
''');
      expect(helpRows.single[0], 'resolved');
      expect(
        DateTime.parse(helpRows.single[1]!.toString()).toUtc(),
        DateTime.utc(2026, 7, 17, 9),
      );
      expect(helpRows.single[2], isNotNull);
    }, skip: skipReason);
  }, skip: skipReason);
}

Future<String?> _settlementKind(Connection writer, String accountId) async {
  final rows = await writer.execute('''
SELECT settlement_kind
FROM public.notification_outbox
WHERE beacon_id = '$_beaconId'
  AND account_id = '$accountId'
  AND requires_action
ORDER BY created_at DESC
LIMIT 1
''');
  if (rows.isEmpty) return null;
  return rows.single[0] as String?;
}

Future<String?> _liveReceiptId(Connection writer, String accountId) async {
  final rows = await writer.execute('''
SELECT outbox.id
FROM public.notification_outbox AS outbox
JOIN public.attention_occurrence AS occ ON occ.id = outbox.occurrence_id
WHERE outbox.beacon_id = '$_beaconId'
  AND outbox.account_id = '$accountId'
  AND outbox.requires_action
  AND outbox.settlement_kind IS NULL
ORDER BY outbox.created_at DESC
LIMIT 1
''');
  if (rows.isEmpty) return null;
  return rows.single[0] as String?;
}

Future<void> _resetFixture(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.notification_outbox,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.beacon,
  public."user"
CASCADE
''');

  for (final id in [_authorId, _reviewer1, _reviewer2, _subjectId]) {
    await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'key-$id')
''');
  }

  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES ('$_beaconId', '$_authorId', 'Obligation beacon', 'desc', ${BeaconStatus.open.smallintValue})
''');
}

final class _NoopTrustEvidenceRepository extends Fake
    implements TrustEvidenceRepositoryPort {}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}
