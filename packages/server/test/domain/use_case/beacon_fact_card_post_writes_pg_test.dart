@Tags(['pg'])
library;

import 'dart:convert';

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
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_fact_card_case.dart';
import 'package:tentura_server/domain/use_case/room_write_guard.dart';
import 'package:tentura_server/env.dart';

import '../../support/beacon_not_request_matcher.dart';
import '../../support/beacon_repository_ctor_arg.dart';
import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';

/// Fact writes on Posts and on drafts, through `BeaconFactCardCase` over the
/// real repositories and a real Postgres, built the way DI builds it.
///
/// Posts: an admitted member pins (always discussion-only), edits, restores
/// and removes facts; a blocked member and a leaver are refused; an expired
/// or closed Post is read-only; a Post has no «Make public / private».
/// Drafts: pin, edit, restore, visibility and upload are refused; the author
/// removing a fact deletes it without a chat line or event.

String _publicKey(int world, int slot) =>
    'fpost${world}w${slot}s'.padRight(44, 'q');

final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52,
]);

final class _Images extends Fake implements ImageRepositoryPort {
  final puts = <String>[];

  @override
  Future<String> put({
    required String authorId,
    required Stream<Uint8List> bytes,
  }) async {
    await bytes.drain<void>();
    puts.add(authorId);
    return '00000000-0000-4000-8000-${'${puts.length}'.padLeft(12, '0')}';
  }
}

final class _Tasks extends Fake implements TaskRepositoryPort {
  final scheduled = <TaskEntity>[];

  @override
  Future<String> schedule(TaskEntity task) async {
    scheduled.add(task);
    return 'task-${scheduled.length}';
  }
}

/// One isolated set of users and beacons per test.
final class _World {
  _World(this.n);

  final int n;

  String _id(String prefix) => '$prefix${'pw$n'.padLeft(11, '0')}';

  String get author => _id('Ua');
  String get member => _id('Um');
  String get blocked => _id('Ub');
  String get leaver => _id('Ul');
  String get stranger => _id('Us');

  /// Open, unexpired, published Post with a root message.
  String get post => _id('Bp');
  String get postRoot => _id('Rp');

  /// Published Post whose expiry passed (status still open).
  String get expiredPost => _id('Be');
  String get expiredRoot => _id('Re');

  /// Published Post that was closed.
  String get closedPost => _id('Bc');
  String get closedRoot => _id('Rc');

  /// Open Post without a root message: a draft Post.
  String get rootlessPost => _id('Bn');

  String get request => _id('Bq');
  String get draftRequest => _id('Bd');

  String get factInPost => _id('Fp');
  String get factInExpired => _id('Fe');
  String get factInClosed => _id('Fc');
  String get factInRootless => _id('Fn');
  String get factInRequest => _id('Fq');
  String get factInDraft => _id('Fd');
}

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FACT_POST_WRITES_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_fact_post_writes',
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
  late _Images images;
  late _Tasks tasks;
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
    images = _Images();
    tasks = _Tasks();
    // Built as DI builds it, with the beacon repository when the
    // constructor still takes one.
    case_ = buildWithBeaconRepository<BeaconFactCardCase>(
      BeaconFactCardCase.new,
      positional: [
        BeaconFactCardRepository(db, room),
        room,
        images,
        tasks,
        BeaconHierarchyRepository(db),
        FakeBeaconAccessGuard(),
      ],
      named: {
        #env: Env(environment: Environment.test),
        #logger: Logger('BeaconFactCardPostWritesPgTest'),
      },
      beaconRepository: BeaconRepository(db),
    );
  });

  tearDownAll(() => tearDownDisposablePgWriter(session: session, drift: db));

  Future<void> seedFact(
    _World w, {
    required String id,
    required String beaconId,
    int visibility = BeaconFactCardVisibilityBits.room,
  }) async {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, status, revision_seq)
VALUES (@id, @beacon, 'Head', @vis, @author,
        ${BeaconFactCardStatusBits.active}, 2)
