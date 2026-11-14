@Tags(['pg'])
library;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/domain/entity/fact_copy_outcome.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_fact_card_case.dart';
import 'package:tentura_server/domain/use_case/room_write_guard.dart';
import 'package:tentura_server/env.dart';

import '../../support/beacon_repository_ctor_arg.dart';
import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';

/// Copying facts to and from Posts, and listing Posts as copy destinations,
/// through `BeaconFactCardCase` over the real repositories and Postgres.

String _publicKey(int world, int slot) =>
    'fcpst${world}w${slot}s'.padRight(44, 'q');

final class _NoImages extends Fake implements ImageRepositoryPort {}

final class _Tasks extends Fake implements TaskRepositoryPort {
  @override
  Future<String> schedule(TaskEntity task) async => 'task';
}

/// One isolated set of users and beacons per test. The actor is an admitted
/// member of every published beacon except [foreignPost].
final class _World {
  _World(this.n);

  final int n;

  String _id(String prefix) => '$prefix${'cq$n'.padLeft(11, '0')}';

  String get author => _id('Ua');
  String get actor => _id('Uc');

  String get request => _id('Bq');
  String get request2 => _id('Br');
  String get post => _id('Bp');
  String get post2 => _id('Bo');
  String get expiredPost => _id('Be');
  String get closedPost => _id('Bc');
  String get foreignPost => _id('Bf');
  String get ownDraftRequest => _id('Bd');
  String get ownDraftPost => _id('Bn');
  String get otherDraftRequest => _id('Bg');
  String get otherDraftPost => _id('Bh');

  String root(String beaconId) => 'R${beaconId.substring(1)}';

  String get factInRequest => _id('Fq');
  String get factInPost => _id('Fp');
  String get factInExpired => _id('Fe');
  String get factInClosed => _id('Fc');
}

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FACT_COPY_POSTS_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_fact_copy_posts',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;
  late TenturaDb db;
  late BeaconFactCardCase case_;
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
    final room = BeaconRoomRepository(db);
    case_ = buildWithBeaconRepository<BeaconFactCardCase>(
      BeaconFactCardCase.new,
      positional: [
        BeaconFactCardRepository(db, room),
        room,
        _NoImages(),
        _Tasks(),
        BeaconHierarchyRepository(db),
        FakeBeaconAccessGuard(),
      ],
      named: {
        #env: Env(environment: Environment.test),
        #logger: Logger('BeaconFactCardCopyPostsPgTest'),
      },
      beaconRepository: BeaconRepository(db),
    );
  });

  tearDownAll(() => tearDownDisposablePgWriter(session: session, drift: db));

  Future<void> seedFact(
    _World w, {
    required String id,
    required String beaconId,
    required int visibility,
  }) async {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, status, revision_seq)
VALUES (@id, @beacon, @text, @vis, @author,
        ${BeaconFactCardStatusBits.active}, 1)
