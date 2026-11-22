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
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/attention_settlement_case.dart';

import '../../support/fake_user_block_repository.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/mocks/invite_seed_prompt_repository_mock.dart';

const _beaconId = 'Broblgbcn001';
const _authorId = 'Uroblgauth01';
const _reviewer1 = 'Uroblgrevw01';
const _reviewer2 = 'Uroblgrevw02';
const _subjectId = 'Uroblgsubj01';

/// Live help-offer settlement surface plus the user-settle guard.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_OFFER_OBLIGATION_DISMISS_TEST_DB',
    defaultNamePrefix: 'tentura_test_offer_obl_dismiss',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('dismissing a help-offer obligation as its recipient', () {
    late Connection writer;
    late TenturaDb database;
    late AttentionDispatchRepository dispatch;
    late AttentionIntentCase intents;

    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);

      database = TenturaDb(target.databaseEnv);
      final logger = Logger('OfferObligationDismissPgTest');
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
          _NoopInviteGenealogyRepository(),
          InviteSeedPromptRepositoryMock(),
        ),
        BeaconAccessRepository(database),
        FakeUserBlockRepository(),
      );
    });

    setUp(() async => _resetFixture(writer));

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });

    AttentionSettlementCase settlementCase() => AttentionSettlementCase(
      AttentionSettlementRepository(database),
      env: target.databaseEnv,
      logger: Logger('OfferObligationDismissPgTest'),
    );

    Future<String> offerReceipt(String key) async {
      await dispatch.record(
        await intents.helpOfferSubmitted(
          beaconId: _beaconId,
          helpOffererId: _reviewer2,
          authorId: _authorId,
          sourceEventKey: key,
        ),
      );
      final id = await _liveReceiptId(writer, _authorId);
      expect(id, isNotNull);
      return id!;
    }

    // The offer behind the receipt, in each state the card can meet it in.
    const states = {
      'pending': (status: 0, stake: 1),
      'admitted': (status: 0, stake: 2),
      'withdrawn': (status: 1, stake: 1),
    };

    Future<void> setOfferState(({int status, int stake}) state) =>
        writer.execute('''
INSERT INTO public.beacon_help_offer
  (beacon_id, user_id, message, status, stake_state)
VALUES ('$_beaconId', '$_reviewer2', 'I can sew', ${state.status}, ${state.stake})
''');

    for (final entry in states.entries) {
      test('the recipient dismisses the receipt of a ${entry.key} offer, '
          'and only they can', () async {
        await setOfferState(entry.value);
        final receiptId = await offerReceipt('help_offer:${entry.key}');

        // Another user is turned away first; the receipt stays live.
        Object? foreignError;
        var foreignUpdated = 0;
        try {
          foreignUpdated = await settlementCase().settle(
            accountId: _reviewer1,
            receiptId: receiptId,
            kind: AttentionSettlementKind.dismissed,
          );
        } on Object catch (e) {
          foreignError = e;
        }
        expect(foreignError != null || foreignUpdated == 0, isTrue);
        expect(await _liveReceiptId(writer, _authorId), receiptId);

        // The owner then closes it, and it leaves the unsettled set.
        final updated = await settlementCase().settle(
          accountId: _authorId,
          receiptId: receiptId,
          kind: AttentionSettlementKind.dismissed,
        );

        expect(updated, 1);
        expect(await _settlementKind(writer, _authorId), 'dismissed');
        expect(await _liveReceiptId(writer, _authorId), isNull);
      }, skip: skipReason);
    }
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

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}
