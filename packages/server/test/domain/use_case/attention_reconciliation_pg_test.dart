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
import 'package:tentura_server/env.dart';

import '../../support/fake_user_block_repository.dart';

/// U12 / D15 — reconciliation repairs *derived* obligation state and nothing
/// else.
///
/// The fixture is built from corruption that can actually occur, not from an
/// empty database: a receipt that outlived its task, a task with no receipt, a
/// receipt settled with the wrong reason, and a pre-U05c row with no
/// `logical_task_key`. Each one has an assertion for what repair does to it,
/// and the acts a person performed have assertions that repair leaves them
/// alone — over-reach is the dangerous failure here, not an unrepaired row.
const _accountId = 'Urecnauth001';
const _otherAccountId = 'Urecnothr001';
const _helperStale = 'Urecnhelp001';
const _helperAnswered = 'Urecnhelp002';
const _helperMissing = 'Urecnhelp003';
const _helperWrongReason = 'Urecnhelp004';
const _helperLegacy = 'Urecnhelp005';
const _helperHealthy = 'Urecnhelp006';
const _helperUserSettled = 'Urecnhelp007';
const _helperForeign = 'Urecnhelp008';
const _helperMultiAudience = 'Urecnhelp009';
const _helperRemoved = 'Urecnhelp010';
const _helperDeclined = 'Urecnhelp011';
const _stewardB = 'Urecnstew001';
const _stewardC = 'Urecnstew002';

