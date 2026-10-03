@Tags(['pg'])
library;

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_participant_status_bits.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
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
import 'package:tentura_server/domain/exception.dart';
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

const _author = 'Uintermauthor1';
const _addressee = 'Uintermaddr001';
const _otherAddressee = 'Uintermaddr002';
const _helper = 'Uintermhelper1';
const _users = [_author, _addressee, _otherAddressee, _helper];

const _request = 'Bintermreq0001';

const _kindRequest = 0;

const _roleHelper = 2;
const _roleAddressee = 6;

const _offerActive = 0;
const _offerWithdrawn = 1;

/// A Request converted from a Post keeps its addressees in the room as
/// `role 6` participants. Such an addressee who offers help, is declined, or
/// withdraws the offer stays admitted and stays an addressee; only the author
/// accepting the offer turns the row into an admitted helper (`role 2`). An
/// ordinary helper keeps today's behaviour (declined or withdrawn means room
/// access is revoked), and the addressee can still leave the room. Real
/// repositories over a disposable Postgres, with real attention dispatch. See
/// `docs/plans/post-and-constellation-composer-plan.md` §5.9.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_INTERMEDIATE_STATE_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_intermediate',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('Offering help from the intermediate role-6 state', () {
    late DisposablePgWriterSession session;
    late TenturaDb database;
    late Connection writer;
    late _Harness harness;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      harness = _Harness.build(database, target.databaseEnv);
    });

    setUp(() async => _seed(writer));

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<ResultRow> participant(String userId) async =>
        (await writer.execute('''
SELECT role, room_access, status, offer_note FROM public.beacon_participant
WHERE beacon_id = '$_request' AND user_id = '$userId'
''')).single;

    Future<ResultRow?> helpOffer(String userId) async =>
        (await writer.execute('''
SELECT status, withdraw_reason FROM public.beacon_help_offer
WHERE beacon_id = '$_request' AND user_id = '$userId'
''')).singleOrNull;

    Future<bool> isAdmittedHelper(String userId) async =>
        (await writer.execute('''
SELECT 1 FROM public.beacon_admitted_helper
WHERE beacon_id = '$_request' AND user_id = '$userId'
''')).isNotEmpty;

    Future<void> expectStillAdmittedAddressee(String userId) async {
      final row = await participant(userId);
      expect(row[0], _roleAddressee, reason: 'role stays addressee');
      expect(row[1], RoomAccessBits.admitted, reason: 'room_access');
    }

    test('the seeded addressee starts admitted and is not a helper', () async {
      await expectStillAdmittedAddressee(_addressee);
      expect(await isAdmittedHelper(_addressee), isFalse);
    });

    group('offering through the room', () {
      test('records the offer and keeps the addressee admitted', () async {
        await harness.room.offerHelp(
          beaconId: _request,
          userId: _addressee,
          note: 'I can drive the van',
        );

        final row = await participant(_addressee);
        expect(row[2], BeaconParticipantStatusBits.offeredHelp, reason: 'offer');
        expect(row[3], 'I can drive the van', reason: 'offer note');
        expect(row[0], _roleAddressee, reason: 'role stays addressee');
        expect(
          row[1],
          RoomAccessBits.admitted,
          reason: 'offering must not push an admitted addressee back to '
              'requested',
        );
      });

      test('lets the addressee keep posting in the room', () async {
        await harness.room.offerHelp(
          beaconId: _request,
          userId: _addressee,
          note: 'I can drive the van',
        );

        final message = await harness.room.createMessage(
          beaconId: _request,
          userId: _addressee,
          body: 'Still here',
        );

        expect(message['id'], isNotNull);
      });

      test(
        'still resets an ordinary helper without access to requested',
        () async {
          await writer.execute('''
UPDATE public.beacon_participant SET room_access = 0, role = $_roleHelper
WHERE beacon_id = '$_request' AND user_id = '$_addressee'
''');

          await harness.room.offerHelp(
            beaconId: _request,
            userId: _addressee,
            note: 'Me too',
          );

          expect((await participant(_addressee))[1], RoomAccessBits.requested);
        },
      );
    });

    group('offering through the help-offer path', () {
      test('records an active offer and keeps the addressee admitted', () async {
        await harness.helpOffers.offerHelp(
          beaconId: _request,
          userId: _addressee,
          message: 'I can drive the van',
        );

        final offer = await helpOffer(_addressee);
        expect(offer, isNotNull);
        expect(offer![0], _offerActive);
        await expectStillAdmittedAddressee(_addressee);
        expect(
          await isAdmittedHelper(_addressee),
          isFalse,
          reason: 'an unanswered offer does not make an addressee a helper',
        );
      });
    });

    group('declining the offer', () {
      test('keeps an addressee admitted and an addressee', () async {
        await harness.helpOffers.offerHelp(
          beaconId: _request,
          userId: _addressee,
        );

        await harness.coordination.declineHelpOffer(
          beaconId: _request,
          offerUserId: _addressee,
          actorUserId: _author,
          reason: 'We have enough drivers',
        );

        await expectStillAdmittedAddressee(_addressee);
        expect(await isAdmittedHelper(_addressee), isFalse);
      });

      test('still closes the offer', () async {
        await harness.helpOffers.offerHelp(
          beaconId: _request,
          userId: _addressee,
        );

        await harness.coordination.declineHelpOffer(
          beaconId: _request,
          offerUserId: _addressee,
          actorUserId: _author,
          reason: 'We have enough drivers',
        );

        expect((await helpOffer(_addressee))![0], _offerWithdrawn);
      });

      test('lets the addressee keep posting in the room', () async {
        await harness.helpOffers.offerHelp(
          beaconId: _request,
          userId: _addressee,
        );
        await harness.coordination.declineHelpOffer(
          beaconId: _request,
          offerUserId: _addressee,
          actorUserId: _author,
          reason: 'We have enough drivers',
        );

        final message = await harness.room.createMessage(
          beaconId: _request,
          userId: _addressee,
          body: 'Understood',
        );

        expect(message['id'], isNotNull);
      });

      test('still revokes room access of an ordinary helper', () async {
        await writer.execute('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES ('Pintermhelper01', '$_request', '$_helper', $_roleHelper, 0, 3)
''');
        await harness.helpOffers.offerHelp(
          beaconId: _request,
          userId: _helper,
        );

        await harness.coordination.declineHelpOffer(
          beaconId: _request,
          offerUserId: _helper,
          actorUserId: _author,
          reason: 'Changed plans',
        );

        expect((await participant(_helper))[1], RoomAccessBits.none);
      });
    });

    group('withdrawing the offer', () {
      test('keeps an addressee admitted and an addressee', () async {
        await harness.helpOffers.offerHelp(
          beaconId: _request,
          userId: _addressee,
        );

        await harness.helpOffers.withdraw(
          beaconId: _request,
          userId: _addressee,
          withdrawReason: 'timing',
        );

        expect((await helpOffer(_addressee))![0], _offerWithdrawn);
        await expectStillAdmittedAddressee(_addressee);
        expect(await isAdmittedHelper(_addressee), isFalse);
      });

      test('lets the addressee keep posting in the room', () async {
        await harness.helpOffers.offerHelp(
          beaconId: _request,
          userId: _addressee,
        );
        await harness.helpOffers.withdraw(
          beaconId: _request,
          userId: _addressee,
          withdrawReason: 'timing',
        );

        final message = await harness.room.createMessage(
          beaconId: _request,
          userId: _addressee,
          body: 'Sorry, cannot make it',
        );

        expect(message['id'], isNotNull);
      });
    });

    group('withdrawing the offer as an ordinary helper', () {
      test('still revokes room access', () async {
        await writer.execute('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES ('Pintermhelper01', '$_request', '$_helper', $_roleHelper, 0, 3)
''');
        await harness.helpOffers.offerHelp(
          beaconId: _request,
          userId: _helper,
        );

        await harness.helpOffers.withdraw(
          beaconId: _request,
          userId: _helper,
          withdrawReason: 'timing',
        );

        expect((await helpOffer(_helper))![0], _offerWithdrawn);
        expect((await participant(_helper))[1], RoomAccessBits.none);
      });
    });

    group('admitting through the invite-offer repository entry point', () {
      test(
        'records the offer outcome and keeps an admitted addressee admitted',
        () async {
          await writer.execute('''
UPDATE public.beacon_participant
SET status = ${BeaconParticipantStatusBits.offeredHelp},
    offer_note = 'I can drive the van'
WHERE beacon_id = '$_request' AND user_id = '$_addressee'
''');
          await expectStillAdmittedAddressee(_addressee);

          await harness.roomRepository.inviteOfferUserToBeaconRoom(
            beaconId: _request,
            offerUserId: _addressee,
            authorUserId: _author,
          );

          final row = await participant(_addressee);
          expect(
            row[2],
            BeaconParticipantStatusBits.committed,
            reason: 'an admitted addressee must not make the call a no-op',
          );
          expect(row[1], RoomAccessBits.admitted, reason: 'room_access');
        },
      );

      test('does not move an already admitted ordinary helper', () async {
        await writer.execute('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES ('Pintermhelper01', '$_request', '$_helper', $_roleHelper, 1, 3)
''');

        await harness.roomRepository.inviteOfferUserToBeaconRoom(
          beaconId: _request,
          offerUserId: _helper,
          authorUserId: _author,
        );

        final row = await participant(_helper);
        expect(row[0], _roleHelper);
        expect(row[1], RoomAccessBits.admitted);
        expect(
          row[2],
          BeaconParticipantStatusBits.offeredHelp,
          reason: 'the early return for ordinary admitted helpers is kept',
        );
      });
    });

    group('accepting the offer', () {
      test('makes the addressee an admitted helper', () async {
        await harness.helpOffers.offerHelp(
          beaconId: _request,
          userId: _addressee,
        );

        await harness.coordination.acceptHelpOffer(
          beaconId: _request,
          offerUserId: _addressee,
          actorUserId: _author,
        );

        final row = await participant(_addressee);
        expect(row[0], _roleHelper, reason: 'role becomes helper');
        expect(row[1], RoomAccessBits.admitted, reason: 'room_access');
        expect(await isAdmittedHelper(_addressee), isTrue);
      });

      test(
        'after an earlier withdrawal and a fresh offer, makes the addressee '
        'an admitted helper',
        () async {
          await harness.helpOffers.offerHelp(
            beaconId: _request,
            userId: _addressee,
          );
          await harness.helpOffers.withdraw(
            beaconId: _request,
            userId: _addressee,
            withdrawReason: 'timing',
          );
          await harness.helpOffers.offerHelp(
            beaconId: _request,
            userId: _addressee,
            message: 'Now I can',
          );

          await harness.coordination.acceptHelpOffer(
            beaconId: _request,
            offerUserId: _addressee,
            actorUserId: _author,
          );

          final row = await participant(_addressee);
          expect(row[0], _roleHelper, reason: 'role becomes helper');
          expect(row[1], RoomAccessBits.admitted, reason: 'room_access');
          expect(await isAdmittedHelper(_addressee), isTrue);
        },
      );

      test(
        'after an earlier decline and a fresh offer, makes the addressee an '
        'admitted helper',
        () async {
          await harness.helpOffers.offerHelp(
            beaconId: _request,
            userId: _addressee,
          );
          await harness.coordination.declineHelpOffer(
            beaconId: _request,
            offerUserId: _addressee,
            actorUserId: _author,
            reason: 'Not yet',
          );
          await harness.helpOffers.offerHelp(
            beaconId: _request,
            userId: _addressee,
            message: 'Now I can',
          );

          await harness.coordination.acceptHelpOffer(
            beaconId: _request,
            offerUserId: _addressee,
            actorUserId: _author,
          );

          expect((await participant(_addressee))[0], _roleHelper);
          expect(await isAdmittedHelper(_addressee), isTrue);
        },
      );

      test('leaves the other addressees untouched', () async {
        await harness.helpOffers.offerHelp(
          beaconId: _request,
          userId: _addressee,
        );

        await harness.coordination.acceptHelpOffer(
          beaconId: _request,
          offerUserId: _addressee,
          actorUserId: _author,
        );

        await expectStillAdmittedAddressee(_otherAddressee);
        expect(await isAdmittedHelper(_otherAddressee), isFalse);
      });

      test('admits an ordinary offerer as a helper as before', () async {
        await harness.helpOffers.offerHelp(
          beaconId: _request,
          userId: _helper,
        );

        await harness.coordination.acceptHelpOffer(
          beaconId: _request,
          offerUserId: _helper,
          actorUserId: _author,
        );

        final row = await participant(_helper);
        expect(row[0], _roleHelper);
        expect(row[1], RoomAccessBits.admitted);
        expect(await isAdmittedHelper(_helper), isTrue);
      });
    });

    group('leaving the room as an addressee', () {
      test('sets room access to left and rejects reads and writes', () async {
        await expectStillAdmittedAddressee(_addressee);

        await harness.posts.leave(userId: _addressee, beaconId: _request);

        expect((await participant(_addressee))[0], _roleAddressee);
        expect((await participant(_addressee))[1], RoomAccessBits.left);
        await expectLater(
          harness.room.createMessage(
            beaconId: _request,
            userId: _addressee,
            body: 'Still here?',
          ),
          throwsA(isA<UnauthorizedException>()),
        );
        await expectLater(
          harness.room.listMainRoomReadWatermarks(
            beaconId: _request,
            userId: _addressee,
          ),
          throwsA(isA<UnauthorizedException>()),
        );
      });

      test('works while an offer is pending', () async {
        await harness.helpOffers.offerHelp(
          beaconId: _request,
          userId: _addressee,
        );
        await expectStillAdmittedAddressee(_addressee);

        await harness.posts.leave(userId: _addressee, beaconId: _request);

        expect((await participant(_addressee))[1], RoomAccessBits.left);
      });
    });

    group('leaving after the offer was declined', () {
      test('sets room access to left and rejects the addressee', () async {
        await harness.helpOffers.offerHelp(
          beaconId: _request,
          userId: _addressee,
        );
        await harness.coordination.declineHelpOffer(
          beaconId: _request,
          offerUserId: _addressee,
          actorUserId: _author,
          reason: 'We have enough drivers',
        );
        await expectStillAdmittedAddressee(_addressee);

        await harness.posts.leave(userId: _addressee, beaconId: _request);

        expect((await participant(_addressee))[1], RoomAccessBits.left);
        await expectLater(
          harness.room.createMessage(
            beaconId: _request,
            userId: _addressee,
            body: 'Still here?',
          ),
          throwsA(isA<UnauthorizedException>()),
        );
      });
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
      parameters: {'id': _users[i], 'key': pgTestPublicKey('interm', i + 1)},
    );
  }
  // A Request converted from a Post: both addressees keep `role 6` and
  // `room_access 3`; admission is no longer reconciled from edges.
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, published_at)
VALUES ('$_request', '$_author', 'Converted', 'Move a piano', 0, $_kindRequest,
        now())
''');
  await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES
  ('Fintermauthadd01', '$_request', '$_author', '$_addressee'),
  ('Fintermauthadd02', '$_request', '$_author', '$_otherAddressee')
''');
  await writer.execute('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES
  ('Pintermaddr00001', '$_request', '$_addressee', $_roleAddressee, 0, 3),
  ('Pintermaddr00002', '$_request', '$_otherAddressee', $_roleAddressee, 0, 3)
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
    final logger = Logger('PostIntermediateStatePgTest');
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
