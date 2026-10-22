@Tags(['pg'])
library;

import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/attention_system_settlement_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_people_seen_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/capability_evidence_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/coordination_item_repository.dart';
import 'package:tentura_server/data/repository/coordination_repository.dart';
import 'package:tentura_server/data/repository/forward_attribution_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/person_capability_event_repository.dart';
import 'package:tentura_server/data/repository/person_visibility_repository.dart';
import 'package:tentura_server/data/repository/post_lock_repository.dart';
import 'package:tentura_server/data/repository/user_availability_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_profile_batch_lookup.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/data/repository/vote_user_friendship_lookup.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/entity/gql_public/help_offer_with_coordination_row.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/domain/use_case/capability_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/coordination_case.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/help_offer_case.dart';
import 'package:tentura_server/domain/use_case/post_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_beacon_child_create_port.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'Udeclremauth01';
const _accepted = 'Udeclremacc001';
const _pendingA = 'Udeclrempend01';
const _pendingB = 'Udeclrempend02';
const _backup = 'Udeclrembkup01';
const _addressee = 'Udeclremaddr01';
const _recipient = 'Udeclremrcpt01';
const _users = [
  _author,
  _accepted,
  _pendingA,
  _pendingB,
  _backup,
  _addressee,
  _recipient,
];

const _request = 'Bdeclremreq001';

const _kindRequest = 0;
const _roleAddressee = 6;
const _offerActive = 0;
const _offerWithdrawn = 1;
const _reason = 'Thank you! I have enough help now.';

