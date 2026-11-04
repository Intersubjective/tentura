@Tags(['pg'])
library;

import 'dart:convert';

import 'package:graphql_server2/graphql_server2.dart' show GraphQL;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';

const _viewer = 'Upersonview01';
const _peer = 'Upersonpeer01';
const _outsider = 'Upersonother1';

// Real registered GraphQL -> production DI -> migrated PostgreSQL.
// Matrix: Request/Post; open-family/review/closed/expired/hidden; viewer/other
// hides; admitted/unadmitted; both block directions; search and cursor paging.
// Input devices, viewport, locale and browser lifecycle are n/a (server API).
// Wire contract follows existing page conventions: items, nextCursor, counts.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PERSON_FIELD_ITEMS_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_person_field_items',
  );
  final unavailable = await pgSkipReason(target);
  if (unavailable != null) {
    throw StateError('Person Field items require PostgreSQL: $unavailable');
  }

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

  Future<void> person(String id, {String name = 'Ёлка', String? handle}) async {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, handle, public_key)
VALUES (@id, @name, @handle, @key)
'''),
      parameters: {
        'id': id,
        'name': name,
        'handle': handle,
        'key': base64Encode(utf8.encode(id.padRight(32, 'x'))),
      },
    );
  }

  Future<void> trust(String peer, {bool mutual = true}) async {
    await writer.execute(
      Sql.named('''
INSERT INTO public.vote_user (subject, object, amount) VALUES (@viewer, @peer, 1)
'''),
      parameters: {'viewer': _viewer, 'peer': peer},
    );
    if (mutual) {
      await writer.execute(
        Sql.named('''
INSERT INTO public.vote_user (subject, object, amount) VALUES (@peer, @viewer, 1)
'''),
        parameters: {'viewer': _viewer, 'peer': peer},
      );
    }
  }

  Future<void> request(
    String id,
    String author, {
    String title = 'Ёлка во дворе',
    bool discoverable = true,
    int status = 0,
  }) async {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, is_discoverable, published_at)
VALUES (@id, @author, @title, '', @status, 0, @discoverable, now())
'''),
      parameters: {
        'id': id,
        'author': author,
        'title': title,
        'status': status,
        'discoverable': discoverable,
      },
    );
  }

  Future<void> admit(String id) async {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_participant
  (beacon_id, user_id, role, status, room_access)
VALUES (@id, @viewer, 6, 0, 3)
'''),
      parameters: {'id': id, 'viewer': _viewer},
    );
  }

  Future<void> post(
    String id,
    String author, {
    String body = 'Ёлка распустилась',
    bool admitted = false,
    bool expired = false,
    int status = 0,
  }) async {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, is_discoverable,
   published_at, expires_at)
VALUES (@id, @author, '', '', 0, 1, false,
        now() - interval '4 days', now() + interval '1 day')
'''),
      parameters: {'id': id, 'author': author},
    );
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES (@message, @id, @author, @body)
'''),
      parameters: {'message': 'M$id', 'id': id, 'author': author, 'body': body},
    );
    await writer.execute(
      Sql.named(
        'UPDATE public.beacon SET post_root_message_id = @message WHERE id = @id',
      ),
      parameters: {'message': 'M$id', 'id': id},
    );
    if (admitted) await admit(id);
    // Archive only after publishing the root and admitting the reader, as in
    // the real lifecycle: archived Posts reject message/admission writes.
    if (expired || status != 0) {
      await writer.execute(
        Sql.named('''
UPDATE public.beacon SET status = @status,
  expires_at = CASE WHEN @expired THEN now() - interval '1 day'
                    ELSE expires_at END
