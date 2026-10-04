@Tags(['pg'])
library;

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/data/repository/attention_system_settlement_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_command_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/capability_evidence_repository.dart';
import 'package:tentura_server/data/repository/closure_reminder_repository.dart';
import 'package:tentura_server/data/repository/closure_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/constellation_field_repository.dart';
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
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/closure_finalizer_port.dart';
import 'package:tentura_server/domain/port/closure_receipts_port.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/domain/use_case/beacon_child_create_case.dart';
import 'package:tentura_server/domain/use_case/beacon_display_case.dart';
import 'package:tentura_server/domain/use_case/beacon_forward_graph_case.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/domain/use_case/capability_case.dart';
import 'package:tentura_server/domain/use_case/closure_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/coordination_case.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/help_offer_case.dart';
import 'package:tentura_server/domain/use_case/post_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/beacon_not_request_matcher.dart';
import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'Uaudauthor001';
const _bob = 'Uaudbob000001';
const _carol = 'Uaudcarol0001';
const _users = [_author, _bob, _carol];
const _draftPost = 'Baudpost00001';
const _request = 'Baudrequest01';
const _recipients = [_bob, _carol];
const _kindPost = 1;
const _statusDraft = 3;

/// A Post has no help offers, closure, cancellation, forking or child
/// Requests; it does keep its inbox items, room, receipts and forward graph.
/// This audit seeds one Post (through `postPublish`) and one Request with the
/// same author and the same two recipients, over real repositories, and checks
/// both sides of that line.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_REQUEST_ONLY_AUDIT_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_reqonly_audit',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('Request-only surfaces with a Post and a Request side by side', () {
    late DisposablePgWriterSession session;
    late TenturaDb database;
    late _Harness harness;
    late Connection writer;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      harness = _Harness.build(database, target.databaseEnv);
    });

    setUp(() async {
      await _seedUsersAndTrust(writer);
      await _insertRequest(writer);
      await _insertPostDraft(writer);
      await harness.forwards.forward(
        senderId: _author,
        beaconId: _request,
        recipientIds: _recipients,
      );
      await harness.posts.publish(
        authorId: _author,
        beaconId: _draftPost,
        body: 'Heads up, both of you',
        mentionUserIds: const [],
        mentionOffsets: const [],
        mentionLengths: const [],
        recipientIds: _recipients,
        notes: const {},
        forwardPolicy: BeaconForwardPolicyValue.closed,
      );
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    group('lists and reminders that only carry Requests', () {
      test('responsibility scope lists the Request and not the Post', () async {
        final rows = await writer.execute(
          Sql.named(
            'SELECT beacon_id FROM public.responsibility_scope_base_beacons(@u)',
          ),
          parameters: {'u': _author},
        );
        final ids = rows.map((r) => r[0]! as String).toSet();
        expect(ids, contains(_request));
        expect(ids, isNot(contains(_draftPost)));
      });

      test('constellation Request sections list the Request and not the '
          'Post', () async {
        final constellation = ConstellationFieldRepository(
          database,
          _NoProfiles(),
        );

        final own = await constellation.ownRequests(viewerId: _author);
        expect(own.map((r) => r.id), contains(_request));
        expect(own.map((r) => r.id), isNot(contains(_draftPost)));

        final discoverable = await constellation.discoverableRequests(
          viewerId: _bob,
          context: '',
          cap: 50,
        );
        expect(discoverable.map((r) => r.id), contains(_request));
        expect(discoverable.map((r) => r.id), isNot(contains(_draftPost)));

        for (final viewer in [_author, _bob, _carol]) {
          final snapshot = await constellation.readSnapshot(
            viewerId: viewer,
            context: '',
            params: (
              filters: ConstellationFieldMembershipFilters.defaults,
              projection: ConstellationProjection.full,
            ),
          );
          final ids = snapshot.requests.map((r) => r.id).toSet();
          if (viewer == _author) {
            expect(ids, contains(_request), reason: 'author snapshot');
          }
          expect(ids, isNot(contains(_draftPost)), reason: 'viewer $viewer');
        }
      });

      test('deadline reminder candidates include the Request and not the '
          'Post', () async {
        final today = DateTime.now().toUtc();
        final next = DateTime.utc(
          today.year,
          today.month,
          today.day,
        ).add(const Duration(days: 1));
        final following = next.add(const Duration(days: 1));
        final beacons = BeaconRepository(database);

        final ids = await beacons.deadlineReminderCandidateIds(
          nextUtcDayStart: next,
          followingUtcDayStart: following,
        );
        expect(ids, contains(_request));
        expect(ids, isNot(contains(_draftPost)));

        expect(
          await beacons.lockOpenBeaconForDeadlineReminder(
            beaconId: _draftPost,
            nextUtcDayStart: next,
            followingUtcDayStart: following,
          ),
          isNull,
        );
      });

      test('stale-request reminders are written for the Request and not the '
          'Post', () async {
        await ClosureReminderRepository(database).writeStaleRequestReminders(
          now: DateTime.now().toUtc().add(const Duration(days: 60)),
          weekKey: '2026-W40',
        );

        final rows = await writer.execute('''
SELECT beacon_id FROM public.notification_outbox
WHERE source_event_key LIKE 'stale_request:%'
''');
        final ids = rows.map((r) => r[0]! as String).toSet();
        expect(ids, contains(_request));
        expect(ids, isNot(contains(_draftPost)));
      });

      test('deleting a Request tombstones its inbox items and deleting a '
          'Post does not', () async {
        final beacons = BeaconRepository(database);
        for (final id in [_request, _draftPost]) {
          await beacons.recordBeaconStatusTransition(
            beaconId: id,
            fromStatus: BeaconStatus.open,
            toStatus: BeaconStatus.deleted,
            reason: BeaconLifecycleChangeReason.deleted,
            actorId: _author,
          );
        }

        final rows = await writer.execute('''
SELECT beacon_id, count(*) FILTER (WHERE before_response_terminal_at IS NOT NULL)
FROM public.inbox_item
WHERE beacon_id IN ('$_request', '$_draftPost')
GROUP BY beacon_id
''');
        final stamped = {for (final r in rows) r[0]! as String: r[1]! as int};
        expect(stamped[_request], _recipients.length);
        expect(stamped[_draftPost], 0);
      });

      test('display statuses cover the Request and skip the Post', () async {
        for (final viewer in [_author, _bob]) {
          final statuses = await harness.display.displayStatuses(
            beaconIds: [_request, _draftPost],
            viewerId: viewer,
          );
          final ids = statuses.map((s) => s.beaconId).toSet();
          expect(ids, contains(_request), reason: 'viewer $viewer');
          expect(ids, isNot(contains(_draftPost)), reason: 'viewer $viewer');
        }
      });
    });

    group('operations that need a Request reject a Post', () {
      test('offerHelp', () async {
        await expectLater(
          harness.helpOffers.offerHelp(beaconId: _draftPost, userId: _bob),
          throwsBeaconNotRequest,
        );
      });

      test('acceptHelpOffer', () async {
        await expectLater(
          harness.coordination.acceptHelpOffer(
            beaconId: _draftPost,
            offerUserId: _bob,
            actorUserId: _author,
          ),
          throwsBeaconNotRequest,
        );
      });

      test('close', () async {
        await expectLater(
          harness.closure.close(authorId: _author, beaconId: _draftPost),
          throwsBeaconNotRequest,
        );
      });

      test('beaconCancel', () async {
        await expectLater(
          harness.beacons.beaconCancel(beaconId: _draftPost, userId: _author),
          throwsBeaconNotRequest,
        );
      });

      test('fork', () async {
        await expectLater(
          harness.beacons.fork(sourceId: _draftPost, userId: _bob),
          throwsBeaconNotRequest,
        );
      });

      test('createChild with a Post as the parent', () async {
        await expectLater(
          harness.children.createChild(
            actorUserId: _author,
            parentBeaconId: _draftPost,
            clientCommandId: 'audit-command-1',
            title: 'Child of a Post',
            description: 'Cannot hang a Request under a Post',
            draft: false,
          ),
          throwsBeaconNotRequest,
        );
      });

      test('room plan line update', () async {
        await expectLater(
          harness.room.updateRoomNowLine(
            beaconId: _draftPost,
            userId: _author,
            text: 'Today we sort the boxes',
          ),
          throwsBeaconNotRequest,
        );
      });

      test('room help offer by an addressee', () async {
        await expectLater(
          harness.room.offerHelp(
            beaconId: _draftPost,
            userId: _bob,
            note: 'I can help',
          ),
          throwsBeaconNotRequest,
        );
      });

      test('room admission', () async {
        await expectLater(
          harness.room.admit(
            beaconId: _draftPost,
            participantUserId: _bob,
            actorUserId: _author,
          ),
          throwsBeaconNotRequest,
        );
      });

      test('steward promotion', () async {
        await expectLater(
          harness.room.stewardPromote(
            beaconId: _draftPost,
            stewardUserId: _bob,
            authorUserId: _author,
          ),
          throwsBeaconNotRequest,
        );
      });

      test('the rejected calls leave the Post without a closure row, help '
          'offer or child', () async {
        await expectLater(
          harness.closure.close(authorId: _author, beaconId: _draftPost),
          throwsBeaconNotRequest,
        );
        await expectLater(
          harness.helpOffers.offerHelp(beaconId: _draftPost, userId: _bob),
          throwsBeaconNotRequest,
        );

        expect(await _count(writer, 'beacon_closure', _draftPost), 0);
        expect(await _count(writer, 'beacon_help_offer', _draftPost), 0);
        final children = await writer.execute(
          Sql.named(
            'SELECT count(*) FROM public.beacon WHERE parent_beacon_id = @id',
          ),
          parameters: {'id': _draftPost},
        );
        expect(children.single.single, 0);
      });
    });

    group('what a Post keeps for its recipients', () {
      test('has an inbox item for every recipient', () async {
        for (final recipient in _recipients) {
          final items = await harness.inbox.fetchByUserId(recipient);
          expect(
            items.map((i) => i.beaconId),
            containsAll([_request, _draftPost]),
            reason: 'recipient $recipient',
          );
        }
      });

      test('makes every recipient a beacon member', () async {
        final rows = await writer.execute(
          Sql.named(
            'SELECT user_id FROM public.beacon_member WHERE beacon_id = @id',
          ),
          parameters: {'id': _draftPost},
        );
        expect(
          rows.map((r) => r[0]! as String).toSet(),
          containsAll(_recipients),
        );
      });

      test('keeps the author root message in the room message list', () async {
        final messages = await harness.roomRepository.listMessages(
          beaconId: _draftPost,
        );
        final beacon = (await writer.execute(
          Sql.named(
            'SELECT post_root_message_id FROM public.beacon WHERE id = @id',
          ),
          parameters: {'id': _draftPost},
        )).single;
        expect(beacon[0], isNotNull);
        expect(messages.map((m) => m.id), contains(beacon[0]));
        expect(await _count(writer, 'beacon_closure', _draftPost), 0);
        for (final recipient in _recipients) {
          final visibleMessages = await harness.room.listMessages(
            beaconId: _draftPost,
            userId: recipient,
          );
          expect(
            visibleMessages.map((m) => m['id']),
            contains(beacon[0]),
            reason: 'recipient $recipient',
          );
        }
      });

      test('lets an addressee read and post in the Post room', () async {
        final before = await harness.room.listMessages(
          beaconId: _draftPost,
          userId: _bob,
        );
        expect(before, hasLength(1));

        await harness.room.createMessage(
          beaconId: _draftPost,
          userId: _bob,
          body: 'Thanks for the heads up',
        );

        final after = await harness.room.listMessages(
          beaconId: _draftPost,
          userId: _carol,
        );
        expect(after, hasLength(2));
      });

      test('delivers an attention receipt to every recipient', () async {
        for (final recipient in _recipients) {
          final feed = await harness.attentionQuery.attentionFeed(
            accountId: recipient,
            view: AttentionFeedView.all,
          );
          expect(
            feed.page.items.map((r) => r.beaconId),
            contains(_draftPost),
            reason: 'recipient $recipient',
          );
        }
      });

      test(
        'shows the edge that reached a recipient in the forward graph',
        () async {
          final graph = await harness.graph.asMap(
            beaconId: _draftPost,
            currentUserId: _bob,
          );
          expect(graph.authorId, _author);
          expect(
            graph.edges.map((e) => (e.senderId, e.recipientId)),
            contains((_author, _bob)),
          );
        },
      );
    });
  });
}