const _bStale = 'Brecnstale01';
const _bAnswered = 'Brecnanswr01';
const _bMissing = 'Brecnmissg01';
const _bWrongReason = 'Brecnwrong01';
const _bLegacy = 'Brecnlegcy01';
const _bHealthy = 'Brecnhealt01';
const _bUserSettled = 'Brecnusrst01';
const _bForeign = 'Brecnforgn01';
const _bReviewClosed = 'Brecnrvcls01';
const _bReviewOpen = 'Brecnrvopn01';
const _bCleared = 'Brecnclear01';
const _bMultiAudience = 'Brecnmult01';
const _bMultiAudienceC = 'Brecnmult02';
const _helperMultiAudienceC = 'Urecnhelp012';
const _bRemoved = 'Brecnrmvd01';
const _bDeclined = 'Brecndcln01';
const _bInboxStance = 'Brecninbox01';

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('obligation reconciliation', () {
    late Connection writer;
    late TenturaDb database;
    late ObligationReconciliationCase reconciliation;

    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);
      database = TenturaDb(target.databaseEnv);
      final logger = Logger('AttentionReconciliationPgTest');
      final dispatch = AttentionDispatchRepository(database, logger);
      final helpOffers = HelpOfferRepository(database);
      final intents = AttentionIntentCase(
        BeaconRoomNotificationContextRepository(
          BeaconRoomRepository(database),
          database,
          helpOffers,
          CommitmentRepository(database),
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
      reconciliation = ObligationReconciliationCase(
        AttentionSystemSettlementRepository(database),
        AttentionReconciliationRepository(database),
        AttentionRepository(database),
        TransactionalAttentionCase(MutatingUnitOfWork(database), dispatch),
        intents,
        env: target.databaseEnv,
        logger: logger,
      );
      await _seedFixture(writer);
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });

    test('one pass converges, a second changes nothing, and the '
        "account's own acts survive both", () async {
      final before = await _fingerprint(writer);

      final first = await reconciliation.reconcileAccount(
        accountId: _accountId,
      );

      // --- what was repaired -------------------------------------------
      // stale live receipt, helper withdrew → the real source reason.
      expect(await _settlement(writer, 'Nrecnstale'), 'superseded');
      // stale live receipt, author already accepted → answered, not dropped.
      expect(await _settlement(writer, 'Nrecnanswr'), 'resolved');
      // live review receipt whose window closed without a package.
      expect(await _settlement(writer, 'Nrecnrvcls'), 'expired');
      // removal without withdraw_reason — terminal commitment, not author answer.
      expect(await _settlement(writer, 'Nrecnrmvd'), 'superseded');
      // open task with no receipt → a live obligation exists again.
      expect(
        await _liveObligationCount(
          writer,
          beaconId: _bMissing,
          accountId: _accountId,
        ),
        1,
      );
      expect(
        await _liveObligationCount(
          writer,
          beaconId: _bReviewOpen,
          accountId: _accountId,
        ),
        1,
      );
      expect(
        await _liveObligationCount(
          writer,
          beaconId: _bMultiAudience,
          accountId: _accountId,
        ),
        1,
      );
      expect(
        await _outboxCountForAccountOnBeacon(
          writer,
          accountId: _stewardB,
          beaconId: _bMultiAudience,
        ),
        0,
      );
      expect(
        await _outboxCountForAccountOnBeacon(
          writer,
          accountId: _stewardC,
          beaconId: _bMultiAudienceC,
        ),
        0,
      );
      expect(first.createdObligationCount, 4);
      expect(first.settledObligationCount, 4);

      // --- what must not be touched --------------------------------------
      // A receipt settled with the wrong reason stays as it is: the source
      // no longer says which transition ended it, and History is not ours to
      // rewrite. Reported, not repaired.
      expect(await _settlement(writer, 'Nrecnwrong'), 'resolved');
      // A pre-U05c row with no logical_task_key: unnameable task, left for
      // U18 and counted.
      expect(await _settlement(writer, 'Nrecnlegcy'), isNull);
      expect(first.unrepairableObligationCount, 1);
      // A live obligation whose task is genuinely open stays live — a correct
      // result is non-zero.
      expect(await _settlement(writer, 'Nrecnhealt'), isNull);
      expect(first.summary.needsYouTotal, greaterThan(0));
      // The account's own clear survives.
      expect(await _clearedAt(writer, 'Nrecnclear'), isNotNull);
      // The account's own dismissed tombstone survives.
      expect(
        await _scalar(writer, '''
SELECT count(*)::int FROM public.inbox_item
WHERE user_id = '$_accountId' AND tombstone_dismissed_at IS NOT NULL
'''),
        1,
      );
      // Author declined the offer (system resolved) — not a user-dismissed row.
      expect(await _settlement(writer, 'Nrecndecl'), 'resolved');
      expect(
        await _cell(
          writer,
          "SELECT COALESCE(settled_by_user_id, '-') FROM public.notification_outbox WHERE id = 'Nrecndecl'",
        ),
        '-',
        reason: 'decline settlement is system-owned, not user-dismissed',
      );
      // Inbox stance (status) is not derived obligation state.
      expect(
        await _scalar(
          writer,
          "SELECT status::int FROM public.inbox_item WHERE user_id = '$_accountId' AND beacon_id = '$_bInboxStance'",
        ),
        1,
      );
      // An obligation this account settled itself is neither reopened nor
      // re-created beside itself.
      expect(await _settlement(writer, 'Nrecnusrst'), 'dismissed');
      expect(
        await _liveObligationCount(
          writer,
          beaconId: _bUserSettled,
          accountId: _accountId,
        ),
        0,
      );
      // Another account's corruption is not this account's to repair.
      expect(await _settlement(writer, 'Nrecnforgn'), isNull);

      // --- idempotence ---------------------------------------------------
      final second = await reconciliation.reconcileAccount(
        accountId: _accountId,
      );
      expect(second.createdObligationCount, 0);
      expect(second.settledObligationCount, 0);
      expect(second.unrepairableObligationCount, 1);
      expect(second.summary.needsYouTotal, first.summary.needsYouTotal);
      expect(second.summary.myWorkUnreadTotal, first.summary.myWorkUnreadTotal);
      expect(
        second.summary.activityUnreadTotal,
        first.summary.activityUnreadTotal,
      );

      final afterFirst = await _fingerprint(writer);
      expect(afterFirst, isNot(before), reason: 'the first pass must repair');
      expect(
        await _fingerprint(writer),
        afterFirst,
        reason: 'a second invocation must change nothing',
      );
    }, skip: skipReason);

    test('an empty account id is refused', () async {
      await expectLater(
        reconciliation.reconcileAccount(accountId: '  '),
        throwsA(isA<ArgumentError>()),
      );
    }, skip: skipReason);
  });

  group('obligation reconciliation — finisher guards', () {
    late Connection writer;
    late TenturaDb database;
    late ObligationReconciliationCase reconciliation;

    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);
      database = TenturaDb(target.databaseEnv);
      final logger = Logger('AttentionReconciliationFinisherPgTest');
      final dispatch = AttentionDispatchRepository(database, logger);
      final helpOffers = HelpOfferRepository(database);
      final intents = AttentionIntentCase(
        BeaconRoomNotificationContextRepository(
          BeaconRoomRepository(database),
          database,
          helpOffers,
          CommitmentRepository(database),
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
      reconciliation = ObligationReconciliationCase(
        AttentionSystemSettlementRepository(database),
        AttentionReconciliationRepository(database),
        AttentionRepository(database),
        TransactionalAttentionCase(MutatingUnitOfWork(database), dispatch),
        intents,
        env: target.databaseEnv,
        logger: logger,
      );
      await _seedFixture(writer);
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });

    test('a second repair of the same open task is not deduped away', () async {
      final first = await reconciliation.reconcileAccount(accountId: _accountId);
      expect(
        await _liveObligationCount(
          writer,
          beaconId: _bMissing,
          accountId: _accountId,
        ),
        1,
      );
      final keyAfterFirst = await _cell(
        writer,
        '''
SELECT occ.source_event_key
FROM public.notification_outbox AS nb
JOIN public.attention_occurrence AS occ ON occ.id = nb.occurrence_id
WHERE nb.account_id = '$_accountId' AND nb.beacon_id = '$_bMissing'
  AND nb.requires_action AND nb.settlement_kind IS NULL
''',
      );
      expect(keyAfterFirst, contains(':g1'));

      await writer.execute('''
UPDATE public.notification_outbox
SET settlement_kind = 'resolved', settled_at = now()
WHERE account_id = '$_accountId' AND beacon_id = '$_bMissing'
  AND requires_action AND settlement_kind IS NULL
''');

      final second = await reconciliation.reconcileAccount(
        accountId: _accountId,
      );
      expect(second.createdObligationCount, 1);
      expect(
        await _liveObligationCount(
          writer,
          beaconId: _bMissing,
          accountId: _accountId,
        ),
        1,
      );
      final keyAfterSecond = await _cell(
        writer,
        '''
SELECT occ.source_event_key
FROM public.notification_outbox AS nb
JOIN public.attention_occurrence AS occ ON occ.id = nb.occurrence_id
WHERE nb.account_id = '$_accountId' AND nb.beacon_id = '$_bMissing'
  AND nb.requires_action AND nb.settlement_kind IS NULL
''',
      );
      expect(keyAfterSecond, contains(':g2'));
      expect(keyAfterSecond, isNot(keyAfterFirst));
      expect(first.createdObligationCount, greaterThan(0));
    }, skip: skipReason);

    test(
      'creation intent audience includes stewards but repair writes only '
      'for the reconciled account',
      () async {
        expect(
          await _outboxCountForAccountOnBeacon(
            writer,
            accountId: _stewardB,
            beaconId: _bMultiAudience,
          ),
          0,
        );
        expect(
          await _outboxCountForAccountOnBeacon(
            writer,
            accountId: _stewardC,
            beaconId: _bMultiAudienceC,
          ),
          0,
        );

        await reconciliation.reconcileAccount(accountId: _accountId);

        expect(
          await _outboxCountForAccountOnBeacon(
            writer,
            accountId: _stewardB,
            beaconId: _bMultiAudience,
          ),
          0,
        );
        expect(
          await _outboxCountForAccountOnBeacon(
            writer,
            accountId: _stewardC,
            beaconId: _bMultiAudienceC,
          ),
          0,
        );
        expect(
          await _liveObligationCount(
            writer,
            beaconId: _bMultiAudience,
            accountId: _accountId,
          ),
          1,
        );
        expect(
          await _liveObligationCount(
            writer,
            beaconId: _bMultiAudienceC,
            accountId: _accountId,
          ),
          1,
        );
      },
      skip: skipReason,
    );

    test(
      'removedFromChat without withdraw_reason settles superseded not resolved',
      () async {
        await reconciliation.reconcileAccount(accountId: _accountId);
        expect(await _settlement(writer, 'Nrecnrmvd'), 'superseded');
      },
      skip: skipReason,
    );

    test('author-declined help-offer settlement survives repair', () async {
      await reconciliation.reconcileAccount(accountId: _accountId);
      expect(await _settlement(writer, 'Nrecndecl'), 'resolved');
      expect(
        await _cell(
          writer,
          "SELECT COALESCE(settled_by_user_id, '-') FROM public.notification_outbox WHERE id = 'Nrecndecl'",
        ),
        '-',
      );
    }, skip: skipReason);

    test('inbox_item.status survives repair', () async {
      await reconciliation.reconcileAccount(accountId: _accountId);
      expect(
        await _scalar(
          writer,
          "SELECT status::int FROM public.inbox_item WHERE user_id = '$_accountId' AND beacon_id = '$_bInboxStance'",
        ),
        1,
      );
    }, skip: skipReason);
  });
}

