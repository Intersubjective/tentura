@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift_postgres/drift_postgres.dart';
import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:minio/minio.dart' show MinioError;
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/plan/plan.dart';
import '../../support/s3_errors.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_beacon.dart';
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/image_object_gc_repository.dart';
import 'package:tentura_server/data/repository/image_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/upload_quota_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/room/room_attachment_storage_key.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/domain/use_case/beacon_fact_card_case.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/beacon_plan_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/beacon_repository_ctor_arg.dart';
import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_beacon_child_create_port.dart';
import '../../support/plan_cases.dart';

/// Forking a Request with ticked facts, through the real use cases over
/// Postgres: the draft gets discussion-only copies of the facts the forker
/// may read, with their images re-stored under the forker; unavailable facts
/// are skipped without failing the fork; a failure leaves neither a draft
/// nor copied images behind.
///
/// `BeaconCase` gets the fact use case through its constructor; the test
/// finds that parameter by type, not by name (see [_constructBeaconCase]).

String _publicKey(int world, int slot) =>
    'fkfct${world}w${slot}s'.padRight(44, 'q');

final class _Storage extends Fake implements RemoteStoragePort {
  final objects = <String, Uint8List>{};

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

final class _ForcedPlanFailure implements Exception {
  const _ForcedPlanFailure();
}

/// A plan copy that always fails. Before failing it runs [onCopy] inside
/// the fork's transaction, so a test can see what the fork already wrote.
final class _FailingPlan extends Fake implements BeaconPlanCase {
  _FailingPlan(this.onCopy);

  final Future<void> Function(String targetBeaconId) onCopy;

  @override
  Future<int> copyPlan({
    required String actorId,
    required String sourceBeaconId,
    required String targetBeaconId,
    Map<String, ({DateTime? startAt, DateTime? endAt})> stepTimes = const {},
  }) async {
    await onCopy(targetBeaconId);
    throw const _ForcedPlanFailure();
  }
}

/// Counts the transactions the attention port opens.
final class _CountingUnitOfWork implements MutatingUnitOfWorkPort {
  _CountingUnitOfWork(this._inner);

  final MutatingUnitOfWorkPort _inner;
  int runs = 0;

  @override
  Future<T> run<T>({
    required Future<T> Function() action,
    String? actorUserId,
  }) {
    runs++;
    return _inner.run(action: action, actorUserId: actorUserId);
  }
}

/// One isolated set of users and beacons per test. The author owns the
/// source Request and another Request; the forker is an admitted member of
/// both; the reader was forwarded the source but is not admitted.
final class _World {
  _World(this.n);

  final int n;

  String _id(String prefix) => '$prefix${'fk$n'.padLeft(11, '0')}';

  String get author => _id('Ua');
  String get forker => _id('Uf');
  String get reader => _id('Ur');

  String get source => _id('Bs');
  String get other => _id('Bo');

  /// Request-visible, with an image.
  String get publicFact => _id('Fp');

  /// Discussion-only, with an image.
  String get roomFact => _id('Fr');

  /// Request-visible, text only.
  String get textFact => _id('Ft');

  /// Removed from the source.
  String get removedFact => _id('Fx');

  /// Lives in the other Request.
  String get otherFact => _id('Fo');

