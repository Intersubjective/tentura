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

import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/image_object_gc_repository.dart';
import 'package:tentura_server/data/repository/image_repository.dart';
import 'package:tentura_server/data/repository/upload_quota_repository.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_fact_card_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'Uprepsrcau01';
const _actor = 'Uprepsrcac01';
const _beacon = 'Bprepsrcreq1';
const _post = 'Bprepsrcpst1';
const _destination = 'Bprepsrcdst1';

const _factTwoImages = 'Fprepsrctwo1';
const _factPost = 'Fprepsrcpst1';
const _factCopy = 'Fprepsrccpy1';

const _keptImage = '1b0c2d3e-4f50-4617-8a9b-0c1d2e3f4a51';
const _goneImage = '1b0c2d3e-4f50-4617-8a9b-0c1d2e3f4a52';

final _t0 = DateTime.utc(2026, 11, 1, 12);

Map<String, Object?> _imageEntry({
  required String id,
  required String imageId,
  required int position,
}) => {
  'id': id,
  'kind': BeaconRoomMessageAttachmentKind.image,
  'position': position,
  'mime': 'image/png',
  'sizeBytes': 4,
  'fileName': '$id.png',
  'imageId': imageId,
  'imageAuthorId': _author,
  'blurHash': '',
  'width': 2,
  'height': 3,
};

final class _Storage extends Fake implements RemoteStoragePort {
  final objects = <String, Uint8List>{};

  @override
  Future<Uint8List> getObject(String path) async =>
      objects[path] ?? (throw StateError('no object at $path'));

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
  final scheduled = <TaskEntity>[];

  @override
  Future<String> schedule(TaskEntity task) async {
    scheduled.add(task);
    return 'task';
  }
}

/// Records every statement the repository sends through drift.
final class _StatementCounter extends QueryInterceptor {
  final selects = <String>[];

  /// Data-changing statements (INSERT, UPDATE, DELETE).
  final writes = <String>[];

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    selects.add(statement);
    return executor.runSelect(statement, args);
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    writes.add(statement);
    return executor.runInsert(statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    writes.add(statement);
    return executor.runUpdate(statement, args);
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    writes.add(statement);
    return executor.runDelete(statement, args);
  }
}

final class _UnusedHierarchy extends Fake
    implements BeaconHierarchyRepositoryPort {}

