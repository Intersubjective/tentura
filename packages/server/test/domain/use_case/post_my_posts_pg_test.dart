@Tags(['pg'])
library;

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/consts.dart'
    show kAvatarPlaceholderUrl, kImageExt, kImageServer, kImagesPath;
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/capability_evidence_repository.dart';
import 'package:tentura_server/data/repository/forward_attribution_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/person_visibility_repository.dart';
import 'package:tentura_server/data/repository/post_lock_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/post_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'Upostsauthor01';
const _member = 'Upostsmember01';
const _stranger = 'Upoststrange01';
const _post = 'Bpostsquery01';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_MY_POSTS_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_my_posts',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  late DisposablePgWriterSession session;
  late TenturaDb database;
  late Connection writer;
  late PostCase posts;
  setUpAll(() async {
    session = await setUpDisposablePgWriter(
      target: target,
      lastInclusiveVersion: '0214',
    );
    writer = session.writer;
    await migrateDbSchema(writer);
    database = openDisposablePgDatabase(target);
    posts = PostCase(
      forwardCase: ForwardCase(
        ForwardEdgeRepository(database),
        ForwardAttributionRepository(database),
        HelpOfferRepository(database),
        InboxRepository(database),
        CapabilityEvidenceRepository(database),
        BeaconRepository(database),
        UserBlockRepository(target.databaseEnv, database),
        PersonVisibilityRepository(database),
        BeaconAccessRepository(database),
        env: target.databaseEnv,
        logger: Logger('PostMyPostsPgTest'),
      ),
      roomCase: _UnusedRoom(),
      beaconRepository: BeaconRepository(database),
      postLock: PostLockRepository(database),
      attention: _UnusedAttention(),
    );
  });
  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: database);
  });
  setUp(() async {
    await writer.execute('TRUNCATE public."user" CASCADE');
    for (final (index, id) in [_author, _member, _stranger].indexed) {
      await writer.execute(
        Sql.named('''
          INSERT INTO public."user" (id, display_name, public_key)
          VALUES (@id, @id, @key)
        '''),
        parameters: {'id': id, 'key': pgTestPublicKey('my-posts', index + 1)},
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
      VALUES ('Fpostsquery01', '$_post', '$_author', '$_member')
    ''');
    await writer.execute('''
      INSERT INTO public.beacon_room_message
        (id, beacon_id, author_id, body, created_at)
      VALUES ('Mpostsroot001', '$_post', '$_author', 'Root text',
              '2030-01-01T00:00:00Z'),
             ('Mpostsself001', '$_post', '$_member', 'My reply',
              '2030-01-02T00:00:00Z'),
             ('Mpostslast001', '$_post', '$_author', 'Latest text',
              '2030-01-03T00:00:00Z')
    ''');
    await writer.execute('''
      UPDATE public.beacon SET post_root_message_id = 'Mpostsroot001'
      WHERE id = '$_post'
    ''');
  });

  test('upgrade from 0214 exposes executable myPosts projection', () async {
    expect(await posts.myPosts(_author), hasLength(1));
  });
  test(
    'author and admitted addressee see the Post; stranger does not',
    () async {
      final author = (await posts.myPosts(_author)).single;
      final member = (await posts.myPosts(_member)).single;
      expect(author.id, _post);
      expect(author.authorId, _author);
      expect(author.authorName, _author);
      expect(author.authorAvatar, kAvatarPlaceholderUrl);
      expect(author.isAuthor, isTrue);
      expect(member.isAuthor, isFalse);
      expect(member.rootExcerpt, 'Root text');
      expect(member.lastMessageExcerpt, 'Latest text');
      expect(member.lastMessageAt, DateTime.utc(2030, 1, 3));
      expect(member.lastActivityAt, DateTime.utc(2030, 1, 3));
      expect(member.pinnedAt, isNull);
      expect(member.mutedUntil, isNull);
      expect(member.unreadCount, 2);
      expect(author.unreadCount, 1);
      expect(await posts.myPosts(_stranger), isEmpty);
    },
  );
  test(
    'conversation image comes from root attachments in position order',
    () async {
      await writer.execute('''
INSERT INTO public.image (id, author_id) VALUES
  ('00000000-0000-0000-0000-000000000001', '$_member'),
  ('00000000-0000-0000-0000-000000000002', '$_author'),
  ('00000000-0000-0000-0000-000000000003', '$_author')
''');
      await writer.execute('''
INSERT INTO public.beacon_room_message_attachment
  (id, message_id, kind, image_id, position) VALUES
  ('Asecond', 'Mpostsroot001', 1, '00000000-0000-0000-0000-000000000002', 2),
  ('Afirst', 'Mpostsroot001', 1, '00000000-0000-0000-0000-000000000001', 1),
  ('Alatest', 'Mpostslast001', 1, '00000000-0000-0000-0000-000000000003', 0)
''');
      final post = (await posts.myPosts(_member)).single;
      expect(
        post.rootImageUrl,
        '$kImageServer/$kImagesPath/$_member/00000000-0000-0000-0000-000000000001.$kImageExt',
      );
      expect(await posts.myPosts(_stranger), isEmpty);
    },
  );

  test('conversation without root images has no thumbnail URL', () async {
    expect((await posts.myPosts(_member)).single.rootImageUrl, isNull);
  });

  test('left and unadmitted addressees do not see the Post', () async {
    for (final access in [5, 0]) {
      await writer.execute('''
        UPDATE public.beacon_participant SET room_access = $access
        WHERE beacon_id = '$_post' AND user_id = '$_member'
      ''');
      expect(await posts.myPosts(_member), isEmpty);
    }
  });
  test(
    'an admitted participant without the addressee role is excluded',
    () async {
      await writer.execute(
        "UPDATE public.beacon_participant SET role = 2 WHERE beacon_id = '$_post' AND user_id = '$_member'",
      );
      expect(await posts.myPosts(_member), isEmpty);
    },
  );
  test('projects the author avatar URL', () async {
    const image = '00112233-4455-6677-8899-aabbccddeeff';
    await writer.execute(
      "INSERT INTO public.image (id, author_id) VALUES ('$image', '$_author')",
    );
    await writer.execute(
      "UPDATE public.\"user\" SET image_id = '$image' WHERE id = '$_author'",
    );
    final post = (await posts.myPosts(_member)).single;
    expect(
      post.authorAvatar,
      '$kImageServer/$kImagesPath/$_author/$image.$kImageExt',
    );
  });
  test('blocks in either direction hide the Post', () async {
    for (final (blocker, blocked) in [
      (_author, _member),
      (_member, _author),
    ]) {
      await writer.execute('TRUNCATE public.user_block');
      await writer.execute('''
        INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
        VALUES ('$blocker', '$blocked', '$blocker')
      ''');
      expect(await posts.myPosts(_member), isEmpty);
    }
  });
  test('viewer pin, mute and General unread cursor are projected', () async {
    await writer.execute('''
      INSERT INTO public.beacon_pinned (user_id, beacon_id, pinned_at)
      VALUES ('$_member', '$_post', '2030-02-01T00:00:00Z')
    ''');
    await writer.execute('''
      INSERT INTO public.notification_beacon_mute
        (account_id, beacon_id, muted_until)
      VALUES ('$_member', '$_post', '2030-03-01T00:00:00Z')
    ''');
    await writer.execute('''
      INSERT INTO public.beacon_room_seen
        (user_id, beacon_id, thread_item_id, last_seen_at)
      VALUES ('$_member', '$_post', NULL, '2030-01-01T00:00:00Z')
    ''');
    final member = (await posts.myPosts(_member)).single;
    expect(member.pinnedAt, DateTime.utc(2030, 2));
    expect(member.mutedUntil, DateTime.utc(2030, 3));
    expect(member.unreadCount, 1);
    final room = BeaconRoomRepository(database);
    expect(
      member.unreadCount,
      await room.countRoomMessagesAfter(
        beaconId: _post,
        after: await room.getMainRoomLastSeen(beaconId: _post, userId: _member),
        excludeAuthorId: _member,
      ),
    );
    final author = (await posts.myPosts(_author)).single;
    expect(author.pinnedAt, isNull);
    expect(author.mutedUntil, isNull);
  });
  test('a mute with no expiry reads as muted for good', () async {
    final before = (await posts.myPosts(_member)).single;
    expect(before.mutedForever, isFalse);
    await writer.execute('''
      INSERT INTO public.notification_beacon_mute
        (account_id, beacon_id, muted_until)
      VALUES ('$_member', '$_post', NULL)
      ON CONFLICT (account_id, beacon_id) DO UPDATE SET muted_until = NULL
    ''');
    final member = (await posts.myPosts(_member)).single;
    expect(member.mutedUntil, isNull);
    expect(member.mutedForever, isTrue);
    final author = (await posts.myPosts(_author)).single;
    expect(author.mutedForever, isFalse);
  });
  test('postSummary returns one row, or null for a non-member', () async {
    final member = await posts.postSummary(viewerId: _member, beaconId: _post);
    expect(member?.id, _post);
    expect(member?.isAuthor, isFalse);
    final author = await posts.postSummary(viewerId: _author, beaconId: _post);
    expect(author?.isAuthor, isTrue);
    expect(
      await posts.postSummary(viewerId: _stranger, beaconId: _post),
      isNull,
    );
    expect(
      await posts.postSummary(viewerId: _member, beaconId: 'Bpostsmissing'),
      isNull,
    );
  });
  test('draft, deleted and converted Request rows are excluded', () async {
    for (final status in [3, 2]) {
      await writer.execute(
        "UPDATE public.beacon SET status = $status WHERE id = '$_post'",
      );
      expect(await posts.myPosts(_author), isEmpty);
    }
    await writer.execute(
      "UPDATE public.beacon SET kind = 0, status = 0 WHERE id = '$_post'",
    );
    expect(await posts.myPosts(_author), isEmpty);
    expect(await posts.myPosts(_member), isEmpty);
  });
}

final class _UnusedRoom extends Fake implements BeaconRoomCase {}

final class _UnusedAttention extends Fake
    implements TransactionalAttentionCase {}
