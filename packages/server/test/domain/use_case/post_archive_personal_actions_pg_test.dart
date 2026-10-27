@Tags(['pg'])
library;

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
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

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_ARCHIVE_PERSONAL_ACTIONS_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_archive_actions',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
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
  setUp(() async {
    await _seed(writer);
    await writer.execute("""
INSERT INTO public.inbox_item (user_id, beacon_id, status)
VALUES ('$_member', '$_post', 0)
ON CONFLICT (user_id, beacon_id) DO UPDATE SET status = 0
""");
    await writer.execute("""
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body, reply_to_message_id)
VALUES ('Rarchivereply01', '$_post', '$_other', 'Reply', '$_memberMessage'),
       ('Rarchivebaton01', '$_post', '$_member', 'Baton', NULL),
       ('Rarchiverequest1', '$_request', '$_author', 'Request message', NULL)
""");
    await writer.execute("""
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body, reply_to_message_id)
VALUES ('Rrequestreply01', '$_request', '$_author', 'Reply', 'Rarchiverequest1')
""");
    await writer.execute("""
INSERT INTO public.beacon_room_baton (id, message_id, beacon_id, author_id)
VALUES ('Tarchivebaton01', 'Rarchivebaton01', '$_post', '$_member')
""");
  });
  tearDownAll(
    () => tearDownDisposablePgWriter(session: session, drift: database),
  );

  for (final state in ['closed', 'expired']) {
    group('personal actions in a $state Post', () {
      setUp(() async {
        if (state == 'closed') {
          await writer.execute(
            "UPDATE public.beacon SET status = 6 WHERE id = '$_post'",
          );
        } else {
          await writer.execute(
            "UPDATE public.beacon SET expires_at = now() - interval '1 second' WHERE id = '$_post'",
          );
          final lifecycle = await writer.execute(
            "SELECT status, expires_at <= now() FROM public.beacon WHERE id = '$_post'",
          );
          expect(lifecycle.single.toList(), [0, true]);
        }
      });
      Future<void> expectExpiredPostStillOpen() async {
        if (state != 'expired') return;
        final lifecycle = await writer.execute(
          "SELECT status, expires_at <= now() FROM public.beacon WHERE id = '$_post'",
        );
        expect(lifecycle.single.toList(), [0, true]);
      }
      test(
        'a member can leave and return with inbox and room access restored',
        () async {
          Future<List<Object?>> membership() async => (await writer.execute("""
SELECT p.room_access, i.status FROM public.beacon_participant p
JOIN public.inbox_item i ON i.beacon_id = p.beacon_id AND i.user_id = p.user_id
WHERE p.beacon_id = '$_post' AND p.user_id = '$_member'
""")).single;
          expect(await membership(), [3, 0]);
          await harness.posts.leave(userId: _member, beaconId: _post);
          expect(await membership(), [RoomAccessBits.left, 2]);
          await expectExpiredPostStillOpen();
          await harness.posts.returnTo(userId: _member, beaconId: _post);
          expect(await membership(), [3, 1]);
          await expectExpiredPostStillOpen();
        },
      );
      test(
        'deleting an own message preserves another member reply without a reference',
        () async {
          expect(
            await harness.room.deleteMessage(
              beaconId: _post,
              messageId: _memberMessage,
              userId: _member,
            ),
            isTrue,
          );
          expect(
            await writer.execute(
              "SELECT id FROM public.beacon_room_message WHERE id = '$_memberMessage'",
            ),
            isEmpty,
          );
          final reply = await writer.execute(
            "SELECT author_id, reply_to_message_id FROM public.beacon_room_message WHERE id = 'Rarchivereply01'",
          );
          expect(reply.single.toList(), [_other, null]);
          await expectExpiredPostStillOpen();
        },
      );
      test('a member can delete their own baton message', () async {
        expect(
          await harness.room.deleteMessage(
            beaconId: _post,
            messageId: 'Rarchivebaton01',
            userId: _member,
          ),
          isTrue,
        );
        expect(
          await writer.execute(
            "SELECT id FROM public.beacon_room_message WHERE id = 'Rarchivebaton01'",
          ),
          isEmpty,
        );
        await expectExpiredPostStillOpen();
      });
      test('a member cannot delete another member message', () async {
        await expectLater(
          harness.room.deleteMessage(
            beaconId: _post,
            messageId: 'Rarchivereply01',
            userId: _member,
          ),
          throwsA(isA<UnauthorizedException>()),
        );
        expect(
          await writer.execute(
            "SELECT id FROM public.beacon_room_message WHERE id = 'Rarchivereply01'",
          ),
          hasLength(1),
        );
        await expectExpiredPostStillOpen();
      });
      test('the author can delete the Post through its root', () async {
        expect(
          await harness.room.deleteMessage(
            beaconId: _post,
            messageId: _root,
            userId: _author,
          ),
          isTrue,
        );
        expect(
          (await writer.execute(
            "SELECT status FROM public.beacon WHERE id = '$_post'",
          )).single.single,
          2,
        );
        // Published Post deletion is a status transition; its root remains
        // attached to the deleted Post rather than being hard-deleted.
        expect(
          await writer.execute(
            "SELECT id FROM public.beacon_room_message WHERE id = '$_root'",
          ),
          hasLength(1),
        );
      });
    });
  }
  test('an open Request allows deletion of an own message', () async {
    expect(
      await harness.room.deleteMessage(
        beaconId: _request,
        messageId: 'Rarchiverequest1',
        userId: _author,
      ),
      isTrue,
    );
    expect(
      await writer.execute(
        "SELECT id FROM public.beacon_room_message WHERE id = 'Rarchiverequest1'",
      ),
      isEmpty,
    );
    expect(
      (await writer.execute(
        "SELECT status FROM public.beacon WHERE id = '$_request'",
      )).single.single,
      0,
    );
  });
  test('a closed Request refuses deletion of a message with a reply', () async {
    await writer.execute(
      "UPDATE public.beacon SET status = 6 WHERE id = '$_request'",
    );
    await expectLater(
      harness.room.deleteMessage(
        beaconId: _request,
        messageId: 'Rarchiverequest1',
        userId: _author,
      ),
      throwsA(isA<BeaconCreateException>()),
    );
    expect(
      await writer.execute(
        "SELECT id FROM public.beacon_room_message WHERE id = 'Rarchiverequest1'",
      ),
      hasLength(1),
    );
    expect(
      (await writer.execute(
        "SELECT reply_to_message_id FROM public.beacon_room_message WHERE id = 'Rrequestreply01'",
      )).single.single,
      'Rarchiverequest1',
    );
  });
}

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
