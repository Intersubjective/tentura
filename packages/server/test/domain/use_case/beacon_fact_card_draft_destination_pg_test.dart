@Tags(['pg'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../support/s3_errors.dart';
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
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/upload_quota_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/entity/fact_copy_outcome.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/domain/use_case/beacon_fact_card_case.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/beacon_repository_ctor_arg.dart';
import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_beacon_child_create_port.dart';
import '../../support/mocks/invite_seed_prompt_repository_mock.dart';

/// Facts and the author's own drafts, through the real use cases over
/// Postgres: copying a fact into a draft Request or Post, listing drafts as
/// copy destinations, and the image cleanup when a copied fact is removed
/// from a draft or the draft is discarded.

String _publicKey(int world, int slot) =>
    'fcdrf${world}w${slot}s'.padRight(44, 'q');

final class _Storage extends Fake implements RemoteStoragePort {
  final objects = <String, Uint8List>{};

  @override
  Future<Uint8List> getObject(String path) async =>
      objects[path] ?? (throw noSuchKeyError(path));

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

/// One isolated set of users and beacons per test. The actor owns the drafts
/// and is an admitted member of the source Request; the author owns the
/// source Request.
final class _World {
  _World(this.n);

  final int n;

  String _id(String prefix) => '$prefix${'dr$n'.padLeft(11, '0')}';

  String get author => _id('Ua');
  String get actor => _id('Uc');

  String get source => _id('Bs');
  String get published => _id('Bp');
  String get draftRequest => _id('Bd');
  String get draftPost => _id('Bn');
  String get blankDraftPost => _id('Bk');
  String get otherDraftRequest => _id('Bg');
  String get otherDraftPost => _id('Bh');

  String get fact => _id('Fs');
  String get plainFact => _id('Fo');
}

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FACT_DRAFT_DESTINATION_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_fact_draft_dest',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;
  late TenturaDb db;
  late ImageRepository images;
  late BeaconFactCardCase case_;
  late BeaconCase beacons;
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
    final env = Env(environment: Environment.test);
    final logger = Logger('BeaconFactCardDraftDestinationPgTest');
    final storage = _Storage();
    final room = BeaconRoomRepository(db);
    final gc = ImageObjectGcRepository(db, storage);
    images = ImageRepository(
      db,
      storage,
      UploadQuotaRepository(db),
      gc,
      env,
      logger,
    );
    final hierarchy = BeaconHierarchyRepository(db);
    case_ = buildWithBeaconRepository<BeaconFactCardCase>(
      BeaconFactCardCase.new,
      positional: [
        BeaconFactCardRepository(db, room),
        room,
        images,
        _Tasks(),
        hierarchy,
        FakeBeaconAccessGuard(),
      ],
      named: {#env: env, #logger: logger},
      beaconRepository: BeaconRepository(db),
    );
    final help = HelpOfferRepository(db);
    final commitments = CommitmentRepository(db);
    final access = BeaconAccessRepository(db);
    final intents = AttentionIntentCase(
      BeaconRoomNotificationContextRepository(room, db, help, commitments),
      UserRepository(
        env,
        db,
        _UnusedGenealogy(),
        InviteSeedPromptRepositoryMock(),
      ),
      access,
      UserBlockRepository(env, db),
    );
    beacons = BeaconCase(
      BeaconRepository(db),
      images,
      gc,
      _Tasks(),
      CommitmentQueryCase(commitments, help, env: env, logger: logger),
      access,
      hierarchy,
      FakeBeaconChildCreatePort(),
      BeaconLifecycleEffectsCase(
        BeaconHierarchyOutboxRepository(db),
        env: env,
        logger: logger,
      ),
      attentionIntents: intents,
      attention: TransactionalAttentionCase(
        MutatingUnitOfWork(db),
        AttentionDispatchRepository(db, logger),
      ),
      remoteStorage: storage,
      env: env,
      logger: logger,
    );
  });

  tearDownAll(() => tearDownDisposablePgWriter(session: session, drift: db));

  Future<String> putImage(String authorId, int salt) => images.put(
    authorId: authorId,
    bytes: Stream.value(Uint8List.fromList([137, 80, 78, 71, salt])),
  );

  Future<void> seedFact(
    _World w, {
    required String id,
    required String beaconId,
    required String pinnedBy,
    List<Map<String, Object?>> attachments = const [],
    String? originFactCardId,
  }) async {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, status, revision_seq,
   origin_fact_card_id, origin_revision_seq, origin_beacon_kind)
VALUES (@id, @beacon, @text, ${BeaconFactCardVisibilityBits.public}, @by,
        ${BeaconFactCardStatusBits.active}, 1, @origin::text,
        CASE WHEN @origin::text IS NULL THEN NULL ELSE 1 END,
        CASE WHEN @origin::text IS NULL THEN NULL ELSE 0::smallint END)
'''),
      parameters: {
        'id': id,
        'beacon': beaconId,
        'text': 'Fact $id',
        'by': pinnedBy,
        'origin': originFactCardId,
      },
    );
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_fact_card_revision
  (fact_card_id, seq, fact_text, actor_id, kind, attachments_json)
VALUES (@id, 1, @text, @by, @kind, @att::jsonb)
'''),
      parameters: {
        'id': id,
        'text': 'Fact $id',
        'by': pinnedBy,
        'kind': originFactCardId == null
            ? BeaconFactCardRevisionKindBits.created
            : BeaconFactCardRevisionKindBits.copied,
        'att': jsonEncode(attachments),
      },
    );
  }

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

  Future<_World> world({bool sourceImage = false}) async {
    final w = _World(++worlds);
    for (final (i, user) in [w.author, w.actor].indexed) {
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
       (@published, @author, 'Published', 'd', 0, 0, now(), false),
       (@draft, @actor, 'Own draft', 'd', 3, 0, NULL, false),
       (@otherDraft, @author, 'Other draft', 'd', 3, 0, NULL, false)
'''),
      parameters: {
        'source': w.source,
        'published': w.published,
        'draft': w.draftRequest,
        'otherDraft': w.otherDraftRequest,
        'author': w.author,
        'actor': w.actor,
      },
    );
    // Draft Posts: open, kind 1, no root message.
    for (final (id, owner, description) in [
      (w.draftPost, w.actor, 'Own draft post excerpt'),
      (w.blankDraftPost, w.actor, ''),
      (w.otherDraftPost, w.author, 'Other draft post'),
    ]) {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at, expires_at)
VALUES (@id, @owner, '', @description, 0, 1, 1, false, NULL, NULL)
'''),
        parameters: {'id': id, 'owner': owner, 'description': description},
      );
    }
    for (final (i, beaconId) in [
      w.source,
      w.published,
      w.otherDraftRequest,
      w.otherDraftPost,
    ].indexed) {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES (@id, @beacon, @user, 0, 0, ${RoomAccessBits.admitted})
'''),
        parameters: {'id': 'Pdr${w.n}x$i', 'beacon': beaconId, 'user': w.actor},
      );
    }
    var attachments = const <Map<String, Object?>>[];
    if (sourceImage) {
      attachments = imageAttachment(await putImage(w.author, w.n), w.author);
    }
    await seedFact(
      w,
      id: w.fact,
      beaconId: w.source,
      pinnedBy: w.author,
      attachments: attachments,
    );
    return w;
  }

  Future<List<Map<String, Object?>>> copiesIn(String beaconId, String origin) =>
      rows(
        '''
SELECT f.id, f.origin_fact_card_id, f.origin_revision_seq,
       (SELECT count(*)::integer FROM public.beacon_fact_card_revision r
         WHERE r.fact_card_id = f.id) AS revisions,
       (SELECT r.kind::integer FROM public.beacon_fact_card_revision r
         WHERE r.fact_card_id = f.id ORDER BY r.seq LIMIT 1) AS first_kind,
       (SELECT r.attachments_json::text
          FROM public.beacon_fact_card_revision r
         WHERE r.fact_card_id = f.id ORDER BY r.seq DESC LIMIT 1)
         AS attachments
FROM public.beacon_fact_card f
WHERE f.beacon_id = @b AND f.origin_fact_card_id = @o
''',
        {'b': beaconId, 'o': origin},
      );

  Future<Map<String, Object?>> footprint(String beaconId) async => (await rows(
    '''
SELECT
  (SELECT count(*)::integer FROM public.beacon_room_message
    WHERE beacon_id = @b) AS messages,
  (SELECT count(*)::integer FROM public.beacon_activity_event
    WHERE beacon_id = @b) AS events
''',
    {'b': beaconId},
  )).single;

  Future<bool> imageRowExists(String imageId) async =>
      await count(
        'SELECT count(*)::integer AS n FROM public.image WHERE id = @i::uuid',
        {'i': imageId},
      ) >
      0;

  Future<bool> gcQueued(String imageId) async =>
      await count(
        'SELECT count(*)::integer AS n FROM public.image_object_gc '
        'WHERE image_id = @i::uuid',
        {'i': imageId},
      ) >
      0;

  Future<int> factCount(String id) => count(
    'SELECT count(*)::integer AS n FROM public.beacon_fact_card '
    'WHERE id = @i',
    {'i': id},
  );

  List<String> imageIdsIn(String attachmentsJson) => [
    for (final e in jsonDecode(attachmentsJson) as List<Object?>)
      (e! as Map)['imageId']! as String,
  ];

  Future<Object> errorOf(Future<Object?> Function() action) async {
    try {
      await action();
    } on TestFailure {
      rethrow;
    } on Object catch (error) {
      return error;
    }
    fail('expected the call to be refused');
  }

  /// Copies the world's image fact into [beaconId] through the use case and
  /// returns the copy's id and its duplicated image id.
  Future<({String factId, String imageId})> copyImageFactInto(
    _World w,
    String beaconId,
  ) async {
    final answer = await case_.copy(
      sourceFactCardId: w.fact,
      destinationBeaconId: beaconId,
      actorUserId: w.actor,
    );
    final copy = (await copiesIn(beaconId, w.fact)).single;
    expect(copy['id'], answer.factCardId);
    return (
      factId: answer.factCardId,
      imageId: imageIdsIn(copy['attachments']! as String).single,
    );
  }

  group("Copying a fact into the author's own draft", () {
    for (final (label, draft) in [
      ('Request', (_World w) => w.draftRequest),
      ('Post', (_World w) => w.draftPost),
    ]) {
      test(
        'a draft $label receives the copy with its origin, silently',
        () async {
          final w = await world();
          final id = draft(w);
          final before = await footprint(id);
          final answer = await case_.copy(
            sourceFactCardId: w.fact,
            destinationBeaconId: id,
            actorUserId: w.actor,
          );
          expect(answer.outcome, FactCopyOutcome.created);
          final copies = await copiesIn(id, w.fact);
          expect(copies, hasLength(1));
          expect(copies.single['id'], answer.factCardId);
          expect(copies.single['origin_fact_card_id'], w.fact);
          expect(copies.single['origin_revision_seq'], 1);
          expect(copies.single['revisions'], 1);
          expect(
            copies.single['first_kind'],
            BeaconFactCardRevisionKindBits.copied,
          );
          expect(
            await footprint(id),
            before,
            reason: 'no chat line and no activity event on a draft',
          );
        },
      );
    }

    test('the copy of an image fact gets its own image row; the source is '
        'unchanged', () async {
      final w = await world(sourceImage: true);
      final sourceImageId = imageIdsIn(
        (await rows(
              'SELECT attachments_json::text AS a '
              'FROM public.beacon_fact_card_revision WHERE fact_card_id = @f',
              {'f': w.fact},
            )).single['a']!
            as String,
      ).single;
      await case_.copy(
        sourceFactCardId: w.fact,
        destinationBeaconId: w.draftRequest,
        actorUserId: w.actor,
      );
      final copy = (await copiesIn(w.draftRequest, w.fact)).single;
      final newImageId = imageIdsIn(copy['attachments']! as String).single;
      expect(newImageId, isNot(sourceImageId));
      expect(
        await count(
          'SELECT count(*)::integer AS n FROM public.image '
          'WHERE id = @i::uuid AND author_id = @a',
          {'i': newImageId, 'a': w.actor},
        ),
        1,
      );
      expect(await imageRowExists(sourceImageId), isTrue);
    });

    test('copying the same fact into the same draft again reports '
        'alreadyThere and inserts nothing', () async {
      final w = await world();
      final first = await case_.copy(
        sourceFactCardId: w.fact,
        destinationBeaconId: w.draftRequest,
        actorUserId: w.actor,
      );
      final second = await case_.copy(
        sourceFactCardId: w.fact,
        destinationBeaconId: w.draftRequest,
        actorUserId: w.actor,
      );
      expect(first.outcome, FactCopyOutcome.created);
      expect(second.outcome, FactCopyOutcome.alreadyThere);
      expect(second.factCardId, first.factCardId);
      expect(await copiesIn(w.draftRequest, w.fact), hasLength(1));
    });

    test("another user's draft is refused like a missing beacon, before the "
        'source is looked at', () async {
      final w = await world();
      final reference = await errorOf(
        () => case_.copy(
          sourceFactCardId: w.fact,
          destinationBeaconId: 'Bmissing$worlds',
          actorUserId: w.author,
        ),
      );
      expect(reference, isA<UnauthorizedException>());
      reference as UnauthorizedException;
      for (final draft in [w.draftRequest, w.draftPost]) {
        for (final source in [w.fact, 'Fmissing$worlds']) {
          final error = await errorOf(
            () => case_.copy(
              sourceFactCardId: source,
              destinationBeaconId: draft,
              actorUserId: w.author,
            ),
          );
          expect(error, isA<UnauthorizedException>(), reason: '$draft $source');
          error as UnauthorizedException;
          expect(error.description, reference.description);
          expect(error.code.codeNumber, reference.code.codeNumber);
          expect(await copiesIn(draft, w.fact), isEmpty);
        }
      }
    });
  });

  group('Copy destinations list drafts', () {
    test(
      "the caller's own drafts are listed with isDraft, nobody else's",
      () async {
        final w = await world();
        final listed = await case_.copyDestinations(
          sourceFactCardId: w.fact,
          userId: w.actor,
        );
        final byId = {for (final r in listed) r['id']! as String: r};
        expect(byId, contains(w.draftRequest));
        expect(byId, contains(w.draftPost));
        expect(byId[w.draftRequest]!['isDraft'], isTrue);
        expect(byId[w.draftRequest]!['title'], 'Own draft');
        expect(byId[w.draftPost]!['isDraft'], isTrue);
        expect(byId[w.draftPost]!['kind'], 1);
        expect(byId[w.draftPost]!['title'], 'Own draft post excerpt');
        expect(byId, contains(w.blankDraftPost));
        expect(byId[w.blankDraftPost]!['isDraft'], isTrue);
        expect(byId[w.blankDraftPost]!['title'], '');
        expect(byId[w.published]!['isDraft'], isFalse);
        expect(byId, isNot(contains(w.otherDraftRequest)));
        expect(byId, isNot(contains(w.otherDraftPost)));
      },
    );
  });

  group('Removing a fact from a draft cleans up its images', () {
    test("a copied fact's duplicated image row is deleted and queued for "
        'storage cleanup, with no chat line or event', () async {
      final w = await world(sourceImage: true);
      final (:factId, :imageId) = await copyImageFactInto(w, w.draftRequest);
      final before = await footprint(w.draftRequest);
      final removed = await case_.remove(
        factCardId: factId,
        beaconId: w.draftRequest,
        actorUserId: w.actor,
      );
      expect(removed, isTrue);
      expect(await factCount(factId), 0);
      expect(await imageRowExists(imageId), isFalse);
      expect(await gcQueued(imageId), isTrue);
      expect(await footprint(w.draftRequest), before);
    });

    test('an ordinary fact sharing its image with a message keeps the '
        "message's image row", () async {
      final w = await world();
      final imageId = await putImage(w.actor, 200 + w.n);
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES (@m, @b, @a, 'with image')
'''),
        parameters: {'m': 'Rdr${w.n}', 'b': w.draftRequest, 'a': w.actor},
      );
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_room_message_attachment
  (id, message_id, kind, image_id, mime, position)
