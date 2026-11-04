@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_notification_preferences.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_constellation_field.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_constellation_field_requests.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/constellation_field_repository.dart';
import 'package:tentura_server/data/repository/constellation_field_requests_repository.dart';
import 'package:tentura_server/data/repository/notification_preference_repository.dart';
import 'package:tentura_server/data/repository/user_availability_repository.dart';
import 'package:tentura_server/data/repository/user_profile_batch_lookup.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/use_case/constellation_field_case.dart';
import 'package:tentura_server/domain/use_case/constellation_field_requests_case.dart';
import 'package:tentura_server/domain/use_case/notification_preference_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/constellation_anchor_batch_fixture.dart';
import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/query_counter.dart';

const _viewer = 'Ufieldunread01';
const _author = 'Ufieldunread02';
const _helper = 'Ufieldunread03';
const _request = 'Bfieldunread01';
const _post = 'Bfieldunread02';
const _questions = 'CIfieldunread01';
final _seenAt = DateTime.utc(2030);
final _messageAt = DateTime.utc(2030, 1, 2);

// Coverage: both Field read resolvers use real PostgreSQL policies, repositories,
// use cases and wire mappers. No readability/unread function is stubbed. The
// full read exercises the temporary-forward path and the author's own path;
// the targeted read exercises the discoverable Request refresh path. Posts
// cover an admitted member and their author. Input/locale/width are n/a for
// this server-only contract. Browser refetch gating and dense-data latency
// remain separate integration/performance checks.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FIELD_UNREAD_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_field_unread',
  );
  final unavailable = await pgSkipReason(target);
  if (unavailable != null) {
    test('Postgres unavailable', () {}, skip: unavailable);
    return;
  }

  late DisposablePgWriterSession session;
  late TenturaDb db;
  late QueryConstellationField full;
  late QueryConstellationFieldRequests targeted;
  late BeaconRoomRepository room;
  late MutationNotificationPreferences mute;
  final counter = QueryCounter();
  final env = Env(environment: Environment.test);
  final logger = Logger('FieldUnreadPgTest');
  const auth = {kGlobalInputQueryJwt: JwtEntity(sub: _viewer)};

  setUpAll(() async {
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    db = TenturaDb(target.databaseEnv, scopeInterceptor: () => counter);
    room = BeaconRoomRepository(db);
    full = QueryConstellationField(
      constellationFieldCase: ConstellationFieldCase(
        ConstellationFieldRepository(
          db,
          DriftUserProfileBatchLookup(db, UserAvailabilityRepository(db)),
        ),
        env: env,
        logger: logger,
      ),
    );
    targeted = QueryConstellationFieldRequests(
      case_: ConstellationFieldRequestsCase(
        ConstellationFieldRequestsRepository(db),
        env: env,
        logger: logger,
      ),
    );
    mute = MutationNotificationPreferences(
      useCase: NotificationPreferenceCase(NotificationPreferenceRepository(db)),
    );
  });

  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: db);
  });

  Future<void> beacon(String id, {bool mine = false, bool post = false}) async {
    final by = mine ? _viewer : _author;
    await session.writer.execute(
      Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, is_discoverable,
   published_at, expires_at)
VALUES (@id, @by, ${post ? "''" : "'Field item'"}, '', 0, @kind, ${!post}, now(),
        ${post ? "now() + interval '30 days'" : 'NULL'})
'''),
      parameters: {'id': id, 'by': by, 'kind': post ? 1 : 0},
    );
    if (!mine) {
      await session.writer.execute(
        Sql.named('''
INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, recipient_id)
VALUES (@id, @by, @viewer)
'''),
        parameters: {'id': id, 'by': by, 'viewer': _viewer},
      );
    }
  }

  setUp(() async {
    await session.writer.execute('TRUNCATE public."user" CASCADE');
    for (final (index, id) in [_viewer, _author, _helper].indexed) {
      await session.writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
        parameters: {
          'id': id,
          'key': pgTestPublicKey('field-unread', index + 1),
        },
      );
    }
    await beacon(_request);
  });

  Future<void> seen(String id, {String? scope, DateTime? at}) async {
    final timestamp = at ?? _seenAt;
    expect(
      await room.markBeaconRoomSeen(
        userId: _viewer,
        beaconId: id,
        threadItemId: scope,
        at: timestamp,
      ),
      timestamp,
    );
  }

  Future<void> message(
    String id, {
    String by = _author,
    String? scope,
    bool system = false,
    DateTime? at,
  }) async {
    await session.writer.execute(
      Sql.named('''
