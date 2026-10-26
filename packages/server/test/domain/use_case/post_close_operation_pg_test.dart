@Tags(['pg'])
library;

import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_hierarchy_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/post_close_operation.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'Uclsopauthor01';
const _member = 'Uclsopmember01';
const _users = [_author, _member];

const _post = 'Bclsoppost0001';
const _child = 'Bclsopchild001';
const _request = 'Bclsopreq00001';

/// The three ways a Post ends (expiry, the author's own close, budding): each
/// moves it to closed, logs why, leaves exactly one notice that says why, and
/// refuses a Post that already ended.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_CLOSE_OPERATION_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_close_operation',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  late DisposablePgWriterSession session;
  late TenturaDb database;
  late Connection writer;
  late MutatingUnitOfWork uow;
  late PostCloseOperation close;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    database = openDisposablePgDatabase(target);
    uow = MutatingUnitOfWork(database);
    close = PostCloseOperation(BeaconRepository(database));
  });

  setUp(() async => _seed(writer));

  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: database);
  });

  Future<void> expire({String postId = _post}) => uow.run(
    action: () => close.expire(postId: postId),
  );

  Future<void> closeByAuthor({
    String postId = _post,
    String actor = _author,
  }) => uow.run(
    actorUserId: actor,
    action: () => close.closeByAuthor(postId: postId, actorId: actor),
  );

  Future<void> closeForBud({String postId = _post}) => uow.run(
    actorUserId: _author,
    action: () => close.closeForBud(
      postId: postId,
      childBeaconId: _child,
      title: 'Fix the fence',
      actorId: _author,
    ),
  );

  Future<int> status(String beaconId) async =>
      (await writer.execute(
            "SELECT status FROM public.beacon WHERE id = '$beaconId'",
          )).single.single!
          as int;

  Future<int> count(String sql) async =>
      (await writer.execute(sql)).single.single! as int;

  Future<int> noticeCount(String beaconId) => count('''
SELECT count(*)::int FROM public.beacon_room_message
WHERE beacon_id = '$beaconId'
  AND system_message_kind = ${BeaconRoomSystemMessageKind.postClosed}
''');

  Future<Map<String, Object?>> onlyNoticePayload() async {
    final notices = await writer.execute('''
SELECT system_payload, author_id FROM public.beacon_room_message
WHERE beacon_id = '$_post'
  AND system_message_kind = ${BeaconRoomSystemMessageKind.postClosed}
''');
    expect(notices, hasLength(1));
    expect(notices.single[1], isNull, reason: 'a system notice has no author');
    return _json(notices.single[0]);
  }

  Future<List<ResultRow>> lifecycleEvents() => writer.execute('''
SELECT diff, actor_id FROM public.beacon_activity_event
WHERE beacon_id = '$_post'
  AND type = ${BeaconActivityEventTypeBits.beaconLifecycleChanged}
ORDER BY created_at
''');

  Future<bool> endedAtOrBeforeNow() async =>
      (await writer.execute(
            "SELECT expires_at <= now() FROM public.beacon WHERE id = '$_post'",
          )).single.single!
          as bool;

  Future<int> statusChangedLines() => count('''
SELECT count(*)::int FROM public.beacon_room_message
WHERE beacon_id = '$_post'
  AND system_message_kind = ${BeaconRoomSystemMessageKind.statusChanged}
''');

  group('PostCloseOperation.expire', () {
    test('moves an open Post to closed', () async {
      await expire();

      expect(await status(_post), 6);
    });

    test('logs a postExpired transition with no actor', () async {
      await expire();

      final events = await lifecycleEvents();
      expect(events, hasLength(1));
      final diff = _json(events.single[0]);
      expect(diff['reason'], 'postExpired');
      expect(diff['fromStatus'], 0);
      expect(diff['toStatus'], 6);
      expect(events.single[1], isNull);
    });

    test('inserts one postClosed notice with reason expired and no child '
        'Request', () async {
      await expire();

      final payload = await onlyNoticePayload();
      expect(payload['reason'], 'expired');
      expect(payload.containsKey('childBeaconId'), isFalse);
    });

    test('pulls expires_at back to now so the end is readable from the row',
        () async {
      expect(await endedAtOrBeforeNow(), isFalse);

      await expire();

      expect(await endedAtOrBeforeNow(), isTrue);
    });

    test('writes no statusChanged chat line for a Post', () async {
      await expire();

      expect(await statusChangedLines(), 0);
    });

    test('refuses a Post that is already closed, with no second notice',
        () async {
      await expire();

      await expectLater(expire(), throwsA(isA<PostNotOpenException>()));
      expect(await noticeCount(_post), 1);
    });

    test('refuses a Request', () async {
      await expectLater(
        expire(postId: _request),
        throwsA(isA<PostNotOpenException>()),
      );
      expect(await status(_request), 0);
    });
  });

  group('PostCloseOperation.closeByAuthor', () {
    test('moves an open Post to closed', () async {
      await closeByAuthor();

      expect(await status(_post), 6);
    });

    test('logs a postClosedByAuthor transition by the author', () async {
      await closeByAuthor();

      final events = await lifecycleEvents();
      expect(events, hasLength(1));
      final diff = _json(events.single[0]);
      expect(diff['reason'], 'postClosedByAuthor');
      expect(diff['fromStatus'], 0);
      expect(diff['toStatus'], 6);
      expect(events.single[1], _author);
    });

    test('inserts one postClosed notice with reason closedByAuthor and no '
        'child Request', () async {
      await closeByAuthor();

      final payload = await onlyNoticePayload();
      expect(payload['reason'], 'closedByAuthor');
      expect(payload.containsKey('childBeaconId'), isFalse);
    });

    test('pulls expires_at back to now so the end is readable from the row',
        () async {
      expect(await endedAtOrBeforeNow(), isFalse);

      await closeByAuthor();

      expect(await endedAtOrBeforeNow(), isTrue);
    });

    test('writes no statusChanged chat line for a Post', () async {
      await closeByAuthor();

      expect(await statusChangedLines(), 0);
    });

    test('refuses a Post that is already closed, with no second notice',
        () async {
      await closeByAuthor();

      await expectLater(
        closeByAuthor(),
        throwsA(isA<PostNotOpenException>()),
      );
      expect(await noticeCount(_post), 1);
    });

    test('refuses a Request', () async {
      await expectLater(
        closeByAuthor(postId: _request),
        throwsA(isA<PostNotOpenException>()),
      );
      expect(await status(_request), 0);
    });
  });

  group('PostCloseOperation.expire after the author closed the Post', () {
    test('is refused and adds no second notice', () async {
      await closeByAuthor();

      await expectLater(expire(), throwsA(isA<PostNotOpenException>()));
      expect(await noticeCount(_post), 1);
    });
  });

  group('PostCloseOperation.closeForBud', () {
    test('keeps the child and title in the notice and adds reason budded',
        () async {
      await closeForBud();

      expect(await onlyNoticePayload(), {
        'childBeaconId': _child,
        'title': 'Fix the fence',
        'reason': 'budded',
      });
    });

    test('refuses a Post that is already closed, with no second notice',
        () async {
      await closeForBud();

      await expectLater(closeForBud(), throwsA(isA<PostNotOpenException>()));
      expect(await noticeCount(_post), 1);
    });

    test('writes no statusChanged chat line for a Post', () async {
      await closeForBud();

      expect(await statusChangedLines(), 0);
    });
  });
}

