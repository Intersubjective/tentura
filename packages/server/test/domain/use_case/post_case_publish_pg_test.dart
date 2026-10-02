@Tags(['pg'])
library;

import 'dart:convert';
import 'dart:typed_data';

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
const _kindRequest = 0;
const _kindPost = 1;
const _statusOpen = 0;
const _statusDraft = 3;

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_PUBLISH_CASE_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_publish_case',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('PostCase.publish with real repositories and attention dispatch', () {
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
      'publishes the draft, forwards to every recipient and posts the root '
      'message',
      () async {
        final result = await publish(
          notes: {_bob: 'you know this one', _carol: 'thought of you'},
        );

        expect(result.beaconId, _beacon);
        final beacon = (await writer.execute(
          Sql.named(
            'SELECT status, forward_policy, post_root_message_id '
            'FROM public.beacon WHERE id = @id',
          ),
          parameters: {'id': _beacon},
        )).single;
        expect(beacon[0], _statusOpen);
        expect(beacon[1], BeaconForwardPolicyValue.closed.value);
        expect(beacon[2], result.rootMessageId);

        final edges = await writer.execute(
          Sql.named(
            'SELECT sender_id, recipient_id, note '
            'FROM public.beacon_forward_edge WHERE beacon_id = @id '
            'ORDER BY recipient_id',
          ),
          parameters: {'id': _beacon},
        );
        expect(edges.map((r) => r.toList()).toList(), [
          [_author, _bob, 'you know this one'],
          [_author, _carol, 'thought of you'],
        ]);

        final addressees = await writer.execute(
          Sql.named(
            'SELECT user_id, room_access FROM public.beacon_participant '
            'WHERE beacon_id = @id AND role = 6 ORDER BY user_id',
          ),
          parameters: {'id': _beacon},
        );
        expect(addressees.map((r) => r.toList()).toList(), [
          [_bob, 3],
          [_carol, 3],
        ]);

        final messages = await writer.execute(
          Sql.named(
            'SELECT id, author_id, body, mention_spans '
            'FROM public.beacon_room_message WHERE beacon_id = @id',
          ),
          parameters: {'id': _beacon},
        );
        final root = messages.single;
        expect(root[0], result.rootMessageId);
        expect(root[1], _author);
        expect(root[2], _body);
        expect(jsonDecode(jsonEncode(root[3])), [
          {'userId': _bob, 'offset': 6, 'length': 4},
        ]);
      },
    );

    test('sends one relay receipt per recipient and no mention receipt to a '
        'mentioned recipient', () async {
      await publish();

      final receipts = await writer.execute(
        Sql.named('''
            SELECT receipt.account_id, occurrence.event_type
            FROM public.notification_outbox receipt
            JOIN public.attention_occurrence occurrence
              ON occurrence.id = receipt.occurrence_id
            WHERE receipt.beacon_id = @id
            ORDER BY receipt.account_id, occurrence.event_type
          '''),
        parameters: {'id': _beacon},
      );
      expect(receipts.map((r) => r.toList()).toList(), [
        [_bob, 'relayReceived'],
        [_carol, 'relayReceived'],
      ]);
    });

    test('a later ordinary room message mentioning the same recipient does '
        'emit a mention receipt (so its absence at publish is real '
        'suppression)', () async {
      await publish();

      await harness.room.createMessage(
        beaconId: _beacon,
        userId: _author,
        body: 'Again @Bob, one more thing',
        explicitMentionUserIds: const [_bob],
        explicitMentionOffsets: const [6],
        explicitMentionLengths: const [4],
      );

      final receipts = await writer.execute(
        Sql.named('''
            SELECT occurrence.event_type
            FROM public.notification_outbox receipt
            JOIN public.attention_occurrence occurrence
              ON occurrence.id = receipt.occurrence_id
            WHERE receipt.beacon_id = @id AND receipt.account_id = @bob
              AND occurrence.event_type = 'roomMessagePosted'
          '''),
        parameters: {'id': _beacon, 'bob': _bob},
      );
      expect(receipts, isNotEmpty);
    });

    test('accepts a photo-only Post: empty body and one attachment', () async {
      final result = await publish(
        body: '   ',
        mentionUserIds: const [],
        mentionOffsets: const [],
        mentionLengths: const [],
        attachmentBytes: Stream.value(
          Uint8List.fromList(utf8.encode('plain attachment')),
        ),
      );

      final attachments = await writer.execute(
        Sql.named(
          'SELECT count(*) FROM public.beacon_room_message_attachment '
          'WHERE message_id = @id',
        ),
        parameters: {'id': result.rootMessageId},
      );
      expect(attachments.single.single, 1);
      expect((await _state(writer))[0], _statusOpen);
    });

    test(
      'rejects an empty body without an attachment and writes nothing',
      () async {
        await expectLater(
          publish(
            body: '  ',
            mentionUserIds: const [],
            mentionOffsets: const [],
            mentionLengths: const [],
          ),
          throwsA(isA<ExceptionBase>()),
        );

        expect(await _state(writer), _untouchedState);
      },
    );

    test(
      'fails the whole call when a recipient is not mutually visible',
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

    test('rejects an empty recipient list and writes nothing', () async {
      await expectLater(
        publish(
          recipientIds: const [],
          mentionUserIds: const [],
          mentionOffsets: const [],
          mentionLengths: const [],
        ),
        throwsA(anything),
      );

      expect(await _state(writer), _untouchedState);
    });

    test(
      'a retry by the author returns the same ids and writes nothing new',
      () async {
        final first = await publish();
        final afterFirst = await _state(writer);

        final second = await publish();

        expect(second.beaconId, first.beaconId);
        expect(second.rootMessageId, first.rootMessageId);
        expect(await _state(writer), afterFirst);
      },
    );

    test('rejects a retry by a non-author on the published Post', () async {
      await publish();
      final afterFirst = await _state(writer);

      await expectLater(
        publish(authorId: _bob),
        throwsA(isA<UnauthorizedException>()),
      );

      expect(await _state(writer), afterFirst);
    });

    test('rejects a Request draft', () async {
      await writer.execute(
        Sql.named('UPDATE public.beacon SET kind = @k WHERE id = @id'),
        parameters: {'k': _kindRequest, 'id': _beacon},
      );

      await expectLater(publish(), throwsA(isA<ExceptionBase>()));

      expect(await _state(writer), _untouchedState);
    });

    test('rejects a Post converted to a Request after publishing', () async {
      await publish();
      await writer.execute(
        Sql.named(
          'UPDATE public.beacon SET kind = @k, forward_policy = 1 '
          'WHERE id = @id',
        ),
        parameters: {'k': _kindRequest, 'id': _beacon},
      );
      final afterConvert = await _state(writer);

      await expectLater(publish(), throwsA(isA<ExceptionBase>()));

      expect(await _state(writer), afterConvert);
    });
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
      ProductionDiscussionProductPolicy(),
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