INSERT INTO public.beacon_room_message
  (beacon_id, author_id, body, thread_item_id, system_message_kind, created_at)
VALUES (@id, @by, 'A new message', @scope, @system, @at)
'''),
      parameters: {
        'id': id,
        'by': by,
        'scope': scope,
        'system': system ? 1 : null,
        'at': at ?? _messageAt,
      },
    );
  }

  Future<Map<String, dynamic>> field() async =>
      await full.constellationField.resolve!(null, {
            ...auth,
            'showClosed': false,
            'participatedOnly': false,
            'projection': 'FULL',
          })
          as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> requests({
    required bool refresh,
    required Set<String> ids,
  }) async {
    if (refresh) {
      return (await targeted.constellationFieldRequests.resolve!(null, {
                ...auth,
                'ids': ids.toList(),
                'showClosed': false,
                'participatedOnly': false,
              })
              as List)
          .cast<Map<String, dynamic>>();
    }
    return ((await field())['requests'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> expectRequest({
    required bool refresh,
    required bool unread,
    String id = _request,
  }) async {
    final rows = await requests(refresh: refresh, ids: {id});
    expect(rows.map((row) => row['id']), contains(id));
    expect(
      rows.singleWhere((row) => row['id'] == id),
      containsPair('has_unread', unread),
    );
  }

  Future<void> expectPost({required bool unread}) async {
    final rows = ((await field())['posts'] as List)
        .cast<Map<String, dynamic>>();
    expect(rows.map((row) => row['id']), contains(_post));
    expect(
      rows.singleWhere((row) => row['id'] == _post),
      containsPair('has_unread', unread),
    );
  }

  Future<void> questions() => session.writer.execute('''
INSERT INTO public.coordination_item
  (id, beacon_id, kind, status, title, body, creator_id, published,
   published_at, source, ordering)
VALUES ('$_questions', '$_request', 7, 0, 'Questions', '', '$_author',
        true, now(), 0, 0)
''');

  Future<void> visibleAuthor() => session.writer.execute(
    "INSERT INTO public.vote_user (subject, object, amount) VALUES ('$_viewer', '$_author', 1), ('$_author', '$_viewer', 1)",
  );

  Future<void> admitViewer() async {
    await session.writer.execute('''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, status, room_access)
VALUES ('$_request', '$_viewer', 2, 0, 3)
''');
    await visibleAuthor();
  }

  Future<void> expectDiscussionCount(int count) async {
    final counts = await room.unreadMainRoomMessageCounts(
      [_request],
      viewerUserId: _viewer,
    );
    expect(counts[_request], count);
  }

  Future<void> setMute(String id, DateTime? until) async {
    expect(
      await mute.beaconMuteSet.resolve!(null, {
        ...auth,
        'beaconId': id,
        'mutedUntil': until?.toUtc().toIso8601String(),
      }),
      isTrue,
    );
  }

  for (final refresh in [false, true]) {
    group(
      refresh
          ? 'Targeted Field Request unread state'
          : 'Full Field Request unread state',
      () {
        test(
          'a forwarded Request never opened by the viewer is unread',
          () async {
            await expectRequest(refresh: refresh, unread: true);
          },
        );

        test(
          'marking a forwarded Request seen clears its unread flag',
          () async {
            await seen(_request);
            await expectRequest(refresh: refresh, unread: false);
          },
        );

        test(
          'a discussion message after the read cursor makes the Request unread again',
          () async {
            await admitViewer();
            await seen(_request);
            await message(_request);
            await expectDiscussionCount(1);
            await expectRequest(refresh: refresh, unread: true);
          },
        );

        test(
          'an unread Questions message lights up a readable Request',
          () async {
            await questions();
            await seen(_request);
            // A General cursor newer than the question must not clear Questions.
            await seen(_request, at: DateTime.utc(2030, 1, 3));
            await seen(_request, scope: _questions);
            final access = await session.writer.execute('''