// ---------------------------------------------------------------------------
// fixture
// ---------------------------------------------------------------------------

Future<void> _seedFixture(Connection writer) async {
  for (final id in [
    _accountId,
    _otherAccountId,
    _helperStale,
    _helperAnswered,
    _helperMissing,
    _helperWrongReason,
    _helperLegacy,
    _helperHealthy,
    _helperUserSettled,
    _helperForeign,
    _helperMultiAudience,
    _helperMultiAudienceC,
    _helperRemoved,
    _helperDeclined,
    _stewardB,
    _stewardC,
  ]) {
    await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'key-$id')
''');
  }

  Future<void> beacon(String id, String authorId, BeaconStatus status) =>
      writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES ('$id', '$authorId', 'Request $id', 'desc', ${status.smallintValue})
''');

  await beacon(_bStale, _accountId, BeaconStatus.open);
  await beacon(_bAnswered, _accountId, BeaconStatus.open);
  await beacon(_bMissing, _accountId, BeaconStatus.open);
  await beacon(_bWrongReason, _accountId, BeaconStatus.open);
  await beacon(_bLegacy, _accountId, BeaconStatus.open);
  await beacon(_bHealthy, _accountId, BeaconStatus.open);
  await beacon(_bUserSettled, _accountId, BeaconStatus.open);
  await beacon(_bCleared, _accountId, BeaconStatus.open);
  await beacon(_bForeign, _otherAccountId, BeaconStatus.open);
  await beacon(_bMultiAudience, _accountId, BeaconStatus.open);
  await beacon(_bMultiAudienceC, _accountId, BeaconStatus.open);
  await beacon(_bRemoved, _accountId, BeaconStatus.open);
  await beacon(_bDeclined, _accountId, BeaconStatus.open);
  await beacon(_bInboxStance, _accountId, BeaconStatus.open);
  await beacon(_bReviewClosed, _otherAccountId, BeaconStatus.closed);
  await beacon(_bReviewOpen, _otherAccountId, BeaconStatus.reviewOpen);

  await writer.execute('''
INSERT INTO public.beacon_steward (beacon_id, user_id) VALUES
  ('$_bMultiAudience', '$_stewardB'),
  ('$_bMultiAudienceC', '$_stewardC')
''');

  Future<void> offer(
    String beaconId,
    String userId, {
    int status = 0,
    String? withdrawReason,
    int stakeState = 1,
  }) => writer.execute(
    Sql.named('''
INSERT INTO public.beacon_help_offer
  (beacon_id, user_id, message, status, offer_kind, stake_state, withdraw_reason)
VALUES (@beaconId, @userId, 'offer', @status, 0, @stakeState, @withdrawReason)
'''),
    parameters: {
      'beaconId': beaconId,
      'userId': userId,
      'status': status,
      'stakeState': stakeState,
      'withdrawReason': withdrawReason,
    },
  );

  // C1 — the helper withdrew, the receipt stayed live.
  await offer(_bStale, _helperStale, status: 1, withdrawReason: 'changed mind');
  // C2 — the author accepted, the receipt stayed live.
  await offer(_bAnswered, _helperAnswered, stakeState: 2);
  await writer.execute('''
INSERT INTO public.beacon_commitment_event
  (id, beacon_id, user_id, actor_user_id, kind)
VALUES ('Crecnanswr01', '$_bAnswered', '$_helperAnswered', '$_accountId', 1)
''');
  // C3 — a live source task with no obligation receipt at all.
  await offer(_bMissing, _helperMissing);
  // Multi-audience creation path — stewards B/C in intent, repair scoped to A.
  await offer(_bMultiAudience, _helperMultiAudience);
  await offer(_bMultiAudienceC, _helperMultiAudienceC);
  // C4 — settled with the wrong reason (the helper withdrew; the row says
  // the author answered).
  await offer(
    _bWrongReason,
    _helperWrongReason,
    status: 1,
    withdrawReason: 'changed mind',
  );
  // C5 — pre-U05c legacy row, withdrawn offer, no logical_task_key.
  await offer(
    _bLegacy,
    _helperLegacy,
    status: 1,
    withdrawReason: 'changed mind',
  );
  // C8 — genuinely open, correctly backed. Must stay live.
  await offer(_bHealthy, _helperHealthy);
  // M3 — open task whose obligation this account settled itself.
  await offer(_bUserSettled, _helperUserSettled);
  // M4 — another account's identical corruption.
  await offer(
    _bForeign,
    _helperForeign,
    status: 1,
    withdrawReason: 'changed mind',
  );
  // Removal — status inactive, no withdraw_reason, terminal commitment event.
  await offer(_bRemoved, _helperRemoved, status: 1);
  await writer.execute('''
INSERT INTO public.beacon_commitment_event
  (id, beacon_id, user_id, actor_user_id, kind)
VALUES ('Crecnrmvd01', '$_bRemoved', '$_helperRemoved', '$_accountId', 5)
''');
  // Author declined — system-resolved obligation must not be rewritten.
  await offer(_bDeclined, _helperDeclined, status: 1);

  await _receipt(
    writer,
    id: 'Nrecnstale',
    accountId: _accountId,
    beaconId: _bStale,
    targetEntityId: _helperStale,
  );
  await _receipt(
    writer,
    id: 'Nrecnanswr',
    accountId: _accountId,
    beaconId: _bAnswered,
    targetEntityId: _helperAnswered,
  );
  await _receipt(
    writer,
    id: 'Nrecnwrong',
    accountId: _accountId,
    beaconId: _bWrongReason,
    targetEntityId: _helperWrongReason,
    settlementKind: 'resolved',
  );
  await _receipt(
    writer,
    id: 'Nrecnlegcy',
    accountId: _accountId,
    beaconId: _bLegacy,
    targetEntityId: _helperLegacy,
    logicalTaskKey: null,
  );
  await _receipt(
    writer,
    id: 'Nrecnhealt',
    accountId: _accountId,
    beaconId: _bHealthy,
    targetEntityId: _helperHealthy,
  );
  await _receipt(
    writer,
    id: 'Nrecnusrst',
    accountId: _accountId,
    beaconId: _bUserSettled,
    targetEntityId: _helperUserSettled,
    settlementKind: 'dismissed',
    settledByUserId: _accountId,
  );
  await _receipt(
    writer,
    id: 'Nrecnforgn',
    accountId: _otherAccountId,
    beaconId: _bForeign,
    targetEntityId: _helperForeign,
  );
  await _receipt(
    writer,
    id: 'Nrecnrmvd',
    accountId: _accountId,
    beaconId: _bRemoved,
    targetEntityId: _helperRemoved,
  );
  await _receipt(
    writer,
    id: 'Nrecndecl',
    accountId: _accountId,
    beaconId: _bDeclined,
    targetEntityId: _helperDeclined,
    settlementKind: 'resolved',
  );

  // C6 — review window closed, obligation still live.
  await writer.execute('''
INSERT INTO public.beacon_review_window
  (beacon_id, opened_at, closes_at, status, extensions_used)
VALUES ('$_bReviewClosed', now() - interval '2 days', now() - interval '1 day', 1, 0)
''');
  await writer.execute('''
INSERT INTO public.beacon_review_status (beacon_id, user_id, status)
VALUES ('$_bReviewClosed', '$_accountId', 4)
''');
  await _receipt(
    writer,
    id: 'Nrecnrvcls',
    accountId: _accountId,
    beaconId: _bReviewClosed,
    eventType: 'reviewOpened',
    presentationKey: 'review_opened',
    logicalTaskKey:
        'v1|reviewOpened|$_bReviewClosed|$_bReviewClosed|$_accountId',
  );

  // C7 — review window open, no obligation receipt.
  await writer.execute('''
INSERT INTO public.beacon_review_window
  (beacon_id, opened_at, closes_at, status, extensions_used)
VALUES ('$_bReviewOpen', now() - interval '1 day', now() + interval '1 day', 0, 0)
''');
  await writer.execute('''
INSERT INTO public.beacon_review_status (beacon_id, user_id, status) VALUES
  ('$_bReviewOpen', '$_accountId', 0),
  ('$_bReviewOpen', '$_stewardB', 0),
  ('$_bReviewOpen', '$_stewardC', 0)
''');

  // M1 — an optional receipt this account cleared.
  await _receipt(
    writer,
    id: 'Nrecnclear',
    accountId: _accountId,
    beaconId: _bCleared,
    eventType: 'roomMessagePosted',
    presentationKey: 'room_message_posted',
    requiresAction: false,
    logicalTaskKey: null,
    clearedAt: '2026-09-01T10:00:00Z',
  );

  // M2 — an Inbox tombstone this account dismissed.
  await writer.execute('''
INSERT INTO public.inbox_item (user_id, beacon_id, status)
VALUES ('$_accountId', '$_bCleared', 0)
''');
  await writer.execute('''
UPDATE public.inbox_item SET tombstone_dismissed_at = now()
WHERE user_id = '$_accountId' AND beacon_id = '$_bCleared'
''');

  // Explicit inbox stance (watching) — not a tombstone dismiss.
  await writer.execute('''
INSERT INTO public.inbox_item (user_id, beacon_id, status)
VALUES ('$_accountId', '$_bInboxStance', 1)
''');
}

