@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:minio/minio.dart' show MinioError;
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
import 'package:tentura_server/data/repository/coordination_item_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/image_object_gc_repository.dart';
import 'package:tentura_server/data/repository/image_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/polling_repository.dart';
import 'package:tentura_server/data/repository/post_lock_repository.dart';
import 'package:tentura_server/data/repository/upload_quota_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/entity/fact_copy_outcome.dart';
import 'package:tentura_server/domain/entity/prepared_fact_copy.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/room/room_attachment_storage_key.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/domain/use_case/beacon_fact_card_case.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_beacon_child_create_port.dart';

/// Copying a fact that holds a file (non-image) attachment, through the real
/// use cases over Postgres: the copy gets its own stored copy of the file
/// (new object, same bytes and metadata) that outlives the source, with no
/// size, daily-cap or count limit, and that object is cleaned up when the
/// copy is not inserted or is discarded from a draft.

String _publicKey(int world, int slot) =>
    'fcfile${world}w${slot}s'.padRight(44, 'q');

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

/// The real repository, letting a test act between prepare and insert.
final class _Facts extends BeaconFactCardRepository {
  // The super constructor's field parameter is private (`_db`).
  // ignore: matching_super_parameters
  _Facts(super.db, super.room);

  Future<void> Function()? beforeInsert;

  @override
  Future<List<String>> insertPreparedCopies({
    required String destinationBeaconId,
    required String actorUserId,
    required List<PreparedFactCopy> prepared,
  }) async {
    final hook = beforeInsert;
    beforeInsert = null;
    if (hook != null) await hook();
    return super.insertPreparedCopies(
      destinationBeaconId: destinationBeaconId,
      actorUserId: actorUserId,
      prepared: prepared,
    );
  }
}

/// A file the source fact holds: its room attachment row and stored object.
final class _SourceFile {
  const _SourceFile({
    required this.attachmentId,
    required this.storageKey,
    required this.bytes,
    required this.fileName,
    required this.mime,
    required this.position,
  });

  final String attachmentId;
  final String storageKey;
  final Uint8List bytes;
  final String fileName;
  final String mime;
  final int position;
}

/// One isolated set of users and beacons per test. The author owns the
/// source Request; the actor is admitted to it and to the published
/// destination and owns a draft Request.
final class _World {
  _World(this.n);

  final int n;

  String _id(String prefix) => '$prefix${'ff$n'.padLeft(11, '0')}';

  String get author => _id('Ua');
  String get actor => _id('Uc');

  /// Member of the published destination only, not of the source.
  String get peer => _id('Up');

  /// Member of neither Request.
  String get stranger => _id('Us');

  String get source => _id('Bs');
  String get published => _id('Bp');
  String get draft => _id('Bd');

