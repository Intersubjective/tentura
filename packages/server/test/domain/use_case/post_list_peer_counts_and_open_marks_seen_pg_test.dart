@Tags(['pg'])
library;

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
import 'package:tentura_server/domain/exception.dart';
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

const _author = 'UpcAuthor001';
const _first = 'UpcFirst0001';
const _second = 'UpcSecond001';
const _outsider = 'UpcOutside01';
const _post = 'BpcPost00001';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_LIST_PEER_COUNTS_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_list_peer_counts',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  late DisposablePgWriterSession session;
  late TenturaDb database;
  late Connection writer;
  late QueryPost query;
  late QueryBeaconRoom roomQuery;
  late BeaconRoomCase room;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    database = openDisposablePgDatabase(target);
    query = QueryPost(
      postCase: PostPublishHarness.build(database, target.databaseEnv).posts,
    );
    room = BeaconRoomCase(
      BeaconRoomRepository(database),
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
      logger: Logger('PostListPeerCountsPgTest'),
    );
    roomQuery = QueryBeaconRoom(beaconRoomCase: room);
  });

  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: database);
  });

  /// One Post by [_author], forwarded to each of [recipients].
  Future<void> seedPost(List<String> recipients) async {
    await writer.execute('TRUNCATE public."user" CASCADE');
    for (final (index, id) in [
      _author,
      _first,
      _second,
      _outsider,
    ].indexed) {
      await writer.execute(
        Sql.named('''
          INSERT INTO public."user" (id, display_name, public_key)
          VALUES (@id, @name, @key)
        '''),
        parameters: {
          'id': id,
          'name': 'Name $id',
          'key': pgTestPublicKey('post-list-peer-counts', index + 1),
        },
      );
    }
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
          'edge': 'FpcEdge0000$index',
          'post': _post,
          'author': _author,
          'recipient': id,
        },
      );
    }
    await writer.execute('''
      INSERT INTO public.beacon_room_message
        (id, beacon_id, author_id, body, created_at)
      VALUES ('MpcRoot00001', '$_post', '$_author', 'A shared Post',
              '2019-01-01Z')
    ''');
    await writer.execute('''
      UPDATE public.beacon SET post_root_message_id = 'MpcRoot00001'
      WHERE id = '$_post'
    ''');
  }

  /// Declines the way the inbox does: only the forward edge is flagged.
  Future<void> decline(String recipient) => writer.execute('''
    UPDATE public.beacon_forward_edge SET recipient_rejected = true
    WHERE beacon_id = '$_post' AND recipient_id = '$recipient'
  ''');

  Future<Map<String, Object?>> listRow(String viewer) async {
    final rows =
        await query.myPosts.resolve!(null, {
              kGlobalInputQueryJwt: JwtEntity(sub: viewer),
            })
            as List;
    expect(rows, hasLength(1));
    return Map<String, Object?>.from(rows.single as Map);
  }

  /// The client's open path: the Post room's General message list.
  Future<List<Map<String, Object?>>> open(String viewer) async {
    final rows =
        await roomQuery.roomMessageList.resolve!(null, {
              kGlobalInputQueryJwt: JwtEntity(sub: viewer),
              'beaconId': _post,
            })
            as List;
    return [for (final row in rows) Map<String, Object?>.from(row as Map)];
  }

  Future<List<Object?>> seenRows(String user) async {
    final rows = await writer.execute('''
      SELECT last_seen_at FROM public.beacon_room_seen
      WHERE beacon_id = '$_post' AND user_id = '$user'
        AND thread_item_id IS NULL
    ''');
    return [for (final row in rows) row.single];
  }

  group('Post list participant count', () {
    test('a recipient counts the author, who has no participant row, '
        'so a one-to-one Post is not «Only you»', () async {
      await seedPost([_first]);
      expect(await listRow(_first), containsPair('participantCount', 1));
    });

    for (final viewer in [_first, _author]) {
      test(
        'the list row counts the same people the Post detail shows '
        '${viewer == _author ? 'the author' : 'a recipient'}, apart from '
        'the viewer',
        () async {
          await seedPost([_first, _second]);
          final sheet = await room.listParticipants(
            beaconId: _post,
            userId: viewer,
          );
          // Detail: the admitted members of the participant sheet plus the
          // Post's author, who has no participant row of their own.
          final admitted = {
            for (final row in sheet)
              if (row['roomAccess'] == 3) row['userId']! as String,
          };
          expect(admitted, containsAll([_first, _second]));
          final detailPeople = {...admitted, _author}..remove(viewer);
          expect(
            await listRow(viewer),
            containsPair('participantCount', detailPeople.length),
          );
          final summary = await query.postSummary.resolve!(null, {
            kGlobalInputQueryJwt: JwtEntity(sub: viewer),
            'id': _post,
          });
          expect(
            summary,
            containsPair('participantCount', detailPeople.length),
          );
        },
      );
    }

    test('the author counts each admitted recipient once and not '
        'themselves', () async {
      await seedPost([_first, _second]);
      expect(await listRow(_author), containsPair('participantCount', 2));
    });

    test('a declined recipient is left out of «N people» for the author '
        'and for the other recipient', () async {
      await seedPost([_first, _second]);
      await decline(_second);
      expect(await listRow(_author), containsPair('participantCount', 1));
      expect(await listRow(_first), containsPair('participantCount', 1));
    });

    test('a declined recipient who never opened is not counted as '
        'not opened', () async {
      await seedPost([_first]);
      expect(await listRow(_author), containsPair('notOpenedCount', 1));
      await decline(_first);
      expect(await listRow(_author), containsPair('notOpenedCount', 0));
    });

    test('a declined recipient is not counted as not opened next to a '
        'recipient who has not opened', () async {
      await seedPost([_first, _second]);
      expect(await listRow(_author), containsPair('notOpenedCount', 2));
      await decline(_second);
      expect(await listRow(_author), containsPair('notOpenedCount', 1));
      expect(await listRow(_first), containsPair('notOpenedCount', 0));
    });
  });

  group('Opening a Post as a recipient', () {
    test(
      'records the recipient as opened without a separate seen call',
      () async {
        await seedPost([_first]);
        expect(await listRow(_author), containsPair('notOpenedCount', 1));
        expect(await seenRows(_first), isEmpty);
        final before = await room.listParticipants(
          beaconId: _post,
          userId: _author,
        );
        expect(
          before.singleWhere((row) => row['userId'] == _first),
          allOf(containsPair('roomAccess', 3), containsPair('opened', false)),
        );

        await open(_first);

        expect(await seenRows(_first), hasLength(1));
        expect(await listRow(_author), containsPair('notOpenedCount', 0));
        final sheet = await room.listParticipants(
          beaconId: _post,
          userId: _author,
        );
        expect(
          sheet.singleWhere((row) => row['userId'] == _first),
          containsPair('opened', true),
        );
      },
    );

    test('a second open neither adds a seen row nor moves the one the '
        'first open wrote', () async {
      await seedPost([_first]);
      await open(_first);
      final first = await seenRows(_first);
      expect(first, hasLength(1));

      await open(_first);

      expect(await seenRows(_first), first);
    });

    test('only a user who can read the Post gets a seen row from opening '
        'it', () async {
      await seedPost([_first]);

      // Control: the admitted recipient's open reads the Post and is recorded.
      final readable = await open(_first);
      expect(readable, contains(containsPair('id', 'MpcRoot00001')));
      expect(await seenRows(_first), hasLength(1));

      // The outsider is refused (or shown nothing); any other failure is a
      // broken fixture and must surface.
      List<Map<String, Object?>> shown;
      try {
        shown = await open(_outsider);
      } on UnauthorizedException {
        shown = [];
      }
      expect(shown, isEmpty, reason: 'An outsider is shown no messages');
      expect(await seenRows(_outsider), isEmpty);
    });

    test('the author opening their own Post writes no seen row and '
        'leaves the counts alone', () async {
      await seedPost([_first, _second]);
      final before = await listRow(_author);

      await open(_author);

      expect(await seenRows(_author), isEmpty);
      final after = await listRow(_author);
      expect(after['participantCount'], before['participantCount']);
      expect(after['notOpenedCount'], before['notOpenedCount']);
      expect(after['notOpenedCount'], 2);
    });

    test(
      'an author reply posted after the recipient opened is returned '
      'on the next open and is their only unread message',
      () async {
        await seedPost([_first]);
        await open(_first);
        await writer.execute('''
        INSERT INTO public.beacon_room_message
          (id, beacon_id, author_id, body, created_at)
        VALUES ('MpcReply0001', '$_post', '$_author', 'Reply after you opened',
                now() + interval '1 minute')
      ''');

        // Before the next open the reply is the only thing the first open
        // did not cover.
        expect(await listRow(_first), containsPair('unreadCount', 1));
        expect(
          await listRow(_first),
          containsPair('lastMessageExcerpt', 'Reply after you opened'),
        );

        final messages = await open(_first);

        expect(
          messages,
          contains(
            allOf(
              containsPair('authorId', _author),
              containsPair('body', 'Reply after you opened'),
            ),
          ),
        );
        // Fetching the messages again is not reading them: the reply stays
        // unread until the room marks it seen.
        expect(await listRow(_first), containsPair('unreadCount', 1));
      },
    );
  });
}

final class _UnusedFactCards extends Fake
    implements BeaconFactCardRepositoryPort {}

final class _UnusedImages extends Fake implements ImageRepositoryPort {}

final class _UnusedTasks extends Fake implements TaskRepositoryPort {}

final class _UnusedStorage extends Fake implements RemoteStoragePort {}

final class _UnusedQuota extends Fake implements UploadQuotaRepositoryPort {}