SELECT access FROM public.questions_access_levels('$_request', ARRAY['$_viewer'])
''');
            expect(access.single.single, greaterThan(0));
            await message(_request, scope: _questions);
            await expectRequest(refresh: refresh, unread: true);
          },
        );

        test(
          'seeing Questions clears its unread flag independently of discussion',
          () async {
            await questions();
            await seen(_request);
            await message(_request, scope: _questions);
            await seen(_request, scope: _questions, at: _messageAt);
            await expectRequest(refresh: refresh, unread: false);
          },
        );

        test(
          'Questions the viewer cannot read do not make a seen Request unread',
          () async {
            await questions();
            await seen(_request);
            await session.writer.execute('''
INSERT INTO public.beacon_lobby_ban (beacon_id, user_id, banned_by)
VALUES ('$_request', '$_viewer', '$_author')
''');
            await message(_request, scope: _questions);
            final access = await session.writer.execute('''
SELECT access FROM public.questions_access_levels('$_request', ARRAY['$_viewer'])
''');
            expect(access.single.single, 0);
            await expectRequest(refresh: refresh, unread: false);
          },
        );

        test('system lines in Questions leave a seen Request read', () async {
          await questions();
          await seen(_request);
          await message(_request, scope: _questions, system: true);
          await expectRequest(refresh: refresh, unread: false);
        });

        test('system lines alone leave a seen Request read', () async {
          await admitViewer();
          await seen(_request);
          await message(_request, system: true);
          await expectDiscussionCount(0);
          await expectRequest(refresh: refresh, unread: false);
        });

        test(
          'the viewers own message does not make a seen Request unread',
          () async {
            await admitViewer();
            await seen(_request);
            await message(_request, by: _viewer);
            await expectRequest(refresh: refresh, unread: false);
          },
        );

        for (final permanent in [false, true]) {
          test(
            '${permanent ? 'a permanent' : 'an active timed'} mute suppresses unread Request messages',
            () async {
              await admitViewer();
              await seen(_request);
              await message(_request);
              await expectDiscussionCount(1);
              await setMute(
                _request,
                permanent
                    ? null
                    : DateTime.now().toUtc().add(const Duration(days: 1)),
              );
              await expectRequest(refresh: refresh, unread: false);
            },
          );
        }

        test(
          'an expired mute allows unread Request messages to light up again',
          () async {
            await admitViewer();
            await seen(_request);
            await message(_request);
            await setMute(
              _request,
              DateTime.now().toUtc().subtract(const Duration(days: 1)),
            );
            await expectRequest(refresh: refresh, unread: true);
          },
        );
      },
    );
  }

  group('Field unread state on authored Requests', () {
    test('an author sees a helpers new discussion reply as unread', () async {
      await session.writer.execute(
        "DELETE FROM public.beacon WHERE id = '$_request'",
      );
      await beacon(_request, mine: true);
      await session.writer.execute('''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, status, room_access)