  String get fact => _id('Fs');
  String get message => _id('Rs');
}

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FACT_COPY_FILES_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_fact_copy_files',
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
  late _Facts facts;
  late BeaconFactCardCase case_;
  late BeaconCase beacons;
  late BeaconRoomCase roomCase;
  var worlds = 0;

  Future<List<Map<String, Object?>>> rows(
    String sql, [
    Map<String, Object?> parameters = const {},
  ]) async {
    final result = await writer.execute(Sql.named(sql), parameters: parameters);
    return [for (final r in result) r.toColumnMap()];
  }

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
    final logger = Logger('FactCopyFileAttachmentsPgTest');
    storage = _Storage();
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
    facts = _Facts(db, room);
    case_ = BeaconFactCardCase(
      facts,
      room,
      images,
      _Tasks(),
      hierarchy,
      FakeBeaconAccessGuard(),
      env: env,
      logger: logger,
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
    final uow = MutatingUnitOfWork(db);
    roomCase = BeaconRoomCase(
      room,
      CoordinationItemRepository(db),
      facts,
      images,
      _Tasks(),
      storage,
      PollingRepository(db),
      UploadQuotaRepository(db),
      UserBlockRepository(env, db),
      uow,
      hierarchy,
      const ProductionDiscussionProductPolicy(),
      beaconRepository: BeaconRepository(db),
      postLock: PostLockRepository(db),
      attention: TransactionalAttentionCase(
        uow,
        AttentionDispatchRepository(db, logger),
      ),
      attentionIntents: intents,
      env: env,
      logger: logger,
    );
  });

  tearDownAll(() => tearDownDisposablePgWriter(session: session, drift: db));

  Future<_World> world() async {
    final w = _World(++worlds);
    for (final (i, user) in [w.author, w.actor, w.peer, w.stranger].indexed) {
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
       (@draft, @actor, 'Own draft', 'd', 3, 0, NULL, false)
'''),
      parameters: {
        'source': w.source,
        'published': w.published,
        'draft': w.draft,
        'author': w.author,
        'actor': w.actor,
      },
    );
    for (final (i, beaconId) in [w.source, w.published].indexed) {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES (@id, @beacon, @user, 0, 0, ${RoomAccessBits.admitted})
'''),
        parameters: {'id': 'Pff${w.n}x$i', 'beacon': beaconId, 'user': w.actor},
      );
    }
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES (@id, @beacon, @user, 0, 0, ${RoomAccessBits.admitted})
'''),
      parameters: {'id': 'Pff${w.n}xp', 'beacon': w.published, 'user': w.peer},
    );
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES (@m, @b, @a, 'Here is the document')
'''),
      parameters: {'m': w.message, 'b': w.source, 'a': w.author},
    );
    return w;
  }

  /// Stores [bytes] as a file attachment of the world's source message, the
  /// way a room upload does, and returns it.
  Future<_SourceFile> attachFile(
    _World w, {
    required int position,
    required Uint8List bytes,
    String fileName = 'plan.pdf',
    String mime = 'application/pdf',
  }) async {
    final attachmentId = 'Aff${w.n}p$position'.padRight(13, 'x');
    final key = '${roomAttachmentStorageKey(bytes)}/$attachmentId';
    await storage.putObject(key, Stream.value(bytes));
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_room_message_attachment
  (id, message_id, kind, file_url, mime, size_bytes, position, file_name)
VALUES (@id, @m, ${BeaconRoomMessageAttachmentKind.file}, @url, @mime,
        @size, @pos, @name)
'''),
      parameters: {
        'id': attachmentId,
        'm': w.message,
        'url': key,
        'mime': mime,
        'size': bytes.length,
        'pos': position,
        'name': fileName,
      },
    );
    return _SourceFile(
      attachmentId: attachmentId,
      storageKey: key,
      bytes: bytes,
      fileName: fileName,
      mime: mime,
      position: position,
    );
  }

  /// Stores an image as an attachment of the world's source message.
  Future<String> attachImage(_World w, {required int position}) async {
    final imageId = await images.put(
      authorId: w.author,
      bytes: Stream.value(Uint8List.fromList([137, 80, 78, 71, w.n % 250])),
    );
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_room_message_attachment
  (id, message_id, kind, image_id, mime, size_bytes, position, file_name)
VALUES (@id, @m, ${BeaconRoomMessageAttachmentKind.image}, @i::uuid,
        'image/png', 5, @pos, 'photo.png')
'''),
      parameters: {
        'id': 'Aff${w.n}i$position'.padRight(13, 'x'),
        'm': w.message,
        'i': imageId,
        'pos': position,
      },
    );
    return imageId;
  }

  /// Pins the world's source message as a fact: its head revision snapshots
  /// the message attachments exactly as pinning does.
  Future<void> pinSourceMessage(_World w) async {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, status, revision_seq,
   source_message_id)
VALUES (@id, @beacon, 'The plan', ${BeaconFactCardVisibilityBits.public},
        @by, ${BeaconFactCardStatusBits.active}, 1, @m)