Map<String, Object?> _json(Object? value) => switch (value) {
  final Map<String, Object?> map => map,
  final String text => jsonDecode(text) as Map<String, Object?>,
  _ => throw StateError('Not JSON: $value'),
};

Future<void> _seed(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.beacon_hierarchy_deliveries,
  public.beacon_hierarchy_events,
  public.notification_outbox,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.inbox_item,
  public.beacon_activity_event,
  public.beacon_room_message_reaction,
  public.beacon_room_message,
  public.beacon_forward_edge,
  public.beacon_participant,
  public.beacon,
  public."user"
CASCADE
''');
  for (var i = 0; i < _users.length; i++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': _users[i], 'key': pgTestPublicKey('clsop', i + 1)},
    );
  }
  // An open Post with a day left to live.
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at, expires_at)
VALUES ('$_post', '$_author', '', '', 0, 1, 1, false,
        now() - interval '1 hour', now() + interval '23 hours')
''');
  await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES ('Fclsopauthmem1', '$_post', '$_author', '$_member')
''');
  // The Request budded from the Post.
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, parent_beacon_id,
   is_discoverable, published_at)
VALUES ('$_child', '$_member', 'Fix the fence', '', 0, 0, '$_post', false,
        now())
''');
  // An unrelated Request.
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, published_at)
VALUES ('$_request', '$_author', 'Request', '', 0, 0, now())
''');
}
