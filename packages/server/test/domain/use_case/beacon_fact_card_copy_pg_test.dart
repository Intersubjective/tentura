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

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_fact_card.dart';
import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/image_object_gc_repository.dart';
import 'package:tentura_server/data/repository/image_repository.dart';
import 'package:tentura_server/data/repository/upload_quota_repository.dart';
import 'package:tentura_server/domain/entity/fact_copy_source.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/prepared_fact_copy.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_fact_card_case.dart';
import 'package:tentura_server/domain/use_case/room_write_guard.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';

final _t0 = DateTime.utc(2026, 11, 1, 12);

/// A unique 44-character public key for user [slot] of world [world].
String _publicKey(int world, int slot) =>
    'fcopy${world}w${slot}s'.padRight(44, 'q');

final class _Storage extends Fake implements RemoteStoragePort {
  final objects = <String, Uint8List>{};
  int puts = 0;

  @override
  Future<Uint8List> getObject(String path) async =>
      objects[path] ?? (throw StateError('no object at $path'));

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

/// Records scheduled tasks and, for each hash task, whether a committed
/// fact revision already referenced that image when it was scheduled.
final class _Tasks extends Fake implements TaskRepositoryPort {
  _Tasks(this._committedReferences);

  final Future<bool> Function(String imageId) _committedReferences;

  final scheduled = <TaskEntity>[];
  final committedAtSchedule = <String, bool>{};
  Exception? failWith;

  List<String> get hashImageIds => [
    for (final t in scheduled)
      if (t.details case final TaskCalculateImageHashDetails d) d.imageId,
  ];

  @override
  Future<String> schedule(TaskEntity task) async {
    if (task.details case final TaskCalculateImageHashDetails d) {
      committedAtSchedule[d.imageId] = await _committedReferences(d.imageId);
    }
    if (failWith case final error?) throw error;
    scheduled.add(task);
    return 'task-${scheduled.length}';
  }
}

/// The real repository, counting source loads and letting a test act
/// between the destination check and the insert.
final class _Facts extends BeaconFactCardRepository {
  // The super constructor's field parameter is private (`_db`).
  // ignore: matching_super_parameters
  _Facts(super.db, super.room);

  int sourceLoads = 0;
  Future<void> Function()? beforeInsert;

  @override
  Future<List<FactCopySource>> loadCopySources({
    required List<String> factCardIds,
  }) {
    sourceLoads++;
    return super.loadCopySources(factCardIds: factCardIds);
  }

  @override
  Future<List<String>> insertPreparedCopies({
    required String destinationBeaconId,
    required String actorUserId,
    required List<PreparedFactCopy> prepared,
  }) async {
    final hook = beforeInsert;
    if (hook != null) await hook();
    return super.insertPreparedCopies(
      destinationBeaconId: destinationBeaconId,
      actorUserId: actorUserId,
      prepared: prepared,
    );
  }
}

/// One isolated world per test: fresh users, so rate windows never leak
/// between tests sharing the database.
final class _World {
  _World(this.n);

  final int n;

  String _id(String prefix) => '$prefix${'cp$n'.padLeft(11, '0')}';

  String get author => _id('Ua');
  String get actor => _id('Uc');
  String get peer => _id('Up');
  String get stranger => _id('Us');

  /// Source Request A and destination Request B; the actor is a member of
  /// both, the peer of B only.
  String get a => _id('Ba');
  String get b => _id('Bb');

  /// Request the actor is not a member of.
  String get foreign => _id('Bf');
  String get ownDraft => _id('Bd');
  String get ownPost => _id('Bp');
  String get closed => _id('Bx');
  String get deleted => _id('Bz');
  String get ballast => _id('Bl');
  String get missing => _id('Bm');

  String get fact => _id('Ff');

  /// An ordinary fact pinned in B, used for the edit rate limit.
  String get ordinaryInB => _id('Fo');
}

final class _CopyAnswer {
  const _CopyAnswer(this.factCardId, this.outcome);

