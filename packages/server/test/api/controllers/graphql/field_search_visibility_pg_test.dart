@Tags(['pg'])
library;

import 'dart:convert';

import 'package:graphql_server2/graphql_server2.dart' show GraphQL;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/data/database/tentura_db.dart' show TenturaDb;
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/env.dart';

import '../../../support/constellation_anchor_batch_fixture.dart';
import '../../../support/disposable_pg_target.dart';

const _viewer = 'Usearchview01';
const _peer = 'Usearchpeer01';
const _outsider = 'Usearchout001';
const _ownRequest = 'Bsearchown01';
const _peerRequest = 'Bsearchpeer01';
const _ownPost = 'Bsearchown02';
const _peerPost = 'Bsearchpeer02';

// Real registered GraphQL operation -> production DI -> migrated PostgreSQL.
// Covers author/visible peer/contact/bond/temporary/outsider, Requests/Posts,
// open/closed/expired, hidden, both block directions, normalization and caps.
// Device, viewport and browser lifecycle are n/a for this server contract.
// SQL round-trip scaling and local p95 are exercised separately in
// field_search_performance_pg_test.dart.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FIELD_SEARCH_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_field_search',
  );
  final unavailable = await pgSkipReason(target);
  if (unavailable != null) {
    test('Postgres unavailable', () {}, skip: unavailable);
    return;
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

  Future<Map<String, dynamic>> search(String query) async {
    final result = await run(
      r'''
query FieldSearch($query: String!, $context: String!) {
  fieldSearch(query: $query, context: $context) {
    people { id }
    requests { id status hidden }
    posts { id status hidden expiresAt }
  }
}
''',
      variables: {'query': query, 'context': ''},
    );
    expect(
      result['fieldSearch'],
      isA<Map<String, dynamic>>(),
      reason:
          'Field search must return all three groups for the authenticated viewer',
    );
    final payload = result['fieldSearch'] as Map<String, dynamic>;
    for (final group in ['people', 'requests', 'posts']) {
      expect(
        payload[group],
        isA<List<Object?>>(),
        reason: '$group must be a result list',
      );
    }
    return payload;
  }

  List<Map<String, dynamic>> rows(Map<String, dynamic> result, String group) =>
      (result[group] as List).cast<Map<String, dynamic>>();
  List<String> ids(Map<String, dynamic> result, String group) =>
      rows(result, group).map((row) => row['id'] as String).toList();

  setUp(() async {
    await writer.execute('TRUNCATE public."user" CASCADE');
    await person(_viewer, name: 'Viewer');
    await person(_peer, handle: 'forest_keeper');
    await person(_outsider);
    await trust(_peer);
    await request(_ownRequest, _viewer);
    await request(_peerRequest, _peer);
    await post(_ownPost, _viewer);
    await post(_peerPost, _peer, admitted: true);
    // These assertions must succeed before any new operation is called.
    await readable(_peerRequest, expected: true);
    await readable(_peerPost, expected: true);
  });

  group('Field search visibility', () {
    test(
      'mutually visible people are searchable while non-visible people are excluded',
      () async {
        final visible = await writer.execute(
          "SELECT unnest(public.person_visible_peer_ids_tx('$_viewer', ''))",
        );
        expect(visible.map((row) => row.single), contains(_peer));
        expect(visible.map((row) => row.single), isNot(contains(_outsider)));
        final result = await search('Ёлка');
        expect(ids(result, 'people'), contains(_peer));
        expect(ids(result, 'people'), isNot(contains(_outsider)));
      },
    );

    test('a visible peers Request title is searchable', () async {
      await request('Bsearchother1', _peer, title: 'A different subject');
      final result = await search('Ёлка');
      expect(ids(result, 'requests'), contains(_peerRequest));
      expect(ids(result, 'requests'), isNot(contains('Bsearchother1')));
    });

    test(
      'a Request by a non-visible author is excluded',
      () async {
        await request('Bsearchout01', _outsider);
        await readable('Bsearchout01', expected: false);
        final result = await search('Ёлка');
        expect(ids(result, 'requests'), contains(_peerRequest));
        expect(ids(result, 'requests'), isNot(contains('Bsearchout01')));
      },
    );

    test('a visible peers unreadable Request is excluded', () async {
      await request('Bsearchpriv1', _peer, discoverable: false);
      await readable('Bsearchpriv1', expected: false);
      final result = await search('Ёлка');
      expect(ids(result, 'requests'), contains(_peerRequest));
      expect(ids(result, 'requests'), isNot(contains('Bsearchpriv1')));
    });

    test('the viewers own Requests and Posts are searchable', () async {
      final result = await search('Ёлка');
      expect(ids(result, 'requests'), contains(_ownRequest));
      expect(ids(result, 'posts'), contains(_ownPost));
    });

    test(
      'a forwarded Request is searchable without exposing the authors other Requests',
      () async {
        await request('Bsearchfwd01', _outsider, discoverable: false);
        await request('Bsearchfwd02', _outsider);
        await getIt<ForwardEdgeRepositoryPort>().create(
          beaconId: 'Bsearchfwd01',
          senderId: _outsider,
          recipientId: _viewer,
          note: 'Please take a look',
        );
        await readable('Bsearchfwd01', expected: true);
        final result = await search('Ёлка');
        expect(ids(result, 'requests'), contains('Bsearchfwd01'));
        expect(ids(result, 'requests'), isNot(contains('Bsearchfwd02')));
      },
    );

    test(
      'temporary Field people are searchable while unrelated people are excluded',
      () async {
        await person('Usearchnone1');
        await request('Bsearchtemp1', _outsider, discoverable: false);
        await getIt<ForwardEdgeRepositoryPort>().create(
          beaconId: 'Bsearchtemp1',
          senderId: _outsider,
          recipientId: _viewer,
          note: 'Please take a look',
        );
        // Keeping an active offer on the forwarded Request establishes temporary
        // presence under the Field's existing policy; a forward alone need not.
        await writer.execute(
          "INSERT INTO public.beacon_help_offer (beacon_id, user_id, message, status) VALUES ('Bsearchtemp1', '$_viewer', 'I can help', 0)",
        );
        final temporary = await writer.execute(
          "SELECT peer_id FROM public.person_temporary_forward_peers('$_viewer')",
        );
        expect(temporary.map((row) => row.single), contains(_outsider));
        expect(
          temporary.map((row) => row.single),
          isNot(contains('Usearchnone1')),
        );
        final result = await search('Ёлка');
        expect(ids(result, 'people'), contains(_outsider));
        expect(ids(result, 'people'), isNot(contains('Usearchnone1')));
      },
    );

    test(
      'a readable pinned Request is searchable outside the visible peer set',
      () async {
        await request('Bsearchpin01', _outsider);
        // An active offer grants content access without making the author a
        // mutually visible peer. The anchor brings this Request onto the Field.
        await writer.execute(
          "INSERT INTO public.beacon_help_offer (beacon_id, user_id, message, status) VALUES ('Bsearchpin01', '$_viewer', 'I can help', 0)",
        );
        await constellationAnchorRepositoryFor(
          getIt<TenturaDb>(),
        ).applyAnchorUpsert(
          viewerId: _viewer,
          context: '',
          target: ConstellationAnchorTarget.beacon('Bsearchpin01'),
          position: const ConstellationAnchorPosition(
            xUnits: 1,
            yUnits: 2,
            coordinateSpaceVersion: 1,
          ),
        );
        await readable('Bsearchpin01', expected: true);
        expect(ids(await search('Ёлка'), 'requests'), contains('Bsearchpin01'));
      },
    );

    test('a closed Request is returned with its closed status', () async {
      await request('Bsearchclose', _peer, status: 6);
      await admit('Bsearchclose');
      await readable('Bsearchclose', expected: true);
      final result = await search('Ёлка');
      final closed = rows(
        result,
        'requests',
      ).where((row) => row['id'] == 'Bsearchclose');
      expect(closed, hasLength(1));
      expect(closed.single['status'], 6);
    });

    for (final (id, kind, group) in [
      (_peerRequest, 0, 'requests'),
      (_peerPost, 1, 'posts'),
    ]) {
      test(
        'a personally hidden $group result remains searchable with hidden true',
        () async {
          expect(
            await run(
              'mutation { fieldHide(targetKind: $kind, targetId: "$id") }',
            ),
            {'fieldHide': true},
          );
          final result = await search('Ёлка');
          expect(ids(result, group), contains(id));
          final hidden = rows(result, group).where((row) => row['id'] == id);
          expect(hidden, hasLength(1));
          expect(hidden.single['hidden'], isTrue);
          final ownId = kind == 0 ? _ownRequest : _ownPost;
          expect(
            rows(
              result,
              group,
            ).singleWhere((row) => row['id'] == ownId)['hidden'],
            isFalse,
          );
        },
      );
    }

    test('Posts require admission even when their author is visible', () async {
      await post('Bsearchnoadm', _peer);
      await readable('Bsearchnoadm', expected: false);
      final result = await search('Ёлка');
      expect(ids(result, 'posts'), contains(_peerPost));
      expect(ids(result, 'posts'), isNot(contains('Bsearchnoadm')));
    });

    for (final status in [0, 6]) {
      test(
        'an expired admitted Post with status $status remains searchable with its lifecycle fields',
        () async {
          await post(
            'Bsearchexpir',
            _peer,
            admitted: true,
            expired: true,
            status: status,
          );
          await readable('Bsearchexpir', expected: true);
          final result = await search('Ёлка');
          final expired = rows(
            result,
            'posts',
          ).where((row) => row['id'] == 'Bsearchexpir');
          expect(expired, hasLength(1));
          expect(expired.single['status'], status);
          expect(
            DateTime.parse(
              expired.single['expiresAt'] as String,
            ).isBefore(DateTime.now().toUtc()),
            isTrue,
          );
        },
      );
    }

    for (final viewerBlocks in [true, false]) {
      test(
        '${viewerBlocks ? 'blocking a person' : 'being blocked by a person'} removes the person and their items from every group',
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
          final result = await search('Ёлка');
          expect(ids(result, 'people'), isNot(contains(_peer)));
          expect(ids(result, 'requests'), isNot(contains(_peerRequest)));
          expect(ids(result, 'posts'), isNot(contains(_peerPost)));
          expect(ids(result, 'requests'), contains(_ownRequest));
          expect(ids(result, 'posts'), contains(_ownPost));
        },
      );
    }

    test(
      'direct contacts are searchable while unrelated people and contact-only Requests are excluded',
      () async {
        await person('Usearchnone1');
        await trust(_outsider, mutual: false);
        final visible = await writer.execute(
          "SELECT unnest(public.person_visible_peer_ids_tx('$_viewer', ''))",
        );
        expect(visible.map((row) => row.single), isNot(contains(_outsider)));
        final direct = await writer.execute(
          "SELECT object FROM public.vote_user WHERE subject = '$_viewer' AND amount > 0",
        );
        expect(direct.map((row) => row.single), contains(_outsider));
        expect(
          direct.map((row) => row.single),
          isNot(contains('Usearchnone1')),
        );
        await request('Bsearchcont1', _outsider);
        final result = await search('Ёлка');
        expect(ids(result, 'people'), contains(_outsider));
        expect(ids(result, 'requests'), contains(_peerRequest));
        expect(ids(result, 'requests'), isNot(contains('Bsearchcont1')));
        expect(ids(result, 'people'), isNot(contains('Usearchnone1')));
      },
    );

    test(
      'bond people are searchable while unrelated people are excluded',
      () async {
        await person('Usearchnone1');
        await request('Bsearchbond1', _outsider, discoverable: false);
        await admit('Bsearchbond1');
        final bond = await writer.execute(
          "SELECT peer_id FROM public.person_bond_peers('$_viewer')",
        );
        expect(bond.map((row) => row.single), contains(_outsider));
        expect(bond.map((row) => row.single), isNot(contains('Usearchnone1')));
        final result = await search('Ёлка');
        expect(ids(result, 'people'), contains(_outsider));
        expect(ids(result, 'people'), isNot(contains('Usearchnone1')));
      },
    );
  });

  group('Field people search membership boundaries', () {
    test(
      'withdrawing direct trust removes a contact with no other Field relationship',
      () async {
        await trust(_outsider, mutual: false);
        await writer.execute(
          "DELETE FROM public.vote_user WHERE subject = '$_viewer' AND object = '$_outsider'",
        );
        final result = await search('Ёлка');
        expect(ids(result, 'people'), contains(_peer));
        expect(ids(result, 'people'), isNot(contains(_outsider)));
      },
    );

    test(
      'revoking the only shared room admission removes a bond person',
      () async {
        await request('Bsearchbond1', _outsider, discoverable: false);
        await admit('Bsearchbond1');
        await writer.execute(
          "UPDATE public.beacon_participant SET room_access = 0 WHERE beacon_id = 'Bsearchbond1' AND user_id = '$_viewer'",
        );
        final bond = await writer.execute(
          "SELECT peer_id FROM public.person_bond_peers('$_viewer')",
        );
        expect(bond.map((row) => row.single), isNot(contains(_outsider)));
        final result = await search('Ёлка');
        expect(ids(result, 'people'), contains(_peer));
        expect(ids(result, 'people'), isNot(contains(_outsider)));
      },
    );

    test(
      'ending the kept forward removes a person with only temporary presence',
      () async {
        await request('Bsearchtemp1', _outsider, discoverable: false);
        await getIt<ForwardEdgeRepositoryPort>().create(
          beaconId: 'Bsearchtemp1',
          senderId: _outsider,
          recipientId: _viewer,
          note: 'Please take a look',
        );
        await writer.execute(
          "INSERT INTO public.beacon_help_offer (beacon_id, user_id, message, status) VALUES ('Bsearchtemp1', '$_viewer', 'I can help', 0)",
        );
        await writer.execute(
          "UPDATE public.beacon_forward_edge SET cancelled_at = now() WHERE beacon_id = 'Bsearchtemp1' AND recipient_id = '$_viewer'",
        );
        await writer.execute(
          "DELETE FROM public.beacon_help_offer WHERE beacon_id = 'Bsearchtemp1' AND user_id = '$_viewer'",
        );
        final temporary = await writer.execute(
          "SELECT peer_id FROM public.person_temporary_forward_peers('$_viewer')",
        );
        expect(temporary.map((row) => row.single), isNot(contains(_outsider)));
        final result = await search('Ёлка');
        expect(ids(result, 'people'), contains(_peer));
        expect(ids(result, 'people'), isNot(contains(_outsider)));
      },
    );
  });

  group('Field search matching', () {
    for (final query in ['ёлка', 'ЕЛКА', '@еЛкА']) {
      test(
        'people names Request titles and Post excerpts match $query equivalently',
        () async {
          final result = await search(query);
          expect(ids(result, 'people'), contains(_peer));
          expect(ids(result, 'people'), isNot(contains(_outsider)));
          expect(
            ids(result, 'requests'),
            containsAll([_ownRequest, _peerRequest]),
          );
          expect(ids(result, 'posts'), containsAll([_ownPost, _peerPost]));
        },
      );
    }

    test(
      'people match handles with a leading at sign and mixed case',
      () async {
        final result = await search('@FoReSt_KeEpEr');
        expect(ids(result, 'people'), [_peer]);
        expect(ids(result, 'requests'), isEmpty);
        expect(ids(result, 'posts'), isEmpty);
      },
    );

    test(
      'Post search matches the root excerpt rather than later chat messages',
      () async {
        await post(
          'Bsearchchat1',
          _peer,
          body: 'Different news',
          admitted: true,
        );
        await writer.execute(
          "INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body) VALUES ('Msearchchat1', 'Bsearchchat1', '$_peer', 'Ёлка in later chat')",
        );
        final result = await search('Ёлка');
        expect(ids(result, 'posts'), contains(_peerPost));
        expect(ids(result, 'posts'), isNot(contains('Bsearchchat1')));
      },
    );

    for (final query in ['', 'ё', '@ё']) {
      test(
        'a query with fewer than two normalized characters returns three empty groups ($query)',
        () async {
          final result = await search(query);
          for (final group in ['people', 'requests', 'posts']) {
            expect(ids(result, group), isEmpty);
          }
        },
      );
    }
  });

  group('Field search result limits and order', () {
    test(
      'groups cap at twenty matches and Requests and Posts keep the newest twenty',
      () async {
        for (var i = 0; i < 23; i++) {
          final suffix = i.toString().padLeft(3, '0');
          final peer = 'Usearchcap$suffix';
          await person(peer, name: 'Crowd person $suffix');
          await trust(peer, mutual: false);
          await request(
            'Bsearchreq$suffix',
            _viewer,
            title: 'Crowd Request $suffix',
          );
          await post('Bsearchpost$suffix', _viewer, body: 'Crowd Post $suffix');
        }
        // All 23 rows in each item group are eligible. Give every item a
        // distinct activity time, independent of insertion/publication order,
        // so an arbitrary LIMIT 20 cannot satisfy the newest-results promise.
        await writer.execute('''
UPDATE public.beacon b SET
  published_at = timestamptz '2026-01-01T00:00:00Z',
  last_activity_at = timestamptz '2026-02-01T00:00:00Z' + i * interval '1 minute'
FROM generate_series(0, 22) i
WHERE b.id IN ('Bsearchreq' || lpad(i::text, 3, '0'),
               'Bsearchpost' || lpad(i::text, 3, '0'))
''');
        final result = await search('Crowd');
        for (final group in ['people', 'requests', 'posts']) {
          final found = ids(result, group);
          expect(
            found,
            hasLength(20),
            reason: '$group has 23 eligible matches',
          );
          expect(
            found.toSet(),
            hasLength(20),
            reason: 'no duplicate search hits',
          );
        }
        // People have no promised activity order; any 20 distinct eligible
        // people are valid. Item groups must contain exactly the latest 20.
        expect(
          ids(result, 'people'),
          everyElement(
            isIn({
              for (var i = 0; i < 23; i++)
                'Usearchcap${i.toString().padLeft(3, '0')}',
            }),
          ),
        );
        for (final (group, prefix) in [
          ('requests', 'Bsearchreq'),
          ('posts', 'Bsearchpost'),
        ]) {
          expect(
            ids(result, group),
            [
              for (var i = 22; i >= 3; i--)
                '$prefix${i.toString().padLeft(3, '0')}',
            ],
            reason:
                '$group must select and order the newest twenty of 23 eligible matches',
          );
        }
      },
    );

    for (final (group, first, second) in [
      ('requests', _ownRequest, _peerRequest),
      ('posts', _ownPost, _peerPost),
    ]) {
      test(
        '$group sort by last activity newest first rather than publication time',
        () async {
          await writer.execute(
            Sql.named('''
UPDATE public.beacon SET
  published_at = CASE WHEN id = @first THEN now() - interval '3 days' ELSE now() - interval '1 day' END,
  last_activity_at = CASE WHEN id = @first THEN now() ELSE now() - interval '1 hour' END
WHERE id IN (@first, @second)
'''),
            parameters: {'first': first, 'second': second},
          );
          expect(ids(await search('Ёлка'), group), [first, second]);
        },
      );
    }
  });
}
