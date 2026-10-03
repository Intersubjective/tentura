@Tags(['pg'])
library;

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_channel_delivery_repository.dart';
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
import 'package:tentura_server/data/service/beacon_notification_service.dart';
import 'package:tentura_server/data/service/fcm_batch_queue.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/fcm_message_entity.dart';
import 'package:tentura_server/domain/entity/fcm_token_entity.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_preferences_entity.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/email_notification_port.dart';
import 'package:tentura_server/domain/port/fcm_remote_repository_port.dart';
import 'package:tentura_server/domain/port/fcm_token_repository_port.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/notification_preference_repository_port.dart';
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

const _author = 'Unotifauthor01';
const _bob = 'Unotifbob00001';
const _carol = 'Unotifcarol001';
const _beacon = 'Bnotifpost0001';
const _request = 'Bnotifrequest01';
const _users = [_author, _bob, _carol];
const _kindPost = 1;
const _statusDraft = 3;

/// A Post's arrival and its first response reach push/email as Post copy, and
/// batches of them as Post batch copy; a Request relay keeps its Request copy.
/// The jobs come from real `PostCase.publish`, `ForwardCase.forward` and room
/// writes over real attention dispatch; they are claimed the way the delivery
/// worker claims them and handed to the real notification service and the real
/// FCM batch queue, with only the device transport faked.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_NOTIFICATION_PIPELINE_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_notif_pipeline',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('Post notification pipeline with real dispatch', () {
    late DisposablePgWriterSession session;
    late TenturaDb database;
    late _Harness harness;
    late Connection writer;
    late AttentionChannelDeliveryRepository deliveries;
    late _RecordingRemote remote;
    FcmBatchQueue? queue;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      harness = _buildHarness(database, target.databaseEnv);
      deliveries = AttentionChannelDeliveryRepository(database);
    });
    setUp(() async {
      await _seed(writer);
      remote = _RecordingRemote();
    });
    tearDown(() {
      queue?.dispose();
      queue = null;
    });
    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<void> publish() => harness.posts.publish(
      authorId: _author,
      beaconId: _beacon,
      body: 'Have a look at this',
      mentionUserIds: const [],
      mentionOffsets: const [],
      mentionLengths: const [],
      recipientIds: const [_bob, _carol],
      notes: const {},
      forwardPolicy: BeaconForwardPolicyValue.open,
    );

    Future<void> forward({
      required String senderId,
      required String beaconId,
      required List<String> recipientIds,
    }) => harness.forwards.forward(
      senderId: senderId,
      beaconId: beaconId,
      recipientIds: recipientIds,
    );

    /// Every pending delivery job, claimed the way the worker claims them: at
    /// most one job per account per claim, so claim until none are left.
    Future<List<AttentionChannelDecision>> claimJobs() async {
      final claimed = <AttentionChannelDecision>[];
      var now = DateTime.timestamp().add(const Duration(days: 1));
      for (var round = 0; round < 10; round++) {
        final jobs = await deliveries.claimDue(
          workerId: 'post-notification-pipeline-test',
          now: now,
          limit: 50,
        );
        if (jobs.isEmpty) break;
        for (final job in jobs) {
          claimed.add(job.decision);
          await deliveries.markDelivered(
            id: job.id,
            workerId: 'post-notification-pipeline-test',
          );
        }
        now = now.add(const Duration(minutes: 5));
      }
      return claimed;
    }

    List<AttentionChannelDecision> forRecipient(
      List<AttentionChannelDecision> jobs,
      String recipientId,
    ) => [
      for (final job in jobs)
        if (job.recipientId == recipientId) job,
    ];

    /// Hands [jobs] to the real notification service and returns what the real
    /// batch queue finally sends. The queue is built here so its one-second
    /// flush cannot fire between two hand-offs of the same window.
    Future<List<FcmNotificationEntity>> pushed(
      List<AttentionChannelDecision> jobs, {
      Map<String, String> locales = const {},
    }) async {
      final logger = Logger('PostNotificationPipelinePgTest');
      final batch = queue = FcmBatchQueue(remote, logger);
      final channels = BeaconNotificationService(
        batch,
        _Tokens(),
        remote,
        _Preferences(locales),
        _SilentEmail(),
        logger,
      );
      await channels.handOffChannels(jobs);
      final deadline = DateTime.timestamp().add(const Duration(seconds: 10));
      while (remote.sent.isEmpty && DateTime.timestamp().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return remote.sent;
    }

    group('a Post arrival', () {
      test('has a job that says a post was shared', () async {
        await publish();

        final jobs = await claimJobs();

        for (final recipient in [_bob, _carol]) {
          final job = forRecipient(jobs, recipient).single;
          expect(job.kind, NotificationKind.newRelay);
          expect(job.title, 'Alice');
          expect(job.body, 'Alice shared a post with you');
        }
      });

      test('is pushed with the Post copy', () async {
        await publish();
        final job = forRecipient(await claimJobs(), _bob).single;

        final sent = await pushed([job]);

        expect(sent.single.body, 'Alice shared a post with you');
      });

      test(
        'is pushed in Russian to a recipient whose locale is Russian',
        () async {
          await publish();
          final jobs = await claimJobs();

          final sent = await pushed(
            [forRecipient(jobs, _bob).single],
            locales: const {_bob: 'ru'},
          );

          expect(sent.single.body, 'Alice поделился постом с вами');
        },
      );

      test('two distinct arrivals in one window are pushed as one Post '
          'batch', () async {
        await publish();
        await forward(
          senderId: _bob,
          beaconId: _beacon,
          recipientIds: const [_carol],
        );
        final arrivals = forRecipient(await claimJobs(), _carol);
        expect(arrivals.map((job) => job.body), [
          'Alice shared a post with you',
          'Bob shared a post with you',
        ]);

        final sent = await pushed(arrivals);

        expect(sent, hasLength(1));
        expect(sent.single.body, startsWith('2 posts shared with you'));
      });
    });

    group('a first response to a Post', () {
      test('has a job that carries the responder text', () async {
        await publish();
        await harness.room.createMessage(
          beaconId: _beacon,
          userId: _bob,
          body: 'Count me in',
        );

        final job = forRecipient(await claimJobs(), _author).single;

        expect(job.kind, NotificationKind.postFirstResponse);
        expect(job.title, 'Bob');
        expect(job.body, 'Count me in');
      });

      test('two distinct responses in one window are pushed as one replies '
          'batch', () async {
        await publish();
        await harness.room.createMessage(
          beaconId: _beacon,
          userId: _bob,
          body: 'Count me in',
        );
        await harness.room.createMessage(
          beaconId: _beacon,
          userId: _carol,
          body: 'Me too',
        );
        final responses = forRecipient(await claimJobs(), _author);
        expect(responses.map((job) => job.body), ['Count me in', 'Me too']);

        final sent = await pushed(responses);

        expect(sent, hasLength(1));
        expect(sent.single.body, startsWith('2 replies to your posts'));
      });
    });

    group('a Request relay', () {
      test('has a job that says a request was forwarded', () async {
        await forward(
          senderId: _author,
          beaconId: _request,
          recipientIds: const [_bob],
        );

        final job = forRecipient(await claimJobs(), _bob).single;

        expect(job.kind, NotificationKind.newRelay);
        expect(job.body, 'Alice forwarded a request to you');
      });

      test('two distinct relays in one window keep the Request batch '
          'text', () async {
        await forward(
          senderId: _author,
          beaconId: _request,
          recipientIds: const [_bob, _carol],
        );
        await forward(
          senderId: _bob,
          beaconId: _request,
          recipientIds: const [_carol],
        );
        final arrivals = forRecipient(await claimJobs(), _carol);
        expect(arrivals.map((job) => job.body), [
          'Alice forwarded a request to you',
          'Bob forwarded a request to you',
        ]);

        final sent = await pushed(arrivals);

        expect(sent, hasLength(1));
        expect(sent.single.body, startsWith('2 requests forwarded to you'));
      });
    });
  });
}