  final String factCardId;
  final String outcome;
}

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FACT_COPY_MUTATION_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_fact_copy_mutation',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;
  late TenturaDb db;
  late _Facts facts;
  late ImageRepository images;
  late _Storage storage;
  late _Tasks tasks;
  late BeaconFactCardCase case_;
  late Env env;
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
    env = Env(environment: Environment.test);
  });

  /// Rebuilds the case under test with [config], e.g. a lower copy limit.
  void useEnv(Env config) {
    final room = BeaconRoomRepository(db);
    facts = _Facts(db, room);
    storage = _Storage();
    images = ImageRepository(
      db,
      storage,
      UploadQuotaRepository(db),
      ImageObjectGcRepository(db, storage),
      config,
      Logger('BeaconFactCardCopyPgTest.images'),
    );
    tasks = _Tasks(
      (imageId) async =>
          await count(
            'SELECT count(*)::integer AS n '
            'FROM public.beacon_fact_card_revision '
            "WHERE attachments_json::text LIKE '%' || @image || '%'",
            {'image': imageId},
          ) >
          0,
    );
    case_ = BeaconFactCardCase(
      facts,
      room,
      images,
      tasks,
      BeaconHierarchyRepository(db),
      FakeBeaconAccessGuard(),
      env: config,
      logger: Logger('BeaconFactCardCopyPgTest'),
    );
  }

  setUp(() => useEnv(env));

  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: db);
  });

  Future<_World> world({bool withImage = false}) async {
    final w = _World(++worlds);
    var k = 0;
    for (final user in [w.author, w.actor, w.peer, w.stranger]) {
      k++;
      await writer.execute(
        Sql.named(
          'INSERT INTO public."user" (id, display_name, public_key) '
          'VALUES (@id, @id, @key)',
        ),
        parameters: {
          'id': user,
          'key': _publicKey(w.n, k),
        },
      );
    }
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, published_at,
   is_discoverable)
VALUES (@a, @author, 'Source', 'd', 0, 0, @t0, false),
       (@b, @author, 'Destination', 'd', 0, 0, @t0, false),
       (@foreign, @author, 'Foreign', 'd', 0, 0, @t0, false),
       (@closed, @author, 'Closed', 'd', 0, 0, @t0, false),
       (@deleted, @actor, 'Deleted', 'd', 0, 0, @t0, false),
       (@ballast, @author, 'Ballast', 'd', 0, 0, @t0, false),
       (@draft, @actor, 'Own draft', 'd', 3, 0, NULL, false)
'''),
      parameters: {
        'a': w.a,
        'b': w.b,
        'foreign': w.foreign,
        'closed': w.closed,
        'deleted': w.deleted,
        'ballast': w.ballast,
        'draft': w.ownDraft,
        'author': w.author,
        'actor': w.actor,
        't0': _t0,
      },
    );
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at, expires_at)
VALUES (@post, @actor, '', '', 0, 1, 1, false, now(),
        now() + interval '24 hours')
'''),
      parameters: {'post': w.ownPost, 'actor': w.actor},
    );
    final members = [
      (w.a, w.actor),
      (w.b, w.actor),
      (w.b, w.peer),
      (w.closed, w.actor),
      (w.deleted, w.actor),
    ];
    for (final (i, (beaconId, userId)) in members.indexed) {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES (@id, @beacon, @user, 0, 0, 3)
'''),
        parameters: {
          'id': 'Pfc${w.n}x$i',
          'beacon': beaconId,
          'user': userId,
        },
      );
    }
    await writer.execute(
      Sql.named(
        'UPDATE public.beacon SET status = @closedStatus WHERE id = @closed',
      ),
      parameters: {'closed': w.closed, 'closedStatus': 1},
    );
    await writer.execute(
      Sql.named('UPDATE public.beacon SET status = 2 WHERE id = @deleted'),
      parameters: {'deleted': w.deleted},
    );

    var attachments = const <Map<String, Object?>>[];
    if (withImage) {
      final imageId = await images.put(
        authorId: w.author,
        bytes: Stream.value(Uint8List.fromList([137, 80, 78, 71, w.n])),
      );
      attachments = [
        {
          'id': 'Asrc${'${w.n}'.padLeft(8, '0')}',
          'kind': BeaconRoomMessageAttachmentKind.image,
          'position': 0,
          'mime': 'image/png',
          'sizeBytes': 5,
          'fileName': 'source.png',
          'imageId': imageId,
          'imageAuthorId': w.author,
          'blurHash': '',
          'width': 2,
          'height': 3,
        },
      ];
    }
    await _seedFact(
      writer,
      id: w.fact,
      beaconId: w.a,
      author: w.author,
      headSeq: 3,
      headText: 'Head text of the source fact ${w.n}',
      headAttachments: attachments,
    );
    await _seedFact(
      writer,
      id: w.ordinaryInB,
      beaconId: w.b,
      author: w.author,
      headSeq: 1,
      headText: 'An ordinary fact in B',
      headAttachments: const [],
    );
    return w;
  }

  /// Seeds [n] copy revisions (kind 4) by [userId], [age] ago.
  Future<void> seedCopyRevisions(
    _World w, {
    required String userId,
    required int n,
    int kind = BeaconFactCardRevisionKindBits.copied,
    Duration age = Duration.zero,
    String tag = 'r',
  }) async {
    final id = 'F$tag${'${w.n}'.padLeft(10, '0')}';
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, status, created_at,
   updated_at, revision_seq)
VALUES (@id, @beacon, 'Ballast', 1, @user, 0, now(), now(), @n)
'''),
      parameters: {'id': id, 'beacon': w.ballast, 'user': userId, 'n': n},
    );
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_fact_card_revision
  (fact_card_id, seq, fact_text, actor_id, kind, created_at, attachments_json)
