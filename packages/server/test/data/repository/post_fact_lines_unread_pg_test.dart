@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/room_unread_sql.dart';
import 'package:tentura_server/domain/entity/post_summary.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'Upostfactauth1';
const _viewer = 'Upostfactview1';
const _post = 'Bpostfactline1';
const _root = 'Mpostfactroot1';
const _reply = 'Mpostfactrepl1';
const _line = 'Mpostfactline1';

/// Chat lines that announce fact changes; the Posts list and the Field must
/// treat them as invisible activity.
const _factLineMarkers = {
  'pinFactPublic': BeaconRoomSemanticMarker.pinFactPublic,
  'pinFactPrivate': BeaconRoomSemanticMarker.pinFactPrivate,
  'factEdited': BeaconRoomSemanticMarker.factEdited,
  'factUnpinned': BeaconRoomSemanticMarker.factUnpinned,
  'factsBrought': BeaconRoomSemanticMarker.factsBrought,
};

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_FACT_LINES_UNREAD_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_fact_lines',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  late DisposablePgWriterSession session;
  late TenturaDb database;
  late Connection writer;
  late BeaconRepository beacons;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    database = openDisposablePgDatabase(target);
    beacons = BeaconRepository(database);
  });
  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: database);
  });

  setUp(() async {
    await writer.execute('TRUNCATE public."user" CASCADE');
    for (final (index, id) in [_author, _viewer].indexed) {
      await writer.execute(
        Sql.named('''
          INSERT INTO public."user" (id, display_name, public_key)
          VALUES (@id, @id, @key)
        '''),
        parameters: {'id': id, 'key': pgTestPublicKey('post-facts', index + 1)},
      );
    }
    await writer.execute('''
      INSERT INTO public.beacon
        (id, user_id, title, description, status, kind, is_discoverable,
         published_at)
      VALUES ('$_post', '$_author', '', '', 0, 1, false, now())
    ''');
    await writer.execute('''
      INSERT INTO public.beacon_forward_edge
        (id, beacon_id, sender_id, recipient_id)
      VALUES ('Fpostfactline1', '$_post', '$_author', '$_viewer')
    ''');
    await writer.execute('''
      INSERT INTO public.beacon_room_message
        (id, beacon_id, author_id, body, created_at)
      VALUES ('$_root', '$_post', '$_author', 'Root text',
              '2030-01-01T00:00:00Z')
    ''');
    await writer.execute('''
      UPDATE public.beacon SET post_root_message_id = '$_root'
      WHERE id = '$_post'
    ''');
    // The viewer has opened the Post and read up to the root.
    await writer.execute('''
      INSERT INTO public.beacon_room_seen
        (user_id, beacon_id, thread_item_id, last_seen_at)
      VALUES ('$_viewer', '$_post', NULL, '2030-01-01T12:00:00Z')
    ''');
  });

  Future<PostSummary> summary() async =>
      (await beacons.postSummary(viewerId: _viewer, beaconId: _post))!;

  Future<bool> fieldHasUnread() async =>
      (await writer.execute(
            Sql(
              'SELECT ${fieldPostHasUnreadSql()} '
              r'FROM public.beacon b WHERE b.id = $2',
            ),
            parameters: [_viewer, _post],
          )).single.single!
          as bool;

  Future<void> insertMessage({
    required String id,
    required String body,
    required int? marker,
    required String createdAt,
  }) => writer.execute(
    Sql.named('''
      INSERT INTO public.beacon_room_message
        (id, beacon_id, author_id, body, semantic_marker, created_at)
      VALUES (@id, '$_post', '$_author', @body, @marker::smallint,
              @createdAt::timestamptz)
    '''),
    parameters: {
      'id': id,
      'body': body,
      'marker': marker,
      'createdAt': createdAt,
    },
  );

  // PostSummary does not carry the id; read it from the same projection.
  Future<String?> lastMessageId() async =>
      (await writer.execute(
            Sql(
              r'SELECT last_message_id FROM public.post_my_posts($1) '
              r'WHERE id = $2',
            ),
            parameters: [_viewer, _post],
          )).single.single
          as String?;

  Future<Map<String, Object?>> listView(PostSummary s) async => {
    'lastMessageId': await lastMessageId(),
    'lastMessageAt': s.lastMessageAt,
    'lastMessageExcerpt': s.lastMessageExcerpt,
    'lastMessageIsRoot': s.lastMessageIsRoot,
    'unreadCount': s.unreadCount,
  };

  group('Fact lines do not change a Post in the Posts list or the Field', () {
    for (final MapEntry(key: name, value: marker) in _factLineMarkers.entries) {
      test('a $name line (marker $marker) leaves the latest message, '
          'unread count and Field flag unchanged', () async {
        final before = await listView(await summary());
        expect(before, {
          'lastMessageId': _root,
          'lastMessageAt': DateTime.utc(2030),
          'lastMessageExcerpt': 'Root text',
          'lastMessageIsRoot': true,
          'unreadCount': 0,
        });
        expect(await fieldHasUnread(), isFalse);

        await insertMessage(
          id: _line,
          body: '',
          marker: marker,
          createdAt: '2030-01-02T00:00:00Z',
        );

        expect(await listView(await summary()), before);
        expect(await fieldHasUnread(), isFalse);
      });
    }

    test('a fact line after a reply keeps that reply as the latest '
        'message', () async {
      await insertMessage(
        id: _reply,
        body: 'Reply text',
        marker: null,
        createdAt: '2030-01-02T00:00:00Z',
      );
      await insertMessage(
        id: _line,
        body: '',
        marker: BeaconRoomSemanticMarker.pinFactPublic,
        createdAt: '2030-01-03T00:00:00Z',
      );
      expect(await listView(await summary()), {
        'lastMessageId': _reply,
        'lastMessageAt': DateTime.utc(2030, 1, 2),
        'lastMessageExcerpt': 'Reply text',
        'lastMessageIsRoot': false,
        'unreadCount': 1,
      });
    });
  });

  group('Other messages still update the Posts list and the Field', () {
    for (final (name, marker) in [
      ('an ordinary message', null),
      ('a plan update line (marker 1)', BeaconRoomSemanticMarker.updatePlan),
    ]) {
      test('$name becomes the latest message and counts as unread', () async {
        await insertMessage(
          id: _reply,
          body: 'Something new',
          marker: marker,
          createdAt: '2030-01-02T00:00:00Z',
        );
        expect(await listView(await summary()), {
          'lastMessageId': _reply,
          'lastMessageAt': DateTime.utc(2030, 1, 2),
          'lastMessageExcerpt': 'Something new',
          'lastMessageIsRoot': false,
          'unreadCount': 1,
        });
        expect(await fieldHasUnread(), isTrue);
      });
    }
  });
}
