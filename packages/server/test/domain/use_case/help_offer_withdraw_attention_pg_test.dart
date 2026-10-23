@Tags(['pg'])
library;

import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/attention_system_settlement_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/coordination_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/person_capability_event_repository.dart';
import 'package:tentura_server/data/repository/user_availability_repository.dart';
import 'package:tentura_server/data/repository/user_profile_batch_lookup.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/data/repository/vote_user_friendship_lookup.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/capability_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/coordination_case.dart';
import 'package:tentura_server/domain/use_case/help_offer_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_user_block_repository.dart';

const _beaconId = 'Bhowdattn01';
const _authorId = 'Uhowdauth01';
const _helperId = 'Uhowdhelp01';
const _helper2Id = 'Uhowdhelp02';

/// #516 — a withdrawal tells the author who left, why, and whether the next
/// step still names them: a `helpWithdrawn` optional update (never an
/// obligation), with the reason key, the helper's note and two flags.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_HELP_WITHDRAW_ATTENTION_TEST_DB',
    defaultNamePrefix: 'tentura_test_help_wd_attn',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('helpWithdrawn receipt (#516)', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late _Harness harness;

    setUpAll(() async {
      if (skipReason != false) return;
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      harness = _Harness.build(database, target.databaseEnv);
    });

    setUp(() async {
      if (skipReason != false) return;
      await _resetFixture(writer);
    });

    tearDownAll(() async {
      if (skipReason != false) return;
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<void> admitHelper() async {
      await harness.helpOfferCase.offerHelp(
        beaconId: _beaconId,
        userId: _helperId,
      );
      await harness.coordinationCase.acceptHelpOffer(
        beaconId: _beaconId,
        offerUserId: _helperId,
        actorUserId: _authorId,
      );
    }

    Future<void> setNextStep(String text) async {
      final repo = BeaconRoomRepository(database);
      await repo.setBeaconRoomCurrentLine(
        beaconId: _beaconId,
        text: text,
        updatedBy: _authorId,
        baseRevision:
            (await repo.getBeaconRoomState(_beaconId))?.currentLineRevision ??
            0,
      );
    }

    test(
      'an admitted helper named in the next step: left, flagged, with '
      'reason and note',
      () async {
        await admitHelper();
        await setNextStep('Omar: dolly, Nina: van');
        await harness.helpOfferCase.withdraw(
          beaconId: _beaconId,
          userId: _helperId,
          withdrawReason: 'timing',
          message: 'Saturday fell through',
        );

        final receipts = await _withdrawnReceipts(writer, _authorId);
        expect(receipts, hasLength(1));
        final r = receipts.single;
        expect(r.requiresAction, isFalse);
        expect(r.targetEntityId, _helperId);
        expect(r.payload['eventType'], 'helpWithdrawn');
        expect(r.payload['withdrawReason'], 'timing');
        expect(r.payload['leftDiscussion'], isTrue);
        expect(r.payload['nextStepMentionsActor'], isTrue);
        expect(r.payload['excerpt'], 'Saturday fell through');
        expect(r.payload['personal'], isFalse);
        // The helper is never told about their own withdrawal.
        expect(await _withdrawnReceipts(writer, _helperId), isEmpty);
      },
      skip: skipReason,
    );

    test(
      'a pending offer withdrawn: not in the discussion, not flagged',
      () async {
        await setNextStep('Omar brings the van');
        await harness.helpOfferCase.offerHelp(
          beaconId: _beaconId,
          userId: _helperId,
        );
        await harness.helpOfferCase.withdraw(
          beaconId: _beaconId,
          userId: _helperId,
          withdrawReason: 'someone_else',
        );

        final receipts = await _withdrawnReceipts(writer, _authorId);
        expect(receipts, hasLength(1));
        final payload = receipts.single.payload;
        expect(payload['withdrawReason'], 'someone_else');
        expect(payload['leftDiscussion'], isFalse);
        // Only a member of the discussion can be "in" its next step.
        expect(payload['nextStepMentionsActor'], isFalse);
        expect(payload['excerpt'], '');
      },
      skip: skipReason,
    );

    test('a next step that names someone else is not flagged', () async {
      await admitHelper();
      await setNextStep('Nina: van 9:45');
      await harness.helpOfferCase.withdraw(
        beaconId: _beaconId,
        userId: _helperId,
        withdrawReason: 'other',
      );
      final payload = (await _withdrawnReceipts(
        writer,
        _authorId,
      )).single.payload;
      expect(payload['leftDiscussion'], isTrue);
      expect(payload['nextStepMentionsActor'], isFalse);
    }, skip: skipReason);
  }, skip: skipReason);
}

