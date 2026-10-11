@Tags(['pg'])
library;

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
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/closure_repository.dart';
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
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/closure_finalizer_port.dart';
import 'package:tentura_server/domain/port/closure_receipts_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/use_case/admission_operation.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/capability_case.dart';
import 'package:tentura_server/domain/use_case/closure_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/coordination_case.dart';
import 'package:tentura_server/domain/use_case/help_offer_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/admission_row_set.dart';
import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_user_block_repository.dart';

/// A2 / Arch §5.3: one admission operation, two entry points. The row set an
/// admission leaves behind is pinned against offer + `acceptHelpOffer`, and
/// the shared operation must reproduce it when the helper is the mutating
/// actor and the author is recorded only as data.
const _authorId = 'Uadmrsauth01';
const _helperId = 'Uadmrshelp01';
const _forwarderId = 'Uadmrsfwdr01';
const _stewardId = 'Uadmrsstew01';
const _beaconId = 'Badmrsbeac01';

/// The admission facts, with [confirmer] as the confirming author. Trust
/// evidence: the approval edge (kind 5) credits the forwarder through whom the
/// helper arrived; kind 6 is the engagement the offer insert records.
List<String> _expectedRowSet(String confirmer) => [
  _row('beacon_help_offer', [
    'user=$_helperId',
    'status=0',
    'offer_kind=0',
    'stake_state=2',
  ]),
  _row('beacon_commitment_event', [
    'user=$_helperId',
    'actor=$_helperId',
    'kind=0',
  ]),
  _row('beacon_commitment_event', [
    'user=$_helperId',
    'actor=$confirmer',
    'kind=1',
  ]),
  _row('beacon_help_offer_coordination', [
    'user=$_helperId',
    'author=$confirmer',
    'response_type=0',
  ]),
  _row('beacon_help_offer_admission_event', [
    'user=$_helperId',
    'actor=$confirmer',
    'action=1',
  ]),
  _row('beacon_participant', [
    'user=$_helperId',
    'role=2',
    'status=5',
    'room_access=3',
  ]),
  _row('beacon_activity_event', [
    'user=$_helperId',
    'actor=$confirmer',
    'visibility=1',
    'reason=accept',
  ]),
  _row('trust_evidence', [
    'subject=$_helperId',
    'object=$_forwarderId',
    'related=$_forwarderId',
    'kind=5',
    'count=1.0',
    'retracted=false',
  ]),
  _row('trust_evidence', [
    'subject=$_helperId',
    'object=$_forwarderId',
    'related=null',
    'kind=6',
    'count=1.0',
    'retracted=false',
  ]),
];

String _row(String table, List<String> columns) =>
    [table, ...columns].join('|');

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ADMISSION_ROW_SET_TEST_DB',
    defaultNamePrefix: 'tentura_test_admission_rows',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('admission row set', () {
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

    Future<List<String>> rowSet() => collectAdmissionRowSet(
      writer,
      beaconId: _beaconId,
      helperId: _helperId,
    );

    Future<void> offer() => harness.helpOfferCase.offerHelp(
      beaconId: _beaconId,
      userId: _helperId,
    );

    /// The shared operation, called the way invite accept will call it: the
    /// helper is the authenticated actor, the author confirms as data.
    Future<void> admitAsHelper() => harness.attention.runAction<void>(
      actorUserId: _helperId,
      action: (transaction) async {
        final beacon = await harness.beacons.getBeaconById(
          beaconId: _beaconId,
        );
        await harness.admission.admitWithConfirmations(
          beacon: beacon,
          helperId: _helperId,
          confirmingAuthorId: _authorId,
          actorId: _helperId,
          transaction: transaction,
          attention: () => harness.attentionIntents.offerAccepted(
            receiverId: _helperId,
            beaconId: _beaconId,
            actorUserId: _authorId,
            sourceEventKey: 'admission:test',
          ),
        );
      },
    );

    /// The ordinary accept: the author is the mutating actor, no invite.
    Future<void> admitAsAuthorWithoutInvite() =>
        harness.attention.runAction<void>(
          actorUserId: _authorId,
          action: (transaction) async {
            final beacon = await harness.beacons.getBeaconById(
              beaconId: _beaconId,
            );
            await harness.admission.admitWithConfirmations(
              beacon: beacon,
              helperId: _helperId,
              confirmingAuthorId: _authorId,
              actorId: _authorId,
              transaction: transaction,
              attention: () => harness.attentionIntents.offerAccepted(
                receiverId: _helperId,
                beaconId: _beaconId,
                actorUserId: _authorId,
                sourceEventKey: 'admission:test',
              ),
            );
          },
        );

    test('offer then author accept writes the admission row set', () async {
      await offer();
      await harness.coordinationCase.acceptHelpOffer(
        beaconId: _beaconId,
        offerUserId: _helperId,
        actorUserId: _authorId,
      );

      expect(await rowSet(), _expectedRowSet(_authorId));
    }, skip: skipReason);

    test(
      'a steward accept records the steward as the confirming author',
      () async {
        await writer.execute('''
INSERT INTO public.beacon_steward (beacon_id, user_id)
VALUES ('$_beaconId', '$_stewardId')
''');
        await offer();
        await harness.coordinationCase.acceptHelpOffer(
          beaconId: _beaconId,
          offerUserId: _helperId,
          actorUserId: _stewardId,
        );

        expect(await rowSet(), _expectedRowSet(_stewardId));
      },
      skip: skipReason,
    );

    test(
      'the operation under the helper as actor writes the same row set',
      () async {
        await offer();
        await admitAsHelper();

        expect(await rowSet(), _expectedRowSet(_authorId));
      },
      skip: skipReason,
    );

    test(
      'the operation creates the offer and offered event when none is active',
      () async {
        await admitAsHelper();

        expect(await rowSet(), _expectedRowSet(_authorId));
      },
      skip: skipReason,
    );

    test(
      'an ordinary admission without an active offer is rejected as an '
      'inactive offer and writes nothing',
      () async {
        final before = await rowSet();

        await expectLater(
          admitAsAuthorWithoutInvite(),
          throwsA(
            isA<HelpOfferCoordinationException>().having(
              (e) => e.code.codeNumber,
              'codeNumber',
              HelpOfferCoordinationExceptionCodes(
                HelpOfferCoordinationExceptionCode.helpOfferNotActive,
              ).codeNumber,
            ),
          ),
        );

        expect(await rowSet(), before);
      },
      skip: skipReason,
    );

    test(
      'an ordinary admission after the helper withdrew is rejected as an '
      'inactive offer and does not revive the offer',
      () async {
        await offer();
        await harness.helpOfferCase.withdraw(
          beaconId: _beaconId,
          userId: _helperId,
          withdrawReason: 'cannot_do_it',
        );
        final before = await rowSet();

        await expectLater(
          admitAsAuthorWithoutInvite(),
          throwsA(
            isA<HelpOfferCoordinationException>().having(
              (e) => e.code.codeNumber,
              'codeNumber',
              HelpOfferCoordinationExceptionCodes(
                HelpOfferCoordinationExceptionCode.helpOfferNotActive,
              ).codeNumber,
            ),
          ),
        );

        expect(await rowSet(), before);
      },
      skip: skipReason,
    );
  }, skip: skipReason);
}