int _occurrenceSeq = 0;

Future<void> _receipt(
  Connection writer, {
  required String id,
  required String accountId,
  required String beaconId,
  String eventType = 'helpOfferSubmitted',
  String presentationKey = 'help_offer_submitted',
  String? targetEntityId,
  String? logicalTaskKey = '',
  String? settlementKind,
  String? settledByUserId,
  String? clearedAt,
  bool requiresAction = true,
}) async {
  final sourceEventKey = 'fixture:${_occurrenceSeq++}:$id';
  final occurrence = await writer.execute(
    Sql.named('''
INSERT INTO public.attention_occurrence
  (source_event_key, event_type, actor_user_id, immutable_payload)
VALUES (@key, @eventType, NULL, '{"eventType":"fixture"}'::jsonb)
RETURNING id
'''),
    parameters: {'key': sourceEventKey, 'eventType': eventType},
  );
  final occurrenceId = occurrence.single[0]! as String;
  final key = logicalTaskKey == ''
      ? 'v1|$eventType|$beaconId|$targetEntityId|$accountId'
      : logicalTaskKey;
  await writer.execute(
    Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at,
  beacon_id, source_event_key, occurrence_id, target_entity_id,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy,
  requires_action, attention_thread_key,
  logical_task_key, lifecycle_generation,
  settlement_kind, settled_at, settled_by_user_id, cleared_at, clear_reason
) VALUES (
  @id, @accountId, 'asksOfMe', 'commitmentEvent', 'normal',
  'Obligation', 'Obligation body', '/attention', @dedupKey,
  '2026-08-16T12:00:00Z'::timestamptz,
  @beaconId, @sourceEventKey, @occurrenceId, CAST(@targetEntityId AS text),
  'beacon', @presentationKey, '{"eventType":"fixture"}'::jsonb,
  'standard', 'beacon_content',
  @requiresAction, CAST(@threadKey AS text),
  CAST(@logicalTaskKey AS text), CAST(@generation AS int),
  CAST(@settlementKind AS text),
  CASE WHEN CAST(@settlementKind AS text) IS NULL THEN NULL
       ELSE '2026-08-20T12:00:00Z'::timestamptz END,
  CAST(@settledByUserId AS text),
  CAST(@clearedAt AS timestamptz),
  CASE WHEN CAST(@clearedAt AS timestamptz) IS NULL THEN NULL ELSE 'sweep' END
)
'''),
    parameters: {
      'id': id,
      'accountId': accountId,
      'dedupKey': 'dedup-$id',
      'beaconId': beaconId,
      'sourceEventKey': sourceEventKey,
      'occurrenceId': occurrenceId,
      'targetEntityId': targetEntityId,
      'presentationKey': presentationKey,
      'requiresAction': requiresAction,
      'threadKey': requiresAction ? 'v1|$eventType|$beaconId|$accountId' : null,
      'logicalTaskKey': key,
      'generation': key == null ? null : 1,
      'settlementKind': settlementKind,
      'settledByUserId': settledByUserId,
      'clearedAt': clearedAt,
    },
  );
}

// ---------------------------------------------------------------------------
// probes
// ---------------------------------------------------------------------------

Future<String?> _settlement(Connection writer, String receiptId) async {
  final rows = await writer.execute(
    "SELECT settlement_kind FROM public.notification_outbox WHERE id = '$receiptId'",
  );
  return rows.single[0] as String?;
}

Future<Object?> _clearedAt(Connection writer, String receiptId) async {
  final rows = await writer.execute(
    "SELECT cleared_at FROM public.notification_outbox WHERE id = '$receiptId'",
  );
  return rows.single[0];
}

Future<int> _liveObligationCount(
  Connection writer, {
  required String beaconId,
  required String accountId,
}) => _scalar(writer, '''
SELECT count(*)::int FROM public.notification_outbox
WHERE beacon_id = '$beaconId' AND account_id = '$accountId'
  AND requires_action AND settlement_kind IS NULL
''');

Future<int> _outboxCountForAccountOnBeacon(
  Connection writer, {
  required String accountId,
  required String beaconId,
}) => _scalar(writer, '''
SELECT count(*)::int FROM public.notification_outbox
WHERE account_id = '$accountId' AND beacon_id = '$beaconId'
''');

Future<String> _cell(Connection writer, String sql) async {
  final rows = await writer.execute(sql);
  return rows.single[0]! as String;
}

Future<int> _scalar(Connection writer, String sql) async {
  final rows = await writer.execute(sql);
  return rows.single[0]! as int;
}

/// Everything repair could possibly move, in one comparable string.
Future<String> _fingerprint(Connection writer) async {
  final receipts = await writer.execute('''
SELECT
  id, account_id, beacon_id, requires_action,
  COALESCE(settlement_kind, '-'),
  COALESCE(settled_by_user_id, '-'),
  CASE WHEN cleared_at IS NULL THEN 'live' ELSE 'cleared' END,
  CASE WHEN seen_at IS NULL THEN 'unseen' ELSE 'seen' END,
  COALESCE(logical_task_key, '-'),
  COALESCE(lifecycle_generation, -1)
FROM public.notification_outbox
ORDER BY account_id, beacon_id, id
''');
  final inbox = await writer.execute('''
SELECT user_id, beacon_id, status,
  CASE WHEN tombstone_dismissed_at IS NULL THEN 'live' ELSE 'dismissed' END
FROM public.inbox_item
ORDER BY user_id, beacon_id
''');
  final offers = await writer.execute('''
SELECT beacon_id, user_id, status, stake_state, COALESCE(withdraw_reason, '-')
FROM public.beacon_help_offer
ORDER BY beacon_id, user_id
''');
  String render(Result result) =>
      result.map((row) => row.map((cell) => '$cell').join('|')).join('\n');
  return [render(receipts), render(inbox), render(offers)].join('\n--\n');
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
        Platform.environment['TENTURA_ATTENTION_RECONCILE_TEST_DB'] ??
        'tentura_test_attn_reconcile_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_ATTENTION_RECONCILE_TEST_DB',
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