'''),
      parameters: {
        'id': w.fact,
        'beacon': w.source,
        'by': w.author,
        'm': w.message,
      },
    );
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_fact_card_revision
  (fact_card_id, seq, fact_text, actor_id, kind, attachments_json)
SELECT @id, 1, 'The plan', @by, ${BeaconFactCardRevisionKindBits.created},
  COALESCE((
    SELECT jsonb_agg(item ORDER BY (item->>'position')::int)
    FROM (
      SELECT jsonb_strip_nulls(jsonb_build_object(
        'id', a.id,
        'kind', a.kind,
        'position', a.position,
        'mime', a.mime,
        'sizeBytes', a.size_bytes,
        'fileName', a.file_name,
        'imageId', COALESCE(i.id::text, ''),
        'imageAuthorId', COALESCE(i.author_id, ''),
        'blurHash', COALESCE(i.hash, ''),
        'width', COALESCE(i.width, 0),
        'height', COALESCE(i.height, 0)
      )) AS item
      FROM public.beacon_room_message_attachment a
      LEFT JOIN public.image i ON i.id = a.image_id
      WHERE a.message_id = @m
    ) q
  ), '[]'::jsonb)
'''),
      parameters: {'id': w.fact, 'by': w.author, 'm': w.message},
    );
  }

  /// A world whose source fact holds one file of [bytes].
  Future<(_World, _SourceFile)> fileFactWorld({Uint8List? bytes}) async {
    final w = await world();
    final file = await attachFile(
      w,
      position: 0,
      bytes: bytes ?? Uint8List.fromList(utf8.encode('plan v${w.n}')),
    );
    await pinSourceMessage(w);
    return (w, file);
  }

  /// The head-revision attachments of the copy of the world's fact in
  /// [beaconId].
  Future<({String factId, List<Map<String, Object?>> attachments})> copyIn(
    _World w,
    String beaconId,
  ) async {
    final found = await rows(
      '''
SELECT f.id,
       (SELECT r.attachments_json::text
          FROM public.beacon_fact_card_revision r
         WHERE r.fact_card_id = f.id ORDER BY r.seq DESC LIMIT 1)
         AS attachments
FROM public.beacon_fact_card f
WHERE f.beacon_id = @b AND f.origin_fact_card_id = @o
''',
      {'b': beaconId, 'o': w.fact},
    );
    expect(found, hasLength(1), reason: 'one copy of the fact in $beaconId');
    return (
      factId: found.single['id']! as String,
      attachments: [
        for (final e
            in jsonDecode(found.single['attachments']! as String) as List)
          Map<String, Object?>.from(e! as Map),
      ],
    );
  }

  /// Keys of stored objects that did not exist in [before] and hold
  /// exactly [bytes].
  List<String> newObjectsHolding(Set<String> before, Uint8List bytes) => [
    for (final MapEntry(:key, :value) in storage.objects.entries)
      if (!before.contains(key) && _sameBytes(value, bytes)) key,
  ];

  /// Deletes the source file: its message (and so its attachment row) and
  /// the stored object.
  Future<void> deleteSource(_World w, _SourceFile file) async {
    await writer.execute(
      Sql.named('DELETE FROM public.beacon_fact_card WHERE id = @f'),
      parameters: {'f': w.fact},
    );
    await writer.execute(
      Sql.named('DELETE FROM public.beacon_room_message WHERE id = @m'),
      parameters: {'m': w.message},
    );
    await storage.removeObject(file.storageKey);
  }

  void expectFileEntry(Map<String, Object?> entry, _SourceFile file) {
    expect(entry['kind'], BeaconRoomMessageAttachmentKind.file);
    expect(entry['fileName'], file.fileName);
    expect(entry['mime'], file.mime);
    expect(entry['sizeBytes'], file.bytes.length);
    expect(entry['position'], file.position);
    expect(
      entry['id'],
      isNot(file.attachmentId),
      reason: 'the copy owns an attachment of its own',
    );
  }

  group('Copying a fact with a file attachment into a published Request', () {
    test('the copy holds a file entry with the source name, type, size and '
        'position, backed by its own stored copy of the bytes that outlives '
        'the source', () async {
      final (w, file) = await fileFactWorld();
      final before = storage.objects.keys.toSet();

      final answer = await case_.copy(
        sourceFactCardId: w.fact,
        destinationBeaconId: w.published,
        actorUserId: w.actor,
      );

      expect(answer.outcome, FactCopyOutcome.created);
      final copy = await copyIn(w, w.published);
      expect(copy.factId, answer.factCardId);
      expect(copy.attachments, hasLength(1));
      expectFileEntry(copy.attachments.single, file);
      final copied = newObjectsHolding(before, file.bytes);
      expect(copied, hasLength(1), reason: 'one new stored object per file');
      expect(copied.single, isNot(file.storageKey));

      await deleteSource(w, file);
      expect(storage.objects[copied.single], file.bytes);
    });

    test(
      'a file larger than the ordinary upload limit is copied in full',
      () async {
        final big = Uint8List(kMaxRoomMessageAttachmentBytes + 1)
          ..fillRange(0, 16, 7);
        final (w, file) = await fileFactWorld(bytes: big);
        final before = storage.objects.keys.toSet();

        final answer = await case_.copy(
          sourceFactCardId: w.fact,
          destinationBeaconId: w.published,
          actorUserId: w.actor,
        );

        expect(answer.outcome, FactCopyOutcome.created);
        final copy = await copyIn(w, w.published);
        expect(copy.attachments, hasLength(1));
        expectFileEntry(copy.attachments.single, file);
        expect(newObjectsHolding(before, big), hasLength(1));
      },
    );

    test('a fact holding a file and an image is copied with both, in source '
        'order, each with a blob of its own', () async {
      final w = await world();
      final file = await attachFile(
        w,
        position: 0,
        bytes: Uint8List.fromList(utf8.encode('mixed ${w.n}')),
      );
      final sourceImage = await attachImage(w, position: 1);
      await pinSourceMessage(w);
      final before = storage.objects.keys.toSet();

      await case_.copy(
        sourceFactCardId: w.fact,
        destinationBeaconId: w.published,
        actorUserId: w.actor,
      );

      final copy = await copyIn(w, w.published);
      expect(
        [for (final a in copy.attachments) a['kind']],
        [
          BeaconRoomMessageAttachmentKind.file,
          BeaconRoomMessageAttachmentKind.image,
        ],
      );
      expect([for (final a in copy.attachments) a['position']], [0, 1]);
      expectFileEntry(copy.attachments.first, file);
      final image = copy.attachments.last;
      expect(image['imageId'], isNot(sourceImage));
      expect(image['imageAuthorId'], w.actor);
      final copied = newObjectsHolding(before, file.bytes);
      expect(copied, hasLength(1));
      expect(copied.single, isNot(file.storageKey));
    });

    test('a copier at the daily upload cap still gets the file copied, and '
        'nothing is counted against the cap for it', () async {
      final (w, file) = await fileFactWorld();
      await writer.execute(
        Sql.named('''
INSERT INTO public.upload_daily_usage (user_id, usage_date, bytes)
VALUES (@u, (now() AT TIME ZONE 'UTC')::date, @cap)
'''),
        parameters: {'u': w.actor, 'cap': env.uploadDailyCapBytes},
      );
      final before = storage.objects.keys.toSet();

      final answer = await case_.copy(
        sourceFactCardId: w.fact,
        destinationBeaconId: w.published,
        actorUserId: w.actor,
      );

      expect(answer.outcome, FactCopyOutcome.created);
      final copy = await copyIn(w, w.published);
      expect(copy.attachments, hasLength(1));
      expectFileEntry(copy.attachments.single, file);
      expect(newObjectsHolding(before, file.bytes), hasLength(1));
      final usage = await rows(
        'SELECT bytes FROM public.upload_daily_usage WHERE user_id = @u',
        {'u': w.actor},
      );
      expect(usage.single['bytes'], env.uploadDailyCapBytes);
    });
  });

  group('A copied file that is not kept is removed from storage', () {
    test('when the destination closes before the insert, the copy fails and '
        'its stored file is removed; the source file stays', () async {
      final (w, file) = await fileFactWorld();
      final before = storage.objects.keys.toSet();
      var storedBeforeInsert = <String>[];
      facts.beforeInsert = () async {
        storedBeforeInsert = newObjectsHolding(before, file.bytes);
        await writer.execute(
          Sql.named('UPDATE public.beacon SET status = 1 WHERE id = @b'),
          parameters: {'b': w.published},
        );
      };

      Object? error;
      try {
        await case_.copy(
          sourceFactCardId: w.fact,
          destinationBeaconId: w.published,
          actorUserId: w.actor,
        );
      } on Object catch (e) {
        error = e;
      }

      expect(error, isNotNull, reason: 'the copy into a closed Request fails');
      expect(
        storedBeforeInsert,
        hasLength(1),
        reason: 'the file copy is stored before the insert',
      );
      expect(storage.objects.containsKey(storedBeforeInsert.single), isFalse);
      expect(storage.objects[file.storageKey], file.bytes);
    });

    test('a copy that loses to a copy inserted meanwhile removes its own '
        "stored file; the winner's file stays", () async {
      final (w, file) = await fileFactWorld();
      final before = storage.objects.keys.toSet();
      var winnerObjects = <String>[];
      var winnerId = '';
      facts.beforeInsert = () async {
        // The loser's own file is already stored at this point.
        final beforeWinner = storage.objects.keys.toSet();
        final winner = await case_.copy(
          sourceFactCardId: w.fact,
          destinationBeaconId: w.published,
          actorUserId: w.actor,
        );
        winnerId = winner.factCardId;
        winnerObjects = newObjectsHolding(beforeWinner, file.bytes);
      };

      final loser = await case_.copy(
        sourceFactCardId: w.fact,
        destinationBeaconId: w.published,
        actorUserId: w.actor,
      );

      expect(loser.outcome, FactCopyOutcome.alreadyThere);
      expect(loser.factCardId, winnerId);
      expect(
        winnerObjects,
        hasLength(1),
        reason: "the winner's copy has its own stored file",
      );
      expect(
        newObjectsHolding(before, file.bytes),
        winnerObjects,
        reason: "only the winner's stored file is left",
      );
      expectFileEntry((await copyIn(w, w.published)).attachments.single, file);
    });
  });

  group('Opening the copied file follows the copy, not the source', () {
    test('a member of the destination who cannot open the source file opens '
        'the copied file as a fact file; a non-member is refused', () async {
      final (w, file) = await fileFactWorld();
      await expectLater(
        roomCase.downloadAttachment(
          userId: w.peer,
          attachmentId: file.attachmentId,
        ),
        throwsA(isA<UnauthorizedException>()),
        reason: 'the peer has no access to the source Request',
      );

      await case_.copy(
        sourceFactCardId: w.fact,
        destinationBeaconId: w.published,
        actorUserId: w.actor,
      );
      final entries = (await copyIn(w, w.published)).attachments;
      expect(entries, hasLength(1), reason: 'the file entry is copied');
      final copiedId = entries.single['id']! as String;

      await deleteSource(w, file);
      final opened = await roomCase.downloadAttachment(
        userId: w.peer,
        attachmentId: copiedId,
      );
      expect(opened.bytes, file.bytes);
      expect(opened.fileName, file.fileName);
      expect(opened.mime, file.mime);

      await expectLater(
        roomCase.downloadAttachment(
          userId: w.stranger,
          attachmentId: copiedId,
        ),
        throwsA(isA<UnauthorizedException>()),
        reason: 'a non-member is refused as for any room file',
      );
    });
  });

  group('A copied file in a draft is removed with it', () {
    test('removing the copied fact from the draft removes its stored file; '
        'the source file stays', () async {
      final (w, file) = await fileFactWorld();
      final before = storage.objects.keys.toSet();
      final answer = await case_.copy(
        sourceFactCardId: w.fact,
        destinationBeaconId: w.draft,
        actorUserId: w.actor,
      );
      final copied = newObjectsHolding(before, file.bytes);
      expect(copied, hasLength(1));

      final removed = await case_.remove(
        factCardId: answer.factCardId,
        beaconId: w.draft,
        actorUserId: w.actor,
      );

      expect(removed, isTrue);
      expect(storage.objects.containsKey(copied.single), isFalse);
      expect(storage.objects[file.storageKey], file.bytes);
    });

    test('discarding the draft removes the stored file of its copied fact; '
        'the source file stays', () async {
      final (w, file) = await fileFactWorld();
      final before = storage.objects.keys.toSet();
      await case_.copy(
        sourceFactCardId: w.fact,
        destinationBeaconId: w.draft,
        actorUserId: w.actor,
      );
      final copied = newObjectsHolding(before, file.bytes);
      expect(copied, hasLength(1));

      final deleted = await beacons.deleteById(
        beaconId: w.draft,
        userId: w.actor,
      );

      expect(deleted, isTrue);
      expect(storage.objects.containsKey(copied.single), isFalse);
      expect(storage.objects[file.storageKey], file.bytes);
    });
  });

  group('Copying a fact whose file object is gone from storage', () {
    test('a direct copy fails, inserts no fact and leaves no stored object '
        'behind', () async {
      final w = await world();
      final present = await attachFile(
        w,
        position: 0,
        bytes: Uint8List.fromList(utf8.encode('present ${w.n}')),
      );
      final gone = await attachFile(
        w,
        position: 1,
        bytes: Uint8List.fromList(utf8.encode('gone ${w.n}')),
        fileName: 'gone.pdf',
      );
      await pinSourceMessage(w);
      await storage.removeObject(gone.storageKey);
      final before = storage.objects.keys.toSet();

      Object? error;
      try {
        await case_.copy(
          sourceFactCardId: w.fact,
          destinationBeaconId: w.published,
          actorUserId: w.actor,
        );
      } on Object catch (e) {
        error = e;
      }

      expect(error, isNotNull, reason: 'a missing file fails a direct copy');
      final inserted = await rows(
        'SELECT id FROM public.beacon_fact_card WHERE beacon_id = @b',
        {'b': w.published},
      );
      expect(inserted, isEmpty);
      expect(storage.objects.keys.toSet(), before);
      expect(storage.objects[present.storageKey], present.bytes);
    });
  });

  group('A fact file the storage cannot give back', () {
    /// A world whose source fact holds a present file at position 0 and a
    /// second file at position 1.
    Future<(_World, _SourceFile, _SourceFile)> twoFileWorld() async {
      final w = await world();
      final first = await attachFile(
        w,
        position: 0,
        bytes: Uint8List.fromList(utf8.encode('first ${w.n}')),
      );
      final second = await attachFile(
        w,
        position: 1,
        bytes: Uint8List.fromList(utf8.encode('second ${w.n}')),
        fileName: 'second.pdf',
      );
      await pinSourceMessage(w);
      return (w, first, second);
    }

    Future<Object?> errorOf(Future<Object?> Function() call) async {
      try {
        await call();
      } on Object catch (e) {
        return e;
      }
      return null;
    }

    test('a fork or bud (skipUnavailable) drops a file whose object is gone '
        'and keeps the rest of the fact with a new object for the first '
        'file', () async {
      final (w, first, second) = await twoFileWorld();
      await storage.removeObject(second.storageKey);
      final before = storage.objects.keys.toSet();

      final result = await case_.prepareCopies(
        sourceFactCardIds: [w.fact],
        actorUserId: w.actor,
        destinationBeaconId: w.published,
        skipUnavailable: true,
      );

      final copy = result.prepared.single;
      final attachments = [
        for (final e in jsonDecode(copy.attachmentsJson) as List<Object?>)
          Map<String, Object?>.from(e! as Map),
      ];
      expect(attachments, hasLength(1));
      expect(attachments.single['fileName'], first.fileName);
      final newKey = attachments.single['fileKey']! as String;
      expect(newKey, isNot(first.storageKey));
      expect(copy.newFileKeys, [newKey]);
      expect(
        storage.objects.keys.toSet().difference(before),
        {newKey},
        reason: 'the kept copy stays stored',
      );
    });

    test('a direct copy of a fact with a gone file says an attachment is no '
        'longer available (not that the fact is unavailable), inserts no '
        'fact and removes the file it already copied', () async {
      final (w, _, second) = await twoFileWorld();
      await storage.removeObject(second.storageKey);
      final before = storage.objects.keys.toSet();

      final error = await errorOf(
        () => case_.copy(
          sourceFactCardId: w.fact,
          destinationBeaconId: w.published,
          actorUserId: w.actor,
        ),
      );

      expect(error, isA<ExceptionBase>());
      final base = error! as ExceptionBase;
      expect(
        base.toMap['extensions'],
        containsPair('code', '1354'),
        reason: 'a new code after 1353, distinct from 1352 fact unavailable',
      );
      expect(base.description.toLowerCase(), contains('attachment'));
      expect(
        base.description,
        isNot(const FactCopySourceUnavailableException().description),
        reason: 'says an attachment, not that the whole fact is gone',
      );
      expect(
        await rows(
          'SELECT id FROM public.beacon_fact_card WHERE beacon_id = @b',
          {'b': w.published},
        ),
        isEmpty,
      );
      expect(storage.objects.keys.toSet(), before, reason: 'no orphan blob');
    });

    final outages = <String, Exception Function()>{
      'a timeout': () => TimeoutException('storage timed out'),
      'a server error (InternalError)': () => s3CodeError('InternalError'),
      'a 503 response': () => MinioError('503 Service Unavailable'),
      'AccessDenied credentials': () => s3CodeError('AccessDenied'),
      'InvalidAccessKeyId credentials': () => s3CodeError('InvalidAccessKeyId'),
      'a network failure': () => const SocketException('unreachable'),
    };
    for (final MapEntry(key: name, value: make) in outages.entries) {
      test('a direct copy fails with the storage error itself on $name for '
          'the second file: no fact is inserted and the first copied file is '
          'removed', () async {
        final (w, _, second) = await twoFileWorld();
        final outage = make();
        storage.getErrors[second.storageKey] = outage;
        final before = storage.objects.keys.toSet();

        final error = await errorOf(
          () => case_.copy(
            sourceFactCardId: w.fact,
            destinationBeaconId: w.published,
            actorUserId: w.actor,
          ),
        );

        expect(error, same(outage));
        expect(
          await rows(
            'SELECT id FROM public.beacon_fact_card WHERE beacon_id = @b',
            {'b': w.published},
          ),
          isEmpty,
        );
        expect(storage.objects.keys.toSet(), before, reason: 'no orphan blob');
      });

      test('prepareCopies with skipUnavailable does not drop a file on '
          '$name: it fails and removes what it already copied', () async {
        final (w, _, second) = await twoFileWorld();
        final outage = make();
        storage.getErrors[second.storageKey] = outage;
        final before = storage.objects.keys.toSet();

        final error = await errorOf(
          () => case_.prepareCopies(
            sourceFactCardIds: [w.fact],
            actorUserId: w.actor,
            destinationBeaconId: w.published,
            skipUnavailable: true,
          ),
        );

        expect(error, same(outage));
        expect(storage.objects.keys.toSet(), before, reason: 'no orphan blob');
      });
    }
  });
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