Future<int> _count(Connection writer, String table, String beaconId) async {
  final rows = await writer.execute(
    Sql.named('SELECT count(*) FROM public.$table WHERE beacon_id = @id'),
    parameters: {'id': beaconId},
  );
  return rows.single.single! as int;
}

Future<void> _seedUsersAndTrust(Connection writer) async {
  await writer.execute('''
    TRUNCATE TABLE public.notification_outbox,
      public.attention_occurrence_recipient, public.attention_occurrence,
      public.beacon, public."user" CASCADE
  ''');
  for (final id in _users) {
    await writer.execute(
      Sql.named('''
        INSERT INTO public."user" (id, display_name, public_key)
        VALUES (@id, @name, @key)
      '''),
      parameters: {
        'id': id,
        'name': id,
        'key': pgTestPublicKey('aud', _users.indexOf(id) + 1),
      },
    );
  }
  for (final peer in _recipients) {
    await writer.execute(
      Sql.named('''
        INSERT INTO public.vote_user (subject, object, amount)
        VALUES (@author, @peer, 1), (@peer, @author, 1)
      '''),
      parameters: {'author': _author, 'peer': peer},
    );
  }
}

/// An open Request that is due inside the next-UTC-day reminder window.
Future<void> _insertRequest(Connection writer) {
  final today = DateTime.now().toUtc();
  final dueAt = DateTime.utc(
    today.year,
    today.month,
    today.day,
  ).add(const Duration(days: 1, hours: 6));
  return writer.execute(
    Sql.named('''
      INSERT INTO public.beacon
        (id, user_id, title, description, status, kind, published_at, end_at,
         is_discoverable)
      VALUES (@id, @author, 'Need a ladder', 'Borrow one', 0, 0, now(),
        @dueAt, true)
    '''),
    parameters: {'id': _request, 'author': _author, 'dueAt': dueAt},
  );
}

