import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_command_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/bud_anchor_sweep_repository.dart';
import 'package:tentura_server/data/repository/capability_evidence_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';
import 'package:tentura_server/data/repository/coordination_item_repository.dart';
import 'package:tentura_server/data/repository/forward_attribution_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/person_visibility_repository.dart';
import 'package:tentura_server/data/repository/post_bud_repository.dart';
import 'package:tentura_server/data/repository/post_lock_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/entity/post_bud.dart';
import 'package:tentura_server/domain/entity/post_publish_result.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/port/post_lock_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/use_case/anchor_inherit_operation.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/domain/use_case/beacon_child_create_case.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/domain/use_case/bud_anchor_sweep_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/post_bud_case.dart';
import 'package:tentura_server/domain/use_case/post_case.dart';
import 'package:tentura_server/domain/use_case/post_close_operation.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import 'fake_beacon_child_create_port.dart';
import 'pg_test_public_keys.dart';

const postPublishRecipient = 'Upubreader01';
String postPublishAuthor(int i) => 'Upubauthor0$i';
String postPublishId(String batch, int i) => 'Bpub${batch}00$i';
String postPublishBody(int i) => 'A Post from author $i';

Future<void> seedPostPublishFixture(Connection writer) async {
  await writer.execute('TRUNCATE public.beacon, public."user" CASCADE');
  for (var i = 0; i < 6; i++) {
    final id = i == 5 ? postPublishRecipient : postPublishAuthor(i);
    await writer.execute(
      Sql.named(
        'INSERT INTO public."user" (id, display_name, public_key) '
        'VALUES (@id, @id, @key)',
      ),
      parameters: {'id': id, 'key': pgTestPublicKey('pubcon', i + 1)},
    );
    if (i == 5) continue;
    for (final batch in ['warm', 'race']) {
      await writer.execute(
        Sql.named(
          'INSERT INTO public.beacon (id, user_id, title, description, status, kind, '
          "forward_policy, is_discoverable) VALUES (@id, @author, '', '', 3, 1, 1, false)",
        ),
        parameters: {'id': postPublishId(batch, i), 'author': id},
      );
    }
  }
  for (var i = 0; i < 5; i++) {
    await writer.execute(
      Sql.named(
        'INSERT INTO public.vote_user (subject, object, amount) '
        'VALUES (@author, @recipient, 1), (@recipient, @author, 1)',
      ),
      parameters: {'author': postPublishAuthor(i), 'recipient': postPublishRecipient},
    );
  }
}

Future<void> expectPublishedPost(
  Connection writer,
  String batch,
  int i,
  PostPublishResult result,
) async {
  expect(result.beaconId, postPublishId(batch, i));
  expect(result.rootMessageId, isNotEmpty);
  final rows = await writer.execute(
    Sql.named('''
    SELECT b.status, b.post_root_message_id, m.author_id, m.body,
      (SELECT count(*) FROM public.beacon_room_message r
       WHERE r.beacon_id = b.id AND r.system_message_kind IS NULL),
      (SELECT count(*) FROM public.beacon_forward_edge e
       WHERE e.beacon_id = b.id AND e.recipient_id = @recipient),
      (SELECT count(*) FROM public.notification_outbox n
       WHERE n.beacon_id = b.id AND n.account_id = @recipient)
    FROM public.beacon b
    JOIN public.beacon_room_message m ON m.id = b.post_root_message_id
    WHERE b.id = @id
  '''),
    parameters: {'id': result.beaconId, 'recipient': postPublishRecipient},
  );
  expect(rows.single.toList(), [
    0,
    result.rootMessageId,
    postPublishAuthor(i),
    postPublishBody(i),
    1,
    1,
    1,
  ]);
}

Future<void> expectBuddedChild(
  Connection writer,
  PostBudResult result,
  String parent,
) async {
  expect(result.childBeaconId, isNotNull);
  final rows = await writer.execute(
    Sql.named(
      'SELECT parent_beacon_id, user_id, status, kind FROM public.beacon WHERE id = @id',
    ),
    parameters: {'id': result.childBeaconId},
  );
  expect(rows.single.toList(), [parent, postPublishAuthor(0), 0, 0]);
  final children = await writer.execute(
    Sql.named(
      'SELECT count(*) FROM public.beacon WHERE parent_beacon_id = @parent',
    ),
    parameters: {'parent': parent},
  );
  expect(children.single.single, 1);
}

final class PostPublishHarness {
  const PostPublishHarness(this.posts, this.buds, this.beacons);

  final PostCase posts;
  final PostBudCase buds;
  final BeaconCase beacons;

  factory PostPublishHarness.build(
    TenturaDb db,
    Env env, {
    PostLockPort? publishLock,
  }) {
    final logger = Logger('PostPublishConcurrencyPgTest');
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
    final notificationContext = BeaconRoomNotificationContextRepository(
      roomRepository,
      db,
      help,
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
    return PostPublishHarness(
      PostCase(
        beaconCase: beacons,
        forwardCase: forwards,
        roomCase: room,
        beaconRepository: beaconRepository,
        postLock: publishLock ?? PostLockRepository(db),
        attention: attention,
      ),
      PostBudCase(
        BeaconChildCreateCase(
          beaconRepository,
          hierarchy,
          BeaconHierarchyCommandRepository(db),
          access,
          notificationContext,
          attentionIntents: intents,
          attention: attention,
          postLock: PostLockRepository(db),
          postBud: PostBudRepository(db, PersonVisibilityRepository(db)),
          env: env,
          logger: logger,
        ),
        PostBudRepository(db, PersonVisibilityRepository(db)),
        ForwardEdgeRepository(db),
        InboxRepository(db),
        intents,
        PostCloseOperation(beaconRepository),
        BudAnchorSweepCase(
          BudAnchorSweepRepository(db),
          AnchorInheritOperation(
            ConstellationAnchorRepository(db),
            BudAnchorSweepRepository(db),
          ),
          env: env,
          logger: logger,
        ),
      ),
      beacons,
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