SELECT @id, s, 'Ballast', @user, @kind,
       now() - make_interval(secs => @age), '[]'::jsonb
FROM generate_series(1, @n) AS s
'''),
      parameters: {
        'id': id,
        'user': userId,
        'kind': kind,
        'age': age.inSeconds.toDouble(),
        'n': n,
      },
    );
  }

  Future<_CopyAnswer> copy(
    String source,
    String destination, {
    required String actor,
  }) async {
    final fields = MutationFactCard(
      beaconFactCardCase: case_,
    ).all.where((f) => f.name == 'BeaconFactCardCopy').toList();
    expect(
      fields,
      hasLength(1),
      reason: 'the V2 mutation BeaconFactCardCopy must exist',
    );
    final field = fields.single;
    final raw = await field.resolve!(null, {
      kGlobalInputQueryJwt: JwtEntity(sub: actor),
      'sourceFactCardId': source,
      'destinationBeaconId': destination,
    });
    final json = raw is Map
        ? Map<String, Object?>.from(raw)
        : Map<String, Object?>.from(field.type.serialize(raw) as Map);
    final outcome = json['outcome'];
    return _CopyAnswer(
      json['factCardId']! as String,
      outcome is Enum ? outcome.name : '$outcome',
    );
  }

  Future<List<Map<String, Object?>>> copiesIn(String beaconId, String origin) =>
      rows(
        '''
SELECT id, fact_text, visibility::integer AS visibility, pinned_by,
       status::integer AS status, revision_seq, origin_fact_card_id,
       origin_revision_seq, origin_beacon_kind::integer AS origin_beacon_kind
FROM public.beacon_fact_card
WHERE beacon_id = @b AND origin_fact_card_id = @o
ORDER BY created_at, id
''',
        {'b': beaconId, 'o': origin},
      );

  Future<List<Map<String, Object?>>> revisionsOf(String factId) => rows(
    '''
SELECT seq, kind::integer AS kind, actor_id, fact_text,
       attachments_json::text AS attachments