Future<void> _insertPostDraft(Connection writer) => writer.execute(
  Sql.named('''
    INSERT INTO public.beacon
      (id, user_id, title, description, status, kind, forward_policy,
       is_discoverable)
    VALUES (@id, @author, '', '', @draft, @kind, 1, false)
  '''),
  parameters: {
    'id': _draftPost,
    'author': _author,
    'draft': _statusDraft,
    'kind': _kindPost,
  },
);

final class _Harness {
  const _Harness({
    required this.posts,
    required this.forwards,
    required this.helpOffers,
    required this.coordination,
    required this.closure,
    required this.beacons,
    required this.children,
    required this.display,
    required this.graph,
    required this.inbox,
    required this.roomRepository,
    required this.attentionQuery,
    required this.room,
  });

  final PostCase posts;
  final ForwardCase forwards;
  final HelpOfferCase helpOffers;
  final CoordinationCase coordination;
  final ClosureCase closure;
  final BeaconCase beacons;
  final BeaconChildCreateCase children;
  final BeaconDisplayCase display;
  final BeaconForwardGraphCase graph;
  final InboxRepository inbox;
  final BeaconRoomRepository roomRepository;
  final AttentionRepository attentionQuery;
  final BeaconRoomCase room;

  factory _Harness.build(TenturaDb db, Env env) {
    final logger = Logger('PostRequestOnlyAuditPgTest');
    final uow = MutatingUnitOfWork(db);
    final attention = TransactionalAttentionCase(
      uow,
      AttentionDispatchRepository(db, logger),
    );
    final beaconRepository = BeaconRepository(db);
    final roomRepository = BeaconRoomRepository(db);
    final helpOfferRepository = HelpOfferRepository(db);
    final commitments = CommitmentRepository(db);
    final access = BeaconAccessRepository(db);
    final blocks = UserBlockRepository(env, db);
    final hierarchy = BeaconHierarchyRepository(db);
    final inbox = InboxRepository(db);
    final notificationContext = BeaconRoomNotificationContextRepository(
      roomRepository,
      db,
      helpOfferRepository,
      commitments,
    );
    final intents = AttentionIntentCase(
      notificationContext,
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
      helpOfferRepository,
      env: env,
      logger: logger,
    );
    final lifecycleEffects = BeaconLifecycleEffectsCase(
      BeaconHierarchyOutboxRepository(db),
      env: env,
      logger: logger,
    );
    final images = _UnusedImages();
    final tasks = _Tasks();
    final children = BeaconChildCreateCase(
      beaconRepository,
      hierarchy,
      BeaconHierarchyCommandRepository(db),
      access,
      notificationContext,
      attentionIntents: intents,
      attention: attention,
      env: env,
      logger: logger,
    );
    final beacons = BeaconCase(
      beaconRepository,
      images,
      _UnusedImageGc(),
      tasks,
      commitmentQuery,
      access,
      hierarchy,
      children,
      lifecycleEffects,
      attentionIntents: intents,
      attention: attention,
      env: env,
      logger: logger,
    );
    final forwards = ForwardCase(
      ForwardEdgeRepository(db),
      ForwardAttributionRepository(db),
      helpOfferRepository,
      inbox,
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
      beaconRepository: beaconRepository,
      attentionIntents: intents,
      attention: attention,
      env: env,
      logger: logger,
    );
    final closureRepository = ClosureRepository(db);
    final closure = ClosureCase(
      unitOfWork: uow,
      closureRepository: closureRepository,
      beaconRepository: beaconRepository,
      commitmentRepository: commitments,
      helpOfferRepository: helpOfferRepository,
      hierarchyRepository: hierarchy,
      lifecycleEffects: lifecycleEffects,
      attentionSystemSettlement: AttentionSystemSettlementRepository(db),
      receipts: const NoopClosureReceipts(),
      finalizer: _NoFinalizer(),
      env: env,
      logger: logger,
    );
    final coordinationRepository = CoordinationRepository(
      db,
      DriftUserProfileBatchLookup(db, UserAvailabilityRepository(db)),
      VoteUserFriendshipLookup(db),
      roomRepository,
    );
    return _Harness(
      posts: PostCase(
        beaconCase: beacons,
        forwardCase: forwards,
        roomCase: room,
        beaconRepository: beaconRepository,
        postLock: PostLockRepository(db),
        attention: attention,
      ),
      forwards: forwards,
      helpOffers: HelpOfferCase(
        helpOfferRepository,
        beaconRepository,
        commitments,
        inbox,
        CapabilityCase(
          PersonCapabilityEventRepository(db),
          env: env,
          logger: logger,
        ),
        access,
        roomRepository: roomRepository,
        attentionIntents: intents,
        attention: attention,
        env: env,
        logger: logger,
      ),
      coordination: CoordinationCase(
        beaconRepository,
        helpOfferRepository,
        coordinationRepository,
        roomRepository,
        blocks,
        commitments,
        commitmentQuery,
        hierarchy,
        attentionIntents: intents,
        attention: attention,
        guard: access,
        env: env,
        logger: logger,
      ),
      closure: closure,
      beacons: beacons,
      children: children,
      display: BeaconDisplayCase(
        beaconRepository,
        helpOfferRepository,
        coordinationRepository,
        closureRepository,
        roomRepository,
        access,
        commitmentQuery,
        env: env,
        logger: logger,
      ),
      graph: BeaconForwardGraphCase(
        beaconRepository,
        ForwardEdgeRepository(db),
        helpOfferRepository,
        access,
        env: env,
        logger: logger,
      ),
      inbox: inbox,
      roomRepository: roomRepository,
      attentionQuery: AttentionRepository(db),
      room: room,
    );
  }
}

final class _NoProfiles implements UserProfileBatchLookup {
  @override
  Future<Map<String, UserEntity>> userEntitiesByIds(
    Iterable<String> ids,
  ) async => {};

  @override
  Future<Map<String, UserPublicRecord>> userPublicRecordsByIds({
    required Iterable<String> ids,
    required Set<String> reciprocalPeerIds,
    Set<String> trustsViewerPeerIds = const {},
    Set<String> viewerTrustsPeerIds = const {},
    Map<String, MutualScoreRecord> scoresByPeerId = const {},
  }) async => {};
}

final class _UnusedGenealogy extends Fake
    implements InviteGenealogyRepositoryPort {}

final class _UnusedImages extends Fake implements ImageRepositoryPort {}

final class _UnusedImageGc extends Fake implements ImageObjectGcPort {}

final class _UnusedFactCards extends Fake
    implements BeaconFactCardRepositoryPort {}

final class _UnusedPolling extends Fake implements PollingRepositoryPort {}

final class _NoFinalizer extends Fake implements ClosureFinalizerPort {}

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
