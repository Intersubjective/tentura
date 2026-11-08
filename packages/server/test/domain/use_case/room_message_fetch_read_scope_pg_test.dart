@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_beacon_room.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_post.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/coordination_item_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/polling_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/post_publish_pg_support.dart';

const _author = 'UrfsAuthor001';
const _member = 'UrfsMember001';
const _declined = 'UrfsDeclined1';
const _other = 'UrfsOther0001';
const _post = 'BrfsPost00001';
const _request = 'BrfsRequest01';
const _postRoot = 'MrfsPostRoot1';

// Real GraphQL resolvers over a real BeaconRoomCase and PostgreSQL. Reading
// a room's messages is not reading them: only a Post recipient's first open
// records «Opened». Requests, the author, refetches and older pages leave the
// seen watermark (and so the unread band and peer read receipts) alone.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ROOM_FETCH_READ_SCOPE_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_room_fetch_read_scope',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  late DisposablePgWriterSession session;
  late TenturaDb database;
  late Connection writer;
  late Connection listener;
  late StreamSubscription<String> subscription;
  late QueryPost postQuery;
  late _PageReadHookRoomRepository roomRepository;
  late BeaconRoomCase room;
  late QueryBeaconRoom roomQuery;
  final notifications = <Map<String, dynamic>>[];
  var barrier = 0;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    database = openDisposablePgDatabase(target);
    postQuery = QueryPost(
      postCase: PostPublishHarness.build(database, target.databaseEnv).posts,
    );
    roomRepository = _PageReadHookRoomRepository(database);
    room = BeaconRoomCase(
      roomRepository,
      CoordinationItemRepository(database),
      _UnusedFactCards(),
      _UnusedImages(),
      _UnusedTasks(),
      _UnusedStorage(),
      PollingRepository(database),
      _UnusedQuota(),
      UserBlockRepository(target.databaseEnv, database),
      MutatingUnitOfWork(database),
      FakeBeaconHierarchyRepository(),
      const ProductionDiscussionProductPolicy(),
      beaconRepository: BeaconRepository(database),
      env: target.databaseEnv,
      logger: Logger('RoomMessageFetchReadScopePgTest'),
    );
    roomQuery = QueryBeaconRoom(beaconRoomCase: room);
    listener = await Connection.open(
      target.databaseEnv.pgEndpoint,
      settings: target.databaseEnv.pgEndpointSettings,
    );
    subscription = listener.channels['entity_changes'].listen(
      (payload) =>
          notifications.add(jsonDecode(payload) as Map<String, dynamic>),
    );
    await listener.execute('LISTEN entity_changes');
  });

  tearDownAll(() async {
    await subscription.cancel();
    await listener.close();
    await tearDownDisposablePgWriter(session: session, drift: database);
  });

  // A committed NOTIFY after the action is a delivery barrier for every
  // earlier notification, so «no receipt» does not rest on a guessed sleep.
  Future<void> drainNotifications() async {
    final token = ++barrier;
    await writer.execute(
      Sql.named("SELECT pg_notify('entity_changes', @payload)"),
      parameters: {
        'payload': jsonEncode({'test_barrier': token}),
      },
    );
    final deadline = DateTime.timestamp().add(const Duration(seconds: 5));
    while (!notifications.any((event) => event['test_barrier'] == token)) {
      if (DateTime.timestamp().isAfter(deadline)) {
        fail('The notification listener did not receive its delivery barrier');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  Future<void> startObservingReceipts() async {
    await drainNotifications();
    notifications.clear();
  }

  Future<List<Map<String, dynamic>>> seenReceiptsFor(
    String beaconId,
    String seenUserId,
  ) async {
    await drainNotifications();
    return [
      for (final event in notifications)
        if (event['entity'] == 'room_seen_peer' &&
            event['id'] == beaconId &&
            jsonEncode(event).contains(seenUserId))
          event,
    ];
  }

  Future<void> insertUsers() async {
    await writer.execute('TRUNCATE public."user" CASCADE');
    for (final (index, id) in [_author, _member, _declined, _other].indexed) {
      await writer.execute(
        Sql.named('''
          INSERT INTO public."user" (id, display_name, public_key)
          VALUES (@id, @name, @key)
        '''),
        parameters: {
          'id': id,
          'name': 'Name $id',
          'key': pgTestPublicKey('room-fetch-read-scope', index + 1),
        },
      );
    }
  }

  /// One Post by [_author], forwarded to each of [recipients]; its root
  /// message is old so every later message sorts after it.
  Future<void> seedPost(List<String> recipients) async {
    await insertUsers();
    await writer.execute('''
      INSERT INTO public.beacon
        (id, user_id, title, description, status, kind, forward_policy,
         is_discoverable, published_at)
      VALUES ('$_post', '$_author', '', '', 0, 1, 1, false, now())
    ''');
    for (final (index, id) in recipients.indexed) {
      await writer.execute(
        Sql.named('''
          INSERT INTO public.beacon_forward_edge
            (id, beacon_id, sender_id, recipient_id, created_at)
          VALUES (@edge, @post, @author, @recipient, '2019-01-01Z')
        '''),
        parameters: {
          'edge': 'FrfsEdge000$index',
          'post': _post,
          'author': _author,
          'recipient': id,
        },
      );
    }
    await writer.execute('''
      INSERT INTO public.beacon_room_message
        (id, beacon_id, author_id, body, created_at)
      VALUES ('$_postRoot', '$_post', '$_author', 'A shared Post',
              '2019-01-01Z')
    ''');
    await writer.execute('''
      UPDATE public.beacon SET post_root_message_id = '$_postRoot'
      WHERE id = '$_post'
    ''');
  }

  /// One Request by [_author] with [_member] admitted to its room.
  Future<void> seedRequest() async {
    await insertUsers();
    await writer.execute('''
      INSERT INTO public.beacon
        (id, user_id, title, description, kind, status, is_discoverable,
         published_at)
      VALUES ('$_request', '$_author', 'Moving help', '', 0, 0, true, now())
    ''');
    await roomRepository.inviteOfferUserToBeaconRoom(
      beaconId: _request,
      offerUserId: _member,
      authorUserId: _author,
    );
    final access = await room.listParticipants(
      beaconId: _request,
      userId: _member,
    );
    expect(
      access,
      contains(
        allOf(containsPair('userId', _member), containsPair('roomAccess', 3)),
      ),
      reason: 'fixture: the member can use the Request room',
    );
  }

  /// A message by [authorId], [offset] after the database clock.
  Future<({String id, DateTime createdAt})> postMessage({
    required String beaconId,
    required String id,
    required Duration offset,
    String authorId = _author,
  }) async {
    final rows = await writer.execute(
      Sql.named('''
        INSERT INTO public.beacon_room_message
          (id, beacon_id, author_id, body, created_at)
        VALUES (@id, @beacon, @author, @body,
                now() + make_interval(secs => @secs))
        RETURNING created_at
      '''),
      parameters: {
        'id': id,
        'beacon': beaconId,
        'author': authorId,
        'body': 'Message $id',
        'secs': offset.inSeconds,
      },
    );
    return (id: id, createdAt: (rows.single.single! as DateTime).toUtc());
  }

  Future<DateTime> setSeen({
    required String beaconId,
    required String userId,
    required Duration offset,
  }) async {
    final rows = await writer.execute(
      Sql.named('''
        INSERT INTO public.beacon_room_seen
          (user_id, beacon_id, thread_item_id, last_seen_at)
        VALUES (@user, @beacon, NULL, now() + make_interval(secs => @secs))
        RETURNING last_seen_at
      '''),
      parameters: {
        'user': userId,
        'beacon': beaconId,
        'secs': offset.inSeconds,
      },
    );
    return (rows.single.single! as DateTime).toUtc();
  }

  Future<List<DateTime>> seenRows(String beaconId, String userId) async {
    final rows = await writer.execute(
      Sql.named('''
        SELECT last_seen_at FROM public.beacon_room_seen
        WHERE beacon_id = @beacon AND user_id = @user
          AND thread_item_id IS NULL
      '''),
      parameters: {'beacon': beaconId, 'user': userId},
    );
    return [for (final row in rows) (row.single! as DateTime).toUtc()];
  }

  /// The client's room fetch: the General message list, first page unless
  /// [beforeIso] asks for older history.
  Future<List<Map<String, Object?>>> fetchMessages(
    String beaconId,
    String viewer, {
    String? beforeIso,
  }) async {
    final rows =
        await roomQuery.roomMessageList.resolve!(null, {
              kGlobalInputQueryJwt: JwtEntity(sub: viewer),
              'beaconId': beaconId,
              'beforeIso': ?beforeIso,
            })
            as List;
    return [for (final row in rows) Map<String, Object?>.from(row as Map)];
  }

  /// The room's peer read watermarks as the client loads them right after
  /// the messages (RoomCubit's full snapshot).
  Future<DateTime?> watermarkOf(String beaconId, String viewer) async {
    final rows =
        await roomQuery.beaconRoomReadWatermarks.resolve!(null, {
              kGlobalInputQueryJwt: JwtEntity(sub: viewer),
              'beaconId': beaconId,
            })
            as List;
    for (final row in rows.cast<Map<String, Object?>>()) {
      if (row['userId'] == viewer) {
        return DateTime.parse(row['lastSeenAt']! as String).toUtc();
      }
    }
    return null;
  }

  /// The unread band the room shows: messages by others in [messages] newer
  /// than the viewer's own watermark.
  ({int unreadCount, String? firstUnreadMessageId}) unreadBand(
    List<Map<String, Object?>> messages,
    String viewer,
    DateTime? watermark,
  ) {
    final unread =
        [
          for (final m in messages)
            if (m['authorId'] != viewer &&
                (watermark == null ||
                    DateTime.parse(
                      m['createdAt']! as String,
                    ).isAfter(watermark)))
              m,
        ]..sort(
          (a, b) => (a['createdAt']! as String).compareTo(
            b['createdAt']! as String,
          ),
        );
    return (
      unreadCount: unread.length,
      firstUnreadMessageId: unread.isEmpty
          ? null
          : unread.first['id'] as String?,
    );
  }

  /// Opening a room the way RoomCubit does: messages first, then the
  /// watermarks, and the band computed from both.
  Future<({int unreadCount, String? firstUnreadMessageId})> openRoom(
    String beaconId,
    String viewer,
  ) async {
    final messages = await fetchMessages(beaconId, viewer);
    final watermark = await watermarkOf(beaconId, viewer);
    return unreadBand(messages, viewer, watermark);
  }

  Future<Map<String, Object?>> postListRow(String viewer) async {
    final rows =
        await postQuery.myPosts.resolve!(null, {
              kGlobalInputQueryJwt: JwtEntity(sub: viewer),
            })
            as List;
    final mine = [
      for (final row in rows)
        if ((row as Map)['id'] == _post) Map<String, Object?>.from(row),
    ];
    expect(mine, hasLength(1));
    return mine.single;
  }

  setUp(() {
    roomRepository.afterPageRead = null;
  });

  group('A Post recipient opening the Post', () {
    test('marks the recipient as opened for the author', () async {
      await seedPost([_member, _other]);
      final before = await postListRow(_author);
      expect(before['notOpenedCount'], 2);

      await fetchMessages(_post, _member);

      expect(
        await postListRow(_author),
        containsPair('notOpenedCount', (before['notOpenedCount']! as int) - 1),
      );
      final sheet = await room.listParticipants(
        beaconId: _post,
        userId: _author,
      );
      expect(
        sheet.singleWhere((row) => row['userId'] == _member),
        containsPair('opened', true),
      );
    });

    test('does not mark a reply that arrives while the page is being read '
        'as read', () async {
      await seedPost([_member]);
      final page = <String, Object?>{};
      roomRepository.afterPageRead = (messages) async {
        roomRepository.afterPageRead = null;
        page['maxCreatedAt'] = messages
            .map((m) => DateTime.parse(m['createdAt']! as String).toUtc())
            .reduce((a, b) => a.isAfter(b) ? a : b);
        page['reply'] = await postMessage(
          beaconId: _post,
          id: 'MrfsRace0001',
          offset: const Duration(seconds: 30),
        );
      };

      await fetchMessages(_post, _member);

      final reply = page['reply']! as ({String id, DateTime createdAt});
      final pageMax = page['maxCreatedAt']! as DateTime;
      final seen = await seenRows(_post, _member);
      expect(seen, hasLength(1), reason: 'the first open is still recorded');
      expect(
        seen.single.isAfter(pageMax),
        isFalse,
        reason: 'the watermark goes no further than the page that was read',
      );
      expect(seen.single.isBefore(reply.createdAt), isTrue);

      // The author's own fetch writes nothing, so it is a clean read.
      final everything = await fetchMessages(_post, _author);
      final band = unreadBand(
        everything,
        _member,
        await watermarkOf(_post, _member),
      );
      expect(band.unreadCount, 1);
      expect(band.firstUnreadMessageId, reply.id);
      expect(await postListRow(_member), containsPair('unreadCount', 1));
    });

    test('again after opening it before keeps the unread band on the first '
        'new message', () async {
      await seedPost([_member]);
      await fetchMessages(_post, _member);
      expect(await seenRows(_post, _member), hasLength(1));
      final first = await postMessage(
        beaconId: _post,
        id: 'MrfsNewOne01',
        offset: const Duration(minutes: 1),
      );
      await postMessage(
        beaconId: _post,
        id: 'MrfsNewTwo01',
        offset: const Duration(minutes: 2),
      );

      final band = await openRoom(_post, _member);

      expect(band.unreadCount, 2);
      expect(band.firstUnreadMessageId, first.id);
    });
  });

  group('Fetching room messages leaves the seen watermark alone', () {
    test(
      'for a Request participant who has never been seen in the room',
      () async {
        await seedRequest();
        await postMessage(
          beaconId: _request,
          id: 'MrfsReqMsg01',
          offset: const Duration(minutes: 1),
        );
        await startObservingReceipts();

        final messages = await fetchMessages(_request, _member);

        expect(messages, contains(containsPair('id', 'MrfsReqMsg01')));
        expect(await seenRows(_request, _member), isEmpty);
        expect(await seenReceiptsFor(_request, _member), isEmpty);
      },
    );

    test('for a Request participant, so opening the room still shows both '
        'new messages as unread', () async {
      await seedRequest();
      final seenAt = await setSeen(
        beaconId: _request,
        userId: _member,
        offset: const Duration(seconds: 30),
      );
      final first = await postMessage(
        beaconId: _request,
        id: 'MrfsReqNew01',
        offset: const Duration(minutes: 1),
      );
      await postMessage(
        beaconId: _request,
        id: 'MrfsReqNew02',
        offset: const Duration(minutes: 2),
      );
      await startObservingReceipts();

      final band = await openRoom(_request, _member);

      expect(await seenRows(_request, _member), [seenAt]);
      expect(await seenReceiptsFor(_request, _member), isEmpty);
      expect(band.unreadCount, 2);
      expect(band.firstUnreadMessageId, first.id);
    });

    test('for the author of a Post', () async {
      await seedPost([_member]);
      await startObservingReceipts();

      await fetchMessages(_post, _author);

      expect(await seenRows(_post, _author), isEmpty);
      expect(await seenReceiptsFor(_post, _author), isEmpty);
    });

    test(
      'for a Post recipient refetching after they already opened it',
      () async {
        await seedPost([_member]);
        await fetchMessages(_post, _member);
        final opened = await seenRows(_post, _member);
        expect(opened, hasLength(1));
        final reply = await postMessage(
          beaconId: _post,
          id: 'MrfsReply001',
          offset: const Duration(minutes: 1),
        );
        await startObservingReceipts();

        final messages = await fetchMessages(_post, _member);

        expect(messages, contains(containsPair('id', reply.id)));
        expect(await seenRows(_post, _member), opened);
        expect(await seenReceiptsFor(_post, _member), isEmpty);
        expect(await postListRow(_member), containsPair('unreadCount', 1));
      },
    );

    test('for a Post recipient loading an older page', () async {
      await seedPost([_member]);
      await startObservingReceipts();

      await fetchMessages(
        _post,
        _member,
        beforeIso: DateTime.timestamp()
            .add(const Duration(days: 1))
            .toIso8601String(),
      );

      expect(await seenRows(_post, _member), isEmpty);
      expect(await seenReceiptsFor(_post, _member), isEmpty);
    });
  });

  group('Post participant count', () {
    test(
      'the posts list and the room participant set count the same '
      'people: the author yes, the viewer and a declined recipient no',
      () async {
        await seedPost([_member, _declined, _other]);
        await writer.execute('''
        UPDATE public.beacon_forward_edge SET recipient_rejected = true
        WHERE beacon_id = '$_post' AND recipient_id = '$_declined'
      ''');
        final declined = {
          for (final row in await writer.execute('''
          SELECT recipient_id FROM public.beacon_forward_edge
          WHERE beacon_id = '$_post' AND recipient_rejected
        '''))
            row.single! as String,
        };

        for (final viewer in [_member, _author]) {
          final sheet = await room.listParticipants(
            beaconId: _post,
            userId: viewer,
          );
          final roomPeople = {
            for (final row in sheet)
              if (row['roomAccess'] == 3) row['userId']! as String,
            _author,
          }..removeAll({viewer, ...declined});
          expect(roomPeople, hasLength(2), reason: 'viewer $viewer');
          expect(
            await postListRow(viewer),
            containsPair('participantCount', roomPeople.length),
            reason: 'viewer $viewer',
          );
        }
      },
    );
  });
}

/// The real room repository, with a hook that runs right after the message
/// page has been read and before the use case continues.
final class _PageReadHookRoomRepository extends BeaconRoomRepository {
  _PageReadHookRoomRepository(super._db);

  Future<void> Function(List<Map<String, Object?>> page)? afterPageRead;

  @override
  Future<List<Map<String, Object?>>> listMessagesEnriched({
    required String beaconId,
    required String viewerUserId,
    String? threadItemId,
    DateTime? before,
    String? messageId,
    int limit = 50,
  }) async {
    final page = await super.listMessagesEnriched(
      beaconId: beaconId,
      viewerUserId: viewerUserId,
      threadItemId: threadItemId,
      before: before,
      messageId: messageId,
      limit: limit,
    );
    final hook = afterPageRead;
    if (hook != null && page.isNotEmpty) await hook(page);
    return page;
  }
}

final class _UnusedFactCards extends Fake
    implements BeaconFactCardRepositoryPort {}

final class _UnusedImages extends Fake implements ImageRepositoryPort {}

final class _UnusedTasks extends Fake implements TaskRepositoryPort {}

final class _UnusedStorage extends Fake implements RemoteStoragePort {}

final class _UnusedQuota extends Fake implements UploadQuotaRepositoryPort {}
