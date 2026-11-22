@Tags(['pg'])
library;

import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
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
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/person_visibility_repository.dart';
import 'package:tentura_server/data/repository/post_lock_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/entity/post_publish_result.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
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
import '../../support/mocks/invite_seed_prompt_repository_mock.dart';

/// Facts copied into a draft Post are announced once the Post is published:
/// one "facts brought" chat line (marker 20) by the Post author, after the
/// root message, plus one `factPinned` event per copied fact. Publishing a
/// Post is two-phase; the line belongs to the phase that creates the root
/// message, so a failure between the phases leaves no line and a retry
/// writes it exactly once. Real repositories over a disposable Postgres.

const _author = 'Upfaauthor01';
const _beacon = 'Bpfadraft001';
const _body = 'A Post with facts';
const _kindPost = 1;
const _statusOpen = 0;
const _statusDraft = 3;

/// When armed, fails the next room message write once. In a Post publish
/// that write is phase 2 creating the root message, after phase 1 has
/// committed, so phase 2 rolls back with no root message.
final class _FailingRootRoomCase extends BeaconRoomCase {
  _FailingRootRoomCase(
    super._room,
    super._items,
    super._factCards,
    super._imageRepository,
    super._tasksRepository,
    super._remoteStorage,
    super._pollingRepository,
    super._uploadQuota,
    super._userBlockRepository,
    super._unitOfWork,
    super._hierarchyRepository,
    super._discussionPolicy, {
    required super.env,
    required super.logger,
    super.attentionIntents,
    super.attention,
  });

  bool failNextMessage = false;
  int injectedFailures = 0;

  void reset() {
    failNextMessage = false;
    injectedFailures = 0;
  }