/// «Decline remaining offers» (#268, D10) over real repositories and a
/// disposable Postgres: after «Enough help» one call declines exactly the
/// offers still waiting for an answer. Admitted helpers, backup offers and
/// people who never offered stay as they are; each declined person sees the
/// reason privately; the author's «answer this offer» obligations settle.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_DECLINE_REMAINING_OFFERS_TEST_DB',
    defaultNamePrefix: 'tentura_test_decline_remaining',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('declineRemainingHelpOffers', () {
    late DisposablePgWriterSession session;
    late TenturaDb database;
    late Connection writer;
    late _Harness harness;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      harness = _Harness.build(database, target.databaseEnv);
      // The offer list maps presence through GetIt's Env.
      if (!GetIt.I.isRegistered<Env>()) {
        GetIt.I.registerSingleton<Env>(target.databaseEnv);
        addTearDown(() => GetIt.I.unregister<Env>());
      }
    });

    setUp(() async => _seed(writer));

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<int?> offerStatus(String userId) async =>
        (await writer.execute('''
SELECT status FROM public.beacon_help_offer
WHERE beacon_id = '$_request' AND user_id = '$userId'
''')).singleOrNull?[0]
            as int?;

    Future<int?> roomAccess(String userId) async =>
        (await writer.execute('''
SELECT room_access FROM public.beacon_participant
WHERE beacon_id = '$_request' AND user_id = '$userId'
''')).singleOrNull?[0]
            as int?;

    Future<bool> isAdmittedHelper(String userId) async =>
        (await writer.execute('''
SELECT 1 FROM public.beacon_admitted_helper
WHERE beacon_id = '$_request' AND user_id = '$userId'
''')).isNotEmpty;

    /// The author's open «answer this offer» obligations about [userId].
    Future<int> openAuthorObligations(String userId) async =>
        (await writer.execute('''
SELECT count(*)::int FROM public.notification_outbox
WHERE beacon_id = '$_request' AND account_id = '$_author'
  AND target_entity_id = '$userId' AND requires_action
  AND settlement_kind IS NULL
''')).single[0]!
            as int;

    /// Everyone offers; [_accepted] is accepted; «Enough help» is set; then
    /// [_backup] offers (a backup offer).
    Future<void> arrange() async {
      for (final u in [_accepted, _pendingA, _pendingB, _addressee]) {
        await harness.helpOffers.offerHelp(beaconId: _request, userId: u);
      }
      await harness.coordination.acceptHelpOffer(
        beaconId: _request,
        offerUserId: _accepted,
        actorUserId: _author,
      );
      await harness.coordination.setBeaconStatus(
        beaconId: _request,
        authorUserId: _author,
        status: BeaconStatus.enoughHelp.smallintValue,
      );
      await harness.helpOffers.offerHelp(beaconId: _request, userId: _backup);
    }

    test('declines only the offers still waiting for an answer', () async {
      await arrange();
      expect(await openAuthorObligations(_pendingA), greaterThan(0));

      final declined = await harness.coordination.declineRemainingHelpOffers(
        beaconId: _request,
        actorUserId: _author,
        reason: _reason,
      );

      expect(declined, 3, reason: 'pendingA, pendingB and the addressee');
      expect(await offerStatus(_pendingA), _offerWithdrawn);
      expect(await offerStatus(_pendingB), _offerWithdrawn);
      expect(await offerStatus(_addressee), _offerWithdrawn);

      // Admitted helper untouched.
      expect(await offerStatus(_accepted), _offerActive);
      expect(await isAdmittedHelper(_accepted), isTrue);
      expect(await roomAccess(_accepted), RoomAccessBits.admitted);
      // Backup offers stay.
      expect(await offerStatus(_backup), _offerActive);
      // A recipient is never removed; the addressee keeps the room.
      expect(await roomAccess(_addressee), RoomAccessBits.admitted);
      expect(await offerStatus(_recipient), isNull);
      expect(
        (await writer.execute('''
SELECT count(*)::int FROM public.beacon_forward_edge
WHERE beacon_id = '$_request' AND recipient_id = '$_recipient'
  AND cancelled_at IS NULL
''')).single[0],
        1,
      );
    });

    test("settles the author's obligations for the declined offers", () async {
      await arrange();

      await harness.coordination.declineRemainingHelpOffers(
        beaconId: _request,
        actorUserId: _author,
        reason: _reason,
      );

      expect(await openAuthorObligations(_pendingA), 0);
      expect(await openAuthorObligations(_pendingB), 0);
      expect(await openAuthorObligations(_addressee), 0);
    });

    test('keeps the reason private to each declined person', () async {
      await arrange();

      await harness.coordination.declineRemainingHelpOffers(
        beaconId: _request,
        actorUserId: _author,
        reason: _reason,
      );

      String? reasonSeenBy(
        List<HelpOfferWithCoordinationRow> rows,
        String offerer,
      ) => rows.firstWhere((r) => r.userId == offerer).lastDeclineReason;

      final own = await harness.coordination.helpOffersWithCoordination(
        beaconId: _request,
        viewerId: _pendingA,
      );
      expect(reasonSeenBy(own, _pendingA), _reason);

      final other = await harness.coordination.helpOffersWithCoordination(
        beaconId: _request,
        viewerId: _accepted,
      );
      expect(reasonSeenBy(other, _pendingA), isNull);
      expect(reasonSeenBy(other, _pendingB), isNull);

      final messages = await writer.execute('''
SELECT body FROM public.beacon_room_message
WHERE beacon_id = '$_request' AND body LIKE '%enough help now%'
''');
      expect(messages, isEmpty, reason: 'never posted to the room');
    });

    test('a second call declines nothing more', () async {
      await arrange();
      await harness.coordination.declineRemainingHelpOffers(
        beaconId: _request,
        actorUserId: _author,
        reason: _reason,
      );

      final again = await harness.coordination.declineRemainingHelpOffers(
        beaconId: _request,
        actorUserId: _author,
        reason: _reason,
      );

      expect(again, 0);
      expect(await offerStatus(_backup), _offerActive);
      expect(await offerStatus(_accepted), _offerActive);
    });

    test('refuses unless «Enough help» is set, declining nothing', () async {
      for (final u in [_pendingA, _pendingB]) {
        await harness.helpOffers.offerHelp(beaconId: _request, userId: u);
      }

      await expectLater(
        harness.coordination.declineRemainingHelpOffers(
          beaconId: _request,
          actorUserId: _author,
          reason: _reason,
        ),
        throwsA(
          isA<HelpOfferCoordinationException>().having(
            (e) =>
                (e.code as HelpOfferCoordinationExceptionCodes).exceptionCode,
            'code',
            HelpOfferCoordinationExceptionCode.invalidCoordinationStatus,
          ),
        ),
      );
      expect(await offerStatus(_pendingA), _offerActive);
      expect(await offerStatus(_pendingB), _offerActive);
    });

    test('only the author or a steward may do it', () async {
      await arrange();

      await expectLater(
        harness.coordination.declineRemainingHelpOffers(
          beaconId: _request,
          actorUserId: _accepted,
          reason: _reason,
        ),
        throwsA(isA<HelpOfferCoordinationException>()),
      );
      expect(await offerStatus(_pendingA), _offerActive);
    });

    test('requires a reason', () async {
      await arrange();

      await expectLater(
        harness.coordination.declineRemainingHelpOffers(
          beaconId: _request,
          actorUserId: _author,
          reason: '   ',
        ),
        throwsA(isA<HelpOfferCoordinationException>()),
      );
      expect(await offerStatus(_pendingA), _offerActive);
    });
  });
}

Future<void> _seed(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.notification_outbox,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.inbox_item,
  public.beacon_room_message,
  public.beacon_forward_edge,
  public.beacon_participant,
  public.beacon,
  public."user"
CASCADE
''');
  for (var i = 0; i < _users.length; i++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': _users[i], 'key': pgTestPublicKey('declrem', i + 1)},
    );
  }
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, published_at)
VALUES ('$_request', '$_author', 'Move', 'Move a piano', 0, $_kindRequest,
        now())
''');
  await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES
  ('Fdeclremaddr001', '$_request', '$_author', '$_addressee'),
  ('Fdeclremrcpt001', '$_request', '$_author', '$_recipient')
''');
  await writer.execute('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES
  ('Pdeclremaddr001', '$_request', '$_addressee', $_roleAddressee, 0, 3)
''');
}

final class _Harness {
  const _Harness({
    required this.helpOffers,
    required this.coordination,
    required this.room,
    required this.roomRepository,
    required this.posts,
  });

