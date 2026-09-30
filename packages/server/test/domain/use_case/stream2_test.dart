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
import 'package:tentura_server/data/repository/evaluation_repository.dart';
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
import 'package:tentura_server/domain/port/closure_finalizer_port.dart';
import 'package:tentura_server/domain/port/closure_receipts_port.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/closure_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/coordination_case.dart';
import 'package:tentura_server/domain/use_case/help_offer_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_user_block_repository.dart';

/// A15 / Arch §5.7: stream 2 — approving a help offer writes
/// `approval:<beacon>:<helper>` (`useful_forward`, helper → forwarder).
const _authorId = 'Ustr2author1';
const _helperId = 'Ustr2helper1';
const _forwarderId = 'Ustr2fwdr001';
const _forwarder2Id = 'Ustr2fwdr002';
const _beaconId = 'Bstr2beacon1';
const _beacon2Id = 'Bstr2beacon2';
const _usefulForward = 5;

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_STREAM2_TEST_DB',
    defaultNamePrefix: 'tentura_test_stream2',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('stream 2 approval edge', () {
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

    Future<void> offer(String beaconId) =>
        harness.helpOfferCase.offerHelp(beaconId: beaconId, userId: _helperId);

    Future<void> approve(String beaconId) async {
      await harness.coordinationCase.acceptHelpOffer(
        beaconId: beaconId,
        offerUserId: _helperId,
        actorUserId: _authorId,
      );
    }

    test('approve creates helper -> forwarder useful_forward', () async {
      await _forward(writer, _beaconId, _forwarderId, _helperId);
      await offer(_beaconId);
      await approve(_beaconId);

      final rows = await _edgeRows(writer);
      expect(rows, hasLength(1));
      expect(rows.single.key, 'approval:$_beaconId:$_helperId');
      expect(rows.single.subject, _helperId);
      expect(rows.single.object, _forwarderId);
      expect(rows.single.related, _forwarderId);
      expect(rows.single.count, 1);
      expect(rows.single.retracted, isFalse);
      expect(rows.single.arrivalEdgeId, 'Fedge0000001');
    }, skip: skipReason);

    test('voluntary withdrawal retracts the edge', () async {
      await _forward(writer, _beaconId, _forwarderId, _helperId);
      await offer(_beaconId);
      await approve(_beaconId);

      await harness.helpOfferCase.withdraw(
        beaconId: _beaconId,
        userId: _helperId,
        withdrawReason: 'timing',
      );

      final rows = await _edgeRows(writer);
      expect(rows, hasLength(1));
      expect(rows.single.retracted, isTrue);
    }, skip: skipReason);

    test(
      're-accept after withdrawal restores the original occurred_at',
      () async {
        await _forward(writer, _beaconId, _forwarderId, _helperId);
        await offer(_beaconId);
        await approve(_beaconId);
        await writer.execute('''
UPDATE public.trust_evidence SET occurred_at = now() - interval '10 days'
WHERE source_key = 'approval:$_beaconId:$_helperId'
''');
        final original = (await _edgeRows(writer)).single.occurredAt;

        await harness.helpOfferCase.withdraw(
          beaconId: _beaconId,
          userId: _helperId,
          withdrawReason: 'timing',
        );
        await offer(_beaconId);
        await approve(_beaconId);

        final rows = await _edgeRows(writer);
        expect(rows, hasLength(1), reason: 'same row, not a second one');
        expect(rows.single.retracted, isFalse);
        expect(rows.single.occurredAt, original);
      },
      skip: skipReason,
    );

    test('author removal keeps the edge', () async {
      await _forward(writer, _beaconId, _forwarderId, _helperId);
      await offer(_beaconId);
      await approve(_beaconId);

      await harness.coordinationCase.removeFromRoom(
        beaconId: _beaconId,
        offerUserId: _helperId,
        actorUserId: _authorId,
        reason: 'no longer needed',
      );

      final rows = await _edgeRows(writer);
      expect(rows, hasLength(1));
      expect(rows.single.retracted, isFalse);
    }, skip: skipReason);

    test('helper who came without a forward gets no edge', () async {
      await offer(_beaconId);
      await approve(_beaconId);

      expect(await _edgeRows(writer), isEmpty);
    }, skip: skipReason);

    test(
      'two requests approved concurrently within 30 days -> one live row',
      () async {
        await _forward(writer, _beaconId, _forwarderId, _helperId);
        await _forward(
          writer,
          _beacon2Id,
          _forwarderId,
          _helperId,
          id: 'Fedge0000002',
        );
        await offer(_beaconId);
        await offer(_beacon2Id);

        await Future.wait([approve(_beaconId), approve(_beacon2Id)]);

        final acks = await writer.execute('''
SELECT beacon_id FROM public.beacon_commitment_event
WHERE user_id = '$_helperId' AND kind = 1
''');
        expect(
          acks.map((r) => r[0]! as String).toSet(),
          {_beaconId, _beacon2Id},
          reason: 'both concurrent approvals must have completed',
        );

        final live = (await _edgeRows(writer)).where((r) => !r.retracted);
        expect(live, hasLength(1));
        expect(live.single.subject, _helperId);
        expect(live.single.object, _forwarderId);
      },
      skip: skipReason,
    );
  }, skip: skipReason);
}

typedef _EdgeRow = ({
  String key,
  String subject,
  String object,
  String? related,
  double count,
  bool retracted,
  DateTime occurredAt,
  String? arrivalEdgeId,
});

Future<List<_EdgeRow>> _edgeRows(Connection writer) async {
  final rows = await writer.execute('''
SELECT source_key, subject_user_id, object_user_id, related_user_id, count,
       retracted_at IS NOT NULL, occurred_at, metadata->>'arrival_edge_id'
FROM public.trust_evidence
WHERE kind = $_usefulForward AND source_key LIKE 'approval:%'
ORDER BY source_key
''');
  return [
    for (final r in rows)
      (
        key: r[0]! as String,
        subject: r[1]! as String,
        object: r[2]! as String,
        related: r[3] as String?,
        count: (r[4]! as num).toDouble(),
        retracted: r[5]! as bool,
        occurredAt: r[6]! as DateTime,
        arrivalEdgeId: r[7] as String?,
      ),
  ];
}

Future<void> _forward(
  Connection writer,
  String beaconId,
  String senderId,
  String recipientId, {
  String id = 'Fedge0000001',
  String createdAgo = '1 hour',
  String? cancelledAgo,
}) => writer.execute('''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at, cancelled_at
) VALUES (
  '$id', '$beaconId', '$senderId', '$recipientId',
  now() - interval '$createdAgo',
  ${cancelledAgo == null ? 'NULL' : "now() - interval '$cancelledAgo'"}
)
''');

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
  for (final id in [_authorId, _helperId, _forwarderId, _forwarder2Id]) {
    await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'key-$id')
''');
  }
  for (final id in [_beaconId, _beacon2Id]) {
    await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (
  '$id', '$_authorId', 'Stream2 beacon', 'desc',
  ${BeaconStatus.open.smallintValue}
)
''');
  }
}

final class _Harness {
  const _Harness({
    required this.helpOfferCase,
    required this.coordinationCase,
  });

  final HelpOfferCase helpOfferCase;
  final CoordinationCase coordinationCase;

  static _Harness build(TenturaDb db, Env env) {
    final logger = Logger('Stream2PgTest');
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
    final evalRepo = EvaluationRepository(db);
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
        closureCase: closureCase,
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
        evalRepo,
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
