@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_repository.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'Ucardunread01';
const _viewer = 'Ucardunread02';
const _post = 'Bcardunread01';

/// A conversation card's unread count and its latest-message preview describe
/// the same messages: system lines (status notices and the like) are shown in
/// neither, so a card never says «2 unread» next to a preview with nothing new.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_CARD_UNREAD_COUNT_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_card_unread',
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
        parameters: {
          'id': id,
          'key': pgTestPublicKey('card-unread', index + 1),
        },
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
      VALUES ('Fcardunread01', '$_post', '$_author', '$_viewer')
    ''');
    await writer.execute('''
      INSERT INTO public.beacon_room_message
        (id, beacon_id, author_id, body, created_at)
      VALUES ('Mcardunreadroot', '$_post', '$_author', 'Root text',
              '2030-01-01T00:00:00Z')
    ''');
    await writer.execute('''
      UPDATE public.beacon SET post_root_message_id = 'Mcardunreadroot'
      WHERE id = '$_post'
    ''');
    // The viewer has read everything up to and including the root.
    await writer.execute('''
      INSERT INTO public.beacon_room_seen
        (user_id, beacon_id, thread_item_id, last_seen_at)
      VALUES ('$_viewer', '$_post', NULL, '2030-01-01T00:00:00Z')
    ''');
  });

  Future<void> addSystemLines() => writer.execute('''
    INSERT INTO public.beacon_room_message
      (id, beacon_id, author_id, body, system_message_kind, created_at)
    VALUES ('Mcardunreadsys1', '$_post', '$_author', 'Notice one', 1,
            '2030-01-03T00:00:00Z'),
           ('Mcardunreadsys2', '$_post', '$_author', 'Notice two', 1,
            '2030-01-04T00:00:00Z')
  ''');

  test('a card whose only unread lines are system lines counts none', () async {
    await addSystemLines();

    final card = (await beacons.myPosts(_viewer)).single;

    expect(card.unreadCount, 0);
  });

  test('one user message among system lines counts as one unread, '
      'and the preview shows that same message', () async {
    await writer.execute('''
      INSERT INTO public.beacon_room_message
        (id, beacon_id, author_id, body, created_at)
      VALUES ('Mcardunreadmsg1', '$_post', '$_author', 'Fresh reply',
              '2030-01-02T00:00:00Z')
    ''');
    await addSystemLines();

    final card = (await beacons.myPosts(_viewer)).single;

    expect(card.unreadCount, 1);
    expect(card.lastMessageExcerpt, 'Fresh reply');
    expect(card.lastMessageAt, DateTime.utc(2030, 1, 2));
  });

  test('without a read cursor, system lines still add nothing to the '
      'count of the one message the preview can show', () async {
    await writer.execute(
      "DELETE FROM public.beacon_room_seen WHERE beacon_id = '$_post'",
    );
    await addSystemLines();

    final card = (await beacons.myPosts(_viewer)).single;

    expect(card.unreadCount, 1);
    expect(card.lastMessageExcerpt, 'Root text');
  });
}