  @override
  Future<Map<String, Object?>> createMessage({
    required String beaconId,
    required String userId,
    required String body,
    String? replyToMessageId,
    String? threadItemId,
    Stream<Uint8List>? attachmentBytes,
    String? attachmentFilename,
    String? attachmentMimeType,
    List<UploadedRoomAttachment> savedAttachments = const [],
    List<String> explicitMentionUserIds = const [],
    List<int> explicitMentionOffsets = const [],
    List<int> explicitMentionLengths = const [],
    String? quotedFactCardId,
    int? quotedFactRevisionSeq,
    Set<String> suppressMentionNotifyFor = const {},
    String? clientMessageId,
  }) {
    if (failNextMessage) {
      failNextMessage = false;
      injectedFailures++;
      throw StateError('injected phase-2 failure before the root message');
    }
    return super.createMessage(
      beaconId: beaconId,
      userId: userId,
      body: body,
      replyToMessageId: replyToMessageId,
      threadItemId: threadItemId,
      attachmentBytes: attachmentBytes,
      attachmentFilename: attachmentFilename,
      attachmentMimeType: attachmentMimeType,
      savedAttachments: savedAttachments,
      explicitMentionUserIds: explicitMentionUserIds,
      explicitMentionOffsets: explicitMentionOffsets,
      explicitMentionLengths: explicitMentionLengths,
      quotedFactCardId: quotedFactCardId,
      quotedFactRevisionSeq: quotedFactRevisionSeq,
      suppressMentionNotifyFor: suppressMentionNotifyFor,
      clientMessageId: clientMessageId,
    );
  }
}

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_PUBLISH_ANNOUNCES_FACTS_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_publish_announces_facts',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('Publishing a Post announces its copied facts', () {
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
    setUp(() async {
      harness.room.reset();
      await _seed(writer);
    });
    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<List<Map<String, Object?>>> rows(
      String sql, [
      Map<String, Object?> parameters = const {},
    ]) async {
      final result = await writer.execute(
        Sql.named(sql),
        parameters: parameters,
      );
      return [for (final r in result) r.toColumnMap()];
    }

    Future<PostPublishResult> publish() => harness.posts.publish(
      authorId: _author,
      beaconId: _beacon,
      body: _body,
      mentionUserIds: const [],
      mentionOffsets: const [],
      mentionLengths: const [],
      recipientIds: const [],
      notes: const {},
    );

    /// Seeds [texts] as facts copied into the draft Post (origin set, as the
    /// copy path leaves them); returns their ids.
    /// [originKinds] gives each fact's origin beacon kind (default Request).
    Future<List<String>> seedCopiedFacts(
      List<String> texts, {
      List<int>? originKinds,
    }) async {
      final ids = <String>[];
      for (final (i, text) in texts.indexed) {
        final id = 'Fpfacopy$i'.padRight(14, '0');
        await writer.execute(
          Sql.named('''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, status, revision_seq,
   origin_fact_card_id, origin_revision_seq, origin_beacon_kind)
VALUES (@id, @beacon, @text, ${BeaconFactCardVisibilityBits.room}, @by,
        ${BeaconFactCardStatusBits.active}, 1, @origin, 1, @kind::smallint)
'''),
          parameters: {
            'id': id,
            'beacon': _beacon,
            'text': text,
            'by': _author,
            'origin': 'Fpfaorigin$i'.padRight(14, '0'),
            'kind': originKinds?[i] ?? 0,
          },
        );
        await writer.execute(
          Sql.named('''
INSERT INTO public.beacon_fact_card_revision
  (fact_card_id, seq, fact_text, actor_id, kind, attachments_json)
VALUES (@id, 1, @text, @by, ${BeaconFactCardRevisionKindBits.copied},
        '[]'::jsonb)
'''),
          parameters: {'id': id, 'text': text, 'by': _author},
        );
        ids.add(id);
      }
      return ids;
    }

    /// All messages of the Post in the order the room shows them.
    Future<List<Map<String, Object?>>> messages() => rows(
      '''
SELECT id, author_id, body, semantic_marker, system_payload::text AS payload,
       created_at
FROM public.beacon_room_message
WHERE beacon_id = @b
ORDER BY created_at, id
''',
      {'b': _beacon},
    );

    List<Map<String, Object?>> factLines(List<Map<String, Object?>> all) => [
      for (final m in all)
        if (m['semantic_marker'] == BeaconRoomSemanticMarker.factsBrought) m,
    ];

    Future<List<Map<String, Object?>>> factPinnedEvents() => rows(
      '''
SELECT type, visibility, actor_id, source_message_id, fact_card_id,
       diff::text AS diff
FROM public.beacon_activity_event
WHERE beacon_id = @b AND type = ${BeaconActivityEventTypeBits.factPinned}
''',
      {'b': _beacon},
    );

    Map<String, Object?> payloadOf(Map<String, Object?> line) =>
        (jsonDecode(line['payload']! as String) as Map).cast<String, Object?>();

    /// Exactly one `factPinned` event per id in [factIds]: room visibility,
    /// by the author, pointing at [lineId], diff = the fact's id and text.
    Future<void> expectPinnedEvents({
      required String lineId,
      required Map<String, String> textByFactId,
    }) async {
      final events = await factPinnedEvents();
      expect(
        [for (final e in events) e['fact_card_id']],
        unorderedEquals(textByFactId.keys),
      );
      for (final e in events) {
        final factId = e['fact_card_id']! as String;
        expect(e['type'], BeaconActivityEventTypeBits.factPinned);
        expect(e['visibility'], BeaconActivityEventVisibilityBits.room);
        expect(e['actor_id'], _author);
        expect(e['source_message_id'], lineId);
        expect(jsonDecode(e['diff']! as String), {
          'factCardId': factId,
          'factText': textByFactId[factId],
        });
      }
    }

    /// The room lists messages by `created_at`: the line must be strictly
    /// later than the root message, not tied with it.
    void expectAfterRoot(
      List<Map<String, Object?>> all,
      Map<String, Object?> line,
      String rootMessageId,
    ) {
      final root = all.singleWhere((m) => m['id'] == rootMessageId);
      final rootAt = root['created_at']! as DateTime;
      final lineAt = line['created_at']! as DateTime;
      expect(
        lineAt.isAfter(rootAt),
        isTrue,
        reason: 'the line ($lineAt) follows the root message ($rootAt)',
      );
    }

    Future<Map<String, Object?>> postState() async => (await rows(
      'SELECT status, post_root_message_id FROM public.beacon WHERE id = @b',
      {'b': _beacon},
    )).single;

    test('two copied facts: one line by the author after the root message, '
        'and one factPinned event per fact', () async {
      final copies = await seedCopiedFacts(['First', 'Second']);

      final result = await publish();

      final all = await messages();
      final lines = factLines(all);
      expect(lines, hasLength(1), reason: 'announced exactly once');
      final line = lines.single;
      expect(line['author_id'], _author);
      expect(line['body'], '');
      expectAfterRoot(all, line, result.rootMessageId);
      final payload = payloadOf(line);
      expect(
        payload.keys,
        unorderedEquals(['factCardIds', 'count', 'originBeaconKind']),
      );
      expect(payload['factCardIds'], unorderedEquals(copies));
      expect(payload['count'], 2);
      expect(payload['originBeaconKind'], 0);

      await expectPinnedEvents(
        lineId: line['id']! as String,
        textByFactId: {copies[0]: 'First', copies[1]: 'Second'},
      );
    });

    test('one copied fact: count 1 with its text', () async {
      final copies = await seedCopiedFacts(['The only fact']);

      await publish();

      final line = factLines(await messages()).single;
      final payload = payloadOf(line);
      expect(payload['count'], 1);
      expect(payload['factCardIds'], copies);
      expect(payload['factText'], 'The only fact');
      expect(payload['originBeaconKind'], 0);
      await expectPinnedEvents(
        lineId: line['id']! as String,
        textByFactId: {copies.single: 'The only fact'},
      );
    });

    test('facts copied from a Post and from a Request: originBeaconKind is '
        'null', () async {
      final copies = await seedCopiedFacts(
        ['From a Post', 'From a Request'],
        originKinds: [1, 0],
      );

      await publish();

      final line = factLines(await messages()).single;
      final payload = payloadOf(line);
      expect(payload['count'], 2);
      expect(payload, containsPair('originBeaconKind', null));
      expect(payload['factCardIds'], unorderedEquals(copies));
      await expectPinnedEvents(
        lineId: line['id']! as String,
        textByFactId: {copies[0]: 'From a Post', copies[1]: 'From a Request'},
      );
    });

    test('a Post without copied facts gets no line', () async {
      await publish();

      expect(factLines(await messages()), isEmpty);
      expect(await factPinnedEvents(), isEmpty);
    });

    test('a failure before the root message leaves no line; the retry '
        'writes it once after the root, and a further publish writes '
        'nothing', () async {
      final copies = await seedCopiedFacts(['First', 'Second']);
      harness.room.failNextMessage = true;

      await expectLater(publish(), throwsA(anything));
      expect(
        harness.room.injectedFailures,
        1,
        reason: 'the failure hit the root message write in phase 2',
      );

      final afterFailure = await postState();
      expect(afterFailure['status'], _statusOpen, reason: 'phase 1 committed');
      expect(afterFailure['post_root_message_id'], isNull);
      expect(
        await messages(),
        isEmpty,
        reason: 'no root message and no line after the phase-2 failure',
      );
      expect(await factPinnedEvents(), isEmpty);

      final result = await publish();

      final all = await messages();
      final lines = factLines(all);
      expect(lines, hasLength(1));
      expectAfterRoot(all, lines.single, result.rootMessageId);
      expect(payloadOf(lines.single)['factCardIds'], unorderedEquals(copies));
      await expectPinnedEvents(
        lineId: lines.single['id']! as String,
        textByFactId: {copies[0]: 'First', copies[1]: 'Second'},
      );

      await publish();

      expect(factLines(await messages()), hasLength(1));
      expect(await factPinnedEvents(), hasLength(2));
    });
  });
}

Future<void> _seed(Connection writer) async {
  await writer.execute('''
    TRUNCATE TABLE public.notification_outbox,
      public.attention_occurrence_recipient, public.attention_occurrence,
      public.beacon, public."user" CASCADE
  ''');
  await writer.execute(
    Sql.named('''
      INSERT INTO public."user" (id, display_name, public_key)
      VALUES (@id, @id, @key)
    '''),
    parameters: {'id': _author, 'key': pgTestPublicKey('pfa', 1)},
  );
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

final class _Harness {
  const _Harness(this.posts, this.room);

  final PostCase posts;
  final _FailingRootRoomCase room;

  factory _Harness.build(TenturaDb db, Env env) {
    final logger = Logger('PostPublishAnnouncesCopiedFactsPgTest');
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
    final room = _FailingRootRoomCase(
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