'''),
      parameters: {
        'id': id,
        'beacon': beaconId,
        'text': 'Fact $id',
        'vis': visibility,
        'author': w.author,
      },
    );
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_fact_card_revision
  (fact_card_id, seq, fact_text, actor_id, kind)
VALUES (@id, 1, @text, @author, ${BeaconFactCardRevisionKindBits.created})
'''),
      parameters: {'id': id, 'text': 'Fact $id', 'author': w.author},
    );
  }

  Future<_World> world() async {
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
VALUES (@request, @author, 'Request', 'd', 0, 0, now(), false),
       (@request2, @author, 'Request 2', 'd', 0, 0, now(), false),
       (@ownDraft, @actor, 'Own draft', 'd', 3, 0, NULL, false),
       (@otherDraft, @author, 'Other draft', 'd', 3, 0, NULL, false)
'''),
      parameters: {
        'request': w.request,
        'request2': w.request2,
        'ownDraft': w.ownDraftRequest,
        'otherDraft': w.otherDraftRequest,
        'author': w.author,
        'actor': w.actor,
      },
    );
    final posts = [
      (w.post, w.author, true),
      (w.post2, w.author, true),
      (w.expiredPost, w.author, true),
      (w.closedPost, w.author, true),
      (w.foreignPost, w.author, true),
      (w.ownDraftPost, w.actor, false),
      (w.otherDraftPost, w.author, false),
    ];
    for (final (id, owner, withRoot) in posts) {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at, expires_at)
VALUES (@id, @owner, '', '', 0, 1, 1, false, now(),
        now() + interval '24 hours')
'''),
        parameters: {'id': id, 'owner': owner},
      );
      if (!withRoot) continue;
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES (@root, @id, @owner, 'Root')
'''),
        parameters: {'root': w.root(id), 'id': id, 'owner': owner},
      );
      await writer.execute(
        Sql.named(
          'UPDATE public.beacon SET post_root_message_id = @root '
          'WHERE id = @id',
        ),
        parameters: {'root': w.root(id), 'id': id},
      );
    }
    final memberOf = [
      w.request,
      w.request2,
      w.post,
      w.post2,
      w.expiredPost,
      w.closedPost,
      w.otherDraftRequest,
      w.otherDraftPost,
    ];
    for (final (i, beaconId) in memberOf.indexed) {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES (@id, @beacon, @user, 0, 0, ${RoomAccessBits.admitted})
'''),
        parameters: {'id': 'Pcq${w.n}x$i', 'beacon': beaconId, 'user': w.actor},
      );
    }
    await seedFact(
      w,
      id: w.factInRequest,
      beaconId: w.request,
      visibility: BeaconFactCardVisibilityBits.public,
    );
    for (final (id, beaconId) in [
      (w.factInPost, w.post),
      (w.factInExpired, w.expiredPost),
      (w.factInClosed, w.closedPost),
    ]) {
      await seedFact(
        w,
        id: id,
        beaconId: beaconId,
        visibility: BeaconFactCardVisibilityBits.room,
      );
    }
    await writer.execute(
      Sql.named(
        "UPDATE public.beacon SET expires_at = now() - interval '1 hour' "
        'WHERE id = @id',
      ),
      parameters: {'id': w.expiredPost},
    );
    await writer.execute(
      Sql.named('UPDATE public.beacon SET status = @status WHERE id = @id'),
      parameters: {
        'id': w.closedPost,
        'status': BeaconStatus.closed.smallintValue,
      },
    );
    return w;
  }

  Future<List<Map<String, Object?>>> copiesIn(String beaconId, String origin) =>
      rows(
        '''
SELECT id, fact_text, visibility::integer AS visibility,
       origin_beacon_kind::integer AS origin_beacon_kind
FROM public.beacon_fact_card
WHERE beacon_id = @b AND origin_fact_card_id = @o
''',
        {'b': beaconId, 'o': origin},
      );

  Future<Map<String, Object?>> footprint(String beaconId) async => (await rows(
    '''
SELECT
  (SELECT count(*)::integer FROM public.beacon_fact_card
    WHERE beacon_id = @b) AS facts,
  (SELECT count(*)::integer FROM public.beacon_room_message
    WHERE beacon_id = @b) AS messages,
  (SELECT string_agg(id, ',' ORDER BY id) FROM public.beacon_room_message
    WHERE beacon_id = @b) AS message_ids,
  (SELECT count(*)::integer FROM public.beacon_activity_event
    WHERE beacon_id = @b) AS events,
  (SELECT status::integer FROM public.beacon WHERE id = @b) AS status,
  (SELECT expires_at FROM public.beacon WHERE id = @b) AS expires_at
''',
    {'b': beaconId},
  )).single;

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

  final isReadOnly = isA<BeaconCreateException>().having(
    (e) => e.description,
    'description',
    kRoomReadOnlyException.description,
  );

  group('Copying facts between Requests and Posts', () {
    // (label, source fact, destination, origin beacon kind of the copy)
    for (final (label, sourceFact, destination, kind) in [
      ('Request → Post', 'factInRequest', 'post', 0),
      ('Post → Request', 'factInPost', 'request2', 1),
      ('Post → Post', 'factInPost', 'post2', 1),
    ]) {
      test(
        '$label creates a discussion-only copy for a member of both',
        () async {
          final w = await world();
          final ids = {
            'request': w.request,
            'request2': w.request2,
            'post': w.post,
            'post2': w.post2,
            'factInRequest': w.factInRequest,
            'factInPost': w.factInPost,
          };
          final answer = await case_.copy(
            sourceFactCardId: ids[sourceFact]!,
            destinationBeaconId: ids[destination]!,
            actorUserId: w.actor,
          );
          expect(answer.outcome, FactCopyOutcome.created);
          final copies = await copiesIn(ids[destination]!, ids[sourceFact]!);
          expect(copies, hasLength(1));
          expect(copies.single['id'], answer.factCardId);
          expect(copies.single['fact_text'], 'Fact ${ids[sourceFact]}');
          expect(
            copies.single['visibility'],
            BeaconFactCardVisibilityBits.room,
          );
          expect(copies.single['origin_beacon_kind'], kind);
        },
      );
    }

    for (final state in ['expired', 'closed']) {
      test('a member copies a fact out of an $state Post and the Post keeps '
          'its status, expiry and messages', () async {
        final w = await world();
        final post = state == 'expired' ? w.expiredPost : w.closedPost;
        final fact = state == 'expired' ? w.factInExpired : w.factInClosed;
        final before = await footprint(post);
        final answer = await case_.copy(
          sourceFactCardId: fact,
          destinationBeaconId: w.request,
          actorUserId: w.actor,
        );
        expect(answer.outcome, FactCopyOutcome.created);
        expect(await copiesIn(w.request, fact), hasLength(1));
        expect(await footprint(post), before);
      });
    }
  });

  group('Copy destinations that are refused', () {
    test('another user\'s draft, Request or Post, is refused like a Post '
        'the caller is not a member of, and nothing is inserted', () async {
      final w = await world();
      final reference = await errorOf(
        () => case_.copy(
          sourceFactCardId: w.factInRequest,
          destinationBeaconId: w.foreignPost,
          actorUserId: w.actor,
        ),
      );
      expect(reference, isA<UnauthorizedException>());
      reference as UnauthorizedException;
      expect(reference.description, 'Room access required');

      for (final draft in [
        w.otherDraftRequest,
        w.otherDraftPost,
      ]) {
        final error = await errorOf(
          () => case_.copy(
            sourceFactCardId: w.factInRequest,
            destinationBeaconId: draft,
            actorUserId: w.actor,
          ),
        );
        expect(error, isA<UnauthorizedException>(), reason: draft);
        error as UnauthorizedException;
        expect(error.description, reference.description, reason: draft);
        expect(error.code.codeNumber, reference.code.codeNumber, reason: draft);
        expect(await copiesIn(draft, w.factInRequest), isEmpty, reason: draft);
      }
    });

    for (final state in ['expired', 'closed']) {
      test('an $state Post the caller is a member of throws the read-only '
          'exception and nothing is written there', () async {
        final w = await world();
        final post = state == 'expired' ? w.expiredPost : w.closedPost;
        final before = await footprint(post);
        expect(
          await errorOf(
            () => case_.copy(
              sourceFactCardId: w.factInRequest,
              destinationBeaconId: post,
              actorUserId: w.actor,
            ),
          ),
          isReadOnly,
        );
        expect(await footprint(post), before);
      });
    }
  });

  group('Copy destinations list', () {
    test('lists the open, unexpired Posts the caller belongs to, and no '
        'archived Post, other user\'s draft or foreign Post', () async {
      final w = await world();
      final listed = await case_.copyDestinations(
        sourceFactCardId: w.factInRequest,
        userId: w.actor,
      );
      final ids = [for (final r in listed) r['id']];
      expect(ids, containsAll([w.post, w.post2, w.request2]));
      for (final id in [
        w.expiredPost,
        w.closedPost,
        w.foreignPost,
        w.otherDraftRequest,
        w.otherDraftPost,
      ]) {
        expect(ids, isNot(contains(id)), reason: id);
      }
      final post = listed.firstWhere((r) => r['id'] == w.post);
      expect(post['kind'], 1);
      expect(post['isDraft'], isFalse);
    });
  });
}
