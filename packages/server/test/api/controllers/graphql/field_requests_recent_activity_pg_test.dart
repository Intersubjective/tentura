@Tags(['pg', 'mr'])
library;

import 'package:graphql_server2/graphql_server2.dart' show GraphQL;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/inbox_repository_port.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/pg_test_public_keys.dart';

const _viewer = 'Ufrecent0001';
const _authors = ['Ufrecent0010', 'Ufrecent0011', 'Ufrecent0012'];
const _lateAuthor = 'Ufrecent0099';

// Coverage: the registered `constellationField` GraphQL query (FULL
// projection) over production DI and a migrated PostgreSQL. The discoverable
// Requests of the Field are capped at [kConstellationRequestCap]; the cap keeps
// the most recently active ones, where activity is
// COALESCE(last_activity_at, published_at, created_at). Every Request and Post
// row in `requests` and `posts` carries that activity time as `lastActivityAt`.
// Pinned Requests live in the separate anchorProjection; its placeholder and
// activity contracts are outside this test's scope pending clarification.
// Eligibility regression suites stay unchanged. Timing / statement budgets
// need the local perf-DB benchmark, not a wall-clock assertion on this fixture.
// The created_at-only fallback cannot appear in these published-only Field
// paths. The capped fixture includes an unpublished row with both other times
// null and asserts its exclusion rather than widening publication eligibility.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FIELD_REQUESTS_RECENT_ACTIVITY_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_field_recent_activity',
  );
  final unavailable = await pgSkipReason(target);
  if (unavailable != null) {
    test('Postgres unavailable', () {}, skip: unavailable);
    return;
  }

  const cap = kConstellationRequestCap;

  late DisposablePgWriterSession session;
  late Connection writer;
  late GraphQL schema;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    writer = session.writer;
    final pg = target.databaseEnv;
    await configureDependencies(
      Env(
        environment: Environment.dev,
        serverUri: Uri.parse('http://127.0.0.1:2080'),
        publicKey: Env.kJwtPublicKey,
        privateKey: Env.kJwtPrivateKey,
        pgHost: pg.pgHost,
        pgPort: pg.pgPort,
        pgDatabase: pg.pgDatabase,
        pgUsername: pg.pgUsername,
        pgPassword: pg.pgPassword,
        publicOrigin: 'http://127.0.0.1:2080',
        workersCount: 1,
        printEnv: false,
        isDebugModeOn: false,
      ),
    );
    await getIt.allReady(ignorePendingAsyncCreation: true);
    schema = graphqlSchema;
  });

  tearDownAll(() async {
    await getIt.reset();
    await tearDownDisposablePgWriter(session: session);
  });

  setUp(() async {
    await writer.execute('TRUNCATE public."user" CASCADE');
    for (final (index, id) in [_viewer, ..._authors, _lateAuthor].indexed) {
      await writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
        parameters: {
          'id': id,
          'key': pgTestPublicKey('field-recent-activity', index + 1),
        },
      );
      if (id != _viewer) {
        await writer.execute(
          Sql.named('''
INSERT INTO public.vote_user (subject, object, amount)
VALUES (@viewer, @peer, 1), (@peer, @viewer, 1)
'''),
          parameters: {'viewer': _viewer, 'peer': id},
        );
      }
    }
  });

  Future<Map<String, dynamic>> field(String selection) async {
    final result =
        await schema.parseAndExecute(
              '''
query {
  constellationField(
    showClosed: false, participatedOnly: false, projection: FULL
  ) { $selection }
}
''',
              globalVariables: {
                kGlobalInputQueryJwt: const JwtEntity(sub: _viewer),
              },
            )
            as Map<String, dynamic>;
    return result['constellationField'] as Map<String, dynamic>;
  }

  List<String> peerRequestIds(Map<String, dynamic> payload) => [
    for (final row
        in (payload['requests'] as List).cast<Map<String, dynamic>>())
      if (row['authorId'] != _viewer) row['id'] as String,
  ];

  /// The activity time the Field ranks a beacon by.
  Future<DateTime> activityOf(String id) async {
    final rows = await writer.execute(
      Sql.named('''
SELECT COALESCE(last_activity_at, published_at, created_at)
FROM public.beacon WHERE id = @id
'''),
      parameters: {'id': id},
    );
    return (rows.single.single! as DateTime).toUtc();
  }

  group('Field Requests capped by recent activity', () {
    test(
      '160 eligible Requests return the newest 150 in activity order '
      'and report truncation',
      () async {
        // 160 Requests spread over three authors. Activity grows with the id,
        // so the lowest ids are the least recently active. Odd ids record
        // activity over an old publication; even ids rank by published_at.
        // All three default-eligible statuses (0, 7, 8) share the same cap.
        await writer.execute('''
INSERT INTO public.beacon (
  id, user_id, title, description, status, kind, is_discoverable,
  published_at, last_activity_at, created_at
)
SELECT 'Bfrecent' || lpad(i::text, 4, '0'),
       (ARRAY['${_authors.join("','")}'])[1 + (i - 1) % 3],
       'Request ' || i, '', (ARRAY[0, 7, 8])[1 + (i - 1) % 3], 0, true,
       CASE WHEN i % 2 = 1
            THEN timestamptz '2025-01-01T00:00:00Z'
            ELSE timestamptz '2026-01-01T00:00:00Z' + i * interval '1 minute'
       END,
       CASE WHEN i % 2 = 1
            THEN timestamptz '2026-01-01T00:00:00Z' + i * interval '1 minute'
       END,
       timestamptz '2025-01-01T00:00:00Z'
FROM generate_series(1, 160) AS i
''');

        // Interleave high-activity ineligible rows with the eligible ids. A
        // limit applied before eligibility would leave fewer than 150 results
        // or displace some of the expected newest eligible Requests.
        const blockedAuthor = 'Ufrecent0020';
        const outsider = 'Ufrecent0030';
        for (final (index, id) in [blockedAuthor, outsider].indexed) {
          await writer.execute(
            Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
            parameters: {
              'id': id,
              'key': pgTestPublicKey('field-recent-activity', index + 6),
            },
          );
        }
        await writer.execute('''
INSERT INTO public.vote_user (subject, object, amount)
VALUES ('$_viewer', '$blockedAuthor', 1), ('$blockedAuthor', '$_viewer', 1)
''');
        await writer.execute('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$blockedAuthor', '$_viewer', '$blockedAuthor')
''');
        await writer.execute('''
INSERT INTO public.beacon (
  id, user_id, title, description, status, kind, is_discoverable,
  published_at, last_activity_at, created_at
)
VALUES
  ('Bfrecent004h', '${_authors.first}', 'Hidden', '', 0, 0, true,
   '2026-02-01T00:00:00Z', '2026-06-01T00:00:00Z', '2026-02-01T00:00:00Z'),
  ('Bfrecent008r', '${_authors[1]}', 'Rejected', '', 7, 0, true,
   '2026-02-01T00:00:00Z', '2026-06-01T00:00:00Z', '2026-02-01T00:00:00Z'),
  ('Bfrecent012n', '${_authors.last}', 'Not discoverable', '', 8, 0, false,
   '2026-02-01T00:00:00Z', '2026-06-01T00:00:00Z', '2026-02-01T00:00:00Z'),
  ('Bfrecent016u', '${_authors.first}', 'Unpublished', '', 0, 0, true,
   NULL, NULL, '2026-06-01T00:00:00Z'),
  ('Bfrecent020c', '${_authors[1]}', 'Closed', '', 6, 0, true,
   '2026-02-01T00:00:00Z', '2026-06-01T00:00:00Z', '2026-02-01T00:00:00Z'),
  ('Bfrecent024b', '$blockedAuthor', 'Blocked author', '', 0, 0, true,
   '2026-02-01T00:00:00Z', '2026-06-01T00:00:00Z', '2026-02-01T00:00:00Z'),
  ('Bfrecent028v', '$outsider', 'Non-visible author', '', 0, 0, true,
   '2026-02-01T00:00:00Z', '2026-06-01T00:00:00Z', '2026-02-01T00:00:00Z'),
  ('Bfrecent032p', '${_authors.last}', 'Unreadable private Request', '',
   0, 0, false, '2026-02-01T00:00:00Z', '2026-06-01T00:00:00Z',
   '2026-02-01T00:00:00Z')
''');
        final hide =
            await schema.parseAndExecute(
                  'mutation { fieldHide(targetKind: 0, targetId: "Bfrecent004h") }',
                  globalVariables: {
                    kGlobalInputQueryJwt: const JwtEntity(sub: _viewer),
                  },
                )
                as Map<String, dynamic>;
        expect(hide['fieldHide'], isTrue);
        for (final (id, author) in [
          ('Bfrecent008r', _authors[1]),
          ('Bfrecent012n', _authors.last),
        ]) {
          await getIt<ForwardEdgeRepositoryPort>().create(
            beaconId: id,
            senderId: author,
            recipientId: _viewer,
            note: 'For you',
          );
        }
        await getIt<InboxRepositoryPort>().setStatus(
          userId: _viewer,
          beaconId: 'Bfrecent008r',
          status: 2,
          rejectionMessage: 'Busy this week',
        );

        final payload = await field('requestsCapped requests { id authorId }');

        final ids = peerRequestIds(payload);
        expect(
          ids,
          isNot(
            anyOf([
              for (final excludedId in [
                'Bfrecent004h',
                'Bfrecent008r',
                'Bfrecent012n',
                'Bfrecent016u',
                'Bfrecent020c',
                'Bfrecent024b',
                'Bfrecent028v',
                'Bfrecent032p',
              ])
                contains(excludedId),
            ]),
          ),
          reason: 'ineligible rows cannot consume the recent-activity cap',
        );
        expect(ids, hasLength(cap));
        expect(payload['requestsCapped'], isTrue);
        expect(
          ids,
          unorderedEquals([
            for (var i = 160 - cap + 1; i <= 160; i++)
              'Bfrecent${i.toString().padLeft(4, '0')}',
          ]),
          reason:
              'the ${160 - cap} least recently active Requests (ids 1..'
              '${160 - cap}) are the ones left out',
        );
        expect(
          ids,
          orderedEquals([
            for (var i = 160; i > 160 - cap; i--)
              'Bfrecent${i.toString().padLeft(4, '0')}',
          ]),
          reason: 'activity order is global across authors, newest first',
        );
      },
    );

    test('uncapped Requests use activity descending and id ascending '
        'across authors', () async {
      await writer.execute('''
INSERT INTO public.beacon (
  id, user_id, title, description, status, kind, is_discoverable,
  published_at, last_activity_at, created_at
)
VALUES
  ('Bfrecent0001', '${_authors.first}', 'Old publication', '', 0, 0, true,
   '2026-01-01T00:00:00Z', NULL, '2025-01-01T00:00:00Z'),
  ('Bfrecent0002', '${_authors.last}', 'Active room', '', 0, 0, true,
   '2025-01-01T00:00:00Z', '2026-03-01T00:00:00Z',
   '2025-01-01T00:00:00Z'),
  ('Bfrecent0003', '${_authors.first}', 'Recent publication', '', 0, 0, true,
   '2026-02-01T00:00:00Z', NULL, '2025-01-01T00:00:00Z'),
  ('Bfrecent0004', '${_authors[1]}', 'Equally active room', '', 0, 0, true,
   '2025-01-01T00:00:00Z', '2026-03-01T00:00:00Z',
   '2025-01-01T00:00:00Z')
''');

      final payload = await field('requestsCapped requests { id authorId }');

      expect(payload['requestsCapped'], isFalse);
      expect(
        peerRequestIds(payload),
        orderedEquals([
          'Bfrecent0002',
          'Bfrecent0004',
          'Bfrecent0003',
          'Bfrecent0001',
        ]),
        reason: 'room activity wins over publication; ties ignore author id',
      );
    });

    test('fresh room activity includes the highest-id Request and breaks '
        'equal-activity ties by id', () async {
      await writer.execute('''
INSERT INTO public.beacon (
  id, user_id, title, description, status, kind, is_discoverable,
  published_at, created_at
)
SELECT 'Bfrecent' || lpad(i::text, 4, '0'), '${_authors.first}',
       'Request ' || i, '', 0, 0, true,
       timestamptz '2026-01-01T00:00:00Z',
       timestamptz '2026-01-01T00:00:00Z'
FROM generate_series(1, 159) AS i
''');
      // Published before all of them; only its room is active.
      await writer.execute('''
INSERT INTO public.beacon (
  id, user_id, title, description, status, kind, is_discoverable,
  published_at, created_at
)
VALUES ('Bfrecentzzzz', '$_lateAuthor', 'Late Request', '', 0, 0, true,
        '2025-06-01T00:00:00Z', '2025-06-01T00:00:00Z')
''');
      await writer.execute('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES ('Mfrecentzzzz', 'Bfrecentzzzz', '$_lateAuthor', 'Still need help')
''');

      final payload = await field('requestsCapped requests { id authorId }');

      final ids = peerRequestIds(payload);
      expect(ids, hasLength(cap));
      expect(payload['requestsCapped'], isTrue);
      expect(ids, contains('Bfrecentzzzz'));
      expect(
        ids,
        orderedEquals([
          'Bfrecentzzzz',
          for (var i = 1; i < cap; i++)
            'Bfrecent${i.toString().padLeft(4, '0')}',
        ]),
        reason: 'room activity outranks publication; equal times use id ASC',
      );
    });
  });

  group('Field payload activity time', () {
    for (final own in [true, false]) {
      test(
        own
            ? 'own Requests expose publication fallback alongside Post activity'
            : 'discoverable Requests expose room activity alongside Post activity',
        () async {
          await writer.execute('''
INSERT INTO public.beacon (
  id, user_id, title, description, status, kind, is_discoverable,
  published_at, last_activity_at, created_at, expires_at
)
VALUES
  ('Bfrecentreq1', '${own ? _viewer : _authors.first}', 'Request', '', 0, 0, true,
   '2026-02-01T00:00:00Z', NULL, '2026-01-30T00:00:00Z', NULL),
  ('Bfrecentpost', '${_authors.first}', '', '', 0, 1, false,
   now() - interval '1 hour', NULL, now() - interval '1 hour',
   now() + interval '71 hours')
''');
          if (!own) {
            await writer.execute('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES ('Mfrecentreq1', 'Bfrecentreq1', '${_authors.first}', 'Still active')
''');
          }
          await writer.execute('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES ('Mfrecentpost', 'Bfrecentpost', '${_authors.first}', 'Garden news')
''');
          await writer.execute('''
UPDATE public.beacon SET post_root_message_id = 'Mfrecentpost'
WHERE id = 'Bfrecentpost'
''');
          await writer.execute('''
INSERT INTO public.beacon_participant
  (beacon_id, user_id, role, status, room_access)
VALUES ('Bfrecentpost', '$_viewer', 6, 0, 3)
''');
          final payload = await field('''
requests { id lastActivityAt }
posts { id lastActivityAt }
''');

          final requests = (payload['requests'] as List)
              .cast<Map<String, dynamic>>();
          final posts = (payload['posts'] as List).cast<Map<String, dynamic>>();
          expect(requests.map((row) => row['id']), ['Bfrecentreq1']);
          expect(posts.map((row) => row['id']), ['Bfrecentpost']);
          // Check the Post before the Request, so the missing Request timestamp
          // cannot mask a broken or unexercised Post assertion.
          final rows = <Map<String, dynamic>>[
            ...posts,
            ...requests,
          ];
          for (final row in rows) {
            final id = row['id'] as String;
            final value = row['lastActivityAt'];
            expect(
              value,
              isA<String>(),
              reason: '$id must carry lastActivityAt',
            );
            expect(
              DateTime.parse(value as String).toUtc(),
              await activityOf(id),
              reason: '$id lastActivityAt is its latest activity time',
            );
          }
        },
      );
    }
  });
}