  final HelpOfferCase helpOffers;
  final CoordinationCase coordination;
  final BeaconRoomCase room;
  final BeaconRoomRepository roomRepository;
  final PostCase posts;

  factory _Harness.build(TenturaDb db, Env env) {
    final logger = Logger('DeclineRemainingHelpOffersPgTest');
    final uow = MutatingUnitOfWork(db);
    final dispatch = AttentionDispatchRepository(db, logger);
    final attention = TransactionalAttentionCase(uow, dispatch);
    final systemSettlement = AttentionSystemSettlementRepository(db);
    final beaconRepository = BeaconRepository(db);
    final roomRepository = BeaconRoomRepository(db);
    final help = HelpOfferRepository(db);
    final commitments = CommitmentRepository(db);
    final access = BeaconAccessRepository(db);
    final blocks = UserBlockRepository(env, db);
    final hierarchy = BeaconHierarchyRepository(db);
    final intents = AttentionIntentCase(
      BeaconRoomNotificationContextRepository(
        roomRepository,
        db,
        help,
        commitments,
      ),
      UserRepository(
        env,
        db,
        _UnusedGenealogy(),
        InviteSeedPromptRepositoryMock(),
      ),
      access,
      blocks,
    );
    final commitmentQuery = CommitmentQueryCase(
      commitments,
      help,
      env: env,
      logger: logger,
    );
    final images = _UnusedImages();
    final tasks = _Tasks();
    final beacons = BeaconCase(
      beaconRepository,
      images,
      _UnusedImageGc(),
      tasks,
      commitmentQuery,
      access,
      hierarchy,
      FakeBeaconChildCreatePort(),
      BeaconLifecycleEffectsCase(
        BeaconHierarchyOutboxRepository(db),
        env: env,
        logger: logger,
      ),
      attentionIntents: intents,
      attention: attention,
      env: env,
      logger: logger,
    );
    final forwards = ForwardCase(
      ForwardEdgeRepository(db),
      ForwardAttributionRepository(db),
      help,
      InboxRepository(db),
      CapabilityEvidenceRepository(db),
      beaconRepository,
      blocks,
      PersonVisibilityRepository(db),
      access,
      attentionIntents: intents,
      attention: attention,
      postLock: PostLockRepository(db),
      env: env,
      logger: logger,
    );
    final room = BeaconRoomCase(
      roomRepository,
      CoordinationItemRepository(db),
      _UnusedFactCards(),
      images,
      tasks,
      _Storage(),
      _UnusedPolling(),
      _Quota(),
      blocks,
      uow,
      hierarchy,
      const ProductionDiscussionProductPolicy(),
      attentionIntents: intents,
      attention: attention,
      env: env,
      logger: logger,
    );
    return _Harness(
      helpOffers: HelpOfferCase(
        help,
        beaconRepository,
        commitments,
        InboxRepository(db),
        CapabilityCase(
          PersonCapabilityEventRepository(db),
          env: env,
          logger: logger,
        ),
        FakeBeaconAccessGuard(),
        roomRepository: roomRepository,
        attentionIntents: intents,
        attention: attention,
        attentionSystemSettlement: systemSettlement,
        env: env,
        logger: logger,
      ),
      coordination: CoordinationCase(
        beaconRepository,
        help,
        CoordinationRepository(
          db,
          DriftUserProfileBatchLookup(db, UserAvailabilityRepository(db)),
          VoteUserFriendshipLookup(db),
          roomRepository,
          BeaconPeopleSeenRepository(db),
        ),
        roomRepository,
        blocks,
        commitments,
        commitmentQuery,
        hierarchy,
        attentionIntents: intents,
        attention: attention,
        attentionSystemSettlement: systemSettlement,
        guard: FakeBeaconAccessGuard(),
        env: env,
        logger: logger,
      ),
      room: room,
      roomRepository: roomRepository,
      posts: PostCase(
        beaconCase: beacons,
        forwardCase: forwards,
        roomCase: room,
        beaconRepository: beaconRepository,
        postLock: PostLockRepository(db),
        attention: attention,
      ),
    );
  }
}

final class _UnusedGenealogy extends Fake
    implements InviteGenealogyRepositoryPort {}

final class _UnusedImages extends Fake implements ImageRepositoryPort {}

final class _UnusedImageGc extends Fake implements ImageObjectGcPort {}

final class _UnusedFactCards extends Fake
    implements BeaconFactCardRepositoryPort {}

final class _UnusedPolling extends Fake implements PollingRepositoryPort {}

final class _Tasks extends Fake implements TaskRepositoryPort {
  @override
  Future<String> schedule(TaskEntity task) async => 'task-id';
}

final class _Storage extends Fake implements RemoteStoragePort {
  @override
  Future<String> putObject(
    String path,
    Stream<Uint8List> bytes, {
    Map<String, String>? metadata,
  }) async {
    await bytes.drain<void>();
    return path;
  }
}

final class _Quota extends Fake implements UploadQuotaRepositoryPort {
  @override
  Future<bool> tryReserveDailyBytes({
    required String userId,
    required int bytes,
    required int dailyCapBytes,
  }) async => true;
}
