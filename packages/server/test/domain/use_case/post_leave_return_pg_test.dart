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
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_child_create_port.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'Uleaveauthor1';
const _member = 'Uleavemember1';
const _other = 'Uleaveother01';
const _stranger = 'Uleavestrang1';
const _users = [_author, _member, _other, _stranger];

const _post = 'Bleavepost001';
const _converted = 'Bleaveconv0001';
const _plainRequest = 'Bleavereq00001';

const _kindRequest = 0;
const _kindPost = 1;

const _inboxNeedsMe = 0;
const _inboxWatching = 1;
const _inboxRejected = 2;

const _roleHelper = 2;

/// An addressee of a Post (`role 6`, or a Request converted from a Post) can
/// step out of its room and come back. Leaving rejects the inbox row (which
/// declines a pending contact edge) and sets `room_access` to left; returning
/// puts the inbox row back to watching and reconciles room access from the
/// live forward edges. The author and anybody who is not an addressee are
/// refused. Real repositories over a disposable Postgres, with real attention
/// dispatch. See `docs/plans/post-and-constellation-composer-plan.md` §4.8.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_LEAVE_RETURN_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_leave_return',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('PostCase leave and return of an addressee', () {
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

    Future<int?> access(String beaconId, String userId) async =>
        (await writer.execute('''
SELECT room_access FROM public.beacon_participant
WHERE beacon_id = '$beaconId' AND user_id = '$userId'
''')).singleOrNull?.single
            as int?;

    Future<int?> inboxStatus(String beaconId, String userId) async =>
        (await writer.execute('''
SELECT status FROM public.inbox_item
WHERE beacon_id = '$beaconId' AND user_id = '$userId'
''')).singleOrNull?.single
            as int?;

    Future<ResultRow> contactEdge(String beaconId, String recipientId) async =>
        (await writer.execute('''
SELECT contact_outcome, contact_resolved_at
FROM public.beacon_forward_edge
WHERE beacon_id = '$beaconId' AND recipient_id = '$recipientId'
  AND sender_id = '$_author'
''')).single;

    Future<void> cancelEdges(String beaconId, String recipientId) =>
        writer.execute('''
UPDATE public.beacon_forward_edge SET cancelled_at = now()
WHERE beacon_id = '$beaconId' AND recipient_id = '$recipientId'
  AND cancelled_at IS NULL
''');

    test('the seeded addressee starts admitted and can post', () async {
      expect(await access(_post, _member), RoomAccessBits.admitted);

      final message = await harness.room.createMessage(
        beaconId: _post,
        userId: _member,
        body: 'Count me in',
      );

      expect(message['id'], isNotNull);
    });

    group('leave', () {
      test('rejects the inbox row and sets room access to left', () async {
        await harness.posts.leave(userId: _member, beaconId: _post);

        expect(await inboxStatus(_post, _member), _inboxRejected);
        expect(await access(_post, _member), RoomAccessBits.left);
      });

      test('declines the pending inbound contact edge', () async {
        final before = await contactEdge(_post, _member);
        expect(before[0], isNull);
        expect(before[1], isNull);

        await harness.posts.leave(userId: _member, beaconId: _post);

        final after = await contactEdge(_post, _member);
        expect(after[0], 2, reason: 'contact_outcome = declined');
        expect(after[1], isNotNull, reason: 'contact is resolved');
      });

      test('closes the room to the member', () async {
        await harness.posts.leave(userId: _member, beaconId: _post);

        await expectLater(
          harness.room.createMessage(
            beaconId: _post,
            userId: _member,
            body: 'Still here?',
          ),
          throwsA(isA<UnauthorizedException>()),
        );
        final rows = await writer.execute('''
SELECT count(*) FROM public.beacon_room_message
WHERE beacon_id = '$_post' AND author_id = '$_member'
''');
        expect(rows.single.single, 0);
      });

      test('leaves other addressees of the Post untouched', () async {
        await harness.posts.leave(userId: _member, beaconId: _post);

        expect(await access(_post, _other), RoomAccessBits.admitted);
        expect(await inboxStatus(_post, _other), _inboxNeedsMe);
      });

      test('a new forward edge does not readmit a member who left', () async {
        await harness.posts.leave(userId: _member, beaconId: _post);

        await _insertEdge(writer, _post, _other, _member);

        expect(await access(_post, _member), RoomAccessBits.left);
      });

      test('works for a Request converted from a Post', () async {
        await harness.posts.leave(userId: _member, beaconId: _converted);

        expect(await inboxStatus(_converted, _member), _inboxRejected);
        expect(await access(_converted, _member), RoomAccessBits.left);
      });
    });

    group('return', () {
      test('with an active edge puts the member back in the room', () async {
        await harness.posts.leave(userId: _member, beaconId: _post);

        await harness.posts.returnTo(userId: _member, beaconId: _post);

        expect(await inboxStatus(_post, _member), _inboxWatching);
        expect(await access(_post, _member), RoomAccessBits.admitted);
      });

      test('without an active edge leaves no room access', () async {
        await harness.posts.leave(userId: _member, beaconId: _post);
        await cancelEdges(_post, _member);
        expect(
          await access(_post, _member),
          RoomAccessBits.left,
          reason: 'cancelling the edge does not undo the leave',
        );

        await harness.posts.returnTo(userId: _member, beaconId: _post);

        expect(await inboxStatus(_post, _member), _inboxWatching);
        expect(await access(_post, _member), RoomAccessBits.none);
      });

      test('after a new edge arrived while away readmits the member', () async {
        await harness.posts.leave(userId: _member, beaconId: _post);
        await cancelEdges(_post, _member);
        await _insertEdge(writer, _post, _other, _member);
        expect(await access(_post, _member), RoomAccessBits.left);

        await harness.posts.returnTo(userId: _member, beaconId: _post);

        expect(await access(_post, _member), RoomAccessBits.admitted);
      });

      test('lets the member post again', () async {
        await harness.posts.leave(userId: _member, beaconId: _post);
        await harness.posts.returnTo(userId: _member, beaconId: _post);

        final message = await harness.room.createMessage(
          beaconId: _post,
          userId: _member,
          body: 'Back again',
        );

        expect(message['id'], isNotNull);
      });

      test(
        'admits a member of a converted Request directly, since Request '
        'admission is not reconciled from edges',
        () async {
          await harness.posts.leave(userId: _member, beaconId: _converted);

          await harness.posts.returnTo(userId: _member, beaconId: _converted);

          expect(await inboxStatus(_converted, _member), _inboxWatching);
          expect(await access(_converted, _member), RoomAccessBits.admitted);
        },
      );
    });

    group('refusals', () {
      test('the author cannot leave their own Post', () async {
        await expectLater(
          harness.posts.leave(userId: _author, beaconId: _post),
          throwsA(isA<UnauthorizedException>()),
        );
      });

      test('the author cannot return to their own Post', () async {
        await expectLater(
          harness.posts.returnTo(userId: _author, beaconId: _post),
          throwsA(isA<UnauthorizedException>()),
        );
      });

      test('a user who is not an addressee cannot leave', () async {
        await expectLater(
          harness.posts.leave(userId: _stranger, beaconId: _post),
          throwsA(isA<UnauthorizedException>()),
        );
        expect(await access(_post, _stranger), isNull);
      });

      test('a user who is not an addressee cannot return', () async {
        await expectLater(
          harness.posts.returnTo(userId: _stranger, beaconId: _post),
          throwsA(isA<UnauthorizedException>()),
        );
        expect(await access(_post, _stranger), isNull);
      });

      test(
        'a participant of a plain Request, who is not an addressee, cannot '
        'leave or return',
        () async {
          await expectLater(
            harness.posts.leave(userId: _member, beaconId: _plainRequest),
            throwsA(isA<UnauthorizedException>()),
          );
          await expectLater(
            harness.posts.returnTo(userId: _member, beaconId: _plainRequest),
            throwsA(isA<UnauthorizedException>()),
          );

          expect(await access(_plainRequest, _member), RoomAccessBits.admitted);
          expect(await inboxStatus(_plainRequest, _member), _inboxNeedsMe);
        },
      );
    });
  });
}

