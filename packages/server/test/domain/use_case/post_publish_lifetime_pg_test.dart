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
import 'package:tentura_server/domain/entity/post_publish_result.dart';
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

const _author = 'Ulifeauthor01';
const _bob = 'Ulifebob00001';
const _carol = 'Ulifecarol001';
const _stranger = 'Ulifestrang01';
const _beacon = 'Blifedraft001';
const _body = 'Hello @Bob, welcome to the thread';
const _users = [_author, _bob, _carol, _stranger];
const _kindPost = 1;
const _statusOpen = 0;
const _statusDraft = 3;

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_PUBLISH_LIFETIME_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_publish_lifetime',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('PostCase.publish with a chosen lifetime', () {
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
    setUp(() async => _seed(writer));
    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<PostPublishResult> publishWithoutLifetime() => harness.posts.publish(
      authorId: _author,
      beaconId: _beacon,
      body: _body,
      mentionUserIds: const [],
      mentionOffsets: const [],
      mentionLengths: const [],
      recipientIds: const [_bob],
      notes: const {},
      forwardPolicy: BeaconForwardPolicyValue.closed,
    );

    Future<PostPublishResult> publish({required int lifetimeHours}) =>
        harness.posts.publish(
          authorId: _author,
          beaconId: _beacon,
          body: _body,
          mentionUserIds: const [],
          mentionOffsets: const [],
          mentionLengths: const [],
          recipientIds: const [_bob],
          notes: const {},
          forwardPolicy: BeaconForwardPolicyValue.closed,
          lifetimeHours: lifetimeHours,
        );

    /// status, published_at set, expires_at, expiry_warning_eligible.
    Future<List<Object?>> lifetimeRow() async => (await writer.execute(
      Sql.named('''
        SELECT status, published_at IS NOT NULL, expires_at,
               expiry_warning_eligible
        FROM public.beacon WHERE id = @id
      '''),
      parameters: {'id': _beacon},
    )).single.toList();

    /// Whether `expires_at - published_at` is exactly [hours] hours, plus
    /// the warning flag.
    Future<(bool, bool)> expiryAfter(int hours) async {
      final row = (await writer.execute(
        Sql.named('''
          SELECT expires_at = published_at + make_interval(hours => @hours),
                 expiry_warning_eligible
          FROM public.beacon WHERE id = @id
        '''),
        parameters: {'id': _beacon, 'hours': hours},
      )).single;
      return (row[0]! as bool, row[1]! as bool);
    }

    test('without a lifetime the Post expires 72 hours after publication '
        'and is eligible for the expiry warning', () async {
      await publishWithoutLifetime();

      expect(await expiryAfter(72), (true, true));
    });

    test('a six hour lifetime expires six hours after publication and is '
        'eligible for the expiry warning', () async {
      await publish(lifetimeHours: 6);

      expect((await lifetimeRow())[0], _statusOpen);
      expect(await expiryAfter(6), (true, true));
    });

    test('a three hour lifetime is published but not eligible for the '
        'expiry warning', () async {
      await publish(lifetimeHours: 3);

      expect((await lifetimeRow())[0], _statusOpen);
      expect(await expiryAfter(3), (true, false));
    });

    test('a four hour lifetime, just over the warning lead time, is '
        'eligible for the expiry warning', () async {
      await publish(lifetimeHours: 4);

      expect(await expiryAfter(4), (true, true));
    });

    test('the shortest lifetime, one hour, is accepted and not eligible '
        'for the expiry warning', () async {
      await publish(lifetimeHours: 1);

      expect(await expiryAfter(1), (true, false));
    });

    test('the longest lifetime, 72 hours, is accepted', () async {
      await publish(lifetimeHours: 72);

      expect(await expiryAfter(72), (true, true));
    });

    for (final invalid in [0, 73, -1]) {
      test('a lifetime of $invalid hours is rejected and the draft stays a '
          'draft', () async {
        await expectLater(
          publish(lifetimeHours: invalid),
          throwsA(isA<PostLifetimeInvalidException>()),
        );

        expect(await _state(writer), _untouchedDraftState);
        final row = await lifetimeRow();
        expect(row[0], _statusDraft);
        expect(row[1], isFalse, reason: 'published_at stays unset');
        expect(row[2], isNull, reason: 'no lifetime is stamped');
        expect(row[3], isFalse);
      });
    }

    test('republishing an already published Post keeps its expiry and '
        'warning eligibility', () async {
      final first = await publish(lifetimeHours: 6);
      final before = await lifetimeRow();

      final second = await publish(lifetimeHours: 48);

      expect(second.rootMessageId, first.rootMessageId);
      expect(await lifetimeRow(), before);
    });
  });
}

/// status, policy, edges, addressees, messages, receipts, root message id.
const _untouchedDraftState = <Object?>[_statusDraft, 1, 0, 0, 0, 0, null];

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
        'key': pgTestPublicKey('life', _users.indexOf(id) + 1),
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

  factory _Harness.build(TenturaDb db, Env env) {
    final logger = Logger('PostCasePublishPgTest');
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
