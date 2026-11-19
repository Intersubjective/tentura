import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart' show TenturaDb;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_command_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/bud_anchor_sweep_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';
import 'package:tentura_server/data/repository/coordination_item_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/polling_repository.dart';
import 'package:tentura_server/data/repository/post_bud_repository.dart';
import 'package:tentura_server/data/repository/post_lock_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/entity/post_bud.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/person_visibility_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/use_case/anchor_inherit_operation.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_child_create_case.dart';
import 'package:tentura_server/domain/use_case/beacon_hierarchy_delivery_case.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/domain/use_case/bud_anchor_sweep_case.dart';
import 'package:tentura_server/domain/use_case/post_bud_case.dart';
import 'package:tentura_server/domain/use_case/post_close_operation.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import 'pg_test_public_keys.dart';

/// Anna's private Post, shared with Bob and Carol. Anna ticks only Bob when
/// she turns the Post into a private Request.
final class PostBudPrivacyFixture {
  PostBudPrivacyFixture(this.writer, this.database, this.env);

  static const anna = 'UbudprivacyA';
  static const bob = 'UbudprivacyB';
  static const carol = 'UbudprivacyC';
  static const helper = 'UbudprivacyH';
  static const post = 'BbudprivacyP';
  static const postRoot = 'RbudprivacyP';
  static const postBody = 'Planning notes for the neighborhood garden';
  static const title = 'Move the greenhouse';

  final Connection writer;
  final TenturaDb database;
  final Env env;

  final logger = Logger('PostBudPrivacyFixture');
  late final beacons = BeaconRepository(database);
  late final hierarchy = BeaconHierarchyRepository(database);
  late final access = BeaconAccessRepository(database);
  late final outbox = BeaconHierarchyOutboxRepository(database);
  late final postClose = PostCloseOperation(beacons);
  late final uow = MutatingUnitOfWork(database);
  late final attention = TransactionalAttentionCase(
    uow,
    AttentionDispatchRepository(database, logger),
  );
  late final _room = BeaconRoomRepository(database);
  late final _blocks = UserBlockRepository(env, database);
  late final _context = BeaconRoomNotificationContextRepository(
    _room,
    database,
    HelpOfferRepository(database),
    CommitmentRepository(database),
  );
  late final intents = AttentionIntentCase(
    _context,
    UserRepository(
      env,
      database,
      _UnusedGenealogy(),
      InviteSeedPromptRepositoryMock(),
    ),
    access,
    _blocks,
  );

  late final room = BeaconRoomCase(
    _room,
    CoordinationItemRepository(database),
    _UnusedFactCards(),
    _UnusedImages(),
    _UnusedTasks(),
    _UnusedStorage(),
    PollingRepository(database),
    _UnusedQuota(),
    _blocks,
    uow,
    hierarchy,
    const ProductionDiscussionProductPolicy(),
    beaconRepository: beacons,
    env: env,
    logger: logger,
  );

  Future<void> reset() async {
    await writer.execute(
      'TRUNCATE public."user", public.beacon, public.attention_occurrence CASCADE',
    );
  }

  Future<void> seedPost() async {
    for (final (index, (id, name)) in [
      (anna, 'Anna'),
      (bob, 'Bob'),
      (carol, 'Carol'),
      (helper, 'Dina'),
    ].indexed) {
      await writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @name, @key)
'''),
        parameters: {
          'id': id,
          'name': name,
          'key': pgTestPublicKey('bud-privacy', index + 1),
        },
      );
    }
    await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES ('$post', '$anna', '', '', 0, 1, 1, false, now())
''');
    await writer.execute('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES ('$postRoot', '$post', '$anna', '$postBody')
''');
    await writer.execute('''
UPDATE public.beacon SET post_root_message_id = '$postRoot' WHERE id = '$post'
''');
    await writer.execute('''
INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, recipient_id)
VALUES ('$post', '$anna', '$bob'), ('$post', '$anna', '$carol')
''');
  }

  Future<String> bud({bool closePost = false}) async {
    final postBud = PostBudRepository(database, _VisiblePostMembers());
    final sweep = BudAnchorSweepRepository(database);
    final buds = PostBudCase(
      BeaconChildCreateCase(
        beacons,
        hierarchy,
        BeaconHierarchyCommandRepository(database),
        access,
        _context,
        attentionIntents: intents,
        attention: attention,
        postLock: PostLockRepository(database),
        postBud: postBud,
        env: env,
        logger: logger,
      ),
      postBud,
      ForwardEdgeRepository(database),
      InboxRepository(database),
      intents,
      postClose,
      BudAnchorSweepCase(
        sweep,
        AnchorInheritOperation(ConstellationAnchorRepository(database), sweep),
        env: env,
        logger: logger,
      ),
    );
    final result = await buds.budFromPost(
      actorUserId: anna,
      postId: post,
      sourceMessageId: postRoot,
      clientCommandId: 'bud-for-the-garden',
      title: title,
      description: 'Two people to move the frame.',
      invitees: const [PostBudInvitee(userId: bob)],
      closePost: closePost,
    );
    expect(result.outcome, 'created');
    expect(result.invitees.single.outcome, PostBudInviteOutcome.invited);
    final child = result.childBeaconId!;
    expect(await canRead(post, carol), isTrue);
    expect(await canRead(child, bob), isTrue);
    expect(await canRead(child, carol), isFalse);
    return child;
  }

  Future<bool> canRead(String beacon, String viewer) =>
      access.canReadContent(beaconId: beacon, viewerId: viewer);

  Future<void> closeRequest(String child) async {
    await uow.run(
      actorUserId: anna,
      action: () async {
        await hierarchy.lockMutationScope();
        await beacons.recordBeaconStatusTransition(
          beaconId: child,
          fromStatus: BeaconStatus.open,
          toStatus: BeaconStatus.closed,
          reason: BeaconLifecycleChangeReason.directClose,
          actorId: anna,
        );
        final event =
            await BeaconLifecycleEffectsCase(
              outbox,
              env: env,
              logger: logger,
            ).recordEligibleSourceTransition(
              sourceBeaconId: child,
              fromStatus: BeaconStatus.open,
              toStatus: BeaconStatus.closed,
              occurredAt: DateTime.timestamp(),
              actorUserId: anna,
            );
        expect(event, isNotNull);
      },
    );
    await BeaconHierarchyDeliveryCase(
      outbox,
      attention,
      intents,
      env: env,
      logger: logger,
    ).runDue(workerId: 'hierarchy-worker', now: DateTime.timestamp());
  }
}

final class _UnusedGenealogy extends Fake
    implements InviteGenealogyRepositoryPort {}

final class _UnusedFactCards extends Fake
    implements BeaconFactCardRepositoryPort {}

final class _UnusedImages extends Fake implements ImageRepositoryPort {}

final class _UnusedTasks extends Fake implements TaskRepositoryPort {}

final class _UnusedStorage extends Fake implements RemoteStoragePort {}

final class _UnusedQuota extends Fake implements UploadQuotaRepositoryPort {}

final class _VisiblePostMembers extends Fake
    implements PersonVisibilityRepositoryPort {
  @override
  Future<Set<String>> personVisiblePeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
    required String context,
  }) async => peerIds.toSet();
}