Future<void> _insertEdge(
  Connection writer,
  String beaconId,
  String senderId,
  String recipientId,
) => writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES ('Fleave${senderId.substring(senderId.length - 6)}', '$beaconId',
        '$senderId', '$recipientId')
''');

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
      parameters: {'id': _users[i], 'key': pgTestPublicKey('leave', i + 1)},
    );
  }
  // The Post: the author forwards it to the member and to another addressee;
  // the forward-edge trigger admits both (`role 6`, `room_access 3`).
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES ('$_post', '$_author', '', '', 0, $_kindPost, 1, false, now())
''');
  await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES
  ('Fleaveauthmem01', '$_post', '$_author', '$_member'),
  ('Fleaveauthoth01', '$_post', '$_author', '$_other')
''');
  // A Request converted from a Post: the addressee keeps `role 6`; admission
  // is no longer reconciled from edges.
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, published_at)
VALUES ('$_converted', '$_author', 'Converted', '', 0, $_kindRequest, now())
''');
  await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES ('Fleaveconvmem01', '$_converted', '$_author', '$_member')
''');
  await writer.execute('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES ('Pleaveconvmem01', '$_converted', '$_member', 6, 0, 3)
''');
  // A plain Request in which the member is an ordinary helper.
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, published_at)
VALUES ('$_plainRequest', '$_author', 'Plain', '', 0, $_kindRequest, now())
''');
  await writer.execute('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES ('Pleaveplainmem1', '$_plainRequest', '$_member', $_roleHelper, 0, 3)
''');
  await writer.execute('''
INSERT INTO public.inbox_item (user_id, beacon_id, status)
VALUES
  ('$_member', '$_post', $_inboxNeedsMe),
  ('$_other', '$_post', $_inboxNeedsMe),
  ('$_member', '$_converted', $_inboxNeedsMe),
  ('$_member', '$_plainRequest', $_inboxNeedsMe)
ON CONFLICT (user_id, beacon_id) DO NOTHING
''');
}

final class _Harness {
  const _Harness(this.posts, this.room);

  final PostCase posts;
  final BeaconRoomCase room;

  factory _Harness.build(TenturaDb db, Env env) {
    final logger = Logger('PostLeaveReturnPgTest');
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
      PostCase(
        beaconCase: beacons,
        forwardCase: forwards,
        roomCase: room,
        beaconRepository: beaconRepository,
        postLock: PostLockRepository(db),
        attention: attention,
      ),
      room,
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
