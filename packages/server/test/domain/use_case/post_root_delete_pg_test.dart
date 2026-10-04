@Tags(['pg'])
library;

import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/coordination_item_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/post_lock_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/entity/beacon_conversion_content.dart';
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
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_child_create_port.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'Ufirstrespauth1';
const _memberB = 'Ufirstrespmemb1';
const _memberC = 'Ufirstrespmemb2';
const _users = [_author, _memberB, _memberC];

const _post = 'Bfirstresppost01';
const _request = 'Bfirstrespreq001';
const _postRoot = 'Rfirstresppost01';
const _requestRoot = 'Rfirstrespreq001';

/// Root deletion shares the Post lifecycle; converted roots are ordinary messages.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_ROOT_DELETE_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_root_delete',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }
  group('Post root deletion', () {
    late DisposablePgWriterSession session;
    late TenturaDb database;
    late BeaconRoomCase room;
    late BeaconCase beacons;
    late Connection writer;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      room = _buildRoom(database, target.databaseEnv).room;
      beacons = _buildBeaconCase(database, target.databaseEnv);
    });
    setUp(() async => _seed(writer));
    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<List<Object?>> postRow() async => (await writer.execute(
      "SELECT status, kind, post_root_message_id FROM public.beacon WHERE id = '$_post'",
    )).single;
    Future<bool> messageExists(String id) async =>
        (await writer.execute(
              Sql.named(
                'SELECT EXISTS(SELECT 1 FROM public.beacon_room_message WHERE id = @id)',
              ),
              parameters: {'id': id},
            )).single.single!
            as bool;

    test('author deleting the root deletes the Post', () async {
      expect(
        await room.deleteMessage(
          beaconId: _post,
          messageId: _postRoot,
          userId: _author,
        ),
        isTrue,
      );
      expect((await postRow())[0], 2);
    });

    test(
      'member deleting their own message leaves the Post and root',
      () async {
        const messageId = 'Rrootdelmember01';
        await writer.execute(
          Sql.named("""
        INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
        VALUES (@id, @beacon, @author, 'Reply')
      """),
          parameters: {'id': messageId, 'beacon': _post, 'author': _memberB},
        );
        expect(
          await room.deleteMessage(
            beaconId: _post,
            messageId: messageId,
            userId: _memberB,
          ),
          isTrue,
        );
        expect(await messageExists(messageId), isFalse);
        expect(await messageExists(_postRoot), isTrue);
        expect(await postRow(), [0, 1, _postRoot]);
      },
    );

    test('a member cannot delete the author root', () async {
      await expectLater(
        room.deleteMessage(
          beaconId: _post,
          messageId: _postRoot,
          userId: _memberB,
        ),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(await postRow(), [0, 1, _postRoot]);
      expect(await messageExists(_postRoot), isTrue);
    });

    test(
      'after conversion deleting the former root only removes the message',
      () async {
        await beacons.convertToRequest(
          authorId: _author,
          beaconId: _post,
          content: const BeaconConversionContent(
            title: 'Request',
            description: 'Help with this',
          ),
          isDiscoverable: false,
        );
        expect((await postRow())[1], 0);
        expect(
          await room.deleteMessage(
            beaconId: _post,
            messageId: _postRoot,
            userId: _author,
          ),
          isTrue,
        );
        expect(await messageExists(_postRoot), isFalse);
        expect(await postRow(), [0, 0, null]);
      },
    );
  });
}

BeaconCase _buildBeaconCase(TenturaDb db, Env env) {
  final logger = Logger('PostConvertPgTest');
  final uow = MutatingUnitOfWork(db);
  final attention = TransactionalAttentionCase(
    uow,
    AttentionDispatchRepository(db, logger),
  );
  final help = HelpOfferRepository(db);
  final commitments = CommitmentRepository(db);
  final access = BeaconAccessRepository(db);
  final blocks = UserBlockRepository(env, db);
  final intents = AttentionIntentCase(
    BeaconRoomNotificationContextRepository(
      BeaconRoomRepository(db),
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
  return BeaconCase(
    BeaconRepository(db),
    _UnusedImages(),
    _UnusedImageGc(),
    _Tasks(),
    CommitmentQueryCase(commitments, help, env: env, logger: logger),
    access,
    BeaconHierarchyRepository(db),
    FakeBeaconChildCreatePort(),
    BeaconLifecycleEffectsCase(
      BeaconHierarchyOutboxRepository(db),
      env: env,
      logger: logger,
    ),
    postLock: PostLockRepository(db),
    attentionIntents: intents,
    attention: attention,
    env: env,
    logger: logger,
  );
}

({BeaconRoomCase room, BeaconRoomRepository roomRepository}) _buildRoom(
  TenturaDb db,
  Env env,
) {
  final logger = Logger('PostFirstResponsePgTest');
  final uow = MutatingUnitOfWork(db);
  final attention = TransactionalAttentionCase(
    uow,
    AttentionDispatchRepository(db, logger),
  );
  final roomRepository = BeaconRoomRepository(db);
  final blocks = UserBlockRepository(env, db);
  final intents = AttentionIntentCase(
    BeaconRoomNotificationContextRepository(
      roomRepository,
      db,
      HelpOfferRepository(db),
      CommitmentRepository(db),
    ),
    UserRepository(
      env,
      db,
      _UnusedGenealogy(),
      InviteSeedPromptRepositoryMock(),
    ),
    BeaconAccessRepository(db),
    blocks,
  );
  return (
    room: BeaconRoomCase(
      roomRepository,
      CoordinationItemRepository(db),
      _UnusedFactCards(),
      _UnusedImages(),
      _Tasks(),
      _Storage(),
      _UnusedPolling(),
      _Quota(),
      blocks,
      uow,
      BeaconHierarchyRepository(db),
      const ProductionDiscussionProductPolicy(),
      beaconRepository: BeaconRepository(db),
      beaconCase: _buildBeaconCase(db, env),
      postLock: PostLockRepository(db),
      attentionIntents: intents,
      attention: attention,
      env: env,
      logger: logger,
    ),
    roomRepository: roomRepository,
  );
}

Future<void> _seed(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.post_first_response,
  public.notification_outbox,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.inbox_item,
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
      parameters: {'id': _users[i], 'key': pgTestPublicKey('firstresp', i + 1)},
    );
  }
  // The Post: the author forwards it to both members; the forward-edge trigger
  // admits them as addressees.
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES ('$_post', '$_author', '', '', 0, 1, 1, false, now())
''');
  await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES
  ('Ffirstrespedge1', '$_post', '$_author', '$_memberB'),
  ('Ffirstrespedge2', '$_post', '$_author', '$_memberC')
''');
  await writer.execute('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES ('$_postRoot', '$_post', '$_author', 'Heads up')
''');
  await writer.execute('''
UPDATE public.beacon SET post_root_message_id = '$_postRoot'
WHERE id = '$_post'
''');
  // A Request with the same people in its room.
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at)
VALUES ('$_request', '$_author', 'Request', '', 0, now())
''');
  await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES ('Ffirstrespedge3', '$_request', '$_author', '$_memberB')
''');
  await writer.execute('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES ('Pfirstrespreqb01', '$_request', '$_memberB', 0, 0, 3)
''');
  await writer.execute('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES ('$_requestRoot', '$_request', '$_author', 'Welcome')
''');
}

final class _UnusedGenealogy extends Fake
    implements InviteGenealogyRepositoryPort {}

final class _UnusedImages extends Fake implements ImageRepositoryPort {}

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

final class _UnusedImageGc extends Fake implements ImageObjectGcPort {}
