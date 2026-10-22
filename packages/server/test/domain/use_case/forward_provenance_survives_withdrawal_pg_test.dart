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
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
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
import 'package:tentura_server/domain/use_case/beacon_forward_graph_case.dart';
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

/// #396 / #496: how a Request reached a person is `beacon_forward_edge`
/// history. Offering help, being admitted, withdrawing or declining changes
/// the person's state, never the edge: the author's forward stays in the
/// forwards graph and stays the helper card's "direct forward" fact.
const _authorId = 'Uprov0author';
const _helperId = 'Uprov0helper';
const _otherId = 'Uprov00other';
const _beaconId = 'Bprov0beacon';
const _edgeId = 'Fprov0edge01';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FORWARD_PROVENANCE_TEST_DB',
    defaultNamePrefix: 'tentura_test_fwd_provenance',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('forward provenance survives the recipient leaving', () {
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
      await _forward(writer, _beaconId, _authorId, _helperId, id: _edgeId);
    });

    tearDownAll(() async {
      if (skipReason != false) return;
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<void> offerAndAccept() async {
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

    Future<Set<(String, String)>> graphPairs(String viewerId) async {
      final graph = await harness.forwardGraphCase.asMap(
        beaconId: _beaconId,
        currentUserId: viewerId,
      );
      return {for (final e in graph.edges) (e.senderId, e.recipientId)};
    }

    // The helper card's direct-forward fact (`isDirectAuthorForward`) and
    // the auto-admission rule read this predicate.
    Future<bool> directAuthorForwardOnCard() =>
        ForwardEdgeRepository(database).isDirectAuthorForward(
          beaconId: _beaconId,
          authorId: _authorId,
          userId: _helperId,
        );

    test('an admitted helper keeps the author edge and the direct-forward '
        'fact', () async {
      await offerAndAccept();

      expect(await graphPairs(_authorId), {(_authorId, _helperId)});
      expect(await directAuthorForwardOnCard(), isTrue);
    }, skip: skipReason);

    test('withdrawing after admission leaves the edge in place', () async {
      await offerAndAccept();
      await harness.helpOfferCase.withdraw(
        beaconId: _beaconId,
        userId: _helperId,
        withdrawReason: 'timing',
      );

      final edge = await writer.execute('''
SELECT cancelled_at IS NULL, recipient_rejected
FROM public.beacon_forward_edge WHERE id = '$_edgeId'
''');
      expect(edge, hasLength(1), reason: 'withdrawal never deletes the edge');
      expect(edge.single[0], isTrue, reason: 'nor cancels it');
      expect(edge.single[1], isFalse);
      // The author's "How this request spread" still draws Me -> helper.
      expect(await graphPairs(_authorId), {(_authorId, _helperId)});
      // The withdrawn helper's own graph still shows how it reached them.
      expect(await graphPairs(_helperId), {(_authorId, _helperId)});
      expect(await directAuthorForwardOnCard(), isTrue);
    }, skip: skipReason);

    test('declining keeps the edge, marked declined', () async {
      await writer.execute('''
UPDATE public.inbox_item SET status = 2, rejection_message = 'busy'
WHERE user_id = '$_helperId' AND beacon_id = '$_beaconId'
''');

      final edge = await writer.execute('''
SELECT cancelled_at IS NULL, recipient_rejected
FROM public.beacon_forward_edge WHERE id = '$_edgeId'
''');
      expect(edge.single[0], isTrue);
      expect(edge.single[1], isTrue);
      expect(await graphPairs(_authorId), {(_authorId, _helperId)});
    }, skip: skipReason);

    test('an unrelated viewer is not shown the trail through the graph '
        'seed', () async {
      await offerAndAccept();
      await harness.helpOfferCase.withdraw(
        beaconId: _beaconId,
        userId: _helperId,
        withdrawReason: 'timing',
      );

      // _otherId has no edge and no offer: the graph seeds nothing for them,
      // and a withdrawn helper is no longer an active help offerer either.
      expect(await graphPairs(_otherId), isEmpty);
    }, skip: skipReason);
  }, skip: skipReason);
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
  for (final id in [_authorId, _helperId, _otherId]) {
    await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'key-$id')
''');
  }
  for (final id in [_beaconId]) {
    await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (
  '$id', '$_authorId', 'Provenance beacon', 'desc',
  ${BeaconStatus.open.smallintValue}
)
''');
  }
}

final class _Harness {
  const _Harness({
    required this.helpOfferCase,
    required this.coordinationCase,
    required this.forwardGraphCase,
  });

  final HelpOfferCase helpOfferCase;
  final CoordinationCase coordinationCase;
  final BeaconForwardGraphCase forwardGraphCase;

  factory _Harness.build(TenturaDb db, Env env) {
    final logger = Logger('ForwardProvenancePgTest');
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
    final coordinationRepository = CoordinationRepository(
      db,
      DriftUserProfileBatchLookup(db, UserAvailabilityRepository(db)),
      VoteUserFriendshipLookup(db),
      room,
    );
    return _Harness(
      forwardGraphCase: BeaconForwardGraphCase(
        beacons,
        ForwardEdgeRepository(db),
        helpOffers,
        FakeBeaconAccessGuard(),
        env: env,
        logger: logger,
      ),
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
        coordinationRepository,
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