typedef _Receipt = ({
  bool requiresAction,
  String? targetEntityId,
  Map<String, Object?> payload,
});

Future<List<_Receipt>> _withdrawnReceipts(
  Connection writer,
  String accountId,
) async {
  final rows = await writer.execute('''
SELECT requires_action, target_entity_id, presentation_payload::text
FROM public.notification_outbox
WHERE beacon_id = '$_beaconId'
  AND account_id = '$accountId'
  AND presentation_key = 'help_withdrawn'
ORDER BY created_at
''');
  return [
    for (final r in rows)
      (
        requiresAction: r[0]! as bool,
        targetEntityId: r[1] as String?,
        payload: (jsonDecode(r[2]! as String) as Map).cast<String, Object?>(),
      ),
  ];
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
  for (final (id, name) in [
    (_authorId, 'Author'),
    (_helperId, 'Omar Dinner'),
    (_helper2Id, 'Nina Mover'),
  ]) {
    await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$name', 'key-$id')
''');
  }
  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (
  '$_beaconId', '$_authorId', 'Moving day', 'desc',
  ${BeaconStatus.open.smallintValue}
)
''');
}

final class _Harness {
  const _Harness({
    required this.helpOfferCase,
    required this.coordinationCase,
    required this.systemSettlement,
  });

  final HelpOfferCase helpOfferCase;
  final CoordinationCase coordinationCase;
  final AttentionSystemSettlementRepository systemSettlement;

  factory _Harness.build(TenturaDb db, Env env) {
    final logger = Logger('HelpOfferObligationSettlementPgTest');
    final unitOfWork = MutatingUnitOfWork(db);
    final dispatch = AttentionDispatchRepository(db, logger);
    final attention = TransactionalAttentionCase(unitOfWork, dispatch);
    final systemSettlement = AttentionSystemSettlementRepository(db);
    final room = BeaconRoomRepository(db);
    final helpOffers = HelpOfferRepository(db);
    final commitments = CommitmentRepository(db);
    final beacons = BeaconRepository(db);
    final access = BeaconAccessRepository(db);
    final hierarchy = BeaconHierarchyRepository(db);
    final attentionIntents = AttentionIntentCase(
      BeaconRoomNotificationContextRepository(
        room,
        db,
        helpOffers,
        commitments,
      ),
      UserRepository(
        env,
        db,
        _NoopInviteGenealogyRepository(),
        InviteSeedPromptRepositoryMock(),
      ),
      access,
      FakeUserBlockRepository(),
    );
    final commitmentQuery = CommitmentQueryCase(
      commitments,
      helpOffers,
      env: env,
      logger: logger,
    );
    return _Harness(
      helpOfferCase: HelpOfferCase(
        helpOffers,
        beacons,
        commitments,
        InboxRepository(db),
        CapabilityCase(
          PersonCapabilityEventRepository(db),
          env: env,
          logger: logger,
        ),
        FakeBeaconAccessGuard(),
        roomRepository: room,
        attentionIntents: attentionIntents,
        attention: attention,
        attentionSystemSettlement: systemSettlement,
        env: env,
        logger: logger,
      ),
      coordinationCase: CoordinationCase(
        beacons,
        helpOffers,
        CoordinationRepository(
          db,
          DriftUserProfileBatchLookup(db, UserAvailabilityRepository(db)),
          VoteUserFriendshipLookup(db),
          room,
        ),
        room,
        FakeUserBlockRepository(),
        commitments,
        commitmentQuery,
        hierarchy,
        attentionIntents: attentionIntents,
        attention: attention,
        attentionSystemSettlement: systemSettlement,
        guard: FakeBeaconAccessGuard(),
        env: env,
        logger: logger,
      ),
      systemSettlement: systemSettlement,
    );
  }
}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}
