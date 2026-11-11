@Tags(['pg'])
library;

import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_post.dart';
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
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/post_summary.dart';
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

  group('Authors can list unpublished Posts with previews', () {
    const draftId = 'Bpostsdraft01';

    Future<void> addDraft({String description = 'Draft text'}) async {
      await writer.execute(
        Sql.named('''
          INSERT INTO public.beacon
            (id, user_id, title, description, status, kind, is_discoverable)
          VALUES (@id, @author, '', @description, 3, 1, false)
        '''),
        parameters: {
          'id': draftId,
          'author': _author,
          'description': description,
        },
      );
    }

    Future<PostSummary> authorDraft() async {
      final rows = await posts.myPosts(_author);
      expect(
        rows.map((row) => row.id),
        contains(draftId),
        reason: "myPosts must include the author's unpublished Post",
      );
      return rows.singleWhere((row) => row.id == draftId);
    }

    test(
      'own unpublished Posts are listed with draft status',
      () async {
        await addDraft();
        final draft = await authorDraft();
        expect(draft.isAuthor, isTrue);
        expect(draft.authorId, _author);
        expect(draft.status, BeaconStatus.draft);
      },
    );

    test('GraphQL returns the author draft with status 3', () async {
      await addDraft();
      final graphQL = GraphQL(
        GraphQLSchema(
          queryType: GraphQLObjectType('Query', null)
            ..fields.addAll(QueryPost(postCase: posts).all),
        ),
      );
      final response = await graphQL.parseAndExecute(
        '{ myPosts { id isAuthor status rootExcerpt } }',
        globalVariables: {
          kGlobalInputQueryJwt: const JwtEntity(sub: _author),
        },
      );
      expect(response, {
        'myPosts': unorderedEquals([
          {
            'id': _post,
            'isAuthor': true,
            'status': 0,
            'rootExcerpt': 'Root text',
          },
          {
            'id': draftId,
            'isAuthor': true,
            'status': 3,
            'rootExcerpt': 'Draft text',
          },
        ]),
      });
    });

    test(
      'description supplies the excerpt while published roots retain theirs',
      () async {
        await addDraft();
        expect((await authorDraft()).rootExcerpt, 'Draft text');
        final published = (await posts.myPosts(
          _author,
        )).singleWhere((row) => row.id == _post);
        expect(published.rootExcerpt, 'Root text');
      },
    );

    test('description excerpts stop at 280 characters', () async {
      final prefix = List.filled(280, 'я').join();
      await addDraft(description: '${prefix}hidden suffix');
      expect((await authorDraft()).rootExcerpt, prefix);
    });

    test(
      'cover uses the earliest image position and image owner, skipping files',
      () async {
        await addDraft();
        await writer.execute('''
        INSERT INTO public.image (id, author_id) VALUES
          ('00000000-0000-0000-0000-000000000011', '$_member'),
          ('00000000-0000-0000-0000-000000000012', '$_author');
      ''');
        await writer.execute('''
        INSERT INTO public.post_draft_attachment
          (id, beacon_id, kind, image_id, file_url, position) VALUES
          ('AdraftSecond', '$draftId', 1,
           '00000000-0000-0000-0000-000000000012', NULL, 2),
          ('AdraftFirst', '$draftId', 1,
           '00000000-0000-0000-0000-000000000011', NULL, 1),
          ('AdraftFile', '$draftId', 2, NULL, 'https://files.test/draft.pdf', 0)
      ''');
        expect(
          (await authorDraft()).rootImageUrl,
          '$kImageServer/$kImagesPath/$_member/00000000-0000-0000-0000-000000000011.$kImageExt',
        );
      },
    );

    test('draft without attachments has no cover', () async {
      await addDraft();
      expect((await authorDraft()).rootImageUrl, isNull);
    });

    test('file-only draft has no cover', () async {
      await addDraft();
      await writer.execute('''
        INSERT INTO public.post_draft_attachment
          (id, beacon_id, kind, file_url, position)
        VALUES ('AdraftFile', '$draftId', 2, 'https://files.test/draft.pdf', 0)
      ''');
      expect((await authorDraft()).rootImageUrl, isNull);
    });

    test('picked addressee and stranger cannot see the author draft', () async {
      await addDraft();
      await writer.execute('''
        INSERT INTO public.beacon_forward_edge
          (id, beacon_id, sender_id, recipient_id)
        VALUES ('FdraftPicked', '$draftId', '$_author', '$_member')
      ''');
      await writer.execute('''
        INSERT INTO public.beacon_participant
          (id, beacon_id, user_id, role, status, room_access)
        VALUES ('PdraftPicked', '$draftId', '$_member', 6, 0, 3)
        ON CONFLICT (beacon_id, user_id)
          DO UPDATE SET role = 6, room_access = 3
      ''');
      // Check both negative paths before the positive control: omitting all
      // drafts must not make this privacy guarantee pass vacuously.
      final query = QueryPost(postCase: posts);
      final graphQL = GraphQL(
        GraphQLSchema(
          queryType: GraphQLObjectType('Query', null)..fields.addAll(query.all),
        ),
      );
      for (final viewer in [_member, _stranger]) {
        expect(
          (await posts.myPosts(viewer)).map((row) => row.id),
          isNot(contains(draftId)),
        );
        final resolved = await query.myPosts.resolve!(null, {
          kGlobalInputQueryJwt: JwtEntity(sub: viewer),
        });
        expect(
          resolved,
          viewer == _member ? [containsPair('id', _post)] : isEmpty,
          reason: 'the resolver must hide the draft from $viewer',
        );
        expect(
          await graphQL.parseAndExecute(
            '{ myPosts { id } }',
            globalVariables: {kGlobalInputQueryJwt: JwtEntity(sub: viewer)},
          ),
          {
            'myPosts': viewer == _member
                ? [
                    {'id': _post},
                  ]
                : <Map<String, Object?>>[],
          },
        );
      }
      expect((await authorDraft()).isAuthor, isTrue);
    });

    test(
      'General messages on a draft never contribute unread counts',
      () async {
        await addDraft();
        await writer.execute('''
        INSERT INTO public.beacon_room_message
          (id, beacon_id, author_id, body)
        VALUES ('MdraftReply', '$draftId', '$_member', 'Unread draft message')
      ''');
        expect((await authorDraft()).unreadCount, 0);
      },
    );

    test(
      'adding a draft preserves open Post unread counts and their total',
      () async {
        final before = await posts.myPosts(_author);
        final openUnread = before
            .singleWhere((row) => row.id == _post)
            .unreadCount;
        final totalUnread = before.fold<int>(
          0,
          (sum, row) => sum + row.unreadCount,
        );
        expect(openUnread, greaterThan(0));
        await addDraft();
        expect((await authorDraft()).unreadCount, 0);
        final after = await posts.myPosts(_author);
        expect(
          after.singleWhere((row) => row.id == _post).unreadCount,
          openUnread,
        );
        expect(
          after.fold<int>(0, (sum, row) => sum + row.unreadCount),
          totalUnread,
        );
      },
    );
  });

  group('Post summaries identify whether the last message is the root', () {
    setUp(() async {
      await writer.execute('''
        DELETE FROM public.beacon_room_message
        WHERE beacon_id = '$_post' AND id <> 'Mpostsroot001'
      ''');
    });

    Future<void> expectLastMessageIsRoot({required bool expected}) async {
      final query = QueryPost(postCase: posts);
      final rows = await query.myPosts.resolve!(null, {
        kGlobalInputQueryJwt: const JwtEntity(sub: _member),
      });
      // Observe the public summary rather than accessing a not-yet-added
      // entity getter, so the missing field produces an assertion failure.
      expect(rows, [
        allOf(
          containsPair('id', _post),
          containsPair('rootExcerpt', 'Root text'),
          containsPair('lastMessageExcerpt', 'Root text'),
          containsPair('lastMessageIsRoot', expected),
        ),
      ]);

      final graphQL = GraphQL(
        GraphQLSchema(
          queryType: GraphQLObjectType('Query', null)..fields.addAll(query.all),
        ),
      );
      final response = await graphQL.parseAndExecute(
        '{ myPosts { id lastMessageIsRoot } }',
        globalVariables: {
          kGlobalInputQueryJwt: const JwtEntity(sub: _member),
        },
      );
      expect(response, {
        'myPosts': [
          {'id': _post, 'lastMessageIsRoot': expected},
        ],
      });
    }

    test('a Post with only its root reports true', () async {
      await expectLastMessageIsRoot(expected: true);
    });

    test('a reply with the same text as the root reports false', () async {
      await writer.execute('''
        INSERT INTO public.beacon_room_message
          (id, beacon_id, author_id, body, created_at)
        VALUES ('Mpostsecho001', '$_post', '$_member', 'Root text',
                '2030-01-02T00:00:00Z')
      ''');
      await expectLastMessageIsRoot(expected: false);
    });

    test('a system message after the root still reports true', () async {
      await writer.execute('''
        INSERT INTO public.beacon_room_message
          (id, beacon_id, author_id, body, system_message_kind, created_at)
        VALUES ('Mpostsnotice1', '$_post', '$_author', 'Notice', 1,
                '2030-01-02T00:00:00Z')
      ''');
      await expectLastMessageIsRoot(expected: true);
    });
  });

  Future<void> seedForwardedPost() async {
    // The shared fixture already has Alice's Post and Alice -> Bob delivery.
    await writer.execute('''
      UPDATE public."user" SET display_name = CASE id
        WHEN '$_author' THEN 'QA Alice'
        WHEN '$_member' THEN 'Bob GQ'
        WHEN '$_stranger' THEN 'Carol'
      END
    ''');
    await writer.execute(
      Sql.named('''
        INSERT INTO public."user" (id, display_name, public_key)
        VALUES ('Upostseve0001', 'Eve', @key)
      '''),
      parameters: {'key': pgTestPublicKey('my-posts', 4)},
    );
    await writer.execute('''
      INSERT INTO public.beacon_forward_edge
        (id, beacon_id, sender_id, recipient_id)
      VALUES ('FpostsToEve01', '$_post', '$_member', 'Upostseve0001'),
             ('FpostsCarol01', '$_post', '$_author', '$_stranger')
    ''');
    // Post invitations are author-to-addressee deliveries: m0210 admits
    // Carol through this edge. beacon_author_invite belongs to budded
    // Requests (AuthorInviteCase rejects Posts), not Post invitations.
  }

  test(
    'myPosts names the intermediary forwarder only for indirect recipients',
    () async {
      await seedForwardedPost();
      final query = QueryPost(postCase: posts);
      final rowsByViewer = <String, Object?>{};
      for (final viewer in ['Upostseve0001', _member, _stranger]) {
        // Use the public resolver to observe the serialized summary without
        // referencing forwarder getters that do not exist on PostSummary yet.
        rowsByViewer[viewer] = await query.myPosts.resolve!(null, {
          kGlobalInputQueryJwt: JwtEntity(sub: viewer),
        });
      }
      Matcher summary({String? forwardedById, String? forwardedByName}) =>
          allOf(
            containsPair('id', _post),
            containsPair('authorId', _author),
            containsPair('authorName', 'QA Alice'),
            containsPair('forwardedById', forwardedById),
            containsPair('forwardedByName', forwardedByName),
          );
      expect(rowsByViewer, {
        'Upostseve0001': [
          summary(forwardedById: _member, forwardedByName: 'Bob GQ'),
        ],
        _member: [summary()],
        _stranger: [summary()],
      });
    },
  );

  test('myPosts GraphQL exposes nullable forwarder identity fields', () async {
    await seedForwardedPost();
    final graphQL = GraphQL(
      GraphQLSchema(
        queryType: GraphQLObjectType('Query', null)
          ..fields.addAll(QueryPost(postCase: posts).all),
      ),
    );
    for (final viewer in ['Upostseve0001', _member, _stranger]) {
      final response = await graphQL.parseAndExecute(
        '{ myPosts { id authorName forwardedById forwardedByName } }',
        globalVariables: {kGlobalInputQueryJwt: JwtEntity(sub: viewer)},
      );
      final indirect = viewer == 'Upostseve0001';
      expect(response, {
        'myPosts': [
          {
            'id': _post,
            'authorName': 'QA Alice',
            'forwardedById': indirect ? _member : null,
            'forwardedByName': indirect ? 'Bob GQ' : null,
          },
        ],
      });
    }
  });

  test(
    'myPosts selects the newest active non-author sender to the viewer',
    () async {
      await seedForwardedPost();
      await writer.execute('''
        UPDATE public.beacon_forward_edge
        SET created_at = '2030-01-01T00:00:00Z'
        WHERE id = 'FpostsToEve01'
      ''');
      await writer.execute('''
        INSERT INTO public.beacon_forward_edge
          (id, beacon_id, sender_id, recipient_id, created_at)
        VALUES
          ('FpostsNewEve1', '$_post', '$_stranger', 'Upostseve0001',
           '2030-01-02T00:00:00Z'),
          ('FpostsAuthEv1', '$_post', '$_author', 'Upostseve0001',
           '2030-01-03T00:00:00Z'),
          ('FpostsOther01', '$_post', 'Upostseve0001', '$_author',
           '2030-01-04T00:00:00Z')
      ''');
      final query = QueryPost(postCase: posts);
      final rowsByViewer = <String, Object?>{};
      for (final viewer in ['Upostseve0001', _member, _stranger]) {
        rowsByViewer[viewer] = await query.myPosts.resolve!(null, {
          kGlobalInputQueryJwt: JwtEntity(sub: viewer),
        });
      }
      Matcher summary({String? forwardedById, String? forwardedByName}) =>
          allOf(
            containsPair('id', _post),
            containsPair('authorName', 'QA Alice'),
            containsPair('forwardedById', forwardedById),
            containsPair('forwardedByName', forwardedByName),
          );
      expect(rowsByViewer, {
        'Upostseve0001': [
          summary(forwardedById: _stranger, forwardedByName: 'Carol'),
        ],
        _member: [summary()],
        _stranger: [summary()],
      });
    },
  );

  test('myPosts returns a latest sender when inbound timestamps tie', () async {
    await seedForwardedPost();
    await writer.execute(
      Sql.named('''
        INSERT INTO public."user" (id, display_name, public_key)
        VALUES ('Upostsdave001', 'Dave', @key)
      '''),
      parameters: {'key': pgTestPublicKey('my-posts', 5)},
    );
    await writer.execute('''
      UPDATE public.beacon_forward_edge
      SET created_at = '2030-01-02T00:00:00Z'
      WHERE id = 'FpostsToEve01'
    ''');
    await writer.execute('''
      INSERT INTO public.beacon_forward_edge
        (id, beacon_id, sender_id, recipient_id, created_at)
      VALUES
        ('FpostsToDave1', '$_post', '$_author', 'Upostsdave001',
         '2030-01-01T00:00:00Z'),
        ('FpostsDaveEv1', '$_post', 'Upostsdave001', 'Upostseve0001',
         '2030-01-01T00:00:00Z'),
        ('FpostsTieEve1', '$_post', '$_stranger', 'Upostseve0001',
         '2030-01-02T00:00:00Z')
    ''');
    final rows = await QueryPost(postCase: posts).myPosts.resolve!(null, {
      kGlobalInputQueryJwt: const JwtEntity(sub: 'Upostseve0001'),
    });
    // The contract and PostViewCase.latestTo specify creation time, with no
    // tie-breaker. Either newest sender is valid, with a matching id/name;
    // the older Dave delivery must not win and ties must not duplicate rows.
    expect(rows, [
      allOf(
        containsPair('id', _post),
        containsPair('authorName', 'QA Alice'),
        anyOf(
          allOf(
            containsPair('forwardedById', _member),
            containsPair('forwardedByName', 'Bob GQ'),
          ),
          allOf(
            containsPair('forwardedById', _stranger),
            containsPair('forwardedByName', 'Carol'),
          ),
        ),
      ),
    ]);
  });

  test('myPosts ignores a newer cancelled inbound forward', () async {
    await seedForwardedPost();
    await writer.execute('''
      UPDATE public.beacon_forward_edge
      SET created_at = '2030-01-01T00:00:00Z'
      WHERE id = 'FpostsToEve01'
    ''');
    await writer.execute('''
      INSERT INTO public.beacon_forward_edge
        (id, beacon_id, sender_id, recipient_id, created_at)
      VALUES ('FpostsGoneEv1', '$_post', '$_stranger', 'Upostseve0001',
              '2030-01-02T00:00:00Z')
    ''');
    await ForwardEdgeRepository(database).cancel('FpostsGoneEv1', _stranger);
    final rows = await QueryPost(postCase: posts).myPosts.resolve!(null, {
      kGlobalInputQueryJwt: const JwtEntity(sub: 'Upostseve0001'),
    });
    expect(rows, [
      allOf(
        containsPair('id', _post),
        containsPair('authorName', 'QA Alice'),
        containsPair('forwardedById', _member),
        containsPair('forwardedByName', 'Bob GQ'),
      ),
    ]);
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
  test('an open Post reports its status', () async {
    expect((await posts.myPosts(_author)).single.status, BeaconStatus.open);
  });
  test('a closed Post stays listed for its members with status closed '
      '(budding, plan C5)', () async {
    await writer.execute(
      "UPDATE public.beacon SET status = 6 WHERE id = '$_post'",
    );
    final author = (await posts.myPosts(_author)).single;
    final member = (await posts.myPosts(_member)).single;
    expect(author.status, BeaconStatus.closed);
    expect(member.status, BeaconStatus.closed);
    expect(member.lastMessageExcerpt, 'Latest text');
    expect(
      (await posts.postSummary(viewerId: _member, beaconId: _post))?.status,
      BeaconStatus.closed,
    );
    expect(await posts.myPosts(_stranger), isEmpty);
  });
  test(
    'Deleted Posts and Requests stay hidden alongside open and own unpublished Posts',
    () async {
      const keptDraftId = 'Bpostskept001';
      const deletedPostId = 'Bpostsdeleted';
      await writer.execute('''
        INSERT INTO public.beacon
          (id, user_id, title, description, status, kind, is_discoverable,
           published_at)
        VALUES
          ('$keptDraftId', '$_author', '', 'Kept draft', 3, 1, false, NULL),
          ('$deletedPostId', '$_author', '', '', 2, 1, false, now())
      ''');
      // `kind` is immutable (m0247): a historical converted Request is a
      // kind-0 row that kept its root message and addressee rows.
      await writer.execute('''
      INSERT INTO public.beacon
        (id, user_id, title, description, status, published_at,
         post_root_message_id)
      VALUES ('Bpostsconv001', '$_author', 'Converted', 'd', 0, now(),
              'Mpostsroot001')
    ''');
      await writer.execute('''
      INSERT INTO public.beacon_participant
        (id, beacon_id, user_id, role, status, room_access)
      VALUES ('Ppostsconv001', 'Bpostsconv001', '$_member', 6, 0, 0)
    ''');
      await writer.execute('''
      INSERT INTO public.beacon
        (id, user_id, title, description, status, kind, is_discoverable)
      VALUES ('Brequestdraft', '$_author', '', 'Request draft', 3, 0, false)
    ''');
      final authorRows = await posts.myPosts(_author);
      final authorIds = authorRows.map((row) => row.id);
      for (final excludedId in [
        deletedPostId,
        'Bpostsconv001',
        'Brequestdraft',
      ]) {
        expect(authorIds, isNot(contains(excludedId)));
      }
      expect((await posts.myPosts(_member)).map((row) => row.id), [_post]);
      expect(await posts.myPosts(_stranger), isEmpty);
      final openPost = authorRows.singleWhere((row) => row.id == _post);
      expect(openPost.status, BeaconStatus.open);
      expect(openPost.rootExcerpt, 'Root text');
      // An own unpublished Post remains alongside the existing open Post.
      expect(authorIds, unorderedEquals([_post, keptDraftId]));
      final draft = authorRows.singleWhere((row) => row.id == keptDraftId);
      expect(draft.isAuthor, isTrue);
      expect(draft.status, BeaconStatus.draft);
    },
  );
  test('myPosts and postSummary return the Post expiry', () async {
    await writer.execute('''
      UPDATE public.beacon SET expires_at = '2030-05-01T12:00:00Z'
      WHERE id = '$_post'
    ''');
    final expiry = DateTime.utc(2030, 5, 1, 12);
    expect((await posts.myPosts(_author)).single.expiresAt, expiry);
    expect((await posts.myPosts(_member)).single.expiresAt, expiry);
    expect(
      (await posts.postSummary(viewerId: _member, beaconId: _post))?.expiresAt,
      expiry,
    );
  });
}

final class _UnusedRoom extends Fake implements BeaconRoomCase {}

final class _UnusedAttention extends Fake
    implements TransactionalAttentionCase {}