WHERE id = @id
'''),
        parameters: {'id': id, 'status': status, 'expired': expired},
      );
    }
  }

  Future<void> readable(String id, {required bool expected}) async {
    final rows = await writer.execute(
      Sql.named('SELECT public.beacon_can_read_content(@id, @viewer)'),
      parameters: {'id': id, 'viewer': _viewer},
    );
    expect(rows.single.single, expected, reason: 'Read-wall fixture for $id');
  }

  Future<Map<String, dynamic>> run(
    String document, {
    Map<String, dynamic> variables = const {},
  }) async =>
      await schema.parseAndExecute(
            document,
            variableValues: variables,
            globalVariables: {
              kGlobalInputQueryJwt: const JwtEntity(sub: _viewer),
            },
          )
          as Map<String, dynamic>;

  Future<void> hide(String id, int kind, {String viewer = _viewer}) async {
    final result = await schema.parseAndExecute(
      'mutation { fieldHide(targetKind: $kind, targetId: "$id") }',
      globalVariables: {kGlobalInputQueryJwt: JwtEntity(sub: viewer)},
    );
    expect(result, {'fieldHide': true});
  }

  Future<void> activity(String id, int minute) async {
    await writer.execute(
      Sql.named("""
UPDATE public.beacon SET published_at = timestamptz '2026-01-01T00:00:00Z',
  last_activity_at = timestamptz '2026-02-01T00:00:00Z' + @minute * interval '1 minute'
WHERE id = @id
"""),
      parameters: {'id': id, 'minute': minute},
    );
  }

  Future<Map<String, dynamic>> page(
    String bucket, {
    String? query,
    String? cursor,
  }) async {
    // Omit optional arguments rather than passing null to the GraphQL library.
    final result = await run(
      'query { personFieldItems(personId: "$_peer", bucket: "$bucket"'
      '${query == null ? '' : ', query: ${jsonEncode(query)}'}'
      '${cursor == null ? '' : ', cursor: ${jsonEncode(cursor)}'}) {'
      ' items { id } nextCursor counts { active closed hidden } } }',
    );
    expect(
      result['personFieldItems'],
      isA<Map<String, dynamic>>(),
      reason:
          'personFieldItems must return a page; actual GraphQL response: $result',
    );
    return result['personFieldItems'] as Map<String, dynamic>;
  }

  List<String> ids(Map<String, dynamic> result) => (result['items'] as List)
      .map((row) => (row as Map)['id'] as String)
      .toList();

  const expected = {
    'active': [
      'Bpersonpost01',
      'Bpersonenough',
      'Bpersonneeds1',
      'Bpersonopen01',
    ],
    'closed': [
      'Bpersonarch01',
      'Bpersonexp01',
      'Bpersonclose1',
      'Bpersonrev01',
    ],
    'hidden': ['Bpersonhidep1', 'Bpersonhider1'],
  };

  const unreadableRequests = {
    'active': [
      ('Bpersonpriv01', 0),
      ('Bpersonpriv07', 7),
      ('Bpersonpriv08', 8),
    ],
    'closed': [('Bpersonpriv05', 5), ('Bpersonpriv06', 6)],
    'hidden': [('Bpersonhideu0', 0), ('Bpersonhideu6', 6)],
  };

  setUp(() async {
    await writer.execute('TRUNCATE public."user" CASCADE');
    await person(_viewer, name: 'Viewer');
    await person(_peer, name: 'Author');
    await person(_outsider, name: 'Other author');
    await trust(_peer);
    for (final (id, status) in [
      ('Bpersonopen01', 0),
      ('Bpersonneeds1', 7),
      ('Bpersonenough', 8),
      ('Bpersonrev01', 5),
      ('Bpersonclose1', 6),
      ('Bpersonhider1', 0),
    ]) {
      await request(id, _peer, status: status);
      if (status == 5 || status == 6) await admit(id);
    }
    await post('Bpersonpost01', _peer, admitted: true);
    await post('Bpersonarch01', _peer, admitted: true, status: 6);
    await post('Bpersonexp01', _peer, admitted: true, expired: true);
    await post('Bpersonhidep1', _peer, admitted: true);
    await hide('Bpersonhider1', 0);
    await hide('Bpersonhidep1', 1);
    // Other viewers' hides must not move our readable active item to Hidden.
    await hide('Bpersonopen01', 0, viewer: _peer);
    for (final bucket in unreadableRequests.keys) {
      for (final (id, status) in unreadableRequests[bucket]!) {
        // Hide while readable, then lose discovery access. A persisted hide
        // must never grant content access or contribute to a tab count.
        await request(id, _peer);
        if (bucket == 'hidden') await hide(id, 0);
        await writer.execute(
          Sql.named(
            'UPDATE public.beacon SET is_discoverable = false, status = @status WHERE id = @id',
          ),
          parameters: {'id': id, 'status': status},
        );
        await readable(id, expected: false);
        if (bucket == 'hidden') {
          final visible = await writer.execute(
            Sql.named('SELECT public.field_item_visible(@viewer, 0, @id)'),
            parameters: {'viewer': _viewer, 'id': id},
          );
          expect(
            visible.single.single,
            isFalse,
            reason: '$id has an effective hide but no read access',
          );
        }
      }
    }
    await post('Bpersonnoadm1', _peer);
    await request('Bpersonother1', _viewer);
    await request('Bpersondraft1', _peer, status: 3);
    await request('Bpersondel01', _peer, status: 2);
    await request('Bpersoncancel', _peer, status: 1);
    for (final bucket in expected.keys) {
      final entries = expected[bucket]!;
      for (var i = 0; i < entries.length; i++) {
        await activity(entries[i], entries.length - i);
        await readable(entries[i], expected: true);
      }
    }
    await readable('Bpersonpriv01', expected: false);
    await readable('Bpersonnoadm1', expected: false);
  });

  group('Person Field items', () {
    for (final bucket in expected.keys) {
      test(
        '$bucket contains only the selected authors readable items ordered by activity with matching counts',
        () async {
          final result = await page(bucket);
          expect(ids(result), expected[bucket]);
          for (final fixtures in unreadableRequests.values) {
            for (final (id, _) in fixtures) {
              expect(
                ids(result),
                isNot(contains(id)),
                reason: 'Unreadable Request $id must be absent from $bucket',
              );
            }
          }
          expect(result['counts'], {'active': 4, 'closed': 4, 'hidden': 2});
          expect(result['nextCursor'], isNull);
        },
      );
    }

    test(
      'title and root excerpt search use the same word and character normalization as Field search',
      () async {
        await request('Bpersonnoise1', _peer, title: 'Unrelated title');
        await post(
          'Bpersonnoise2',
          _peer,
          body: 'Unrelated root',
          admitted: true,
        );
        await writer.execute("""
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES ('Mpersonlater1', 'Bpersonnoise2', '$_peer', 'Ёлка распустилась')
""");
        for (final query in ['ёлка', '  @ЕЛКА  ', 'еЛкА']) {
          expect(ids(await page('active', query: query)), expected['active']);
        }
        expect(ids(await page('active', query: 'ДВОРЕ елка')), [
          'Bpersonenough',
          'Bpersonneeds1',
          'Bpersonopen01',
        ]);
        expect(ids(await page('active', query: 'РАСПУСТИЛАСЬ елка')), [
          'Bpersonpost01',
        ]);
        expect(ids(await page('active', query: 'no matching text')), isEmpty);
      },
    );

    for (final bucket in expected.keys) {
      test(
        '$bucket pages contain the newest twenty matches and disjoint ordered continuations while all bucket counts remain accurate',
        () async {
          // Keep readable and unreadable items in every bucket while adding
          // more than one page of matching Requests and Posts to this bucket.
          final ordered = <String>[];
          for (var i = 0; i < 23; i++) {
            final id = 'Bpersonpage${i.toString().padLeft(2, '0')}';
            final kind = i % 2;
            if (kind == 0) {
              await request(id, _peer, status: bucket == 'closed' ? 6 : 0);
              if (bucket == 'closed') await admit(id);
            } else {
              await post(
                id,
                _peer,
                admitted: true,
                status: bucket == 'closed' ? 6 : 0,
              );
            }
            if (bucket == 'hidden') await hide(id, kind);
            // Distinct activity times test the promised newest-first order
            // without prescribing how equal activity times are ordered.
            await activity(id, 100 + i);
            await readable(id, expected: true);
            ordered.insert(0, id);
          }
          ordered.addAll(expected[bucket]!);
          final first = await page(bucket, query: 'елка');
          expect(ids(first), ordered.take(20).toList());
          expect(first['counts'], {
            'active': 4 + (bucket == 'active' ? 23 : 0),
            'closed': 4 + (bucket == 'closed' ? 23 : 0),
            'hidden': 2 + (bucket == 'hidden' ? 23 : 0),
          });
          expect(
            first['nextCursor'],
            isA<String>().having(
              (s) => s.isNotEmpty,
              'nonempty cursor',
              isTrue,
            ),
          );
          final second = await page(
            bucket,
            query: 'елка',
            cursor: first['nextCursor'] as String,
          );
          expect(ids(second), ordered.skip(20).toList());
          expect(ids(first).toSet().intersection(ids(second).toSet()), isEmpty);
          expect([...ids(first), ...ids(second)], ordered);
          expect(second['counts'], first['counts']);
          expect(second['nextCursor'], isNull);
        },
      );
    }

    test(
      'losing Post admission removes a stored hidden Post from both items and counts',
      () async {
        await writer.execute(
          "UPDATE public.beacon_participant SET room_access = 0 WHERE beacon_id = 'Bpersonhidep1' AND user_id = '$_viewer'",
        );
        await readable('Bpersonhidep1', expected: false);
        final hidden = await page('hidden');
        expect(ids(hidden), ['Bpersonhider1']);
        expect(hidden['counts'], {'active': 4, 'closed': 4, 'hidden': 1});
      },
    );

    for (final viewerBlocks in [true, false]) {
      test(
        '${viewerBlocks ? 'blocking the author' : 'being blocked by the author'} removes their items and bucket counts',
        () async {
          await writer.execute(
            Sql.named(
              'INSERT INTO public.user_block (blocker_id, blocked_id, origin_id) VALUES (@blocker, @blocked, @blocker)',
            ),
            parameters: {
              'blocker': viewerBlocks ? _viewer : _peer,
              'blocked': viewerBlocks ? _peer : _viewer,
            },
          );
          for (final bucket in expected.keys) {
            final result = await page(bucket);
            expect(ids(result), isEmpty);
            expect(result['counts'], {'active': 0, 'closed': 0, 'hidden': 0});
          }
        },
      );
    }

    test(
      'a new forward returns an effectively unhidden Request to Active',
      () async {
        await getIt<ForwardEdgeRepositoryPort>().create(
          beaconId: 'Bpersonhider1',
          senderId: _peer,
          recipientId: _viewer,
          note: 'Please take another look',
        );
        final visible = await writer.execute(
          "SELECT public.field_item_visible('$_viewer', 0, 'Bpersonhider1')",
        );
        expect(visible.single.single, isTrue);
        expect(ids(await page('hidden')), ['Bpersonhidep1']);
        final active = await page('active');
        expect(ids(active), contains('Bpersonhider1'));
        expect(active['counts'], {'active': 5, 'closed': 4, 'hidden': 1});
      },
    );
  });
}
