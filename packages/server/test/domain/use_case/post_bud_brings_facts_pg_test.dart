@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:logging/logging.dart';
import 'package:minio/minio.dart' show MinioError;
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_child_command_outcome.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import '../../support/s3_errors.dart';
import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_post_bud.dart';
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_command_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/bud_anchor_sweep_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/image_object_gc_repository.dart';
import 'package:tentura_server/data/repository/image_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/post_bud_repository.dart';
import 'package:tentura_server/data/repository/post_lock_repository.dart';
import 'package:tentura_server/data/repository/upload_quota_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/post_bud.dart';
import 'package:tentura_server/domain/entity/post_parent_stage.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_command_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/person_visibility_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/room/room_attachment_storage_key.dart';
import 'package:tentura_server/domain/use_case/anchor_inherit_operation.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_child_create_case.dart';
import 'package:tentura_server/domain/use_case/beacon_fact_card_case.dart';
import 'package:tentura_server/domain/use_case/bud_anchor_sweep_case.dart';
import 'package:tentura_server/domain/use_case/post_bud_case.dart';
import 'package:tentura_server/domain/use_case/post_close_operation.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/beacon_repository_ctor_arg.dart';
import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/mocks/invite_seed_prompt_repository_mock.dart';

/// Budding a Request from a Post with ticked Post facts, through the real
/// use cases over Postgres: the live child Request gets discussion-only
/// copies (images re-stored under the budder) announced by one "facts
/// brought" line (marker 20); the Post learns nothing beyond the usual
/// child-created notice; unavailable facts are skipped; a replay of the same
/// client command copies nothing again; a failure leaves no image behind.
///
/// The fact use case reaches the bud as the `factCards` argument of
/// `BeaconChildCreateCase`, which prepares and inserts the copies.

/// The `bud:` input hash the bud recorded, before ticked facts existed, for
/// world 900 budding with the inputs of `bud` and no fact list.
const _hashBeforeFactIds =
    'bud:8a5ba090ddccfb2acc46db72156b0cf6bfa8333c53ec91dacf0396d87145d739';

String _publicKey(int world, int slot) =>
    'budfct${world}w${slot}s'.padRight(44, 'q');

final class _Storage extends Fake implements RemoteStoragePort {
  final objects = <String, Uint8List>{};
  int puts = 0;

  /// Object path → error [getObject] raises for it (a storage outage).
  final getErrors = <String, Exception>{};

  @override
  Future<Uint8List> getObject(String path) async {
    if (getErrors[path] case final error?) throw error;
    return objects[path] ?? (throw noSuchKeyError(path));
  }

  @override
  Future<String> putObject(
    String path,
    Stream<Uint8List> bytes, {
    Map<String, String>? metadata,
  }) async {
    puts++;
    final builder = BytesBuilder(copy: false);
    await bytes.forEach(builder.add);
    objects[path] = builder.takeBytes();
    return path;
  }

  @override
  Future<void> removeObject(String path) async => objects.remove(path);
}

final class _Tasks extends Fake implements TaskRepositoryPort {
  @override
  Future<String> schedule(TaskEntity task) async => 'task';
}

final class _UnusedGenealogy extends Fake
    implements InviteGenealogyRepositoryPort {}

/// Every peer is visible to the budder (no invitees are used here).
final class _AllVisible extends Fake implements PersonVisibilityRepositoryPort {
  @override
  Future<Set<String>> personVisiblePeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
    required String context,
  }) async => peerIds.toSet();
}

/// One isolated set of users and beacons per test. The author owns an open
/// Post (with a root message) and a Request; the budder is a member of the
/// Post (a forward edge; its room admission is made explicit) and admitted to the Request.
final class _World {
  _World(this.n);

  final int n;

  String _id(String prefix) => '$prefix${'bf$n'.padLeft(11, '0')}';

  String get author => _id('Ua');
  String get budder => _id('Ub');

  String get post => _id('Bp');
  String get request => _id('Bq');
  String get root => _id('Rp');

  /// Text-only Post facts.
  String get factA => _id('Fa');
  String get factB => _id('Fb');
  String get factC => _id('Fc');

  /// A Post fact with an image.
  String get imageFact => _id('Fi');

  /// Removed from the Post.
  String get removedFact => _id('Fx');

