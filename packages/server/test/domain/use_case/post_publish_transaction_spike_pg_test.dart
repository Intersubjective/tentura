@Tags(['pg'])
library;

// S0 characterization: compose the existing use cases, without production changes.
// In particular, createMessage's undirected persist(null) path must join the
// outer database transaction even though it does not open runAction itself.

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
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
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
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
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_child_create_port.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'Us0author001';
const _recipientB = 'Us0recipb001';
const _recipientC = 'Us0recipc001';
const _beacon = 'Bs0draft0001';
const _body = 'The first message in General';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_PUBLISH_SPIKE_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_publish_spike',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('post publish transaction composition with real dispatch', () {
    late DisposablePgWriterSession session;
    late TenturaDb database;
    late _Harness harness;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      database = openDisposablePgDatabase(target);
      harness = _Harness.build(database, target.databaseEnv);
    });
    setUp(() async => _seed(session.writer));
    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<String> publishForwardMessage() async {
      final published = await harness.beacons.publishDraft(
        userId: _author,
        beaconId: _beacon,
      );
      expect(published.status, BeaconStatus.open);
      final forwarded = await harness.forwards.forward(
        senderId: _author,
        beaconId: _beacon,
        recipientIds: [_recipientB, _recipientC],
      );
      expect(
        forwarded.deliveredRecipientIds,
        unorderedEquals([_recipientB, _recipientC]),
      );
      expect(forwarded.availabilitySkippedRecipientIds, isEmpty);
      final message = await harness.room.createMessage(
        beaconId: _beacon,
        userId: _author,
        body: _body,
      );
      return message['id']! as String;
    }

    test('publish, forward and General message commit together', () async {
      final messageId = await harness.attention.runAction(
        actorUserId: _author,
        action: (tx) => publishForwardMessage(),
      );
      final state = await _state(session.writer);
      expect(state, [0, 2, 1, 2, 1]);
      final edges = await session.writer.execute(
        Sql.named('''
          SELECT sender_id, recipient_id FROM public.beacon_forward_edge
          WHERE beacon_id = @beacon ORDER BY recipient_id
        '''),
        parameters: {'beacon': _beacon},
      );
      expect(edges.map((row) => row.toList()).toList(), [
        [_author, _recipientB],
        [_author, _recipientC],
      ]);
      final messages = await session.writer.execute(
        Sql.named('''
          SELECT id, author_id, body, thread_item_id
          FROM public.beacon_room_message WHERE beacon_id = @beacon
        '''),
        parameters: {'beacon': _beacon},
      );
      expect(messages.single.toList(), [messageId, _author, _body, null]);
      final receipts = await session.writer.execute(
        Sql.named('''
          SELECT receipt.account_id, occurrence.event_type
          FROM public.notification_outbox receipt
          JOIN public.attention_occurrence occurrence
            ON occurrence.id = receipt.occurrence_id
          WHERE receipt.beacon_id = @beacon ORDER BY receipt.account_id
        '''),
        parameters: {'beacon': _beacon},
      );
      expect(receipts.map((row) => row.toList()).toList(), [
        [_recipientB, 'relayReceived'],
        [_recipientC, 'relayReceived'],
      ]);
    });

    test('throw after message rolls back every composed write', () async {
      var reachedLastStep = false;
      await expectLater(
        harness.attention.runAction<void>(
          actorUserId: _author,
          action: (tx) async {
            await publishForwardMessage();
            // Verify real materialization inside the still-open transaction,
            // so absence afterwards cannot pass through a no-op dispatcher.
            final messages = await database
                .customSelect(
                  'SELECT count(*) AS n FROM public.beacon_room_message '
                  'WHERE beacon_id = \$1',
                  variables: [Variable<String>(_beacon)],
                )
                .getSingle();
            expect(messages.read<int>('n'), 1);
            final receipts = await database
                .customSelect(
                  'SELECT count(*) AS n FROM public.notification_outbox '
                  'WHERE beacon_id = \$1',
                  variables: [Variable<String>(_beacon)],
                )
                .getSingle();
            expect(receipts.read<int>('n'), 2);
            reachedLastStep = true;
            throw StateError('boom');
          },
        ),
        throwsA(
          isA<StateError>().having((error) => error.message, 'message', 'boom'),
        ),
      );
      expect(reachedLastStep, isTrue);
      expect(await _state(session.writer), [
        BeaconStatus.draft.smallintValue,
        0,
        0,
        0,
        0,
      ]);
      final recipients = await session.writer.execute(
        'SELECT count(*) FROM public.attention_occurrence_recipient',
      );
      expect(recipients.single.single, 0);
    });
  });
}