VALUES ('$_request', '$_helper', 2, 0, 3)
''');
      await message(_request, by: _helper);
      await expectRequest(refresh: false, unread: true);
    });

    test(
      'an author without new messages has no unread flag even without a read cursor',
      () async {
        await session.writer.execute(
          "DELETE FROM public.beacon WHERE id = '$_request'",
        );
        await beacon(_request, mine: true);
        await expectRequest(refresh: false, unread: false);
      },
    );
  });

  group('Field Post unread state', () {
    test(
      'an admitted viewer sees a Post message after last seen as unread like the Post card',
      () async {
        await beacon(_post, post: true);
        await seen(_post);
        await message(_post);
        final card = (await BeaconRepository(db).myPosts(_viewer)).single;
        expect(card.unreadCount, 1);
        await expectPost(unread: true);
      },
    );

    test('marking a Post seen clears its unread flag', () async {
      await beacon(_post, post: true);
      await message(_post);
      await seen(_post, at: _messageAt);
      expect(
        (await BeaconRepository(db).myPosts(_viewer)).single.unreadCount,
        0,
      );
      await expectPost(unread: false);
    });

    test('an unopened Post is unread even when it has no messages', () async {
      await beacon(_post, post: true);
      await expectPost(unread: true);
    });

    test('an authors own unopened Post without messages is read', () async {
      await beacon(_post, post: true, mine: true);
      await expectPost(unread: false);
    });

    test('system lines alone do not make a seen Post unread', () async {
      await beacon(_post, post: true);
      await seen(_post);
      await message(_post, system: true);
      expect(
        (await BeaconRepository(db).myPosts(_viewer)).single.unreadCount,
        0,
      );
      await expectPost(unread: false);
    });

    for (final permanent in [false, true]) {
      test(
        '${permanent ? 'a permanent' : 'an active timed'} mute suppresses unread Post messages',
        () async {
          await beacon(_post, post: true);
          await seen(_post);
          await message(_post);
          await setMute(
            _post,
            permanent
                ? null
                : DateTime.now().toUtc().add(const Duration(days: 1)),
          );
          await expectPost(unread: false);
        },
      );
    }
  });

  group('Pinned Field items carry the viewers unread state', () {
    for (final post in [false, true]) {
      for (final opened in [false, true]) {
        test(
          'a pinned ${post ? 'Post' : 'Request'} is ${opened ? 'read after opening' : 'unread before opening'}',
          () async {
            final id = post ? _post : _request;
            if (post) await beacon(_post, post: true);
            await constellationAnchorRepositoryFor(db).applyAnchorUpsert(
              viewerId: _viewer,
              context: '',
              target: ConstellationAnchorTarget.beacon(id),
              position: const ConstellationAnchorPosition(
                xUnits: 1,
                yUnits: 2,
                coordinateSpaceVersion: 1,
              ),
            );
            if (opened) await seen(id);
            final projection = (await field())['anchorProjection'] as Map;
            final rows = (projection['pinnedRequests'] as List)
                .cast<Map<String, dynamic>>();
            expect(rows.map((row) => row['id']), contains(id));
            final row = rows.singleWhere((row) => row['id'] == id);
            expect(row['authorId'], _author);
            expect(row['kind'], post ? 1 : 0);
            expect(row, containsPair('has_unread', !opened));
          },
        );
      }
    }
  });

  group('Field unread reads retain their SQL statement budget', () {
    for (final refresh in [false, true]) {
      test(
        '${refresh ? 'targeted Requests' : 'full Requests and Posts'} return unread flags without extra SQL as the item count grows',
        () async {
          await beacon(_post, post: true);
          await visibleAuthor();
          // Warm the visibility/first-seen caches before counting either read.
          await field();
          counter.reset();
          final small = refresh
              ? await requests(refresh: true, ids: {_request})
              : await field();
          final smallCount = counter.count;
          for (var i = 0; i < 12; i++) {
            await beacon('BfieldextraR$i');
            await beacon('BfieldextraP$i', post: true);
          }
          await field();
          counter.reset();
          final large = refresh
              ? await requests(
                  refresh: true,
                  ids: {
                    _request,
                    for (var i = 0; i < 12; i++) 'BfieldextraR$i',
                  },
                )
              : await field();
          final largeCount = counter.count;
          // Frozen on the pre-unread implementation with this exact fixture.
          // Counting BEGIN/COMMIT as well as reads prevents moving work to an
          // extra transaction from escaping the statement budget.
          final baselineStatements = refresh ? 1 : 22;
          expect(smallCount, baselineStatements);
          expect(largeCount, baselineStatements);
          final smallRows = refresh
              ? small as List
              : (small as Map)['requests'] as List;
          final largeRows = refresh
              ? large as List
              : (large as Map)['requests'] as List;
          expect(smallRows, hasLength(1));
          expect(largeRows, hasLength(13));
          for (final row in largeRows.cast<Map<String, dynamic>>()) {
            expect(row, containsPair('has_unread', true));
          }
          if (!refresh) {
            final posts = (large as Map)['posts'] as List;
            expect(posts, hasLength(13));
            for (final row in posts.cast<Map<String, dynamic>>()) {
              expect(row, containsPair('has_unread', true));
            }
          }
        },
      );
    }
  });
}