Future<void> _seed(Connection writer) async {
  await writer.execute('''
    TRUNCATE TABLE public.attention_channel_delivery,
      public.attention_channel_throttle, public.post_first_response,
      public.notification_outbox,
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
          _author => 'Alice',
          _bob => 'Bob',
          _ => 'Carol',
        },
        'key': pgTestPublicKey('notif', _users.indexOf(id) + 1),
      },
    );
  }
  for (final (subject, object) in const [
    (_author, _bob),
    (_bob, _author),
    (_author, _carol),
    (_carol, _author),
    (_bob, _carol),
    (_carol, _bob),
  ]) {
    await writer.execute(
      Sql.named('''
        INSERT INTO public.vote_user (subject, object, amount)
        VALUES (@subject, @object, 1)
      '''),
      parameters: {'subject': subject, 'object': object},
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
  await writer.execute(
    Sql.named('''
      INSERT INTO public.beacon
        (id, user_id, title, description, status, kind, published_at,
         is_discoverable)
      VALUES (@id, @author, 'Need a ladder', 'Borrow one', 0, 0, now(), true)
    '''),
    parameters: {'id': _request, 'author': _author},
  );
}

final class _RecordingRemote implements FcmRemoteRepositoryPort {
  final sent = <FcmNotificationEntity>[];

  @override
  Future<List<Exception>> sendChatNotification({
    required Iterable<String> fcmTokens,
    required FcmNotificationEntity message,
  }) async {
    sent.add(message);
    return const [];
  }
}

final class _Tokens extends Fake implements FcmTokenRepositoryPort {
  @override
  Future<Iterable<FcmTokenEntity>> getTokensByUserId(String userId) async => [
    FcmTokenEntity(
      userId: userId,
      appId: UuidValue.fromString('00000000-0000-4000-8000-000000000001'),
      platform: 'web',
      token: 'token-$userId',
      createdAt: DateTime.utc(2026),
      lastRefreshedAt: DateTime.utc(2026),
    ),
  ];
}

final class _Preferences extends Fake
    implements NotificationPreferenceRepositoryPort {
  _Preferences(this.locales);

  final Map<String, String> locales;

  @override
  Future<NotificationPreferencesEntity> getForAccount(String accountId) async =>
      NotificationPreferencesEntity.defaults(
        accountId,
      ).copyWith(locale: locales[accountId] ?? 'en');

  @override
  Future<Set<String>> getMutedBeaconIds(String accountId, DateTime now) async =>
      const {};
}

final class _SilentEmail extends Fake implements EmailNotificationPort {
  @override
  Future<void> considerImmediate({
    required String recipientUserId,
    required NotificationKind kind,
    required String beaconId,
    required String channelCollapseKey,
    required String title,
    required String body,
    required String actionUrl,
    required bool pushDelivered,
  }) async {}
}

final class _Harness {
  const _Harness(this.posts, this.room, this.forwards);

  final PostCase posts;
  final BeaconRoomCase room;
  final ForwardCase forwards;
}

_Harness _buildHarness(TenturaDb db, Env env) {
  final logger = Logger('PostNotificationPipelinePgTest');
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
    beaconRepository: beaconRepository,
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
    forwards,
  );
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