Future<void> _seed(Connection writer) async {
  await writer.execute('''
    TRUNCATE TABLE public.notification_outbox,
      public.attention_occurrence_recipient, public.attention_occurrence,
      public.beacon, public."user" CASCADE
  ''');
  for (final id in [_author, _recipientB, _recipientC]) {
    await writer.execute(
      Sql.named('''
        INSERT INTO public."user" (id, display_name, public_key)
        VALUES (@id, @id, @key)
      '''),
      parameters: {
        'id': id,
        'key': pgTestPublicKey(
          's0',
          [_author, _recipientB, _recipientC].indexOf(id) + 1,
        ),
      },
    );
  }
  for (final peer in [_recipientB, _recipientC]) {
    await writer.execute(
      Sql.named('''
        INSERT INTO public.vote_user (subject, object, amount)
        VALUES (@author, @peer, 1), (@peer, @author, 1)
      '''),
      parameters: {'author': _author, 'peer': peer},
    );
    final visible = await writer.execute(
      Sql.named(
        "SELECT public.person_are_mutually_visible(@author, @peer, '')",
      ),
      parameters: {'author': _author, 'peer': peer},
    );
    expect(visible.single.single, isTrue);
  }
  await writer.execute(
    Sql.named('''
      INSERT INTO public.beacon (id, user_id, title, description, status)
      VALUES (@beacon, @author, 'S0 draft Request', 'Transaction spike', @draft)
    '''),
    parameters: {
      'beacon': _beacon,
      'author': _author,
      'draft': BeaconStatus.draft.smallintValue,
    },
  );
}

// Read from the independent writer only after the outer action completes.
Future<List<Object?>> _state(Connection writer) async {
  final rows = await writer.execute(
    Sql.named('''
      SELECT status,
        (SELECT count(*) FROM public.beacon_forward_edge WHERE beacon_id = @id),
        (SELECT count(*) FROM public.beacon_room_message WHERE beacon_id = @id),
        (SELECT count(*) FROM public.notification_outbox WHERE beacon_id = @id),
        (SELECT count(*) FROM public.attention_occurrence
         WHERE immutable_payload ->> 'beaconId' = @id)
      FROM public.beacon WHERE id = @id
    '''),
    parameters: {'id': _beacon},
  );
  return rows.single.toList();
}

final class _Harness {
  const _Harness(this.attention, this.beacons, this.forwards, this.room);

  final TransactionalAttentionCase attention;
  final BeaconCase beacons;
  final ForwardCase forwards;
  final BeaconRoomCase room;

  static _Harness build(TenturaDb db, Env env) {
    final logger = Logger('PostPublishTransactionSpikePgTest');
    final uow = MutatingUnitOfWork(db);
    final attention = TransactionalAttentionCase(
      uow,
      AttentionDispatchRepository(db, logger),
    );
    final beacons = BeaconRepository(db);
    final room = BeaconRoomRepository(db);
    final help = HelpOfferRepository(db);
    final commitments = CommitmentRepository(db);
    final access = BeaconAccessRepository(db);
    final blocks = UserBlockRepository(env, db);
    final hierarchy = BeaconHierarchyRepository(db);
    final intents = AttentionIntentCase(
      BeaconRoomNotificationContextRepository(room, db, help, commitments),
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
    final tasks = _UnusedTasks();
    return _Harness(
      attention,
      BeaconCase(
        beacons,
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
      ),
      ForwardCase(
        ForwardEdgeRepository(db),
        ForwardAttributionRepository(db),
        help,
        InboxRepository(db),
        CapabilityEvidenceRepository(db),
        beacons,
        blocks,
        PersonVisibilityRepository(db),
        access,
        attentionIntents: intents,
        attention: attention,
        env: env,
        logger: logger,
      ),
      BeaconRoomCase(
        room,
        CoordinationItemRepository(db),
        _UnusedFactCards(),
        images,
        tasks,
        _UnusedStorage(),
        _UnusedPolling(),
        _UnusedQuota(),
        blocks,
        uow,
        hierarchy,
        ProductionDiscussionProductPolicy(),
        attentionIntents: intents,
        attention: attention,
        env: env,
        logger: logger,
      ),
    );
  }
}

// These dependencies are not called for a standalone draft and plain message.
// Mockito Fake deliberately throws if the spike unexpectedly reaches them.
final class _UnusedGenealogy extends Fake
    implements InviteGenealogyRepositoryPort {}

final class _UnusedImages extends Fake implements ImageRepositoryPort {}

final class _UnusedImageGc extends Fake implements ImageObjectGcPort {}

final class _UnusedTasks extends Fake implements TaskRepositoryPort {}

final class _UnusedFactCards extends Fake
    implements BeaconFactCardRepositoryPort {}

final class _UnusedStorage extends Fake implements RemoteStoragePort {}

final class _UnusedPolling extends Fake implements PollingRepositoryPort {}

final class _UnusedQuota extends Fake implements UploadQuotaRepositoryPort {}