  String step(String suffix) => 'PS${'$n$suffix'.padLeft(12, '0')}';
}

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FORK_BRINGS_FACTS_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_fork_facts',
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
  late Logger logger;
  late _Storage storage;
  late ImageRepository images;
  late ImageObjectGcRepository gc;
  late BeaconFactCardCase factCards;
  late BeaconFactCardRepository factRepository;
  late AttentionIntentCase intents;
  late TransactionalAttentionCase attention;
  late _CountingUnitOfWork unitOfWork;
  late BeaconPlanCase realPlan;
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
    db = TenturaDb.forTest(
      database: PgDatabase.opened(
        Pool<dynamic>.withEndpoints(
          [target.databaseEnv.pgEndpoint],
          settings: target.databaseEnv.pgPoolSettings,
        ),
        enableMigrations: false,
      ),
    );
  });

  setUp(() {
    env = Env(environment: Environment.test);
    logger = Logger('BeaconForkBringsFactsPgTest');
    storage = _Storage();
    final room = BeaconRoomRepository(db);
    gc = ImageObjectGcRepository(db, storage);
    images = ImageRepository(
      db,
      storage,
      UploadQuotaRepository(db),
      gc,
      env,
      logger,
    );
    factRepository = BeaconFactCardRepository(db, room);
    factCards = buildWithBeaconRepository<BeaconFactCardCase>(
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
    intents = AttentionIntentCase(
      BeaconRoomNotificationContextRepository(
        room,
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
      UserBlockRepository(env, db),
    );
    unitOfWork = _CountingUnitOfWork(MutatingUnitOfWork(db));
    attention = TransactionalAttentionCase(
      unitOfWork,
      AttentionDispatchRepository(db, logger),
    );
    realPlan = PlanCases(db, target.databaseEnv).plan;
  });

  tearDownAll(() => tearDownDisposablePgWriter(session: session, drift: db));

  /// The fork use case over the real repositories. [withAttention] false is
  /// the test wiring without the transactional attention port.
  BeaconCase beaconCase({
    bool withAttention = true,
    BeaconPlanCase? plan,
  }) {
    final beaconRepository = BeaconRepository(db);
    final access = BeaconAccessRepository(db);
    return _constructBeaconCase(
      byType: {
        'BeaconRepositoryPort': beaconRepository,
        'ImageRepositoryPort': images,
        'ImageObjectGcPort': gc,
        'TaskRepositoryPort': _Tasks(),
        'CommitmentQueryCase': CommitmentQueryCase(
          CommitmentRepository(db),
          HelpOfferRepository(db),
          env: env,
          logger: logger,
        ),
        'BeaconAccessGuard': access,
        'BeaconHierarchyRepositoryPort': BeaconHierarchyRepository(db),
        'BeaconChildCreatePort': FakeBeaconChildCreatePort(),
        'BeaconLifecycleEffectsCase': BeaconLifecycleEffectsCase(
          BeaconHierarchyOutboxRepository(db),
          env: env,
          logger: logger,
        ),
        'AttentionIntentCase': intents,
        'TransactionalAttentionCase': withAttention ? attention : null,
        'RemoteStoragePort': storage,
        'BeaconPlanCase': plan,
        'PlanAttentionCase': null,
        'RequestChangeLogPort': null,
        'Env': env,
        'Logger': logger,
      },
      namedByName: {
        'attention': withAttention ? attention : null,
        'beaconPlan': plan,
      },
      factCards: factCards,
      factRepository: factRepository,
    );
  }

  /// `BeaconCase.fork` with ticked [factIds], called as the mutation does.
  Future<BeaconEntity> fork(
    BeaconCase beacons, {
    required String sourceId,
    required String userId,
    required List<String> factIds,
    bool copyPlan = false,
  }) {
    final Object? pending;
    try {
      pending = Function.apply(beacons.fork, const [], {
        #sourceId: sourceId,
        #userId: userId,
        #copyPlan: copyPlan,
        #factIds: factIds,
      });
      // A fork without the parameter is the missing behaviour, reported as
      // such instead of as a crash.
      // ignore: avoid_catching_errors
    } on NoSuchMethodError catch (e) {
      fail('BeaconCase.fork does not take ticked facts (factIds): $e');
    }
    return pending! as Future<BeaconEntity>;
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
    int visibility = BeaconFactCardVisibilityBits.public,
    int status = BeaconFactCardStatusBits.active,
    List<Map<String, Object?>> attachments = const [],
  }) async {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, status, revision_seq)
VALUES (@id, @beacon, @text, @visibility, @by, @status, 1)
'''),
      parameters: {
        'id': id,
        'beacon': beaconId,
        'text': 'Fact $id',
        'visibility': visibility,
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

  Future<_World> world({bool sourceBeaconImage = false}) async {
    final w = _World(++worlds);
    for (final (i, user) in [w.author, w.forker, w.reader].indexed) {
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
  (id, user_id, title, description, status, kind, published_at,
   is_discoverable)
VALUES (@source, @author, 'Source', 'd', 0, 0, now(), false),
       (@other, @author, 'Other', 'd', 0, 0, now(), false)
'''),
      parameters: {'source': w.source, 'other': w.other, 'author': w.author},
    );
    for (final (i, beaconId) in [w.source, w.other].indexed) {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES (@id, @beacon, @user, 0, 0, ${RoomAccessBits.admitted})
'''),
        parameters: {
          'id': 'Pfk${w.n}x$i',
          'beacon': beaconId,
          'user': w.forker,
        },
      );
    }
    await writer.execute(
      Sql.named(
        'INSERT INTO public.beacon_forward_edge '
        '(beacon_id, sender_id, recipient_id) VALUES (@b, @s, @r)',
      ),
      parameters: {'b': w.source, 's': w.author, 'r': w.reader},
    );
    if (sourceBeaconImage) {
      final beaconImage = await putImage(w.author, 200 + w.n % 50);
      await writer.execute(
        Sql.named(
          'INSERT INTO public.beacon_image (beacon_id, image_id) '
          'VALUES (@b, @i::uuid)',
        ),
        parameters: {'b': w.source, 'i': beaconImage},
      );
      await writer.execute(
        Sql.named(
          'UPDATE public.beacon SET cover_image_id = @i::uuid WHERE id = @b',
        ),
        parameters: {'b': w.source, 'i': beaconImage},
      );
    }
    await seedFact(
      id: w.publicFact,
      beaconId: w.source,
      pinnedBy: w.author,
      attachments: imageAttachment(
        await putImage(w.author, w.n % 50),
        w.author,
      ),
    );
    await seedFact(
      id: w.roomFact,
      beaconId: w.source,
      pinnedBy: w.author,
      visibility: BeaconFactCardVisibilityBits.room,
      attachments: imageAttachment(
        await putImage(w.author, 50 + w.n % 50),
        w.author,
      ),
    );
    await seedFact(id: w.textFact, beaconId: w.source, pinnedBy: w.author);
    await seedFact(
      id: w.removedFact,
      beaconId: w.source,
      pinnedBy: w.author,
      status: BeaconFactCardStatusBits.removed,
    );
    await seedFact(id: w.otherFact, beaconId: w.other, pinnedBy: w.author);
    return w;
  }

  /// The facts of [beaconId] with their origin and head revision.
  Future<List<Map<String, Object?>>> factsIn(String beaconId) => rows(
    '''
SELECT f.id, f.origin_fact_card_id, f.visibility::integer AS visibility,
       f.pinned_by,
       (SELECT r.kind::integer FROM public.beacon_fact_card_revision r
         WHERE r.fact_card_id = f.id ORDER BY r.seq LIMIT 1) AS first_kind,
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

  List<String> imageIdsOf(Map<String, Object?> fact) => [
    for (final a in jsonDecode(fact['attachments']! as String) as List)
      if ((a as Map)['imageId'] case final String id) id,
  ];

  Future<String?> imageAuthor(String imageId) async {
    final found = await rows(
      'SELECT author_id FROM public.image WHERE id = @i::uuid',
      {'i': imageId},
    );
    return found.isEmpty ? null : found.single['author_id'] as String?;
  }

  Future<int> imagesBy(String userId) => count(
    'SELECT count(*)::integer AS n FROM public.image WHERE author_id = @u',
    {'u': userId},
  );

  Future<int> forksOf(String sourceId) => count(
    'SELECT count(*)::integer AS n FROM public.beacon '
    'WHERE lineage_parent_beacon_id = @s',
    {'s': sourceId},
  );

  Future<int> copiesOf(List<String> originIds) => count(
    'SELECT count(*)::integer AS n FROM public.beacon_fact_card '
    'WHERE origin_fact_card_id = ANY(@o)',
    {'o': TypedValue(Type.textArray, originIds)},
  );

  Future<Map<String, Object?>> footprint(String beaconId) async => (await rows(
    '''
SELECT
  (SELECT count(*)::integer FROM public.beacon_room_message
    WHERE beacon_id = @b) AS messages,
  (SELECT count(*)::integer FROM public.beacon_activity_event
    WHERE beacon_id = @b) AS events,
  (SELECT count(*)::integer FROM public.beacon_activity_event
    WHERE beacon_id = @b
      AND type = ${BeaconActivityEventTypeBits.factPinned}) AS fact_pinned,
  (SELECT count(*)::integer FROM public.notification_outbox
    WHERE beacon_id = @b) AS notifications,
  (SELECT count(*)::integer FROM public.attention_occurrence
    WHERE immutable_payload::text LIKE '%' || @b || '%') AS attention
''',
    {'b': beaconId},
  )).single;

  /// Makes every fact revision [actorId] inserts fail, inside the statement
  /// that inserts it, until the test ends.
  Future<void> failFactInsertsBy(String actorId) async {
    await writer.execute('''
CREATE OR REPLACE FUNCTION public.test_fork_fact_insert_fails()
RETURNS trigger LANGUAGE plpgsql AS \$\$
BEGIN
  IF NEW.actor_id = '$actorId' THEN
    RAISE EXCEPTION 'forced failure after fact insert';
  END IF;
  RETURN NEW;
END
\$\$''');
    await writer.execute('''
CREATE TRIGGER test_fork_fact_insert_fails
AFTER INSERT ON public.beacon_fact_card_revision
FOR EACH ROW EXECUTE FUNCTION public.test_fork_fact_insert_fails()''');
    addTearDown(() async {
      await writer.execute(
        'DROP TRIGGER IF EXISTS test_fork_fact_insert_fails '
        'ON public.beacon_fact_card_revision',
      );
      await writer.execute(
        'DROP FUNCTION IF EXISTS public.test_fork_fact_insert_fails()',
      );
    });
  }

  final forcedInsertFailure = predicate<Object>(
    (e) =>
        e is! TestFailure && '$e'.contains('forced failure after fact insert'),
    'the forced fact-insert failure',
  );

  group('Forking a Request with ticked facts', () {
    test('an admitted forker gets a draft holding a request-visible and a '
        'discussion-only fact as discussion-only copies with origins, images '
        're-stored under the forker, and no chat line', () async {
      final w = await world(sourceBeaconImage: true);
      final sourceBefore = await footprint(w.source);
      final sourceFactsBefore = await factsIn(w.source);

      final draft = await fork(
        beaconCase(),
        sourceId: w.source,
        userId: w.forker,
        factIds: [w.publicFact, w.roomFact],
      );

      final copies = await factsIn(draft.id);
      expect(
        [for (final c in copies) c['origin_fact_card_id']],
        unorderedEquals([w.publicFact, w.roomFact]),
      );
      final sourceFacts = {
        for (final f in sourceFactsBefore) f['id']! as String: f,
      };
      for (final copy in copies) {
        expect(copy['id'], isNot(copy['origin_fact_card_id']));
        expect(
          copy['visibility'],
          BeaconFactCardVisibilityBits.room,
          reason: 'a copy is discussion-only',
        );
        expect(copy['pinned_by'], w.forker);
        expect(copy['first_kind'], BeaconFactCardRevisionKindBits.copied);
        final copied = imageIdsOf(copy);
        final original = imageIdsOf(
          sourceFacts[copy['origin_fact_card_id']! as String]!,
        );
        expect(copied, hasLength(1));
        expect(copied, isNot(contains(original.single)));
        expect(await imageAuthor(copied.single), w.forker);
      }

      expect(
        await footprint(draft.id),
        {
          'messages': 0,
          'events': 0,
          'fact_pinned': 0,
          'notifications': 0,
          'attention': 0,
        },
        reason: 'a draft gets no chat line and no factPinned event',
      );
      expect(
        await footprint(w.source),
        sourceBefore,
        reason: 'the source gets no message, event or notification',
      );
      expect(
        await count(
          'SELECT count(*)::integer AS n FROM public.notification_outbox '
          'WHERE account_id = @a',
          {'a': w.author},
        ),
        0,
        reason: 'the source author is not notified of the fork',
      );
      expect(
        draft.images,
        isEmpty,
        reason: "a non-author's fork still copies no beacon images",
      );
      expect(draft.coverImageId, isNull);
    });

    test('a forker who is not admitted gets the request-visible fact; the '
        'discussion-only one is skipped and the fork succeeds', () async {
      final w = await world();

      final draft = await fork(
        beaconCase(),
        sourceId: w.source,
        userId: w.reader,
        factIds: [w.roomFact, w.publicFact],
      );

      expect(
        [for (final c in await factsIn(draft.id)) c['origin_fact_card_id']],
        [w.publicFact],
      );
      expect(await copiesOf([w.roomFact]), 0);
    });

    test('a fact from another Request, a removed fact and a fact whose image '
        'hits the daily upload cap are skipped; the rest are copied and the '
        'fork succeeds', () async {
      final w = await world();
      await writer.execute(
        Sql.named('''
INSERT INTO public.upload_daily_usage (user_id, usage_date, bytes)
VALUES (@u, (now() AT TIME ZONE 'UTC')::date, @cap)
'''),
        parameters: {'u': w.forker, 'cap': env.uploadDailyCapBytes},
      );

      final draft = await fork(
        beaconCase(),
        sourceId: w.source,
        userId: w.forker,
        factIds: [w.otherFact, w.removedFact, w.publicFact, w.textFact],
      );

      expect(
        [for (final c in await factsIn(draft.id)) c['origin_fact_card_id']],
        [w.textFact],
      );
      expect(await copiesOf([w.otherFact, w.removedFact, w.publicFact]), 0);
      expect(
        await imagesBy(w.forker),
        0,
        reason: 'the capped image copy leaves no blob behind',
      );
    });

    test('a fork whose ticked facts are all unavailable still returns a draft '
        'with no facts', () async {
      final w = await world();

      final draft = await fork(
        beaconCase(),
        sourceId: w.source,
        userId: w.reader,
        factIds: [w.roomFact, w.otherFact, w.removedFact],
      );

      expect(draft.id, isNot(w.source));
      expect(await factsIn(draft.id), isEmpty);
      expect(await forksOf(w.source), 1);
      expect(await imagesBy(w.reader), 0);
    });

    test('the same fact ticked twice is copied once', () async {
      final w = await world();

      final draft = await fork(
        beaconCase(),
        sourceId: w.source,
        userId: w.forker,
        factIds: [w.textFact, w.textFact],
      );

      expect(
        [for (final c in await factsIn(draft.id)) c['origin_fact_card_id']],
        [w.textFact],
      );
    });

    test('more than 20 ticked facts are refused before any draft or image is '
        'created', () async {
      final w = await world();
      final ids = [
        w.publicFact,
        for (var i = 0; i < 20; i++) 'Fmany${'$i'.padLeft(7, '0')}',
      ];

      await expectLater(
        fork(
          beaconCase(),
          sourceId: w.source,
          userId: w.forker,
          factIds: ids,
        ),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(await forksOf(w.source), 0);
      expect(await imagesBy(w.forker), 0);
    });

    test('an empty list of ticked facts forks exactly like a fork without '
        'facts', () async {
      final w = await world();
      final beacons = beaconCase();

      final withEmpty = await fork(
        beacons,
        sourceId: w.source,
        userId: w.forker,
        factIds: const [],
      );
      expect(
        unitOfWork.runs,
        0,
        reason: 'no facts and no plan: the fork opens no transaction',
      );
      final plain = await beacons.fork(sourceId: w.source, userId: w.forker);
      expect(unitOfWork.runs, 0);

      // A ticked fact does go through the transaction, so the count above
      // is a real observation.
      await fork(
        beacons,
        sourceId: w.source,
        userId: w.forker,
        factIds: [w.textFact],
      );
      expect(unitOfWork.runs, 1);

      for (final draft in [withEmpty, plain]) {
        expect(await factsIn(draft.id), isEmpty);
        expect(draft.lineageParentBeaconId, w.source);
      }
      expect(withEmpty.title, plain.title);
      expect(withEmpty.status, plain.status);
      expect(withEmpty.images, plain.images);
      expect(await imagesBy(w.forker), 0);
    });

    test('with the plan copied too, the draft holds both the plan steps and '
        'the copied facts', () async {
      final w = await world();
      await realPlan.save(
        actorId: w.author,
        beaconId: w.source,
        baseSeq: 0,
        stepsJson: PlanSnapshot([
          PlanStepSnapshot(id: w.step('a'), title: 'First step'),
        ]).encode(),
      );

      final draft = await fork(
        beaconCase(plan: realPlan),
        sourceId: w.source,
        userId: w.forker,
        factIds: [w.textFact],
        copyPlan: true,
      );

      expect(
        [for (final c in await factsIn(draft.id)) c['origin_fact_card_id']],
        [w.textFact],
      );
      expect(
        await count(
          'SELECT count(*)::integer AS n FROM public.coordination_item '
          "WHERE beacon_id = @b AND title = 'First step'",
          {'b': draft.id},
        ),
        1,
      );
    });
  });

  group('A fork that brings facts fails as a whole', () {
    test('without a plan copy, a failure after the facts are inserted leaves '
        'no draft, no copied fact and no copied image', () async {
      final w = await world();
      await failFactInsertsBy(w.forker);

      await expectLater(
        fork(
          beaconCase(),
          sourceId: w.source,
          userId: w.forker,
          factIds: [w.publicFact, w.roomFact],
        ),
        throwsA(forcedInsertFailure),
      );

      expect(await forksOf(w.source), 0, reason: 'no draft survives');
      expect(await copiesOf([w.publicFact, w.roomFact]), 0);
      expect(await imagesBy(w.forker), 0, reason: 'copied blobs compensated');
    });

    test('a failing plan copy leaves no draft, no copied fact and no copied '
        'image', () async {
      final w = await world();
      int? factsSeenByPlanCopy;

      await expectLater(
        fork(
          beaconCase(
            plan: _FailingPlan((targetBeaconId) async {
              // Inside the fork's transaction: the copies are already there.
              final row = await db
                  .customSelect(
                    'SELECT count(*)::integer AS n '
                    r'FROM public.beacon_fact_card WHERE beacon_id = $1',
                    variables: [Variable<String>(targetBeaconId)],
                  )
                  .getSingle();
              factsSeenByPlanCopy = row.read<int>('n');
            }),
          ),
          sourceId: w.source,
          userId: w.forker,
          factIds: [w.publicFact, w.textFact],
          copyPlan: true,
        ),
        throwsA(isA<_ForcedPlanFailure>()),
      );
      expect(
        factsSeenByPlanCopy,
        2,
        reason: 'the plan copy fails after the facts were inserted',
      );

      expect(await forksOf(w.source), 0);
      expect(await copiesOf([w.publicFact, w.textFact]), 0);
      expect(await imagesBy(w.forker), 0);
    });

    test(
      "the author's own fork compensates both the duplicated Request "
      'images and the copied fact images, and rethrows the failure',
      () async {
        final w = await world(sourceBeaconImage: true);
        final authorImagesBefore = await imagesBy(w.author);
        await failFactInsertsBy(w.author);

        await expectLater(
          fork(
            beaconCase(),
            sourceId: w.source,
            userId: w.author,
            factIds: [w.publicFact],
          ),
          throwsA(forcedInsertFailure),
        );

        expect(await forksOf(w.source), 0);
        expect(await copiesOf([w.publicFact]), 0);
        expect(
          await imagesBy(w.author),
          authorImagesBefore,
          reason: 'neither the beacon image copy nor the fact image copy stays',
        );
      },
    );

    test('wired without the attention port, the fork creates the draft '
        'without facts and compensates the prepared image copies', () async {
      final w = await world();
      final beacons = beaconCase(withAttention: false);

      // The copy has to be prepared at all for its compensation to mean
      // anything: the same tick with the port wired does copy the fact.
      final wired = await fork(
        beaconCase(),
        sourceId: w.source,
        userId: w.forker,
        factIds: [w.publicFact],
      );
      expect(await factsIn(wired.id), hasLength(1));
      final forkerImagesAfterWired = await imagesBy(w.forker);

      final draft = await fork(
        beacons,
        sourceId: w.source,
        userId: w.forker,
        factIds: [w.publicFact],
      );

      expect(draft.id, isNot(wired.id));
      expect(await factsIn(draft.id), isEmpty);
      expect(
        await imagesBy(w.forker),
        forkerImagesAfterWired,
        reason: 'the unused image copy is compensated',
      );
    });
  });

  group('Forking with ticked facts over GraphQL', () {
    test(
      'beaconFork(id, factIds) answers the draft Beacon holding the '
      'ticked fact as a copy; without factIds the draft has no facts',
      () async {
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
              ..fields.addAll(MutationBeacon(beaconCase: beaconCase()).all),
          ),
        );

        final result = await graphQL.parseAndExecute(
          r'''
mutation Fork($id: String!, $factIds: [String!]) {
  beaconFork(id: $id, factIds: $factIds) { id }
}
''',
          variableValues: {
            'id': w.source,
            'factIds': [w.textFact],
          },
          globalVariables: {kGlobalInputQueryJwt: JwtEntity(sub: w.forker)},
        );

        final plain = await graphQL.parseAndExecute(
          r'''
mutation Fork($id: String!) {
  beaconFork(id: $id) { id }
}
''',
          variableValues: {'id': w.source},
          globalVariables: {kGlobalInputQueryJwt: JwtEntity(sub: w.forker)},
        );
        final plainId =
            ((plain! as Map<String, dynamic>)['beaconFork']
                    as Map<String, dynamic>)['id']
                as String;
        expect(await factsIn(plainId), isEmpty);

        final draftId =
            ((result! as Map<String, dynamic>)['beaconFork']
                    as Map<String, dynamic>)['id']
                as String;
        expect(draftId, isNot(w.source));
        expect(
          [for (final c in await factsIn(draftId)) c['origin_fact_card_id']],
          [w.textFact],
        );
      },
    );
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

  group('Forking brings the files of ticked facts', () {
    test('a ticked fact with a file arrives in the draft with a file entry '
        'backed by its own stored copy, readable after the source fact, its '
        'message and its stored file are deleted', () async {
      final w = await world();
      final factId = 'Fl${'fk${w.n}'.padLeft(10, '0')}';
      final files = await seedFileFact(
        beaconId: w.source,
        author: w.author,
        factId: factId,
        count: 1,
      );
      final file = files.single;

      final draft = await fork(
        beaconCase(),
        sourceId: w.source,
        userId: w.forker,
        factIds: [factId],
      );

      final copy = (await factsIn(draft.id)).single;
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

    test('more files in total than the per-call image limit are all copied, '
        'with no fact dropped', () async {
      final w = await world();
      const perFact = 14;
      final factIds = [
        for (var k = 0; k < 3; k++) 'Fl${'fk${w.n}m$k'.padLeft(10, '0')}',
      ];
      expect(factIds.length * perFact, greaterThan(kMaxFactCopyImagesPerCall));
      final filesByFact = {
        for (final id in factIds)
          id: await seedFileFact(
            beaconId: w.source,
            author: w.author,
            factId: id,
            count: perFact,
          ),
      };
      final sourceKeys = {
        for (final files in filesByFact.values)
          for (final f in files) f.key,
      };

      final draft = await fork(
        beaconCase(),
        sourceId: w.source,
        userId: w.forker,
        factIds: factIds,
      );

      final copies = await factsIn(draft.id);
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
          final copies = copiesOfBytes(sourceKeys, f.bytes);
          expect(copies, hasLength(1));
          expect(sourceKeys, isNot(contains(copies.single)));
        }
      }
    });
  });

  group('Forking skips a file whose stored object is gone', () {
    test('the fork completes and the copy carries the remaining file and '
        'image but no entry for the missing file', () async {
      final w = await world();
      final factId = 'Fl${'fk${w.n}'.padLeft(10, '0')}';
      final files = await seedFileFact(
        beaconId: w.source,
        author: w.author,
        factId: factId,
        count: 2,
      );
      final image = await putImage(w.author, 150 + w.n % 50);
      await writer.execute(
        Sql.named('''
UPDATE public.beacon_fact_card_revision
SET attachments_json = attachments_json || @img::jsonb
WHERE fact_card_id = @f
'''),
        parameters: {
          'img': jsonEncode([
            {...imageAttachment(image, w.author).single, 'position': 2},
          ]),
          'f': factId,
        },
      );
      await storage.removeObject(files[0].key);

      final draft = await fork(
        beaconCase(),
        sourceId: w.source,
        userId: w.forker,
        factIds: [factId],
      );

      final copy = (await factsIn(draft.id)).single;
      expect(copy['origin_fact_card_id'], factId);
      final entries = entriesOf(copy);
      expect(
        [for (final e in entries) e['kind']],
        unorderedEquals([
          BeaconRoomMessageAttachmentKind.file,
          BeaconRoomMessageAttachmentKind.image,
        ]),
      );
      final fileEntry = entries.singleWhere(
        (e) => e['kind'] == BeaconRoomMessageAttachmentKind.file,
      );
      expect(fileEntry['fileName'], files[1].name);
      expect(fileEntry['sizeBytes'], files[1].bytes.length);
      final text = await rows(
        'SELECT fact_text FROM public.beacon_fact_card WHERE id = @i',
        {'i': copy['id']},
      );
      expect(text.single['fact_text'], 'Fact $factId');
      final stored = copiesOfBytes({files[1].key}, files[1].bytes);
      expect(stored, hasLength(1));
    });

    test('a fact whose only file is missing is still copied, with no '
        'attachments, next to a fact whose file is present', () async {
      final w = await world();
      final x = 'Fl${'fk${w.n}x'.padLeft(10, '0')}';
      final y = 'Fl${'fk${w.n}y'.padLeft(10, '0')}';
      final xFiles = await seedFileFact(
        beaconId: w.source,
        author: w.author,
        factId: x,
        count: 1,
      );
      final yFiles = await seedFileFact(
        beaconId: w.source,
        author: w.author,
        factId: y,
        count: 1,
      );
      await storage.removeObject(xFiles.single.key);

      final draft = await fork(
        beaconCase(),
        sourceId: w.source,
        userId: w.forker,
        factIds: [x, y],
      );

      final copies = {
        for (final c in await factsIn(draft.id))
          c['origin_fact_card_id']! as String: c,
      };
      expect(copies.keys, unorderedEquals([x, y]));
      for (final id in [x, y]) {
        final text = await rows(
          'SELECT fact_text FROM public.beacon_fact_card WHERE id = @i',
          {'i': copies[id]!['id']},
        );
        expect(text.single['fact_text'], 'Fact $id');
      }
      expect(entriesOf(copies[x]!), isEmpty);
      expect(entriesOf(copies[y]!), hasLength(1));
      expect(
        copiesOfBytes({yFiles.single.key}, yFiles.single.bytes),
        hasLength(1),
      );
    });

    test('a skipped missing file leaves no extra stored object: only the '
        'copy of the present file is new', () async {
      final w = await world();
      final factId = 'Fl${'fk${w.n}'.padLeft(10, '0')}';
      final files = await seedFileFact(
        beaconId: w.source,
        author: w.author,
        factId: factId,
        count: 2,
      );
      await storage.removeObject(files[0].key);
      final before = storage.objects.keys.toSet();

      await fork(
        beaconCase(),
        sourceId: w.source,
        userId: w.forker,
        factIds: [factId],
      );

      final created = storage.objects.keys.toSet().difference(before);
      expect(created, hasLength(1));
      expect(storage.objects[created.single], files[1].bytes);
    });
  });

  group('Forking when the storage fails while copying a fact file', () {
    final outages = <String, Exception Function()>{
      'a timeout': () => TimeoutException('storage timed out'),
      'a server error (InternalError)': () => s3CodeError('InternalError'),
      'a 503 response': () => MinioError('503 Service Unavailable'),
      'a network failure': () => const SocketException('unreachable'),
    };
    for (final MapEntry(key: name, value: make) in outages.entries) {
      test('$name fails the fork with that error: no Request is created, '
          'every copied blob is removed and a retry succeeds', () async {
        final w = await world();
        final factId = 'Fl${'fk${w.n}'.padLeft(10, '0')}';
        final files = await seedFileFact(
          beaconId: w.source,
          author: w.author,
          factId: factId,
          count: 2,
        );
        final outage = make();
        storage.getErrors[files[1].key] = outage;
        final beaconsBefore = await count(
          'SELECT count(*)::integer AS n FROM public.beacon '
          'WHERE user_id = @u',
          {'u': w.forker},
        );
        final objectsBefore = storage.objects.keys.toSet();

        Object? error;
        try {
          await fork(
            beaconCase(),
            sourceId: w.source,
            userId: w.forker,
            factIds: [w.publicFact, factId],
          );
        } on Object catch (e) {
          error = e;
        }

        expect(error, same(outage), reason: 'the attachment is not dropped');
        expect(
          await count(
            'SELECT count(*)::integer AS n FROM public.beacon '
            'WHERE user_id = @u',
            {'u': w.forker},
          ),
          beaconsBefore,
        );
        // Image objects are removed later by the object GC (their rows are
        // asserted gone below); copied file objects are removed at once.
        expect(
          storage.objects.keys.where((k) => !k.startsWith('images/')).toSet(),
          objectsBefore.where((k) => !k.startsWith('images/')).toSet(),
        );
        expect(await imagesBy(w.forker), 0, reason: 'copied blobs removed');

        storage.getErrors.clear();
        final draft = await fork(
          beaconCase(),
          sourceId: w.source,
          userId: w.forker,
          factIds: [w.publicFact, factId],
        );
        final copies = await factsIn(draft.id);
        expect(
          [for (final c in copies) c['origin_fact_card_id']],
          unorderedEquals([w.publicFact, factId]),
        );
        final fileCopy = copies.singleWhere(
          (c) => c['origin_fact_card_id'] == factId,
        );
        expect(
          [for (final e in entriesOf(fileCopy)) e['fileName']],
          unorderedEquals([for (final f in files) f.name]),
          reason: 'both files are kept, none silently dropped',
        );
        for (final f in files) {
          expect(
            copiesOfBytes({for (final x in files) x.key}, f.bytes),
            hasLength(1),
          );
        }
      });
    }
  });
}

/// Builds [BeaconCase] through its constructor tear-off. The task names the
/// type that carries the fact use case (`BeaconFactCardCase`, plan §5.2) but
/// not the parameter, so parameters are matched by their declared type, read
/// from the tear-off's signature as the VM prints it:
/// `(PortA, PortB, {TypeC? name, required TypeD other}) => BeaconCase`.
/// Ports the constructor already had keep their objects; a parameter typed
/// with a fact type gets [factCards] (or [factRepository] for the
/// repository port). A constructor that takes no fact type fails the test.
BeaconCase _constructBeaconCase({
  required Map<String, Object?> byType,
  required Map<String, Object?> namedByName,
  required BeaconFactCardCase factCards,
  required BeaconFactCardRepository factRepository,
}) {
  final signature = '${BeaconCase.new.runtimeType}';
  final open = signature.indexOf('(');
  final close = signature.lastIndexOf(') =>');
  final params = _splitTopLevel(signature.substring(open + 1, close));

  var factPassed = false;
  Object? valueFor(String rawType) {
    final type = rawType.replaceAll('?', '').trim();
    if (type == 'BeaconFactCardRepositoryPort') {
      factPassed = true;
      return factRepository;
    }
    if (type.contains('Fact')) {
      factPassed = true;
      return factCards;
    }
    if (byType.containsKey(type)) return byType[type];
    fail('BeaconCase takes a $rawType the test cannot provide ($signature)');
  }

  final positional = <Object?>[];
  final named = <Symbol, Object?>{};
  for (final param in params) {
    if (param.startsWith('{') || param.startsWith('[')) {
      for (final entry in _splitTopLevel(
        param.substring(1, param.length - 1),
      )) {
        final words = entry.replaceFirst('required ', '').trim();
        final cut = words.lastIndexOf(' ');
        final type = words.substring(0, cut);
        final name = words.substring(cut + 1);
        named[Symbol(name)] = namedByName.containsKey(name)
            ? namedByName[name]
            : valueFor(type);
      }
    } else {
      positional.add(valueFor(param));
    }
  }
  if (!factPassed) {
    fail(
      'BeaconCase takes no constructor parameter for the fact use case '
      '(BeaconFactCardCase), so a fork cannot prepare fact copies: $signature',
    );
  }
  return Function.apply(BeaconCase.new, positional, named) as BeaconCase;
}

/// Splits [list] at commas outside any brackets.
List<String> _splitTopLevel(String list) {
  final parts = <String>[];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < list.length; i++) {
    final c = list[i];
    if ('<({['.contains(c)) depth++;
    if ('>)}]'.contains(c) && !(c == '>' && i > 0 && list[i - 1] == '=')) {
      depth--;
    }
    if (c == ',' && depth == 0) {
      parts.add(list.substring(start, i).trim());
      start = i + 1;
    }
  }
  final last = list.substring(start).trim();
  if (last.isNotEmpty) parts.add(last);
  return parts;
}