  /// Lives in the author's Request, not in the Post.
  String get otherFact => _id('Fo');
}

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_BUD_BRINGS_FACTS_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_bud_facts',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;
  late TenturaDb db;
  late Env env;
  late _Storage storage;
  late ImageRepository images;
  late PostBudCase buds;
  late BeaconChildCreateCase childCreate;
  late bool factCaseWired;
  var worlds = 0;

  Future<List<Map<String, Object?>>> rows(
    String sql, [
    Map<String, Object?> parameters = const {},
  ]) async {
    final result = await writer.execute(Sql.named(sql), parameters: parameters);
    return [for (final r in result) r.toColumnMap()];
  }

  Future<int> count(String sql, [Map<String, Object?> p = const {}]) async =>
      (await rows(sql, p)).single['n']! as int;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    db = openDisposablePgDatabase(target);
  });

  setUp(() {
    env = target.databaseEnv;
    final logger = Logger('PostBudBringsFactsPgTest');
    storage = _Storage();
    final gc = ImageObjectGcRepository(db, storage);
    images = ImageRepository(
      db,
      storage,
      UploadQuotaRepository(db),
      gc,
      env,
      logger,
    );
    final room = BeaconRoomRepository(db);
    final factRepository = BeaconFactCardRepository(db, room);
    final factCards = buildWithBeaconRepository<BeaconFactCardCase>(
      BeaconFactCardCase.new,
      positional: [
        factRepository,
        room,
        images,
        _Tasks(),
        BeaconHierarchyRepository(db),
        FakeBeaconAccessGuard(),
      ],
      named: {#env: env, #logger: logger},
      beaconRepository: BeaconRepository(db),
    );
    final notificationContext = BeaconRoomNotificationContextRepository(
      room,
      db,
      HelpOfferRepository(db),
      CommitmentRepository(db),
    );
    final intents = AttentionIntentCase(
      notificationContext,
      UserRepository(
        env,
        db,
        _UnusedGenealogy(),
        InviteSeedPromptRepositoryMock(),
      ),
      BeaconAccessRepository(db),
      UserBlockRepository(env, db),
    );
    final attention = TransactionalAttentionCase(
      MutatingUnitOfWork(db),
      AttentionDispatchRepository(db, logger),
    );
    final beacons = BeaconRepository(db);
    final postBud = PostBudRepository(db, _AllVisible());
    final anchorSweepPort = BudAnchorSweepRepository(db);

    final hierarchy = BeaconHierarchyRepository(db);
    final commands = BeaconHierarchyCommandRepository(db);
    final guard = BeaconAccessRepository(db);
    final postLock = PostLockRepository(db);
    // Every dependency is passed explicitly, as in production DI. The fact
    // use case is the one new argument (`factCards`, as on `BeaconCase`); it
    // is applied dynamically only so this file compiles before the parameter
    // exists. Without it the bud cannot copy facts, and [bud] says so.
    BeaconChildCreateCase withoutFacts() => BeaconChildCreateCase(
      beacons,
      hierarchy,
      commands,
      guard,
      notificationContext,
      attentionIntents: intents,
      attention: attention,
      postLock: postLock,
      postBud: postBud,
      env: env,
      logger: logger,
    );
    BeaconChildCreateCase children;
    try {
      children =
          Function.apply(
                BeaconChildCreateCase.new,
                [beacons, hierarchy, commands, guard, notificationContext],
                {
                  #attentionIntents: intents,
                  #attention: attention,
                  #postLock: postLock,
                  #postBud: postBud,
                  #factCards: factCards,
                  #env: env,
                  #logger: logger,
                },
              )
              as BeaconChildCreateCase;
      factCaseWired = true;
      // A constructor without the argument is the missing behaviour; [bud]
      // reports it instead of the test crashing in setUp.
      // ignore: avoid_catching_errors
    } on NoSuchMethodError {
      children = withoutFacts();
      factCaseWired = false;
    }
    childCreate = children;
    buds = PostBudCase(
      children,
      postBud,
      ForwardEdgeRepository(db),
      InboxRepository(db),
      intents,
      PostCloseOperation(beacons),
      BudAnchorSweepCase(
        anchorSweepPort,
        AnchorInheritOperation(
          ConstellationAnchorRepository(db),
          anchorSweepPort,
        ),
        env: env,
        logger: logger,
      ),
    );
  });

  tearDownAll(() => tearDownDisposablePgWriter(session: session, drift: db));

  /// `PostBudCase.budFromPost` with ticked [factIds], called as the mutation
  /// does. [factIds] null leaves the argument out.
  Future<PostBudResult> bud(
    _World w, {
    required List<String>? factIds,
    String commandId = 'cmd-bud-facts',
    String? actor,
  }) {
    if (factIds == null) {
      return buds.budFromPost(
        actorUserId: actor ?? w.budder,
        postId: w.post,
        clientCommandId: commandId,
        title: 'Move the piano',
        description: 'Saturday, two people',
      );
    }
    final Object? pending;
    try {
      pending = Function.apply(buds.budFromPost, const [], {
        #actorUserId: actor ?? w.budder,
        #postId: w.post,
        #clientCommandId: commandId,
        #title: 'Move the piano',
        #description: 'Saturday, two people',
        #factIds: factIds,
      });
      // A bud without the parameter is the missing behaviour, reported as
      // such instead of as a crash.
      // ignore: avoid_catching_errors
    } on NoSuchMethodError catch (e) {
      fail('PostBudCase.budFromPost does not take ticked facts (factIds): $e');
    }
    if (!factCaseWired) {
      fail(
        'BeaconChildCreateCase takes no factCards (BeaconFactCardCase) '
        'argument, so a bud cannot prepare or insert fact copies',
      );
    }
    return pending! as Future<PostBudResult>;
  }

  Future<String> putImage(String authorId, int salt) => images.put(
    authorId: authorId,
    bytes: Stream.value(Uint8List.fromList([137, 80, 78, 71, salt])),
  );

  List<Map<String, Object?>> imageAttachment(String imageId, String author) => [
    {
      'id': 'A${imageId.substring(0, 8)}',
      'kind': BeaconRoomMessageAttachmentKind.image,
      'position': 0,
      'mime': 'image/png',
      'sizeBytes': 5,
      'fileName': 'p.png',
      'imageId': imageId,
      'imageAuthorId': author,
      'blurHash': '',
      'width': 2,
      'height': 3,
    },
  ];

  Future<void> seedFact({
    required String id,
    required String beaconId,
    required String pinnedBy,
    int status = BeaconFactCardStatusBits.active,
    List<Map<String, Object?>> attachments = const [],
  }) async {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, status, revision_seq)
VALUES (@id, @beacon, @text, ${BeaconFactCardVisibilityBits.room}, @by,
        @status, 1)
'''),
      parameters: {
        'id': id,
        'beacon': beaconId,
        'text': 'Fact $id',
        'by': pinnedBy,
        'status': status,
      },
    );
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_fact_card_revision
  (fact_card_id, seq, fact_text, actor_id, kind, attachments_json)
VALUES (@id, 1, @text, @by, ${BeaconFactCardRevisionKindBits.created},
        @att::jsonb)
'''),
      parameters: {
        'id': id,
        'text': 'Fact $id',
        'by': pinnedBy,
        'att': jsonEncode(attachments),
      },
    );
  }

  /// [fixed] pins the world's ids (and so the bud's input hash) whatever
  /// order the tests run in.
  Future<_World> world({int? fixed}) async {
    final w = _World(fixed ?? ++worlds);
    for (final (i, user) in [w.author, w.budder].indexed) {
      await writer.execute(
        Sql.named(
          'INSERT INTO public."user" (id, display_name, public_key) '
          'VALUES (@id, @id, @key)',
        ),
        parameters: {'id': user, 'key': _publicKey(w.n, i + 1)},
      );
    }
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at, expires_at)
VALUES (@post, @author, '', '', 0, 1, 1, false,
        now() - interval '1 hour', now() + interval '23 hours')