Future<void> _resetFixture(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.trust_evidence,
  public.notification_outbox,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.beacon,
  public."user"
CASCADE
''');
  for (final id in [_authorId, _helperId, _forwarderId, _stewardId]) {
    await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'key-$id')
''');
  }
  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (
  '$_beaconId', '$_authorId', 'Admission row set', 'desc',
  ${BeaconStatus.open.smallintValue}
)
''');
  await writer.execute('''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at
) VALUES (
  'Fadmrsedge01', '$_beaconId', '$_forwarderId', '$_helperId',
  now() - interval '1 hour'
)
''');
}

final class _Harness {
  const _Harness({
    required this.helpOfferCase,
    required this.coordinationCase,
    required this.admission,
    required this.attention,
    required this.attentionIntents,
    required this.beacons,
  });

  final HelpOfferCase helpOfferCase;
  final CoordinationCase coordinationCase;
  final AdmissionOperation admission;
  final TransactionalAttentionCase attention;
  final AttentionIntentCase attentionIntents;
  final BeaconRepository beacons;

  factory _Harness.build(TenturaDb db, Env env) {
    final logger = Logger('AdmissionRowSetPgTest');
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
    final coordination = CoordinationRepository(
      db,
      DriftUserProfileBatchLookup(db, UserAvailabilityRepository(db)),
      VoteUserFriendshipLookup(db),
      room,
    );
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
    final closureCase = ClosureCase(
      unitOfWork: unitOfWork,
      closureRepository: ClosureRepository(db),
      beaconRepository: beacons,
      commitmentRepository: commitments,
      helpOfferRepository: helpOffers,
      hierarchyRepository: hierarchy,
      lifecycleEffects: BeaconLifecycleEffectsCase(
        BeaconHierarchyOutboxRepository(db),
        env: env,
        logger: logger,
      ),
      attentionSystemSettlement: systemSettlement,
      receipts: _NoReceipts(),
      finalizer: _NoFinalizer(),
      env: env,
      logger: logger,
    );
    final admission = AdmissionOperation(
      helpOffers,
      coordination,
      commitments,
      closureCase,
      systemSettlement,
    );
    return _Harness(
      admission: admission,
      attention: attention,
      attentionIntents: attentionIntents,
      beacons: beacons,
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
        closureCase: closureCase,
        env: env,
        logger: logger,
      ),
      coordinationCase: CoordinationCase(
        beacons,
        helpOffers,
        coordination,
        room,
        FakeUserBlockRepository(),
        commitments,
        commitmentQuery,
        hierarchy,
        attentionIntents: attentionIntents,
        attention: attention,
        attentionSystemSettlement: systemSettlement,
        guard: FakeBeaconAccessGuard(),
        closureCase: closureCase,
        env: env,
        logger: logger,
      ),
    );
  }
}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}

final class _NoReceipts extends Fake implements ClosureReceiptsPort {}

final class _NoFinalizer extends Fake implements ClosureFinalizerPort {}