FROM public.beacon_fact_card_revision
WHERE fact_card_id = @f
ORDER BY seq
''',
    {'f': factId},
  );

  Future<int> imagesOwnedBy(String userId) => count(
    'SELECT count(*)::integer AS n FROM public.image WHERE author_id = @u',
    {'u': userId},
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
    fail('expected the copy to be refused');
  }

  // kRoomReadOnlyException is a const BeaconCreateException
  // (domain/use_case/room_write_guard.dart); match its type, code and text.
  final isReadOnly = isA<BeaconCreateException>()
      .having(
        (e) => e.code.codeNumber,
        'code',
        kRoomReadOnlyException.code.codeNumber,
      )
      .having(
        (e) => e.description,
        'description',
        kRoomReadOnlyException.description,
      );

  group('Copying a fact into a published Request', () {
    test('a member of both Requests gets a new fact holding the source head '
        'text, origin and a single «copied» revision', () async {
      final w = await world();
      final answer = await copy(w.fact, w.b, actor: w.actor);
      expect(answer.outcome, 'created');
      expect(answer.factCardId, isNot(w.fact));

      final copies = await copiesIn(w.b, w.fact);
      expect(copies, hasLength(1));
      final row = copies.single;
      expect(row['id'], answer.factCardId);
      expect(row['fact_text'], 'Head text of the source fact ${w.n}');
      expect(row['visibility'], BeaconFactCardVisibilityBits.room);
      expect(row['pinned_by'], w.actor);
      expect(row['origin_revision_seq'], 3);
      expect(row['origin_beacon_kind'], 0);

      final revisions = await revisionsOf(answer.factCardId);
      expect(revisions, hasLength(1));
      expect(revisions.single['seq'], 1);
      expect(
        revisions.single['kind'],
        BeaconFactCardRevisionKindBits.copied,
      );
      expect(revisions.single['actor_id'], w.actor);
    });

    test('a second call answers alreadyThere with the same id and stores no '
        'extra image', () async {
      final w = await world(withImage: true);
      final first = await copy(w.fact, w.b, actor: w.actor);
      final putsAfterFirst = storage.puts;
      final second = await copy(w.fact, w.b, actor: w.actor);

      expect(first.outcome, 'created');
      expect(second.outcome, 'alreadyThere');
      expect(second.factCardId, first.factCardId);
      expect(storage.puts, putsAfterFirst);
      expect(await imagesOwnedBy(w.actor), 1);
      expect(await copiesIn(w.b, w.fact), hasLength(1));
    });

    test('two concurrent calls make one copy: one created, one alreadyThere '
        'with the same id, and only one image kept', () async {
      final w = await world(withImage: true);
      final answers = await Future.wait([
        copy(w.fact, w.b, actor: w.actor),
        copy(w.fact, w.b, actor: w.actor),
      ]);

      expect(
        answers.map((a) => a.outcome).toList()..sort(),
        ['alreadyThere', 'created'],
      );
      expect(answers.first.factCardId, answers.last.factCardId);
      expect(await copiesIn(w.b, w.fact), hasLength(1));
      // The loser may have stored a blob before it saw the winner; that blob
      // must be compensated, so the copier owns exactly the copy's image.
      final copyImages = imageIdsIn(
        (await revisionsOf(answers.first.factCardId)).single['attachments']!
            as String,
      );
      final owned = await rows(
        'SELECT id::text AS id FROM public.image WHERE author_id = @u',
        {'u': w.actor},
      );
      expect([for (final r in owned) r['id']], copyImages);
    });

    test('after the copy is removed the fact can be copied again', () async {
      final w = await world();
      final first = await copy(w.fact, w.b, actor: w.actor);
      await case_.remove(
        factCardId: first.factCardId,
        beaconId: w.b,
        actorUserId: w.actor,
      );
      final again = await copy(w.fact, w.b, actor: w.actor);

      expect(again.outcome, 'created');
      expect(again.factCardId, isNot(first.factCardId));
    });

    test('another member of the destination can edit the copy', () async {
      final w = await world();
      final answer = await copy(w.fact, w.b, actor: w.actor);
      final seq = await case_.correct(
        factCardId: answer.factCardId,
        beaconId: w.b,
        actorUserId: w.peer,
        newText: 'Corrected by another member',
        baseRevisionSeq: 1,
      );

      expect(seq, 2);
      final row = (await copiesIn(w.b, w.fact)).single;
      expect(row['fact_text'], 'Corrected by another member');
    });

    test('editing or removing the source afterwards leaves the copy text, '
        'revision and images unchanged', () async {
      final w = await world(withImage: true);
      final answer = await copy(w.fact, w.b, actor: w.actor);
      final before = (await copiesIn(w.b, w.fact)).single;
      final revisionsBefore = await revisionsOf(answer.factCardId);
      final copiedImages = imageIdsIn(
        revisionsBefore.single['attachments']! as String,
      );
      expect(copiedImages, hasLength(1));

      await case_.correct(
        factCardId: w.fact,
        beaconId: w.a,
        actorUserId: w.actor,
        newText: 'The source changed its mind',
        baseRevisionSeq: 3,
        attachmentsJson: '[]',
      );
      await case_.remove(
        factCardId: w.fact,
        beaconId: w.a,
        actorUserId: w.actor,
      );

      final after = (await copiesIn(w.b, w.fact)).single;
      expect(after['fact_text'], before['fact_text']);
      expect(after['revision_seq'], before['revision_seq']);
      expect(await revisionsOf(answer.factCardId), revisionsBefore);
      expect(
        await count(
          'SELECT count(*)::integer AS n FROM public.image '
          'WHERE id::text = @id',
          {'id': copiedImages.single},
        ),
        1,
      );
    });
  });

  group('Copy destinations that are refused', () {
    test('not found, not a member, own draft, Post and deleted destinations '
        'throw the same UnauthorizedException without loading the source', () async {
      final w = await world(withImage: true);
      // world() stored the source image.
      final seededPuts = storage.puts;
      final errors = <String, Object>{
        'not found': await errorOf(() => copy(w.fact, w.missing, actor: w.actor)),
        'not a member': await errorOf(
          () => copy(w.fact, w.foreign, actor: w.actor),
        ),
        'own draft': await errorOf(
          () => copy(w.fact, w.ownDraft, actor: w.actor),
        ),
        'Post': await errorOf(() => copy(w.fact, w.ownPost, actor: w.actor)),
        'deleted': await errorOf(() => copy(w.fact, w.deleted, actor: w.actor)),
      };

      final reference = errors['not found']!;
      expect(reference, isA<UnauthorizedException>());
      for (final MapEntry(:key, :value) in errors.entries) {
        expect(value, isA<UnauthorizedException>(), reason: key);
        value as UnauthorizedException;
        expect(
          value.description,
          (reference as UnauthorizedException).description,
          reason: key,
        );
        expect(value.code.codeNumber, reference.code.codeNumber, reason: key);
      }
      expect(facts.sourceLoads, 0, reason: 'the source is never loaded');
      expect(storage.puts, seededPuts, reason: 'no blob stored');
      expect(await imagesOwnedBy(w.actor), 0);
    });

    test('a read-only Request where the actor is a member throws the room '
        'read-only exception', () async {
      final w = await world();
      expect(
        await errorOf(() => copy(w.fact, w.closed, actor: w.actor)),
        isReadOnly,
      );
      expect(facts.sourceLoads, 0);
    });

    test('a destination that closes between check and insert yields the '
        'read-only exception and no orphaned image', () async {
      final w = await world(withImage: true);
      facts.beforeInsert = () async {
        await writer.execute(
          Sql.named('UPDATE public.beacon SET status = 1 WHERE id = @b'),
          parameters: {'b': w.b},
        );
      };

      expect(
        await errorOf(() => copy(w.fact, w.b, actor: w.actor)),
        isReadOnly,
      );
      expect(await copiesIn(w.b, w.fact), isEmpty);
      expect(await imagesOwnedBy(w.actor), 0, reason: 'blob compensated');
      expect(tasks.hashImageIds, isEmpty);
    });

    // Plan §5.8: a destination deleted between check and insert answers
    // UnauthorizedException, the same as a missing destination.
    test('a destination deleted between check and insert throws '
        'UnauthorizedException and leaves no orphaned image', () async {
      final w = await world(withImage: true);
      facts.beforeInsert = () async {
        await writer.execute(
          Sql.named('UPDATE public.beacon SET status = 2 WHERE id = @b'),
          parameters: {'b': w.b},
        );
      };

      expect(
        await errorOf(() => copy(w.fact, w.b, actor: w.actor)),
        isA<UnauthorizedException>(),
      );
      expect(await imagesOwnedBy(w.actor), 0);
    });
  });

  group('Copy rate limit (FACT_COPY_RATE_MAX copies per edit window)', () {
    test('an actor at the limit is rate-limited before any image work',
        () async {
      final w = await world(withImage: true);
      await seedCopyRevisions(w, userId: w.actor, n: 60);
      // world() stored the source image.
      final seededPuts = storage.puts;

      expect(
        await errorOf(() => copy(w.fact, w.b, actor: w.actor)),
        isA<BeaconFactCardRateLimitedException>(),
      );
      expect(facts.sourceLoads, 0);
      expect(storage.puts, seededPuts, reason: 'no blob stored');
      expect(await imagesOwnedBy(w.actor), 0);
    });

    test('FACT_COPY_RATE_MAX sets the limit: with 2, two copies in the window '
        'refuse a third', () async {
      useEnv(Env(environment: Environment.test, factCopyRateMax: 2));
      final w = await world();
      await seedCopyRevisions(w, userId: w.actor, n: 2);
      expect(
        await errorOf(() => copy(w.fact, w.b, actor: w.actor)),
        isA<BeaconFactCardRateLimitedException>(),
      );
    });

    test('pins and edits do not count toward the copy limit', () async {
      useEnv(Env(environment: Environment.test, factCopyRateMax: 2));
      final w = await world();
      await seedCopyRevisions(
        w,
        userId: w.actor,
        n: 3,
        kind: BeaconFactCardRevisionKindBits.created,
        tag: 'p',
      );
      await seedCopyRevisions(
        w,
        userId: w.actor,
        n: 2,
        kind: BeaconFactCardRevisionKindBits.edited,
        tag: 'e',
      );
      expect((await copy(w.fact, w.b, actor: w.actor)).outcome, 'created');
    });

    test('copies older than the window do not count', () async {
      final w = await world();
      await seedCopyRevisions(
        w,
        userId: w.actor,
        n: 60,
        age: env.factEditRateWindow + const Duration(minutes: 1),
      );
      expect((await copy(w.fact, w.b, actor: w.actor)).outcome, 'created');
    });

    test("another user's copies do not count", () async {
      final w = await world();
      await seedCopyRevisions(w, userId: w.peer, n: 60);
      expect((await copy(w.fact, w.b, actor: w.actor)).outcome, 'created');
    });

    test('the destination is checked before the rate limit', () async {
      final w = await world();
      await seedCopyRevisions(w, userId: w.actor, n: 60);
      expect(
        await errorOf(() => copy(w.fact, w.foreign, actor: w.actor)),
        isA<UnauthorizedException>(),
      );
    });

    test('twenty copies inside the window do not rate-limit a following fact '
        'edit', () async {
      final w = await world();
      // Twenty copies reach the edit limit, so counting them would refuse
      // the edit.
      expect(env.factEditRateMax, lessThanOrEqualTo(20));
      await seedCopyRevisions(w, userId: w.actor, n: 20);
      final seq = await case_.correct(
        factCardId: w.ordinaryInB,
        beaconId: w.b,
        actorUserId: w.actor,
        newText: 'Edited after many copies',
        baseRevisionSeq: 1,
      );
      expect(seq, 2);
    });
  });

  group('Image hash tasks for copied images', () {
    test('a created copy schedules one hash task for its new image after the '
        'commit', () async {
      final w = await world(withImage: true);
      final sourceImage = imageIdsIn(
        (await revisionsOf(w.fact)).last['attachments']! as String,
      ).single;
      final answer = await copy(w.fact, w.b, actor: w.actor);
      final newImage = imageIdsIn(
        (await revisionsOf(answer.factCardId)).single['attachments']! as String,
      ).single;

      expect(newImage, isNot(sourceImage));
      expect(tasks.hashImageIds, [newImage]);
      expect(
        tasks.committedAtSchedule[newImage],
        isTrue,
        reason: 'scheduled only after the copy was committed',
      );
    });

    test('an alreadyThere answer schedules no hash task', () async {
      final w = await world(withImage: true);
      await copy(w.fact, w.b, actor: w.actor);
      tasks.scheduled.clear();
      final second = await copy(w.fact, w.b, actor: w.actor);
      expect(second.outcome, 'alreadyThere');
      expect(tasks.hashImageIds, isEmpty);
    });

    test('a failing hash schedule does not fail the copy', () async {
      final w = await world(withImage: true);
      tasks.failWith = Exception('task queue down');
      final answer = await copy(w.fact, w.b, actor: w.actor);

      expect(answer.outcome, 'created');
      expect(await copiesIn(w.b, w.fact), hasLength(1));
      expect(await imagesOwnedBy(w.actor), 1);
    });
  });
}

Future<void> _seedFact(
  Connection writer, {
  required String id,
  required String beaconId,
  required String author,
  required int headSeq,
  required String headText,
  required List<Map<String, Object?>> headAttachments,
}) async {
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, status, created_at,
   updated_at, revision_seq)
VALUES (@id, @beacon, @text, ${BeaconFactCardVisibilityBits.public}, @author,
        ${BeaconFactCardStatusBits.active}, @at, @at, @head)
'''),
    parameters: {
      'id': id,
      'beacon': beaconId,
      'text': headText,
      'author': author,
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
        'author': author,
        'kind': seq == 1
            ? BeaconFactCardRevisionKindBits.created
            : BeaconFactCardRevisionKindBits.edited,
        'at': _t0,
        'att': jsonEncode(seq == headSeq ? headAttachments : const []),
      },
    );
  }
}