'''),
      parameters: {
        'id': id,
        'beacon': beaconId,
        'vis': visibility,
        'author': w.author,
      },
    );
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_fact_card_revision
  (fact_card_id, seq, fact_text, actor_id, kind)
VALUES (@id, 1, 'Earlier', @author, ${BeaconFactCardRevisionKindBits.created}),
       (@id, 2, 'Head', @author, ${BeaconFactCardRevisionKindBits.edited})
'''),
      parameters: {'id': id, 'author': w.author},
    );
  }

  Future<_World> world() async {
    final w = _World(++worlds);
    for (final (i, user) in [
      w.author,
      w.member,
      w.blocked,
      w.leaver,
      w.stranger,
    ].indexed) {
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
       (@draft, @author, 'Draft', 'd', 3, 0, NULL, false)
'''),
      parameters: {
        'request': w.request,
        'draft': w.draftRequest,
        'author': w.author,
      },
    );
    // Every Post starts open and unexpired, so its root message and fact
    // can be seeded; the expired and closed ones are archived below.
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at, expires_at)
VALUES (@post, @author, '', '', 0, 1, 1, false, now(),
        now() + interval '24 hours'),
       (@expired, @author, '', '', 0, 1, 1, false, now(),
        now() + interval '24 hours'),
       (@closed, @author, '', '', 0, 1, 1, false, now(),
        now() + interval '24 hours'),
       (@rootless, @author, '', '', 0, 1, 1, false, now(),
        now() + interval '24 hours')
'''),
      parameters: {
        'post': w.post,
        'expired': w.expiredPost,
        'closed': w.closedPost,
        'rootless': w.rootlessPost,
        'author': w.author,
      },
    );
    for (final (beaconId, rootId) in [
      (w.post, w.postRoot),
      (w.expiredPost, w.expiredRoot),
      (w.closedPost, w.closedRoot),
    ]) {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES (@root, @beacon, @author, 'Root')
'''),
        parameters: {'root': rootId, 'beacon': beaconId, 'author': w.author},
      );
      await writer.execute(
        Sql.named(
          'UPDATE public.beacon SET post_root_message_id = @root '
          'WHERE id = @beacon',
        ),
        parameters: {'root': rootId, 'beacon': beaconId},
      );
    }
    final participants = [
      (w.post, w.member, RoomAccessBits.admitted),
      (w.post, w.blocked, RoomAccessBits.admitted),
      (w.post, w.leaver, RoomAccessBits.left),
      (w.expiredPost, w.member, RoomAccessBits.admitted),
      (w.closedPost, w.member, RoomAccessBits.admitted),
      (w.request, w.member, RoomAccessBits.admitted),
      (w.draftRequest, w.member, RoomAccessBits.admitted),
      (w.rootlessPost, w.member, RoomAccessBits.admitted),
    ];
    for (final (i, (beaconId, userId, roomAccess)) in participants.indexed) {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES (@id, @beacon, @user, 0, 0, @access)
'''),
        parameters: {
          'id': 'Ppw${w.n}x$i',
          'beacon': beaconId,
          'user': userId,
          'access': roomAccess,
        },
      );
    }
    await seedFact(w, id: w.factInPost, beaconId: w.post);
    await seedFact(w, id: w.factInExpired, beaconId: w.expiredPost);
    await seedFact(w, id: w.factInClosed, beaconId: w.closedPost);
    await seedFact(w, id: w.factInRootless, beaconId: w.rootlessPost);
    await seedFact(
      w,
      id: w.factInRequest,
      beaconId: w.request,
      visibility: BeaconFactCardVisibilityBits.public,
    );
    await seedFact(w, id: w.factInDraft, beaconId: w.draftRequest);

    await writer.execute(
      Sql.named(
        "UPDATE public.beacon SET expires_at = now() - interval '1 hour' "
        'WHERE id = @expired',
      ),
      parameters: {'expired': w.expiredPost},
    );
    await writer.execute(
      Sql.named('UPDATE public.beacon SET status = @status WHERE id = @closed'),
      parameters: {
        'closed': w.closedPost,
        'status': BeaconStatus.closed.smallintValue,
      },
    );
    await writer.execute(
      Sql.named('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES (@author, @blocked, @blocked)
'''),
      parameters: {'author': w.author, 'blocked': w.blocked},
    );
    return w;
  }

  /// Everything a fact write leaves behind in [beaconId]: fact rows, their
  /// revisions, chat lines and activity events.
  Future<Map<String, Object?>> footprint(String beaconId) async => (await rows(
    '''
SELECT
  (SELECT count(*)::integer FROM public.beacon_fact_card
    WHERE beacon_id = @b) AS facts,
  (SELECT string_agg(id || ':' || status || ':' || visibility || ':'
                     || revision_seq || ':' || fact_text, ',' ORDER BY id)
    FROM public.beacon_fact_card WHERE beacon_id = @b) AS fact_state,
  (SELECT count(*)::integer FROM public.beacon_fact_card_revision r
    JOIN public.beacon_fact_card f ON f.id = r.fact_card_id
    WHERE f.beacon_id = @b) AS revisions,
  (SELECT count(*)::integer FROM public.beacon_room_message
    WHERE beacon_id = @b) AS messages,
  (SELECT count(*)::integer FROM public.beacon_activity_event
    WHERE beacon_id = @b) AS events
''',
    {'b': beaconId},
  )).single;

  Future<Map<String, Object?>?> factRow(String id) async {
    final found = await rows(
      '''
SELECT fact_text, visibility::integer AS visibility,
       status::integer AS status, revision_seq
FROM public.beacon_fact_card WHERE id = @id
''',
      {'id': id},
    );
    return found.isEmpty ? null : found.single;
  }

  Future<Object> errorOf(Future<Object?> Function() action) async {
    try {
      await action();
    } on TestFailure {
      rethrow;
    } on Object catch (error) {
      return error;
    }
    fail('expected the write to be refused');
  }

  final isRoomAccessRequired = isA<UnauthorizedException>().having(
    (e) => e.description,
    'description',
    'Room access required',
  );

  final isReadOnly = isA<BeaconCreateException>().having(
    (e) => e.description,
    'description',
    kRoomReadOnlyException.description,
  );

  /// Every fact write on [beaconId] by [actor], against [factId], keyed by
  /// the operation name.
  Map<String, Future<Object?> Function()> everyWrite({
    required String beaconId,
    required String factId,
    required String actor,
  }) => {
    'pin': () => case_.pin(
      beaconId: beaconId,
      factText: 'A new fact',
      visibility: BeaconFactCardVisibilityBits.room,
      userId: actor,
    ),
    'correct': () => case_.correct(
      factCardId: factId,
      beaconId: beaconId,
      actorUserId: actor,
      newText: 'Edited',
      baseRevisionSeq: 2,
    ),
    'restore': () => case_.restore(
      factCardId: factId,
      beaconId: beaconId,
      actorUserId: actor,
      fromSeq: 1,
      baseRevisionSeq: 2,
    ),
    'setVisibility': () => case_.setVisibility(
      factCardId: factId,
      beaconId: beaconId,
      actorUserId: actor,
      visibility: BeaconFactCardVisibilityBits.public,
    ),
    'uploadAttachment': () => case_.uploadAttachment(
      beaconId: beaconId,
      actorUserId: actor,
      attachmentBytes: Stream.value(_png),
      attachmentFilename: 'p.png',
      attachmentMimeType: 'image/png',
    ),
    'remove': () => case_.remove(
      factCardId: factId,
      beaconId: beaconId,
      actorUserId: actor,
    ),
  };

  group('An admitted member of an open Post writes facts', () {
    test(
      'pin stores a discussion-only fact even when public is sent',
      () async {
        final w = await world();
        final pinned = await case_.pin(
          beaconId: w.post,
          factText: 'Meet at the gate',
          visibility: BeaconFactCardVisibilityBits.public,
          userId: w.member,
        );
        expect(pinned['beaconId'], w.post);
        final row = await factRow(pinned['id']! as String);
        expect(row, isNotNull);
        expect(row!['fact_text'], 'Meet at the gate');
        expect(row['visibility'], BeaconFactCardVisibilityBits.room);
      },
    );

    test('correct edits the fact text', () async {
      final w = await world();
      final seq = await case_.correct(
        factCardId: w.factInPost,
        beaconId: w.post,
        actorUserId: w.member,
        newText: 'Edited on a Post',
        baseRevisionSeq: 2,
      );
      expect(seq, 3);
      expect((await factRow(w.factInPost))!['fact_text'], 'Edited on a Post');
    });

    test('restore brings an earlier revision back as the head', () async {
      final w = await world();
      final seq = await case_.restore(
        factCardId: w.factInPost,
        beaconId: w.post,
        actorUserId: w.member,
        fromSeq: 1,
        baseRevisionSeq: 2,
      );
      expect(seq, 3);
      expect((await factRow(w.factInPost))!['fact_text'], 'Earlier');
    });

    test('remove unpins the fact', () async {
      final w = await world();
      await case_.remove(
        factCardId: w.factInPost,
        beaconId: w.post,
        actorUserId: w.member,
      );
      final row = await factRow(w.factInPost);
      expect(row?['status'], isNot(BeaconFactCardStatusBits.active));
    });

    test(
      'uploadAttachment stores the image and answers an attachment id',
      () async {
        final w = await world();
        final json = await case_.uploadAttachment(
          beaconId: w.post,
          actorUserId: w.member,
          attachmentBytes: Stream.value(_png),
          attachmentFilename: 'gate.png',
          attachmentMimeType: 'image/png',
        );
        final attachment = jsonDecode(json) as Map<String, Object?>;
        expect(attachment['id'], isA<String>());
        expect(attachment['id'], isNotEmpty);
        expect(images.puts, [w.member]);
      },
    );

    test(
      'setVisibility is refused as not a Request and changes nothing',
      () async {
        final w = await world();
        final before = await footprint(w.post);
        expect(
          await errorOf(
            () => case_.setVisibility(
              factCardId: w.factInPost,
              beaconId: w.post,
              actorUserId: w.member,
              visibility: BeaconFactCardVisibilityBits.public,
            ),
          ),
          isBeaconNotRequest,
        );
        expect(await footprint(w.post), before);
      },
    );
  });

  group('Post members shut out of the room cannot write facts', () {
    for (final who in ['a member blocked by the author', 'a member who left']) {
      test('$who gets «Room access required» from every fact write and '
          'nothing is written', () async {
        final w = await world();
        final actor = who.contains('blocked') ? w.blocked : w.leaver;
        final before = await footprint(w.post);
        final writes = everyWrite(
          beaconId: w.post,
          factId: w.factInPost,
          actor: actor,
        );
        for (final MapEntry(key: op, value: write) in writes.entries) {
          expect(await errorOf(write), isRoomAccessRequired, reason: op);
        }
        expect(await footprint(w.post), before);
        expect(images.puts, isEmpty);
        expect(tasks.scheduled, isEmpty);
      });
    }
  });

  group('An archived Post is read-only for facts', () {
    for (final state in ['expired', 'closed']) {
      test('every fact write by a member of an $state Post throws the '
          'read-only exception and nothing is written', () async {
        final w = await world();
        final beaconId = state == 'expired' ? w.expiredPost : w.closedPost;
        final factId = state == 'expired' ? w.factInExpired : w.factInClosed;
        final before = await footprint(beaconId);
        final writes = everyWrite(
          beaconId: beaconId,
          factId: factId,
          actor: w.member,
        );
        // setVisibility included: the room check comes first, so an archived
        // Post answers read-only before the Post-has-no-visibility refusal.
        for (final MapEntry(key: op, value: write) in writes.entries) {
          expect(await errorOf(write), isReadOnly, reason: op);
        }
        expect(await footprint(beaconId), before);
        expect(images.puts, isEmpty);
      });
    }
  });

  group('A draft accepts no fact writes but removal', () {
    test(
      'pin, correct, restore, setVisibility and uploadAttachment by the '
      'author are refused on a draft Request, and on an open Post without '
      'a root message with the same draft refusal, writing nothing',
      () async {
        final w = await world();
        final requestBefore = await footprint(w.draftRequest);
        final postBefore = await footprint(w.rootlessPost);
        final onRequest = everyWrite(
          beaconId: w.draftRequest,
          factId: w.factInDraft,
          actor: w.author,
        )..remove('remove');
        final onPost = everyWrite(
          beaconId: w.rootlessPost,
          factId: w.factInRootless,
          actor: w.author,
        );
        for (final MapEntry(key: op, value: write) in onRequest.entries) {
          final requestError = await errorOf(write);
          // A domain refusal, not a raw database error.
          expect(requestError, isA<ExceptionBase>(), reason: op);
          requestError as ExceptionBase;
          final postError = await errorOf(onPost[op]!);
          // A Post draft is refused because it is a draft, exactly like a
          // draft Request, never as "not a Request".
          expect(
            postError,
            isA<ExceptionBase>()
                .having((e) => e.runtimeType, 'type', requestError.runtimeType)
                .having(
                  (e) => e.code.codeNumber,
                  'code',
                  requestError.code.codeNumber,
                )
                .having(
                  (e) => e.description,
                  'description',
                  requestError.description,
                ),
            reason: op,
          );
        }
        expect(await footprint(w.draftRequest), requestBefore);
        expect(await footprint(w.rootlessPost), postBefore);
        expect(images.puts, isEmpty);
        expect(tasks.scheduled, isEmpty);
      },
    );

    test('the author removing a fact of a draft Request deletes the row and '
        'writes no chat line and no event', () async {
      final w = await world();
      final before = await footprint(w.draftRequest);
      await case_.remove(
        factCardId: w.factInDraft,
        beaconId: w.draftRequest,
        actorUserId: w.author,
      );
      expect(await factRow(w.factInDraft), isNull);
      final after = await footprint(w.draftRequest);
      expect(after['messages'], before['messages']);
      expect(after['events'], before['events']);
    });

    test('the author removing a fact of a draft Post deletes the row and '
        'writes no chat line and no event', () async {
      final w = await world();
      final before = await footprint(w.rootlessPost);
      await case_.remove(
        factCardId: w.factInRootless,
        beaconId: w.rootlessPost,
        actorUserId: w.author,
      );
      expect(await factRow(w.factInRootless), isNull);
      final after = await footprint(w.rootlessPost);
      expect(after['messages'], before['messages']);
      expect(after['events'], before['events']);
    });

    for (final kind in ['draft Request', 'draft Post']) {
      test('anyone but the author removing a fact of a $kind is refused and '
          'the fact stays', () async {
        final w = await world();
        final isPost = kind == 'draft Post';
        final beaconId = isPost ? w.rootlessPost : w.draftRequest;
        final factId = isPost ? w.factInRootless : w.factInDraft;
        final before = await footprint(beaconId);
        // An admitted participant of the draft and a stranger.
        for (final actor in [w.member, w.stranger]) {
          final error = await errorOf(
            () => case_.remove(
              factCardId: factId,
              beaconId: beaconId,
              actorUserId: actor,
            ),
          );
          expect(error, isA<ExceptionBase>(), reason: actor);
          expect(error, isNot(isBeaconNotRequest), reason: actor);
        }
        expect(await footprint(beaconId), before);
        expect(
          (await factRow(factId))!['status'],
          BeaconFactCardStatusBits.active,
        );
      });
    }
  });

  group('Visibility on a published Request', () {
    test('pin with public still stores a public fact', () async {
      final w = await world();
      final pinned = await case_.pin(
        beaconId: w.request,
        factText: 'Public on a Request',
        visibility: BeaconFactCardVisibilityBits.public,
        userId: w.member,
      );
      expect(
        (await factRow(pinned['id']! as String))!['visibility'],
        BeaconFactCardVisibilityBits.public,
      );
    });
  });
}
