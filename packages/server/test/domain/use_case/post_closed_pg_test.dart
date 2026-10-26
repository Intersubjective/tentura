@Tags(['pg'])
library;

import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_hierarchy_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/capability_evidence_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/coordination_item_repository.dart';
import 'package:tentura_server/data/repository/forward_attribution_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/person_visibility_repository.dart';
import 'package:tentura_server/data/repository/post_lock_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
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
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/post_case.dart';
import 'package:tentura_server/domain/use_case/post_close_operation.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_child_create_port.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'Uclosedauthor1';
const _member = 'Uclosedmember1';
const _other = 'Uclosedother01';
const _stranger = 'Uclosedstrang1';
const _users = [_author, _member, _other, _stranger];

const _post = 'Bclosedpost001';
const _child = 'Bclosedchild01';
const _request = 'Bclosedreq0001';
const _root = 'Rclosedroot001';
const _memberMessage = 'Rclosedmemb001';

/// Post→Request budding, plan unit C5 (Arch §2.3): a Post closed by budding
/// (status 6) is read-only for everyone, stays readable for its members, and
/// can still be deleted by its author through the root message.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_CLOSED_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_closed',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

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

  // Only the Post's author may close it (#666).
  Future<void> closePost({String postId = _post, String actor = _author}) =>
      harness.uow.run(
        actorUserId: actor,
        action: () => harness.close.closeForBud(
          postId: postId,
          childBeaconId: _child,
          title: 'Fix the fence',
          actorId: actor,
        ),
      );

  Future<int> status(String beaconId) async =>
      (await writer.execute(
            "SELECT status FROM public.beacon WHERE id = '$beaconId'",
          )).single.single!
          as int;

  Future<int> count(String sql) async =>
      (await writer.execute(sql)).single.single! as int;

  group('PostCloseOperation.closeForBud', () {
    test('moves the Post to closed and logs the transition', () async {
      await closePost();

      expect(await status(_post), 6);
      final events = await writer.execute('''
SELECT diff, actor_id FROM public.beacon_activity_event
WHERE beacon_id = '$_post' ORDER BY created_at
''');
      final diff = _json(events.last[0]);
      expect(diff['fromStatus'], 0);
      expect(diff['toStatus'], 6);
      expect(events.last[1], _author);
    });

    test(
      'a member who is not the author cannot close the Post (#666)',
      () async {
        await expectLater(
          closePost(actor: _member),
          throwsA(isA<BeaconChildCreateForbiddenException>()),
        );
        expect(await status(_post), 0, reason: 'still open');
      },
    );

    test(
      'inserts one postClosed notice with the child and the title',
      () async {
        await closePost();

        final notices = await writer.execute('''
SELECT system_payload, author_id FROM public.beacon_room_message
WHERE beacon_id = '$_post'
  AND system_message_kind = ${BeaconRoomSystemMessageKind.postClosed}
''');
        expect(notices, hasLength(1));
        expect(_json(notices.single[0]), {
          'childBeaconId': _child,
          'title': 'Fix the fence',
          'reason': 'budded',
        });
        expect(notices.single[1], isNull);
      },
    );

    test('the child gets no lifecycle notice, and nobody a receipt', () async {
      await closePost();

      expect(
        await count('''
SELECT count(*)::int FROM public.beacon_room_message
WHERE beacon_id = '$_child' AND system_message_kind IS NOT NULL
'''),
        0,
      );
      expect(
        await count(
          'SELECT count(*)::int FROM public.beacon_hierarchy_deliveries',
        ),
        0,
      );
      expect(
        await count('SELECT count(*)::int FROM public.beacon_hierarchy_events'),
        0,
      );
      expect(
        await count('SELECT count(*)::int FROM public.notification_outbox'),
        0,
      );
      expect(await status(_child), 0);
    });

    test('leaves a Post that is already closed as it is', () async {
      await closePost();
      await closePost();
      expect(
        await count('''
SELECT count(*)::int FROM public.beacon_room_message
WHERE system_message_kind = ${BeaconRoomSystemMessageKind.postClosed}
'''),
        1,
      );
    });

    test('refuses a Request', () async {
      await expectLater(
        closePost(postId: _request),
        throwsA(isA<PostNotOpenException>()),
      );
      expect(await status(_request), 0);
    });
  });

  group('a closed Post', () {
    setUp(closePost);

    test('refuses a new message', () async {
      await expectLater(
        harness.room.createMessage(
          beaconId: _post,
          userId: _member,
          body: 'Still here?',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
    });

    test('refuses an edit', () async {
      await expectLater(
        harness.room.editMessage(
          beaconId: _post,
          messageId: _memberMessage,
          userId: _member,
          newBody: 'Edited',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
    });

    test('refuses a reaction', () async {
      await expectLater(
        harness.room.reactionToggle(
          beaconId: _post,
          messageId: _root,
          userId: _member,
          emoji: '\u{1F44D}',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
    });

    test('refuses a poll', () async {
      await expectLater(
        harness.room.createPoll(
          beaconId: _post,
          userId: _member,
          question: 'When?',
          variants: const ['Today', 'Tomorrow'],
        ),
        throwsA(isA<BeaconCreateException>()),
      );
    });

    test('refuses deleting a non-root message', () async {
      await expectLater(
        harness.room.deleteMessage(
          beaconId: _post,
          messageId: _memberMessage,
          userId: _member,
        ),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(
        await count('''
SELECT count(*)::int FROM public.beacon_room_message
WHERE id = '$_memberMessage'
'''),
        1,
      );
    });

    test('refuses a forward', () async {
      await expectLater(
        harness.forwards.forward(
          senderId: _author,
          beaconId: _post,
          recipientIds: const [_stranger],
        ),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(
        await count('''
SELECT count(*)::int FROM public.beacon_forward_edge
WHERE beacon_id = '$_post' AND recipient_id = '$_stranger'
'''),
        0,
      );
    });

    test('refuses leave and return', () async {
      await expectLater(
        harness.posts.leave(userId: _member, beaconId: _post),
        throwsA(isA<PostNotOpenException>()),
      );
      await expectLater(
        harness.posts.returnTo(userId: _member, beaconId: _post),
        throwsA(isA<PostNotOpenException>()),
      );
      expect(
        await count('''
SELECT room_access::int FROM public.beacon_participant
WHERE beacon_id = '$_post' AND user_id = '$_member'
'''),
        3,
      );
    });

    test('stays readable for its members, notice included', () async {
      final messages = await harness.room.listMessages(
        beaconId: _post,
        userId: _member,
      );
      final ids = messages.map((m) => m['id']).toSet();
      expect(ids, containsAll([_root, _memberMessage]));
      expect(
        messages.where(
          (m) =>
              m['systemMessageKind'] == BeaconRoomSystemMessageKind.postClosed,
        ),
        hasLength(1),
      );
      expect(
        await count('''
SELECT count(*)::int FROM public."user" u
WHERE u.id IN ('$_author', '$_member', '$_other')
  AND public.beacon_can_read_content('$_post', u.id)
'''),
        3,
      );
    });

    test('its author can still delete it through the root; the child '
        'survives', () async {
      expect(
        await harness.room.deleteMessage(
          beaconId: _post,
          messageId: _root,
          userId: _author,
        ),
        isTrue,
      );
      expect(await status(_post), 2);
      expect(await status(_child), 0);
    });

    test('a member still cannot delete the root', () async {
      await expectLater(
        harness.room.deleteMessage(
          beaconId: _post,
          messageId: _root,
          userId: _member,
        ),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(await status(_post), 6);
    });
  });
}

Map<String, Object?> _json(Object? value) => switch (value) {
  final Map<String, Object?> map => map,
  final String text => jsonDecode(text) as Map<String, Object?>,
  _ => throw StateError('Not JSON: $value'),
};

Future<void> _seed(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.beacon_hierarchy_deliveries,
  public.beacon_hierarchy_events,
  public.notification_outbox,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.inbox_item,
  public.beacon_activity_event,
  public.beacon_room_message_reaction,
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
      parameters: {'id': _users[i], 'key': pgTestPublicKey('closed', i + 1)},
    );
  }
  // The Post: the author forwards it to the member and to another addressee;
  // the forward-edge trigger admits both (`role 6`, `room_access 3`).
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES ('$_post', '$_author', '', '', 0, 1, 1, false, now())
''');
  await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES
  ('Fclosedauthmem1', '$_post', '$_author', '$_member'),
  ('Fclosedauthoth1', '$_post', '$_author', '$_other')
''');
  await writer.execute('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES
  ('$_root', '$_post', '$_author', 'The fence is down'),
  ('$_memberMessage', '$_post', '$_member', 'I can fix it')
''');
  await writer.execute('''
UPDATE public.beacon SET post_root_message_id = '$_root' WHERE id = '$_post'
''');
  // The Request budded from the member's message.
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, parent_beacon_id,
   is_discoverable, published_at)
VALUES ('$_child', '$_member', 'Fix the fence', '', 0, 0, '$_post', false,
        now())
''');
  // An unrelated Request.
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, published_at)
VALUES ('$_request', '$_author', 'Request', '', 0, 0, now())
''');
}

final class _Harness {
  const _Harness({
    required this.uow,
    required this.posts,
    required this.room,
    required this.forwards,
    required this.close,
  });

  final MutatingUnitOfWork uow;
  final PostCase posts;
  final BeaconRoomCase room;
  final ForwardCase forwards;
  final PostCloseOperation close;

  factory _Harness.build(TenturaDb db, Env env) {
    final logger = Logger('PostClosedPgTest');
    final uow = MutatingUnitOfWork(db);
    final attention = TransactionalAttentionCase(
      uow,
      AttentionDispatchRepository(db, logger),
    );
    final beaconRepository = BeaconRepository(db);
    final roomRepository = BeaconRoomRepository(db);
    final help = HelpOfferRepository(db);
    final commitments = CommitmentRepository(db);
    final access = BeaconAccessRepository(db);
    final blocks = UserBlockRepository(env, db);
    final hierarchy = BeaconHierarchyRepository(db);
    final postLock = PostLockRepository(db);
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
    final images = _UnusedImages();
    final tasks = _Tasks();
    final beacons = BeaconCase(
      beaconRepository,
      images,
      _UnusedImageGc(),
      tasks,
      CommitmentQueryCase(commitments, help, env: env, logger: logger),
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
      postLock: postLock,
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
      beaconCase: beacons,
      postLock: postLock,
      attentionIntents: intents,
      attention: attention,
      env: env,
      logger: logger,
    );
    return _Harness(
      uow: uow,
      posts: PostCase(
        beaconCase: beacons,
        forwardCase: forwards,
        roomCase: room,
        beaconRepository: beaconRepository,
        postLock: postLock,
        attention: attention,
      ),
      room: room,
      forwards: forwards,
      close: PostCloseOperation(beaconRepository),
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