'''),
      parameters: {'post': w.post, 'author': w.author},
    );
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES (@root, @post, @author, 'Root')
'''),
      parameters: {'root': w.root, 'post': w.post, 'author': w.author},
    );
    await writer.execute(
      Sql.named(
        'UPDATE public.beacon SET post_root_message_id = @root '
        'WHERE id = @post',
      ),
      parameters: {'root': w.root, 'post': w.post},
    );
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, published_at,
   is_discoverable)
VALUES (@request, @author, 'Request', 'd', 0, 0, now(), false)
'''),
      parameters: {'request': w.request, 'author': w.author},
    );
    await writer.execute(
      Sql.named(
        'INSERT INTO public.beacon_forward_edge '
        '(beacon_id, sender_id, recipient_id) VALUES (@b, @s, @r)',
      ),
      parameters: {'b': w.post, 's': w.author, 'r': w.budder},
    );
    for (final (i, beaconId) in [w.post, w.request].indexed) {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES (@id, @beacon, @user, 0, 0, ${RoomAccessBits.admitted})
ON CONFLICT (beacon_id, user_id)
  DO UPDATE SET room_access = ${RoomAccessBits.admitted}
'''),
        parameters: {
          'id': 'Pbf${w.n}x$i',
          'beacon': beaconId,
          'user': w.budder,
        },
      );
    }
    for (final id in [w.factA, w.factB, w.factC]) {
      await seedFact(id: id, beaconId: w.post, pinnedBy: w.author);
    }
    await seedFact(
      id: w.imageFact,
      beaconId: w.post,
      pinnedBy: w.author,
      attachments: imageAttachment(
        await putImage(w.author, w.n % 200),
        w.author,
      ),
    );
    await seedFact(
      id: w.removedFact,
      beaconId: w.post,
      pinnedBy: w.author,
      status: BeaconFactCardStatusBits.removed,
    );
    await seedFact(id: w.otherFact, beaconId: w.request, pinnedBy: w.author);
    return w;
  }

  /// The child Requests budded from [postId].
  Future<List<String>> childrenOf(String postId) async => [
    for (final r in await rows(
      'SELECT id FROM public.beacon WHERE parent_beacon_id = @p',
      {'p': postId},
    ))
      r['id']! as String,
  ];

  /// The facts of [beaconId] with their origin and revisions.
  Future<List<Map<String, Object?>>> factsIn(String beaconId) => rows(
    '''
SELECT f.id, f.origin_fact_card_id, f.visibility::integer AS visibility,
       f.status::integer AS status, f.pinned_by,
       (SELECT r.kind::integer FROM public.beacon_fact_card_revision r
         WHERE r.fact_card_id = f.id AND r.seq = 1) AS first_kind,
       (SELECT r.attachments_json::text
          FROM public.beacon_fact_card_revision r
         WHERE r.fact_card_id = f.id ORDER BY r.seq DESC LIMIT 1)
         AS attachments
FROM public.beacon_fact_card f
WHERE f.beacon_id = @b
ORDER BY f.origin_fact_card_id
''',
    {'b': beaconId},
  );

  Future<List<Object?>> originsIn(String beaconId) async => [
    for (final f in await factsIn(beaconId)) f['origin_fact_card_id'],
  ];

  List<String> imageIdsOf(Map<String, Object?> fact) => [
    for (final a in jsonDecode(fact['attachments']! as String) as List)
      if ((a as Map)['imageId'] case final String id) id,
  ];

  Future<Map<String, Object?>?> imageRow(String imageId) async {
    final found = await rows(
      'SELECT id::text AS id, author_id FROM public.image WHERE id = @i::uuid',
      {'i': imageId},
    );
    return found.isEmpty ? null : found.single;
  }

  Future<int> imagesBy(String userId) => count(
    'SELECT count(*)::integer AS n FROM public.image WHERE author_id = @u',
    {'u': userId},
  );

  /// The "facts brought" lines (marker 20) of [beaconId].
  Future<List<Map<String, Object?>>> factLines(String beaconId) async => [
    for (final m in await rows(
      '''
SELECT id, author_id, system_payload::text AS payload
FROM public.beacon_room_message
WHERE beacon_id = @b
  AND semantic_marker = ${BeaconRoomSemanticMarker.factsBrought}
''',
      {'b': beaconId},
    ))
      m,
  ];

  Object? countOf(Map<String, Object?> line) =>
      (jsonDecode(line['payload']! as String) as Map)['count'];

  Future<List<Map<String, Object?>>> factPinnedEvents(String beaconId) => rows(
    '''
SELECT fact_card_id, source_message_id
FROM public.beacon_activity_event
WHERE beacon_id = @b AND type = ${BeaconActivityEventTypeBits.factPinned}
''',
    {'b': beaconId},
  );

  /// What the Post holds that a bud could add to: its messages (with the
  /// child-created notices told apart), facts, fact lines and fact events.
  Future<Map<String, Object?>> postFootprint(String postId) async =>
      (await rows(
        '''
SELECT
  (SELECT count(*)::integer FROM public.beacon_room_message
    WHERE beacon_id = @b
      AND hierarchy_notice_identity IS DISTINCT FROM NULL
      AND hierarchy_notice_identity LIKE 'child_created:%')
    AS child_created_notices,
  (SELECT count(*)::integer FROM public.beacon_room_message
    WHERE beacon_id = @b
      AND (hierarchy_notice_identity IS NULL
           OR hierarchy_notice_identity NOT LIKE 'child_created:%'))
    AS other_messages,
  (SELECT count(*)::integer FROM public.beacon_room_message
    WHERE beacon_id = @b
      AND semantic_marker = ${BeaconRoomSemanticMarker.factsBrought})
    AS fact_lines,
  (SELECT count(*)::integer FROM public.beacon_fact_card
    WHERE beacon_id = @b) AS facts,
  (SELECT count(*)::integer FROM public.beacon_fact_card_revision r
     JOIN public.beacon_fact_card f ON f.id = r.fact_card_id
    WHERE f.beacon_id = @b) AS fact_revisions,
  (SELECT count(*)::integer FROM public.beacon_activity_event
    WHERE beacon_id = @b
      AND type = ${BeaconActivityEventTypeBits.factPinned}) AS fact_pinned
''',
        {'b': postId},
      )).single;

  /// Makes every fact revision [actorId] inserts fail, inside the statement
  /// that inserts it, until the test ends.
  Future<void> failFactInsertsBy(String actorId) async {
    await writer.execute('''
CREATE OR REPLACE FUNCTION public.test_bud_fact_insert_fails()
RETURNS trigger LANGUAGE plpgsql AS \$\$
BEGIN
  IF NEW.actor_id = '$actorId' THEN
    RAISE EXCEPTION 'forced failure after bud fact insert';
  END IF;
  RETURN NEW;
END
\$\$''');
    await writer.execute('''
CREATE TRIGGER test_bud_fact_insert_fails
AFTER INSERT ON public.beacon_fact_card_revision
FOR EACH ROW EXECUTE FUNCTION public.test_bud_fact_insert_fails()''');
    addTearDown(() async {
      await writer.execute(
        'DROP TRIGGER IF EXISTS test_bud_fact_insert_fails '
        'ON public.beacon_fact_card_revision',
      );
      await writer.execute(
        'DROP FUNCTION IF EXISTS public.test_bud_fact_insert_fails()',
      );
    });
  }

  group('Budding a Request from a Post with ticked facts', () {
    test('two ticked facts land in the child as discussion-only copies '
        'announced by one facts-brought line with count 2, and the Post gets '
        'only the child-created notice', () async {
      final w = await world();
      final postBefore = await postFootprint(w.post);

      final result = await bud(w, factIds: [w.factA, w.imageFact]);

      expect(result.outcome, PostBudResultJson.outcomeCreated);
      final child = result.childBeaconId!;
      expect(await childrenOf(w.post), [child]);

      final copies = await factsIn(child);
      expect(
        [for (final c in copies) c['origin_fact_card_id']],
        unorderedEquals([w.factA, w.imageFact]),
      );
      for (final copy in copies) {
        expect(copy['id'], isNot(copy['origin_fact_card_id']));
        expect(
          copy['visibility'],
          BeaconFactCardVisibilityBits.room,
          reason: 'a copy is discussion-only',
        );
        expect(copy['status'], BeaconFactCardStatusBits.active);
        expect(copy['pinned_by'], w.budder);
        expect(copy['first_kind'], BeaconFactCardRevisionKindBits.copied);
      }

      final lines = await factLines(child);
      expect(lines, hasLength(1), reason: 'the live child is told once');
      expect(lines.single['author_id'], w.budder);
      expect(countOf(lines.single), 2);

      expect(
        await postFootprint(w.post),
        {
          ...postBefore,
          'child_created_notices':
              (postBefore['child_created_notices']! as int) + 1,
        },
        reason: 'the Post gets the child-created notice and nothing else',
      );
    });

    test('each copy brought into the child gets one factPinned event pointing '
        'at the facts-brought line', () async {
      final w = await world();

      final result = await bud(w, factIds: [w.factA, w.factB]);

      final child = result.childBeaconId!;
      final lineId = (await factLines(child)).single['id'];
      final copyIds = [for (final c in await factsIn(child)) c['id']];
      expect(copyIds, hasLength(2));
      final events = await factPinnedEvents(child);
      expect(
        [for (final e in events) e['fact_card_id']],
        unorderedEquals(copyIds),
      );
      for (final e in events) {
        expect(e['source_message_id'], lineId);
      }
    });

    test("a Post fact's image is re-stored under the budder for the copy; "
        "the source fact's image is left as it was", () async {
      final w = await world();
      final source = (await factsIn(
        w.post,
      )).singleWhere((f) => f['id'] == w.imageFact);
      final sourceImageId = imageIdsOf(source).single;
      final sourceImageBefore = await imageRow(sourceImageId);

      final result = await bud(w, factIds: [w.imageFact]);

      final copy = (await factsIn(result.childBeaconId!)).single;
      final copied = imageIdsOf(copy);
      expect(copied, hasLength(1));
      expect(copied.single, isNot(sourceImageId));
      expect((await imageRow(copied.single))?['author_id'], w.budder);
      expect(await imageRow(sourceImageId), sourceImageBefore);
      expect(
        imageIdsOf(
          (await factsIn(w.post)).singleWhere(
            (f) => f['id'] == w.imageFact,
          ),
        ),
        [sourceImageId],
      );
    });

    test('budding from an archived Post still brings the ticked facts into '
        'the child', () async {
      final w = await world();
      await writer.execute(
        Sql.named('UPDATE public.beacon SET status = @s WHERE id = @p'),
        parameters: {'p': w.post, 's': BeaconStatus.closed.smallintValue},
      );

      final result = await bud(w, factIds: [w.factA, w.factB]);

      expect(result.outcome, PostBudResultJson.outcomeCreated);
      final child = result.childBeaconId!;
      expect(await originsIn(child), unorderedEquals([w.factA, w.factB]));
      expect(countOf((await factLines(child)).single), 2);
    });

    test(
      'the same fact ticked twice is copied once and counted once',
      () async {
        final w = await world();

        final result = await bud(w, factIds: [w.factA, w.factA]);

        final child = result.childBeaconId!;
        expect(await originsIn(child), [w.factA]);
        expect(countOf((await factLines(child)).single), 1);
      },
    );

    test('a removed Post fact is skipped and the live one is copied', () async {
      final w = await world();

      final result = await bud(w, factIds: [w.removedFact, w.factC]);

      expect(result.outcome, PostBudResultJson.outcomeCreated);
      final child = result.childBeaconId!;
      expect(await originsIn(child), [w.factC]);
      expect(countOf((await factLines(child)).single), 1);
    });

    test('when every ticked fact is unavailable the bud still creates the '
        'child, with no facts, no facts-brought line and no image', () async {
      final w = await world();

      final result = await bud(w, factIds: [w.otherFact, w.removedFact]);

      expect(result.outcome, PostBudResultJson.outcomeCreated);
      final child = result.childBeaconId!;
      expect(await childrenOf(w.post), [child]);
      expect(await factsIn(child), isEmpty);
      expect(await factLines(child), isEmpty);
      expect(await imagesBy(w.budder), 0);
    });

    test('at the daily upload cap a fact with an image is skipped while a '
        'text-only fact is still copied', () async {
      final w = await world();
      await writer.execute(
        Sql.named('''
INSERT INTO public.upload_daily_usage (user_id, usage_date, bytes)
VALUES (@u, (now() AT TIME ZONE 'UTC')::date, @cap)
'''),
        parameters: {'u': w.budder, 'cap': env.uploadDailyCapBytes},
      );

      final result = await bud(w, factIds: [w.imageFact, w.factA]);

      expect(result.outcome, PostBudResultJson.outcomeCreated);
      expect(await originsIn(result.childBeaconId!), [w.factA]);
      expect(await imagesBy(w.budder), 0, reason: 'no blob left behind');
    });

    test('more than 20 ticked facts are refused before any child or image is '
        'created', () async {
      final w = await world();
      final ids = [
        w.imageFact,
        for (var i = 0; i < 20; i++) 'Fmany${'$i'.padLeft(7, '0')}',
      ];

      await expectLater(
        bud(w, factIds: ids),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(await childrenOf(w.post), isEmpty);
      expect(await imagesBy(w.budder), 0);
    });

    test('exactly 20 distinct ticked facts are accepted', () async {
      final w = await world();
      final ids = [
        w.factA,
        for (var i = 0; i < 19; i++) 'Fmany${'$i'.padLeft(7, '0')}',
      ];
      expect(ids.toSet(), hasLength(20));

      final result = await bud(w, factIds: ids);

      expect(result.outcome, PostBudResultJson.outcomeCreated);
      final child = result.childBeaconId!;
      expect(await originsIn(child), [w.factA]);
      expect(countOf((await factLines(child)).single), 1);
    });

    test('an empty list of ticked facts buds a child with no facts and no '
        'facts-brought line', () async {
      final w = await world();

      final result = await bud(w, factIds: const []);

      expect(result.outcome, PostBudResultJson.outcomeCreated);
      final child = result.childBeaconId!;
      expect(await factsIn(child), isEmpty);
      expect(await factLines(child), isEmpty);
    });
  });

  group('Replaying a bud that brought facts', () {
    test(
      'the same command with the same facts in another order returns the '
      'stored result and copies nothing again, with no image stored',
      () async {
        final w = await world();
        final first = await bud(w, factIds: [w.imageFact, w.factB]);
        final child = first.childBeaconId!;
        final factsBefore = await factsIn(child);
        expect(factsBefore, hasLength(2));
        final putsBefore = storage.puts;
        final budderImagesBefore = await imagesBy(w.budder);

        final again = await bud(w, factIds: [w.factB, w.imageFact]);

        expect(again.childBeaconId, child);
        // The stored bud_result comes back verbatim (as for every bud
        // replay): its outcome is the one recorded, `created`.
        expect(again.outcome, PostBudResultJson.outcomeCreated);
        expect(await childrenOf(w.post), [child]);
        expect(await factsIn(child), factsBefore);
        expect(await factLines(child), hasLength(1));
        expect(storage.puts, putsBefore, reason: 'a replay stores no image');
        expect(await imagesBy(w.budder), budderImagesBefore);
      },
    );

    test('the child-create command reports a replay when the same command '
        'comes again with the same facts in another order, and copies '
        'nothing again', () async {
      final w = await world();
      Future<BeaconChildCreateResult> createUnderPost(List<String> factIds) {
        final Object? pending;
        try {
          pending = Function.apply(childCreate.createChildUnderPost, const [], {
            #actorUserId: w.budder,
            #postId: w.post,
            #clientCommandId: 'cmd-port-replay',
            #title: 'Move the piano',
            #description: 'Saturday, two people',
            #factIds: factIds,
          });
          // A command without the parameter is the missing behaviour.
          // ignore: avoid_catching_errors
        } on NoSuchMethodError catch (e) {
          fail(
            'BeaconChildCreateCase.createChildUnderPost does not take ticked '
            'facts (factIds): $e',
          );
        }
        return pending! as Future<BeaconChildCreateResult>;
      }

      final first = await createUnderPost([w.imageFact, w.factB]);
      expect(first.outcome, BeaconChildCommandOutcome.created);
      final child = first.beaconId!;
      final factsBefore = await factsIn(child);
      expect(factsBefore, hasLength(2));
      final putsBefore = storage.puts;
      final budderImagesBefore = await imagesBy(w.budder);

      final again = await createUnderPost([w.factB, w.imageFact]);

      expect(again.outcome, BeaconChildCommandOutcome.replayed);
      expect(again.beaconId, child);
      expect(await factsIn(child), factsBefore);
      expect(storage.puts, putsBefore, reason: 'a replay stores no image');
      expect(await imagesBy(w.budder), budderImagesBefore);
    });

    test('a bud with an empty fact list records the same input hash as a '
        'bud recorded before ticked facts existed', () async {
      final w = await world(fixed: 900);

      await bud(w, factIds: const [], commandId: 'cmd-hash-empty');

      final stored = await rows(
        'SELECT normalized_input_hash FROM public.beacon_child_commands '
        'WHERE actor_user_id = @a AND client_command_id = @c',
        {'a': w.budder, 'c': 'cmd-hash-empty'},
      );
      expect(stored.single['normalized_input_hash'], _hashBeforeFactIds);
    });

    test('a command recorded without facts replays when sent again with an '
        'empty fact list', () async {
      final w = await world();
      final first = await bud(w, factIds: null);

      final again = await bud(w, factIds: const []);

      expect(again.childBeaconId, first.childBeaconId);
      expect(again.outcome, first.outcome);
      expect(await childrenOf(w.post), [first.childBeaconId]);
    });

    test('the same command with different ticked facts is a conflict and '
        'copies nothing', () async {
      final w = await world();
      final first = await bud(w, factIds: [w.factA]);
      final child = first.childBeaconId!;

      await expectLater(
        bud(w, factIds: [w.factA, w.factB]),
        throwsA(isA<BeaconChildCommandConflictException>()),
      );
      expect(await originsIn(child), [w.factA]);
      expect(await childrenOf(w.post), [child]);
    });

    test('two concurrent buds with the same command bring one copy and leave '
        'exactly one image under the budder', () async {
      final w = await world();

      final results = await Future.wait([
        bud(w, factIds: [w.imageFact]),
        bud(w, factIds: [w.imageFact]),
      ]).timeout(const Duration(seconds: 60));

      final children = await childrenOf(w.post);
      expect(children, hasLength(1));
      for (final r in results) {
        expect(r.childBeaconId, children.single);
      }
      expect(await originsIn(children.single), [w.imageFact]);
      expect(
        await imagesBy(w.budder),
        1,
        reason: "the losing side's prepared image is compensated",
      );
    });
  });

  group('A bud that brings facts fails as a whole', () {
    test('a failure while inserting a copy into the child leaves no child, '
        'no copy and no image under the budder', () async {
      final w = await world();
      await failFactInsertsBy(w.budder);

      await expectLater(
        bud(w, factIds: [w.imageFact, w.factA]),
        throwsA(
          predicate<Object>(
            (e) =>
                e is! TestFailure &&
                '$e'.contains('forced failure after bud fact insert'),
            'the forced fact-insert failure',
          ),
        ),
      );

      expect(await childrenOf(w.post), isEmpty);
      expect(
        await count(
          'SELECT count(*)::integer AS n FROM public.beacon_fact_card '
          'WHERE origin_fact_card_id = ANY(@o)',
          {
            'o': TypedValue(Type.textArray, [w.imageFact, w.factA]),
          },
        ),
        0,
      );
      expect(await imagesBy(w.budder), 0, reason: 'copied blob compensated');
    });
  });

  group('Budding with ticked facts over GraphQL', () {
    test('beaconBudFromPost(factIds) answers created and the child holds the '
        'ticked fact as a discussion-only copy', () async {
      final w = await world();
      final graphQL = GraphQL(
        GraphQLSchema(
          queryType: GraphQLObjectType('Query', 'Query root')
            ..fields.add(
              GraphQLObjectField(
                '_health',
                graphQLBoolean.nonNullable(),
                resolve: (_, _) => true,
              ),
            ),
          mutationType: GraphQLObjectType('Mutation', 'Mutation root')
            ..fields.addAll(MutationPostBud(postBudCase: buds).all),
        ),
        customTypes: customTypes,
      );

      final result = await graphQL.parseAndExecute(
        r'''
mutation Bud($postId: String!, $factIds: [String!]) {
  beaconBudFromPost(
    postId: $postId
    clientCommandId: "cmd-gql-facts"
    title: "Move the piano"
    description: "Saturday"
    factIds: $factIds
  ) {
    outcome
    childBeaconId
  }
}
''',
        variableValues: {
          'postId': w.post,
          'factIds': [w.factA],
        },
        globalVariables: {kGlobalInputQueryJwt: JwtEntity(sub: w.budder)},
      );

      final payload =
          (result! as Map<String, dynamic>)['beaconBudFromPost']
              as Map<String, dynamic>;
      expect(payload['outcome'], PostBudResultJson.outcomeCreated);
      final copies = await factsIn(payload['childBeaconId']! as String);
      expect(copies, hasLength(1));
      expect(copies.single['origin_fact_card_id'], w.factA);
      expect(copies.single['status'], BeaconFactCardStatusBits.active);
      expect(copies.single['visibility'], BeaconFactCardVisibilityBits.room);
      expect(
        copies.single['first_kind'],
        BeaconFactCardRevisionKindBits.copied,
      );
    });
  });

  /// Pins a message of [beaconId] holding [count] files (posted by [author])
  /// as fact [factId], the way pinning snapshots the message attachments,
  /// and returns each file's stored key, bytes and name.
  Future<List<({String key, Uint8List bytes, String name})>> seedFileFact({
    required String beaconId,
    required String author,
    required String factId,
    required int count,
  }) async {
    final messageId = 'R${factId.substring(1)}';
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES (@m, @b, @a, 'Documents')
'''),
      parameters: {'m': messageId, 'b': beaconId, 'a': author},
    );
    final files = <({String key, Uint8List bytes, String name})>[];
    final entries = <Map<String, Object?>>[];
    for (var i = 0; i < count; i++) {
      final attachmentId = 'A${factId.substring(1)}$i';
      final bytes = Uint8List.fromList(utf8.encode('file $factId #$i'));
      final key = '${roomAttachmentStorageKey(bytes)}/$attachmentId';
      final name = 'doc$i.pdf';
      await storage.putObject(key, Stream.value(bytes));
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_room_message_attachment
  (id, message_id, kind, file_url, mime, size_bytes, position, file_name)
VALUES (@id, @m, ${BeaconRoomMessageAttachmentKind.file}, @url,
        'application/pdf', @size, @pos, @name)
'''),
        parameters: {
          'id': attachmentId,
          'm': messageId,
          'url': key,
          'size': bytes.length,
          'pos': i,
          'name': name,
        },
      );
      files.add((key: key, bytes: bytes, name: name));
      entries.add({
        'id': attachmentId,
        'kind': BeaconRoomMessageAttachmentKind.file,
        'position': i,
        'mime': 'application/pdf',
        'sizeBytes': bytes.length,
        'fileName': name,
        'imageId': '',
        'imageAuthorId': '',
        'blurHash': '',
        'width': 0,
        'height': 0,
      });
    }
    await seedFact(
      id: factId,
      beaconId: beaconId,
      pinnedBy: author,
      attachments: entries,
    );
    await writer.execute(
      Sql.named(
        'UPDATE public.beacon_fact_card SET source_message_id = @m '
        'WHERE id = @f',
      ),
      parameters: {'m': messageId, 'f': factId},
    );
    return files;
  }

  /// Keys of stored objects other than [sourceKeys] that hold [bytes].
  List<String> copiesOfBytes(Set<String> sourceKeys, Uint8List bytes) => [
    for (final MapEntry(:key, :value) in storage.objects.entries)
      if (!sourceKeys.contains(key) &&
          value.length == bytes.length &&
          String.fromCharCodes(value) == String.fromCharCodes(bytes))
        key,
  ];

  /// Deletes the source fact, its message (and so its attachment rows) and
  /// its stored files.
  Future<void> deleteSourceFileFact(
    String factId,
    List<({String key, Uint8List bytes, String name})> files,
  ) async {
    await writer.execute(
      Sql.named('DELETE FROM public.beacon_fact_card WHERE id = @f'),
      parameters: {'f': factId},
    );
    await writer.execute(
      Sql.named('DELETE FROM public.beacon_room_message WHERE id = @m'),
      parameters: {'m': 'R${factId.substring(1)}'},
    );
    for (final f in files) {
      await storage.removeObject(f.key);
    }
  }

  List<Map<String, Object?>> entriesOf(Map<String, Object?> fact) => [
    for (final e in jsonDecode(fact['attachments']! as String) as List)
      Map<String, Object?>.from(e! as Map),
  ];

  group('Budding brings the files of ticked Post facts', () {
    test('more files in total than the per-call image limit are all copied, '
        'with no fact dropped', () async {
      final w = await world();
      const perFact = 14;
      final factIds = [
        for (var k = 0; k < 3; k++) 'Fl${'bf${w.n}m$k'.padLeft(10, '0')}',
      ];
      expect(factIds.length * perFact, greaterThan(kMaxFactCopyImagesPerCall));
      final filesByFact = {
        for (final id in factIds)
          id: await seedFileFact(
            beaconId: w.post,
            author: w.author,
            factId: id,
            count: perFact,
          ),
      };
      final sourceKeys = {
        for (final files in filesByFact.values)
          for (final f in files) f.key,
      };

      final result = await bud(w, factIds: factIds);

      expect(result.outcome, PostBudResultJson.outcomeCreated);
      final copies = await factsIn(result.childBeaconId!);
      expect(
        [for (final c in copies) c['origin_fact_card_id']],
        unorderedEquals(factIds),
      );
      for (final copy in copies) {
        final entries = entriesOf(copy);
        expect(entries, hasLength(perFact));
        expect(
          {for (final e in entries) e['kind']},
          {BeaconRoomMessageAttachmentKind.file},
        );
      }
      for (final files in filesByFact.values) {
        for (final f in files) {
          final copied = copiesOfBytes(sourceKeys, f.bytes);
          expect(copied, hasLength(1));
          expect(sourceKeys, isNot(contains(copied.single)));
        }
      }
    });

    test('a ticked Post fact with a file arrives in the child with a file '
        'entry backed by its own stored copy, readable after the source '
        'fact, its message and its stored file are deleted', () async {
      final w = await world();
      final factId = 'Fl${'bf${w.n}'.padLeft(10, '0')}';
      final files = await seedFileFact(
        beaconId: w.post,
        author: w.author,
        factId: factId,
        count: 1,
      );
      final file = files.single;

      final result = await bud(w, factIds: [factId]);

      expect(result.outcome, PostBudResultJson.outcomeCreated);
      final copy = (await factsIn(result.childBeaconId!)).single;
      expect(copy['origin_fact_card_id'], factId);
      final entries = entriesOf(copy);
      expect(entries, hasLength(1), reason: 'the file entry is copied');
      final entry = entries.single;
      expect(entry['kind'], BeaconRoomMessageAttachmentKind.file);
      expect(entry['fileName'], file.name);
      expect(entry['mime'], 'application/pdf');
      expect(entry['sizeBytes'], file.bytes.length);
      expect(entry['position'], 0);
      final copied = copiesOfBytes({file.key}, file.bytes);
      expect(copied, hasLength(1), reason: 'the copy has its own stored file');
      expect(copied.single, isNot(file.key));

      await deleteSourceFileFact(factId, files);
      expect(storage.objects[copied.single], file.bytes);
    });
  });

  group('Budding skips a file whose stored object is gone', () {
    test('the bud completes and the child copy holds only the present '
        'file', () async {
      final w = await world();
      final factId = 'Fl${'bf${w.n}'.padLeft(10, '0')}';
      final files = await seedFileFact(
        beaconId: w.post,
        author: w.author,
        factId: factId,
        count: 2,
      );
      await storage.removeObject(files[0].key);
      final before = storage.objects.keys.toSet();

      final result = await bud(w, factIds: [factId]);

      expect(result.outcome, PostBudResultJson.outcomeCreated);
      final copy = (await factsIn(result.childBeaconId!)).single;
      expect(copy['origin_fact_card_id'], factId);
      final text = await rows(
        'SELECT fact_text FROM public.beacon_fact_card WHERE id = @i',
        {'i': copy['id']},
      );
      expect(text.single['fact_text'], 'Fact $factId');
      final entries = entriesOf(copy);
      expect(entries, hasLength(1));
      expect(entries.single['fileName'], files[1].name);
      expect(entries.single['sizeBytes'], files[1].bytes.length);
      final created = storage.objects.keys.toSet().difference(before);
      expect(created, hasLength(1), reason: 'only the present file is stored');
      expect(storage.objects[created.single], files[1].bytes);
    });
  });

  group('Budding when the storage fails while copying a fact file', () {
    final outages = <String, Exception Function()>{
      'a timeout': () => TimeoutException('storage timed out'),
      'a server error (InternalError)': () => s3CodeError('InternalError'),
      'a 503 response': () => MinioError('503 Service Unavailable'),
      'a network failure': () => const SocketException('unreachable'),
    };
    for (final MapEntry(key: name, value: make) in outages.entries) {
      test('$name fails the bud with that error: no child Request or command '
          'row is created, every copied blob is removed and the same command '
          'id succeeds on retry', () async {
        final w = await world();
        final factId = 'Fl${'bf${w.n}'.padLeft(10, '0')}';
        final files = await seedFileFact(
          beaconId: w.post,
          author: w.author,
          factId: factId,
          count: 2,
        );
        final outage = make();
        storage.getErrors[files[1].key] = outage;
        final objectsBefore = storage.objects.keys.toSet();
        Future<int> commandRows() => count(
          'SELECT count(*)::integer AS n FROM public.beacon_child_commands '
          'WHERE actor_user_id = @u',
          {'u': w.budder},
        );

        Object? error;
        try {
          await bud(w, factIds: [w.imageFact, factId], commandId: 'cmd-retry');
        } on Object catch (e) {
          error = e;
        }

        expect(error, same(outage), reason: 'the attachment is not dropped');
        expect(await childrenOf(w.post), isEmpty);
        expect(await commandRows(), 0);
        // Image objects are removed later by the object GC (their rows are
        // asserted gone below); copied file objects are removed at once.
        expect(
          storage.objects.keys.where((k) => !k.startsWith('images/')).toSet(),
          objectsBefore.where((k) => !k.startsWith('images/')).toSet(),
        );
        expect(await imagesBy(w.budder), 0, reason: 'copied blobs removed');

        storage.getErrors.clear();
        final result = await bud(
          w,
          factIds: [w.imageFact, factId],
          commandId: 'cmd-retry',
        );
        expect(result.outcome, PostBudResultJson.outcomeCreated);
        expect(await commandRows(), 1);
        final fileCopy = (await factsIn(result.childBeaconId!)).singleWhere(
          (c) => c['origin_fact_card_id'] == factId,
        );
        expect(
          [for (final e in entriesOf(fileCopy)) e['fileName']],
          unorderedEquals([for (final f in files) f.name]),
          reason: 'both files are kept, none silently dropped',
        );
      });
    }
  });
}
