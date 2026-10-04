@Tags(['pg'])
library;


import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

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
import 'package:tentura_server/domain/entity/beacon_kind.dart';
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

const _author = 'Upubauthor01';
const _bob = 'Upubbob00001';
const _carol = 'Upubcarol001';
const _stranger = 'Upubstrang01';
const _beacon = 'Bpubdraft001';
const _body = 'Hello @Bob, welcome to the thread';
const _users = [_author, _bob, _carol, _stranger];
const _kindPost = 1;
const _statusDraft = 3;

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_PUBLISH_NO_MR_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_publish_no_mr',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('PostCase.publish on a database without MeritRank', () {
    late DisposablePgWriterSession session;
    late TenturaDb database;
    late _Harness harness;
    late Connection writer;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: target,
      );
      writer = session.writer;
      // Plain pg-tagged databases do not ship the MeritRank extension.
      await writer.execute('DROP EXTENSION IF EXISTS pgmer2 CASCADE');
      await writer.execute(
        'DROP FUNCTION IF EXISTS public.mr_mutual_scores(text, text)',
      );
      database = openDisposablePgDatabase(target);
      harness = _Harness.build(database, target.databaseEnv);
    });
    setUp(() async => _seed(writer));
    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<dynamic> publish({
      String authorId = _author,
      String body = _body,
      List<String> recipientIds = const [_bob, _carol],
      Map<String, String> notes = const {},
      BeaconForwardPolicyValue policy = BeaconForwardPolicyValue.closed,
      List<String> mentionUserIds = const [_bob],
      List<int> mentionOffsets = const [6],
      List<int> mentionLengths = const [4],
      Stream<Uint8List>? attachmentBytes,
    }) => harness.posts.publish(
      authorId: authorId,
      beaconId: _beacon,
      body: body,
      mentionUserIds: mentionUserIds,
      mentionOffsets: mentionOffsets,
      mentionLengths: mentionLengths,
      recipientIds: recipientIds,
      notes: notes,
      forwardPolicy: policy,
      attachmentBytes: attachmentBytes,
      attachmentFilename: attachmentBytes == null ? null : 'note.txt',
      attachmentMimeType: attachmentBytes == null ? null : 'text/plain',
    );

    test(
      'the MeritRank function is absent from public in this database',
      () async {
        final rows = await writer.execute(
          'SELECT count(*) FROM pg_proc p '
          'JOIN pg_namespace n ON n.oid = p.pronamespace '
          "WHERE n.nspname = 'public' AND p.proname = 'mr_mutual_scores' "
          "AND pg_get_function_identity_arguments(p.oid) = 'text, text'",
        );
        expect(rows.first.first, 0);
      },
    );

    test(
      'fails the whole call with a domain error and writes nothing when a '
      'recipient has no trust edge',
      () async {
        await expectLater(
          publish(
            recipientIds: const [_bob, _stranger],
            mentionUserIds: const [],
            mentionOffsets: const [],
            mentionLengths: const [],
          ),
          throwsA(isA<ExceptionBase>()),
        );

        expect(await _state(writer), _untouchedState);
      },
    );
  });
}

/// status, policy, edges, addressees, messages, receipts, root message id.
const _untouchedState = <Object?>[_statusDraft, 1, 0, 0, 0, 0, null];

Future<void> _seed(Connection writer) async {
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
        'name': switch (id) {
          _bob => 'Bob',
          _carol => 'Carol',
          _ => id,
        },
        'key': pgTestPublicKey('pub', _users.indexOf(id) + 1),
      },
    );
  }
  for (final peer in [_bob, _carol]) {
    await writer.execute(
      Sql.named('''
        INSERT INTO public.vote_user (subject, object, amount)
        VALUES (@author, @peer, 1), (@peer, @author, 1)
      '''),
      parameters: {'author': _author, 'peer': peer},
    );
  }
  await writer.execute(
    Sql.named('''
      INSERT INTO public.beacon
        (id, user_id, title, description, status, kind, forward_policy,
         is_discoverable)
      VALUES (@beacon, @author, '', '', @draft, @kind, 1, false)
    '''),
    parameters: {
      'beacon': _beacon,
      'author': _author,
      'draft': _statusDraft,
      'kind': _kindPost,
    },
  );
}

Future<List<Object?>> _state(Connection writer) async {
  final rows = await writer.execute(
    Sql.named('''
      SELECT status, forward_policy,
        (SELECT count(*) FROM public.beacon_forward_edge WHERE beacon_id = @id),
        (SELECT count(*) FROM public.beacon_participant
         WHERE beacon_id = @id AND role = 6),
        (SELECT count(*) FROM public.beacon_room_message WHERE beacon_id = @id),
        (SELECT count(*) FROM public.notification_outbox WHERE beacon_id = @id),
        post_root_message_id
      FROM public.beacon WHERE id = @id
    '''),
    parameters: {'id': _beacon},
  );
  return rows.single.toList();
}

final class _Harness {
  const _Harness(this.posts, this.room);

  final PostCase posts;
  final BeaconRoomCase room;

  static _Harness build(TenturaDb db, Env env) {
    final logger = Logger('PostCasePublishWithoutMeritRankPgTest');
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