VALUES (@id, @m, ${BeaconRoomMessageAttachmentKind.image}, @i::uuid,
        'image/png', 0)
'''),
        parameters: {'id': 'Adr${w.n}', 'm': 'Rdr${w.n}', 'i': imageId},
      );
      await seedFact(
        w,
        id: w.plainFact,
        beaconId: w.draftRequest,
        pinnedBy: w.actor,
        attachments: imageAttachment(imageId, w.actor),
      );
      final removed = await case_.remove(
        factCardId: w.plainFact,
        beaconId: w.draftRequest,
        actorUserId: w.actor,
      );
      expect(removed, isTrue);
      expect(await factCount(w.plainFact), 0);
      expect(await imageRowExists(imageId), isTrue);
      expect(await gcQueued(imageId), isFalse);
    });

    test('a user other than the author cannot remove it', () async {
      final w = await world(sourceImage: true);
      final (:factId, :imageId) = await copyImageFactInto(w, w.draftRequest);
      final error = await errorOf(
        () => case_.remove(
          factCardId: factId,
          beaconId: w.draftRequest,
          actorUserId: w.author,
        ),
      );
      expect(error, isA<UnauthorizedException>());
      expect(await factCount(factId), 1);
      expect(await imageRowExists(imageId), isTrue);
    });
  });

  group('Discarding a draft', () {
    test("deletes the copied facts' image rows and queues them; the source "
        "fact's image stays", () async {
      final w = await world(sourceImage: true);
      final sourceImageId = imageIdsIn(
        (await rows(
              'SELECT attachments_json::text AS a '
              'FROM public.beacon_fact_card_revision WHERE fact_card_id = @f',
              {'f': w.fact},
            )).single['a']!
            as String,
      ).single;
      final copiedImageId = (await copyImageFactInto(
        w,
        w.draftRequest,
      )).imageId;
      final deleted = await beacons.deleteById(
        beaconId: w.draftRequest,
        userId: w.actor,
      );
      expect(deleted, isTrue);
      expect(
        await count(
          'SELECT count(*)::integer AS n FROM public.beacon WHERE id = @b',
          {'b': w.draftRequest},
        ),
        0,
      );
      expect(await imageRowExists(copiedImageId), isFalse);
      expect(await gcQueued(copiedImageId), isTrue);
      expect(await imageRowExists(sourceImageId), isTrue);
    });
  });
}