/// Copying a fact first loads it from the database with what the copy needs
/// (its episode, head revision, and whether each attached image still
/// exists), then re-stores its images as new blobs owned by the copier,
/// leaving the source image untouched.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FACT_PREPARE_COPIES_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_fact_prepare_copies',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;
  late TenturaDb db;
  late BeaconFactCardRepository repository;
  late ImageRepository images;
  late _Storage storage;
  late _Tasks tasks;
  late BeaconFactCardCase case_;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    await _seedEpisodes(writer);
    db = TenturaDb.forTest(
      database: PgDatabase.opened(
        Pool<dynamic>.withEndpoints(
          [target.databaseEnv.pgEndpoint],
          settings: target.databaseEnv.pgPoolSettings,
        ),
        enableMigrations: false,
      ),
    );
    final env = Env(environment: Environment.test);
    final room = BeaconRoomRepository(db);
    repository = BeaconFactCardRepository(db, room);
    storage = _Storage();
    images = ImageRepository(
      db,
      storage,
      UploadQuotaRepository(db),
      ImageObjectGcRepository(db, storage),
      env,
      Logger('BeaconFactCardPrepareCopiesPgTest.images'),
    );
    tasks = _Tasks();
    case_ = BeaconFactCardCase(
      repository,
      room,
      images,
      tasks,
      _UnusedHierarchy(),
      FakeBeaconAccessGuard(),
      env: env,
      logger: Logger('BeaconFactCardPrepareCopiesPgTest'),
    );
  });

  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: db);
  });

  Future<List<Map<String, Object?>>> rows(
    String sql, [
    Map<String, Object?> parameters = const {},
  ]) async {
    final result = await writer.execute(Sql.named(sql), parameters: parameters);
    return [for (final r in result) r.toColumnMap()];
  }

  group('Loading a fact as a copy source', () {
    test('returns its episode, head revision, and per attachment whether the '
        'image row still exists', () async {
      await writer.execute(
        Sql.named(
          'INSERT INTO public.image (id, author_id) VALUES '
          '(@kept, @author), (@gone, @author)',
        ),
        parameters: {
          'kept': _keptImage,
          'gone': _goneImage,
          'author': _author,
        },
      );
      await _seedFact(
        writer,
        id: _factTwoImages,
        beaconId: _beacon,
        visibility: BeaconFactCardVisibilityBits.room,
        headSeq: 2,
        headText: 'Head text two',
        headAttachments: [
          _imageEntry(id: 'Aprepkept01', imageId: _keptImage, position: 0),
          _imageEntry(id: 'Aprepgone01', imageId: _goneImage, position: 1),
        ],
      );
      await writer.execute(
        Sql.named('DELETE FROM public.image WHERE id = @gone'),
        parameters: {'gone': _goneImage},
      );
      await _seedFact(
        writer,
        id: _factPost,
        beaconId: _post,
        visibility: BeaconFactCardVisibilityBits.room,
        headSeq: 1,
        headText: 'Post head',
        headAttachments: const [],
      );

      final statements = _StatementCounter();
      final sources = await db.runWithInterceptor(
        () => repository.loadCopySources(
          factCardIds: [_factTwoImages, _factPost, 'Fprepmissin1'],
        ),
        interceptor: statements,
      );
      expect(
        statements.selects,
        hasLength(1),
        reason: 'the copy source is loaded in one SELECT',
      );
      expect(
        statements.writes,
        isEmpty,
        reason: 'loading a copy source changes nothing',
      );
      final byId = {for (final s in sources) s.factCardId: s};
      expect(byId.keys, unorderedEquals([_factTwoImages, _factPost]));

      final two = byId[_factTwoImages]!;
      expect(two.beaconId, _beacon);
      expect(two.beaconKind, 0);
      expect(two.status, BeaconFactCardStatusBits.active);
      expect(two.visibility, BeaconFactCardVisibilityBits.room);
      expect(two.headRevisionSeq, 2);
      expect(two.headText, 'Head text two');
      expect(
        [for (final a in two.attachments) (a.fields['imageId'], a.imageExists)],
        [(_keptImage, true), (_goneImage, false)],
      );
      expect(two.attachments.first.fields['fileName'], 'Aprepkept01.png');

      final post = byId[_factPost]!;
      expect(post.beaconId, _post);
      expect(post.beaconKind, 1);
      expect(post.headRevisionSeq, 1);
      expect(post.headText, 'Post head');
      expect(post.attachments, isEmpty);
    });
  });

  group('Preparing a copy on real storage', () {
    test('re-stores the image as a new row authored by the actor and leaves '
        'the source image unchanged', () async {
      final png = Uint8List.fromList([137, 80, 78, 71]);
      final sourceImage = await images.put(
        authorId: _author,
        bytes: Stream.value(png),
      );
      await _seedFact(
        writer,
        id: _factCopy,
        beaconId: _beacon,
        visibility: BeaconFactCardVisibilityBits.public,
        headSeq: 1,
        headText: 'Fact with a photo',
        headAttachments: [
          _imageEntry(id: 'Aprepcopy01', imageId: sourceImage, position: 0),
        ],
      );
      final before = await rows(
        'SELECT id::text AS id, author_id FROM public.image WHERE id = @id::uuid',
        {'id': sourceImage},
      );

      final result = await case_.prepareCopies(
        sourceFactCardIds: [_factCopy],
        actorUserId: _actor,
        destinationBeaconId: _destination,
        skipUnavailable: false,
      );

      final copy = result.prepared.single;
      expect(copy.originFactCardId, _factCopy);
      expect(copy.factText, 'Fact with a photo');
      final newImage = copy.newImageIds.single;
      expect(newImage, isNot(sourceImage));
      final attachment =
          (jsonDecode(copy.attachmentsJson) as List<Object?>).single!
              as Map<String, Object?>;
      expect(attachment['imageId'], newImage);
      expect(attachment['imageAuthorId'], _actor);

      final created = await rows(
        'SELECT author_id FROM public.image WHERE id = @id::uuid',
        {'id': newImage},
      );
      expect(created.single['author_id'], _actor);
      final after = await rows(
        'SELECT id::text AS id, author_id FROM public.image WHERE id = @id::uuid',
        {'id': sourceImage},
      );
      expect(after, before);
      expect(after.single['author_id'], _author);
      expect(tasks.scheduled, isEmpty);
    });
  });
}

Future<void> _seedEpisodes(Connection writer) async {
  var n = 0;
  for (final id in [_author, _actor]) {
    n++;
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': id, 'key': pgTestPublicKey('factprepsrc', n)},
    );
  }
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, published_at,
   is_discoverable)
VALUES (@beacon, @author, 'Source', 'd', 0, 0, @t0, false),
       (@destination, @actor, 'Destination', 'd', 0, 0, @t0, false)
'''),
    parameters: {
      'beacon': _beacon,
      'destination': _destination,
      'author': _author,
      'actor': _actor,
      't0': _t0,
    },
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at, expires_at)
VALUES (@post, @author, '', '', 0, 1, 1, false, now(),
        now() + interval '24 hours')
'''),
    parameters: {'post': _post, 'author': _author},
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_steward (beacon_id, user_id)
VALUES (@beacon, @actor)
'''),
    parameters: {'beacon': _beacon, 'actor': _actor},
  );
}

Future<void> _seedFact(
  Connection writer, {
  required String id,
  required String beaconId,
  required int visibility,
  required int headSeq,
  required String headText,
  required List<Map<String, Object?>> headAttachments,
}) async {
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, status, created_at,
   updated_at, revision_seq)
VALUES (@id, @beacon, @text, @visibility, @author,
        ${BeaconFactCardStatusBits.active}, @at, @at, @head)
'''),
    parameters: {
      'id': id,
      'beacon': beaconId,
      'text': headText,
      'visibility': visibility,
      'author': _author,
      'at': _t0,
      'head': headSeq,
    },
  );
  for (var seq = 1; seq <= headSeq; seq++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_fact_card_revision
  (fact_card_id, seq, fact_text, actor_id, kind, created_at, attachments_json)
VALUES (@id, @seq, @text, @author, @kind, @at, @att::jsonb)
'''),
      parameters: {
        'id': id,
        'seq': seq,
        'text': seq == headSeq ? headText : 'Earlier $seq',
        'author': _author,
        'kind': seq == 1
            ? BeaconFactCardRevisionKindBits.created
            : BeaconFactCardRevisionKindBits.edited,
        'at': _t0,
        'att': jsonEncode(seq == headSeq ? headAttachments : const []),
      },
    );
  }
}
