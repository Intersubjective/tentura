@Tags(['pg'])
library;

import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_post.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_beacon_room.dart';
import 'package:tentura_server/consts.dart'
    show kAvatarPlaceholderUrl, kImageExt, kImageServer, kImagesPath;
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

const _author = 'UsumAuthor001';
const _bob = 'UsumBob00001';
const _seen = 'UsumSeen0001';
const _inviter = 'UsumInvite01';
const _writer = 'UsumWriter01';
const _idle = 'UsumIdle0001';
const _declined = 'UsumDecline1';
const _otherDeclined = 'UsumDecline2';
const _outsider = 'UsumOutside1';
const _post = 'BsumMembers01';
const _avatar = '00112233-4455-6677-8899-aabbccddeeff';

String _avatarFor(String id) => id == _writer
    ? '$kImageServer/$kImagesPath/$_writer/$_avatar.$kImageExt'
    : kAvatarPlaceholderUrl;
const _members = [_bob, _seen, _inviter, _writer, _idle];

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_PARTICIPANT_SUMMARY_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_participant_summary',
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
      logger: Logger('PostParticipantSummaryPgTest'),
    );
  });

  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: database);
  });

  setUp(() async {
    await writer.execute('TRUNCATE public."user" CASCADE');
    final users = [_author, ..._members, _declined, _otherDeclined, _outsider];
    for (final (index, id) in users.indexed) {
      await writer.execute(
        Sql.named('''
          INSERT INTO public."user" (id, display_name, public_key)
          VALUES (@id, @name, @key)
        '''),
        parameters: {
          'id': id,
          'name': 'Name $id',
          'key': pgTestPublicKey('post-participant-summary', index + 1),
        },
      );
    }
    await writer.execute('''
      INSERT INTO public.image (id, author_id) VALUES ('$_avatar', '$_writer')
    ''');
    await writer.execute('''
      UPDATE public."user" SET image_id = '$_avatar' WHERE id = '$_writer'
    ''');
    await writer.execute('''
      INSERT INTO public.beacon
        (id, user_id, title, description, status, kind, forward_policy,
         is_discoverable, published_at)
      VALUES ('$_post', '$_author', '', '', 0, 1, 1, false, now())
    ''');
    for (final (index, id) in [
      ..._members,
      _declined,
      _otherDeclined,
    ].indexed) {
      await writer.execute(
        Sql.named('''
          INSERT INTO public.beacon_forward_edge
            (id, beacon_id, sender_id, recipient_id, created_at)
          VALUES (@edge, @post, @author, @recipient, '2030-01-01Z')
        '''),
        parameters: {
          'edge': 'FsumMember00$index',
          'post': _post,
          'author': _author,
          'recipient': id,
        },
      );
    }
    await writer.execute('''
      UPDATE public.beacon_forward_edge SET recipient_rejected = true
      WHERE beacon_id = '$_post'
        AND recipient_id IN ('$_declined', '$_otherDeclined')
    ''');
    await writer.execute('''
      INSERT INTO public.beacon_room_message
        (id, beacon_id, author_id, body, created_at)
      VALUES ('MsumRoot0001', '$_post', '$_author', 'A shared Post',
              '2030-01-01Z'),
             ('MsumReply001', '$_post', '$_writer', 'A reply',
              '2030-01-06Z')
    ''');
    await writer.execute('''
      UPDATE public.beacon SET post_root_message_id = 'MsumRoot0001'
      WHERE id = '$_post'
    ''');
    await writer.execute('''
      INSERT INTO public.beacon_room_seen (user_id, beacon_id, last_seen_at)
      VALUES ('$_seen', '$_post', '2030-01-03Z')
    ''');
    final bobSeenBeforeActivity = await writer.execute('''
      SELECT count(*) FROM public.beacon_room_seen
      WHERE beacon_id = '$_post' AND user_id = '$_bob'
    ''');
    expect(
      bobSeenBeforeActivity.single.single,
      0,
      reason: 'Bob has no seen row before forwarding or creating an invite',
    );
    await writer.execute('''
      INSERT INTO public.beacon_forward_edge
        (id, beacon_id, sender_id, recipient_id, recipient_rejected, created_at)
      VALUES ('FsumBobOut01', '$_post', '$_bob', '$_declined', true,
              '2030-01-04Z')
    ''');
    // Declined addressees have no admitted room access; their historical
    // edges still contribute to the sender's declined-forward count.
    await writer.execute('''
      UPDATE public.beacon_participant SET room_access = 0
      WHERE beacon_id = '$_post'
        AND user_id IN ('$_declined', '$_otherDeclined')
    ''');
    await writer.execute('''
      INSERT INTO public.invitation (id, user_id, beacon_id, created_at)
      VALUES ('IsumInvite01', '$_inviter', '$_post', '2030-01-05Z')
    ''');
    // Activity order comes from the events above: a message on Jan 6,
    // an invite on Jan 5, a forward on Jan 4, and a seen event on Jan 3.
    // Membership timestamps are deliberately left as written by admission.
  });

  Future<Map<String, Object?>> summary(String viewer) async {
    final rows =
        await query.myPosts.resolve!(null, {
              kGlobalInputQueryJwt: JwtEntity(sub: viewer),
            })
            as List;
    expect(rows, hasLength(1));
    return Map<String, Object?>.from(rows.single as Map);
  }

  group('Post participant summaries', () {
    for (final viewer in [_author, _bob]) {
      test('${viewer == _author ? 'authors' : 'recipients'} see admitted '
          'participant counts excluding themselves', () async {
        final sheet = await room.listParticipants(
          beaconId: _post,
          userId: viewer,
        );
        final peers = sheet.where(
          (row) => row['roomAccess'] == 3 && row['userId'] != viewer,
        );
        expect(peers, hasLength(viewer == _author ? 5 : 4));
        final result = await summary(viewer);
        // The author has no participant row; a recipient counts them too.
        expect(
          result,
          containsPair(
            'participantCount',
            peers.length + (viewer == _author ? 0 : 1),
          ),
        );
      });
    }

    for (final sample in [
      (viewer: _author, role: 'authors', count: 1),
      (viewer: _bob, role: 'active recipients', count: 1),
      (viewer: _idle, role: 'inactive recipients', count: 0),
    ]) {
      test('${sample.role} see unopened counts excluding the viewer and '
          'nonadmitted members', () async {
        expect(
          await summary(sample.viewer),
          containsPair('notOpenedCount', sample.count),
        );
      });
    }

    for (final sample in [
      (viewer: _author, role: 'authors', count: 2),
      (viewer: _bob, role: 'forwarding recipients', count: 1),
      (viewer: _seen, role: 'recipients with no outgoing forwards', count: 0),
    ]) {
      test('${sample.role} see only their own declined forwards', () async {
        expect(
          await summary(sample.viewer),
          containsPair('myDeclinedForwardCount', sample.count),
        );
      });
    }

    test('a Post with no recipients reports zero counts and no participant '
        'previews', () async {
      await writer.execute('''
        INSERT INTO public.beacon
          (id, user_id, title, description, status, kind, is_discoverable,
           published_at)
        VALUES ('BsumEmpty001', '$_author', '', '', 0, 1, false, now())
      ''');
      await writer.execute('''
        INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
        VALUES ('MsumEmpty001', 'BsumEmpty001', '$_author', 'Only the author')
      ''');
      await writer.execute('''
        UPDATE public.beacon SET post_root_message_id = 'MsumEmpty001'
        WHERE id = 'BsumEmpty001'
      ''');
      final result = await query.postSummary.resolve!(null, {
        kGlobalInputQueryJwt: const JwtEntity(sub: _author),
        'id': 'BsumEmpty001',
      });
      expect(
        result,
        allOf(
          containsPair('id', 'BsumEmpty001'),
          containsPair('participantCount', 0),
          containsPair('notOpenedCount', 0),
          containsPair('myDeclinedForwardCount', 0),
          containsPair('previewParticipants', isEmpty),
        ),
      );
    });

    for (final sample in [
      (
        viewer: _author,
        role: 'authors',
        peers: [_writer, _inviter, _bob, _seen],
      ),
      (
        viewer: _writer,
        role: 'recipients',
        peers: [_inviter, _bob, _seen, _idle],
      ),
    ]) {
      test(
        '${sample.role} see four admitted peer previews in recent activity '
        'order even when declined members were more recently active',
        () async {
          // Both excluded members have seen activity after every admitted
          // peer's event, so LIMIT alone cannot exclude them.
          await writer.execute('''
          INSERT INTO public.beacon_room_seen (user_id, beacon_id, last_seen_at)
          VALUES ('$_declined', '$_post', '2030-01-09Z'),
                 ('$_otherDeclined', '$_post', '2030-01-10Z')
        ''');
          final sheet = await room.listParticipants(
            beaconId: _post,
            userId: sample.viewer,
          );
          for (final id in [_declined, _otherDeclined]) {
            expect(
              sheet.singleWhere((row) => row['userId'] == id)['roomAccess'],
              isNot(3),
            );
          }
          final result = await summary(sample.viewer);
          expect(result['previewParticipants'], [
            for (final id in sample.peers)
              allOf(
                containsPair('id', id),
                containsPair('displayName', 'Name $id'),
                containsPair('avatar', _avatarFor(id)),
              ),
          ]);
          expect(
            result['previewParticipants'],
            isNot(contains(containsPair('id', sample.viewer))),
          );
          for (final id in [_declined, _otherDeclined]) {
            expect(
              result['previewParticipants'],
              isNot(contains(containsPair('id', id))),
            );
          }
        },
      );
    }

    test('a new room reply moves its author ahead of previously more active '
        'peer previews', () async {
      await writer.execute('''
        INSERT INTO public.beacon_room_message
          (id, beacon_id, author_id, body, created_at)
        VALUES ('MsumNewReply1', '$_post', '$_seen', 'The newest reply',
                '2030-01-07Z')
      ''');
      final result = await summary(_author);
      expect(result['previewParticipants'], [
        for (final id in [_seen, _writer, _inviter, _bob])
          allOf(
            containsPair('id', id),
            containsPair('displayName', 'Name $id'),
            containsPair('avatar', _avatarFor(id)),
          ),
      ]);
    });

    for (final sample in [
      (
        viewer: _author,
        role: 'authors',
        participants: 5,
        declined: 2,
        peers: [_writer, _inviter, _bob, _seen],
      ),
      (
        viewer: _bob,
        role: 'forwarding recipients',
        participants: 5,
        declined: 1,
        peers: [_writer, _inviter, _seen, _idle],
      ),
      (
        viewer: _writer,
        role: 'replying recipients',
        participants: 5,
        declined: 0,
        peers: [_inviter, _bob, _seen, _idle],
      ),
    ]) {
      test('${sample.role} receive populated counts and peer identities from '
          'the single Post summary as well as the Post list', () async {
        final result = await query.postSummary.resolve!(null, {
          kGlobalInputQueryJwt: JwtEntity(sub: sample.viewer),
          'id': _post,
        });
        expect(
          result,
          allOf(
            containsPair('id', _post),
            containsPair('participantCount', sample.participants),
            containsPair('notOpenedCount', 1),
            containsPair('myDeclinedForwardCount', sample.declined),
            containsPair('previewParticipants', [
              for (final id in sample.peers)
                allOf(
                  containsPair('id', id),
                  containsPair('displayName', 'Name $id'),
                  containsPair('avatar', _avatarFor(id)),
                ),
            ]),
          ),
        );
        final listRow = await summary(sample.viewer);
        for (final field in [
          'participantCount',
          'notOpenedCount',
          'myDeclinedForwardCount',
          'previewParticipants',
        ]) {
          expect((result as Map)[field], listRow[field], reason: field);
        }
      });
    }

    test('GraphQL serves counts and preview identities to a Post member '
        'and hides the summary from outsiders', () async {
      await expectLater(
        room.listParticipants(beaconId: _post, userId: _outsider),
        throwsA(isA<UnauthorizedException>()),
      );
      final graphQL = GraphQL(
        GraphQLSchema(
          queryType: GraphQLObjectType('Query', null)..fields.addAll(query.all),
        ),
      );
      const operation =
          '{ myPosts { id participantCount notOpenedCount '
          'myDeclinedForwardCount previewParticipants { id displayName avatar } } }';
      final response = await graphQL.parseAndExecute(
        operation,
        globalVariables: {
          kGlobalInputQueryJwt: const JwtEntity(sub: _author),
        },
      );
      expect(response, {
        'myPosts': [
          {
            'id': _post,
            'participantCount': 5,
            'notOpenedCount': 1,
            'myDeclinedForwardCount': 2,
            'previewParticipants': [
              for (final id in [_writer, _inviter, _bob, _seen])
                {
                  'id': id,
                  'displayName': 'Name $id',
                  'avatar': _avatarFor(id),
                },
            ],
          },
        ],
      });
      expect(
        await graphQL.parseAndExecute(
          operation,
          globalVariables: {
            kGlobalInputQueryJwt: const JwtEntity(sub: _outsider),
          },
        ),
        {'myPosts': <Object>[]},
      );
    });
  });

  group('Post opened status from room and sharing activity', () {
    test('the participant query exposes opened status for the sheet', () async {
      final graphQL = GraphQL(
        GraphQLSchema(
          queryType: GraphQLObjectType('Query', null)
            ..fields.add(
              QueryBeaconRoom(beaconRoomCase: room).beaconParticipantList,
            ),
        ),
      );
      final response = await graphQL.parseAndExecute(
        '{ BeaconParticipantList(beaconId: "$_post") { userId opened } }',
        globalVariables: {
          kGlobalInputQueryJwt: const JwtEntity(sub: _author),
        },
      );
      expect(
        response,
        containsPair(
          'BeaconParticipantList',
          allOf(
            contains(equals({'userId': _bob, 'opened': true})),
            contains(equals({'userId': _idle, 'opened': false})),
          ),
        ),
      );
    });

    for (final sample in [
      (id: _seen, behavior: 'a room seen row', opened: true),
      (
        id: _bob,
        behavior: 'an outgoing forward without a seen row',
        opened: true,
      ),
      (id: _inviter, behavior: 'an invite without a seen row', opened: true),
      (
        id: _writer,
        behavior: 'a room message without a seen row',
        opened: true,
      ),
      (id: _idle, behavior: 'no seen row or outgoing activity', opened: false),
    ]) {
      test('${sample.behavior} determines opened status without changing '
          'the read cursor', () async {
        final repository = BeaconRoomRepository(database);
        final before = await repository.getMainRoomLastSeen(
          beaconId: _post,
          userId: sample.id,
        );
        expect(before, sample.id == _seen ? isNotNull : isNull);
        if (sample.id == _inviter) {
          final activity = await writer.execute('''
            SELECT
              (SELECT count(*) FROM public.beacon_forward_edge
               WHERE beacon_id = '$_post' AND sender_id = '$_inviter'),
              (SELECT count(*) FROM public.beacon_room_message
               WHERE beacon_id = '$_post' AND author_id = '$_inviter'),
              (SELECT count(*) FROM public.invitation
               WHERE beacon_id = '$_post' AND user_id = '$_inviter')
          ''');
          expect(activity.single.toList(), [
            0,
            0,
            1,
          ], reason: 'The invite is the only opened signal for this member');
        }
        final sheet = await room.listParticipants(
          beaconId: _post,
          userId: _author,
        );
        final member = sheet.singleWhere((row) => row['userId'] == sample.id);
        expect(member, containsPair('opened', sample.opened));
        final notOpened = sheet
            .where(
              (row) =>
                  row['roomAccess'] == 3 &&
                  row['userId'] != _author &&
                  row['opened'] == false,
            )
            .length;
        expect(notOpened, 1);
        expect(
          await summary(_author),
          containsPair('notOpenedCount', notOpened),
        );
        expect(
          await repository.getMainRoomLastSeen(
            beaconId: _post,
            userId: sample.id,
          ),
          before,
        );
      });
    }

    test('activity in another Post does not open this Post or change its '
        'summary counts', () async {
      await writer.execute('''
        INSERT INTO public.beacon
          (id, user_id, title, description, status, kind, is_discoverable,
           published_at)
        VALUES ('BsumOther001', '$_author', '', '', 0, 1, false, now())
      ''');
      await writer.execute('''
        INSERT INTO public.beacon_forward_edge
          (id, beacon_id, sender_id, recipient_id)
        VALUES ('FsumOther001', 'BsumOther001', '$_author', '$_idle')
      ''');
      await writer.execute('''
        INSERT INTO public.beacon_room_seen (user_id, beacon_id, last_seen_at)
        VALUES ('$_idle', 'BsumOther001', now())
      ''');
      await writer.execute('''
        INSERT INTO public.invitation (id, user_id, beacon_id)
        VALUES ('IsumOther001', '$_idle', 'BsumOther001')
      ''');
      await writer.execute('''
        INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
        VALUES ('MsumOther001', 'BsumOther001', '$_idle', 'Another conversation')
      ''');
      final sheet = await room.listParticipants(
        beaconId: _post,
        userId: _author,
      );
      expect(
        sheet.singleWhere((row) => row['userId'] == _idle),
        containsPair('opened', false),
      );
      // Query all cards, as My Posts does, so an aggregate leaking across
      // different Posts cannot satisfy the expected row.
      final rows =
          await query.myPosts.resolve!(null, {
                kGlobalInputQueryJwt: const JwtEntity(sub: _author),
              })
              as List;
      expect(
        rows.where((row) => (row as Map)['id'] == _post).single,
        allOf(
          containsPair('participantCount', 5),
          containsPair('notOpenedCount', 1),
          containsPair('myDeclinedForwardCount', 2),
        ),
      );
    });

    test('an invite alone removes an inactive member from the unopened '
        'summary count without marking the room seen', () async {
      final otherSignals = await writer.execute('''
        SELECT
          (SELECT count(*) FROM public.beacon_room_seen
           WHERE beacon_id = '$_post' AND user_id = '$_idle'),
          (SELECT count(*) FROM public.beacon_forward_edge
           WHERE beacon_id = '$_post' AND sender_id = '$_idle'),
          (SELECT count(*) FROM public.beacon_room_message
           WHERE beacon_id = '$_post' AND author_id = '$_idle'),
          (SELECT count(*) FROM public.invitation
           WHERE beacon_id = '$_post' AND user_id = '$_idle')
      ''');
      expect(otherSignals.single.toList(), [0, 0, 0, 0]);
      await writer.execute('''
        INSERT INTO public.invitation (id, user_id, beacon_id)
        VALUES ('IsumIdle0001', '$_idle', '$_post')
      ''');
      expect(
        await BeaconRoomRepository(database).getMainRoomLastSeen(
          beaconId: _post,
          userId: _idle,
        ),
        isNull,
      );
      expect(await summary(_author), containsPair('notOpenedCount', 0));
      final sheet = await room.listParticipants(
        beaconId: _post,
        userId: _author,
      );
      expect(
        sheet.singleWhere((row) => row['userId'] == _idle),
        containsPair('opened', true),
      );
    });

    test('forwarding and creating an invite count as opened while the '
        'seen row remains absent', () async {
      final seenBeforeInvite = await writer.execute('''
        SELECT count(*) FROM public.beacon_room_seen
        WHERE beacon_id = '$_post' AND user_id = '$_bob'
      ''');
      expect(
        seenBeforeInvite.single.single,
        0,
        reason: 'Forwarding left Bob without a seen row before inviting',
      );
      await writer.execute('''
        INSERT INTO public.invitation (id, user_id, beacon_id)
        VALUES ('IsumBob00001', '$_bob', '$_post')
      ''');
      final seen = await writer.execute('''
        SELECT count(*) FROM public.beacon_room_seen
        WHERE beacon_id = '$_post' AND user_id = '$_bob'
      ''');
      expect(
        seen.single.single,
        0,
        reason: 'Activity did not mark the chat read',
      );
      final sheet = await room.listParticipants(
        beaconId: _post,
        userId: _author,
      );
      expect(
        sheet.singleWhere((row) => row['userId'] == _bob),
        containsPair('opened', true),
      );
      expect(await summary(_author), containsPair('notOpenedCount', 1));
    });
  });
}

final class _UnusedFactCards extends Fake
    implements BeaconFactCardRepositoryPort {}

final class _UnusedImages extends Fake implements ImageRepositoryPort {}

final class _UnusedTasks extends Fake implements TaskRepositoryPort {}

final class _UnusedStorage extends Fake implements RemoteStoragePort {}

final class _UnusedQuota extends Fake implements UploadQuotaRepositoryPort {}
