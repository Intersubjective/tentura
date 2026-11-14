@Tags(['pg', 'multi-connection'])
@Timeout(Duration(minutes: 3))
library;

// The viewer's saved facts over the V2 GraphQL endpoint: `BeaconFactCardSavedList`
// on the real request path from HTTP through the resolver, use case and
// repository to Postgres. Server only: input devices, locale and viewport are
// n/a.
import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql_controller.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/data/database/main_db_pool.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/pg_test_public_keys.dart';
import '../../../support/session_database_di_harness.dart';

const _owner = 'Uflist000001'; // author of every beacon
const _a = 'Uflist000002'; // member of the rooms of R and P
const _b = 'Uflist000003'; // member of the room of R
const _reader = 'Uflist000004'; // reads R as a Request, in no room
const _empty = 'Uflist000005'; // saved nothing
const _blocked = 'Uflist000006'; // member of R, later blocked by the owner
const _bulk = 'Uflist000007'; // saved 200 facts across three beacons
const _leaver = 'Uflist000008'; // member of R2, leaves it after saving

const _r = 'Bflist0000R'; // published Request
const _r2 = 'Bflist000R2'; // published Request the leaver leaves
const _p = 'Bflist0000P'; // published Post
const _gone = 'Bflist000GN'; // Request deleted after a fact of it was saved
const _bulk1 = 'Bflist00001';
const _bulk2 = 'Bflist00002';
const _bulk3 = 'Bflist00003';

const _fOne = 'Fflist000001';
const _fTwo = 'Fflist000002';
const _fThree = 'Fflist000003';
const _fRemoved = 'Fflist000004';
const _fRoomOnly = 'Fflist000005'; // discussion-only fact of R
const _fPost = 'Fflist000006'; // fact pinned in P
const _fEdited = 'Fflist000007';
const _fFlipped = 'Fflist000008'; // request-visible, later discussion-only
const _fInGone = 'Fflist000009';
const _fBlockedSide = 'Fflist000010';
const _fLeaver = 'Fflist000011';
const _fLaterRemoved = 'Fflist000012';
const _fMine = 'Fflist000013'; // saved by A only
const _fTheirs = 'Fflist000014'; // saved by B only
const _fDangling = 'Fflist999999'; // no such fact

const _listQuery = '''
{
  BeaconFactCardSavedList {
    factCardId available beaconId beaconKind factText attachmentsJson
  }
}
''';

const _shapeQuery = '''
{
  __schema { queryType { fields { name args { name } type {
    kind ofType { kind name ofType { kind name ofType { kind name } } }
  } } } }
}
''';

const _rowShapeQuery = r'''
query ($n: String!) {
  __type(name: $n) { fields { name type { kind name } } }
}
''';

final _t0 = DateTime.utc(2026, 11, 1, 12);

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FACT_SAVED_LIST_ENDPOINT_TEST_DB',
    defaultNamePrefix: 'tentura_test_fact_saved_list_endpoint',
  );
  final unavailable = await pgSkipReason(target);
  if (unavailable != null) {
    test('saved fact list endpoint tests require reachable Postgres', () {
      fail(unavailable);
    });
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;
  late Handler graphql;
  var caller = _a;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    await _seed(writer);
    final db = target.databaseEnv;
    final env = Env(
      environment: Environment.dev,
      serverUri: Uri.parse('http://127.0.0.1:2080'),
      publicOrigin: 'http://127.0.0.1:2080',
      publicKey: Env.kJwtPublicKey,
      privateKey: Env.kJwtPrivateKey,
      pgHost: db.pgHost,
      pgPort: db.pgPort,
      pgDatabase: db.pgDatabase,
      pgUsername: db.pgUsername,
      pgPassword: db.pgPassword,
      maxConnectionCount: 8,
      workersCount: 1,
      printEnv: false,
      isDebugModeOn: false,
    );
    getIt
      ..skipDoubleRegistration = true
      ..registerFactory<TenturaDb>(
        () => TenturaDb.scoped(getIt<MainDbPool>()),
      );
    await configureSessionDatabaseTestGraph(env);
    final controller = GraphqlController(env);
    graphql = (request) => controller.handler(
      request.change(context: {kContextJwtKey: JwtEntity(sub: caller)}),
    );
  });

  tearDownAll(() async {
    getIt.skipDoubleRegistration = false;
    await getIt.reset();
    await tearDownDisposablePgWriter(session: session);
  });

  Future<List<Map<String, Object?>>> rows(
    String sql, [
    Map<String, Object?> p = const {},
  ]) async {
    final result = await writer.execute(Sql.named(sql), parameters: p);
    return [for (final r in result) r.toColumnMap()];
  }

  Future<Map<String, dynamic>> post(
    String query,
    Map<String, Object?> variables, {
    required String as,
  }) async {
    caller = as;
    final response = await graphql(
      Request(
        'POST',
        Uri.parse('http://localhost/api/v2/graphql'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'query': query, 'variables': variables}),
      ),
    );
    expect(response.statusCode, 200);
    return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
  }

  /// Replaces [user]'s saved rows: [facts] oldest first, one minute apart.
  Future<void> saveOnly(String user, List<String> facts) async {
    await rows('DELETE FROM public.user_saved_fact WHERE user_id = @u', {
      'u': user,
    });
    for (final (i, f) in facts.indexed) {
      await rows(
        'INSERT INTO public.user_saved_fact (user_id, fact_card_id, '
        'created_at) VALUES (@u, @f, @t)',
        {'u': user, 'f': f, 't': _t0.add(Duration(minutes: i))},
      );
    }
  }

  Future<List<Map<String, dynamic>>> savedList(String viewer) async {
    final body = await post(_listQuery, const {}, as: viewer);
    expect(body['errors'], isNull, reason: jsonEncode(body));
    final list =
        (body['data'] as Map<String, dynamic>)['BeaconFactCardSavedList']
            as List<dynamic>?;
    expect(list, isNotNull, reason: 'a list, never null: ${jsonEncode(body)}');
    return list!.cast<Map<String, dynamic>>();
  }

  Matcher onlyUnavailable(String id) => equals({
    'factCardId': id,
    'available': false,
    'beaconId': null,
    'beaconKind': null,
    'factText': null,
    'attachmentsJson': null,
  });

  group('BeaconFactCardSavedList in the schema', () {
    test('is a no-argument query returning a list of rows where only '
        'factCardId and available are non-null', () async {
      final body = await post(_shapeQuery, const {}, as: _a);
      expect(body['errors'], isNull, reason: jsonEncode(body));
      final fields =
          (((body['data'] as Map)['__schema'] as Map)['queryType']
                  as Map)['fields']
              as List<dynamic>;
      final field = fields
          .cast<Map<String, dynamic>>()
          .where((f) => f['name'] == 'BeaconFactCardSavedList')
          .toList();
      expect(field, hasLength(1), reason: 'Query.BeaconFactCardSavedList');
      expect(field.single['args'], isEmpty);

      var type = field.single['type'] as Map<String, dynamic>;
      while (type['name'] == null) {
        type = type['ofType'] as Map<String, dynamic>;
      }
      final shape = await post(_rowShapeQuery, {
        'n': type['name'],
      }, as: _a);
      expect(shape['errors'], isNull, reason: jsonEncode(shape));
      final row = {
        for (final f
            in (((shape['data'] as Map)['__type'] as Map)['fields'] as List)
                .cast<Map<String, dynamic>>())
          f['name']! as String: (f['type'] as Map)['kind'] as String,
      };
      expect(row.keys.toSet(), {
        'factCardId',
        'available',
        'beaconId',
        'beaconKind',
        'factText',
        'attachmentsJson',
      });
      expect(row['factCardId'], 'NON_NULL');
      expect(row['available'], 'NON_NULL');
      for (final nullable in [
        'beaconId',
        'beaconKind',
        'factText',
        'attachmentsJson',
      ]) {
        expect(row[nullable], isNot('NON_NULL'), reason: nullable);
      }
    });
  });

  group('BeaconFactCardSavedList results', () {
    test('returns the readable facts newest saved first with their head '
        'text, beacon id and kind', () async {
      await saveOnly(_a, [_fOne, _fTwo]);
      final list = await savedList(_a);
      expect([for (final r in list) r['factCardId']], [_fTwo, _fOne]);
      expect(list.first, {
        'factCardId': _fTwo,
        'available': true,
        'beaconId': _r,
        'beaconKind': 0,
        'factText': 'text of $_fTwo',
        'attachmentsJson': '[]',
      });
      expect(list.last['available'], isTrue);
      expect(list.last['factText'], 'text of $_fOne');
    });

    test("lists only the viewer's own saved facts and an empty list for a "
        'user with none', () async {
      await saveOnly(_a, [_fMine]);
      await saveOnly(_b, [_fTheirs]);
      expect([for (final r in await savedList(_a)) r['factCardId']], [_fMine]);
      expect(
        [
          for (final r in await savedList(_b)) r['factCardId'],
        ],
        [_fTheirs],
      );
      expect(await savedList(_empty), isEmpty);
    });

    test('a fact pinned in a published Post is readable with kind 1', () async {
      await saveOnly(_a, [_fPost]);
      final row = (await savedList(_a)).single;
      expect(row['available'], isTrue);
      expect(row['beaconId'], _p);
      expect(row['beaconKind'], 1);
      expect(row['factText'], 'text of $_fPost');
    });

    test('shows the current head text and attachments, not the saved '
        'ones', () async {
      await saveOnly(_a, [_fEdited]);
      await rows(
        "UPDATE public.beacon_fact_card SET fact_text = 'edited text', "
        'revision_seq = 2 WHERE id = @f',
        {'f': _fEdited},
      );
      await rows(
        '''
INSERT INTO public.beacon_fact_card_revision
  (fact_card_id, seq, fact_text, actor_id, kind, created_at, attachments_json)
VALUES (@f, 2, 'edited text', @o, @kind, @t0,
        '[{"imageId":"img-new"}]'::jsonb)
''',
        {
          'f': _fEdited,
          'o': _owner,
          'kind': BeaconFactCardRevisionKindBits.edited,
          't0': _t0,
        },
      );
      final row = (await savedList(_a)).single;
      expect(row['available'], isTrue);
      expect(row['factText'], 'edited text');
      expect(jsonDecode(row['attachmentsJson'] as String), [
        {'imageId': 'img-new'},
      ]);
    });

    test('unavailable rows keep their place in the saved-time order', () async {
      await saveOnly(_a, [_fOne, _fRemoved, _fThree]);
      final list = await savedList(_a);
      expect(
        [for (final r in list) r['factCardId']],
        [
          _fThree,
          _fRemoved,
          _fOne,
        ],
      );
      expect([for (final r in list) r['available']], [true, false, true]);
    });

    test('a removed fact returns only its id and available false', () async {
      await saveOnly(_a, [_fRemoved]);
      expect((await savedList(_a)).single, onlyUnavailable(_fRemoved));
    });

    test(
      'a dangling fact id returns only its id and available false',
      () async {
        await saveOnly(_a, [_fDangling]);
        expect((await savedList(_a)).single, onlyUnavailable(_fDangling));
      },
    );

    test('a request-visible fact stays readable for a non-member reader '
        'while a discussion-only one is unavailable', () async {
      await saveOnly(_reader, [_fOne, _fRoomOnly]);
      final list = await savedList(_reader);
      expect(list.first, onlyUnavailable(_fRoomOnly));
      expect(list.last['factCardId'], _fOne);
      expect(list.last['available'], isTrue);
      expect(list.last['beaconId'], _r);
      expect(list.last['factText'], 'text of $_fOne');
    });

    test('a member can read a discussion-only fact of their room', () async {
      await saveOnly(_a, [_fRoomOnly]);
      final row = (await savedList(_a)).single;
      expect(row['available'], isTrue);
      expect(row['factText'], 'text of $_fRoomOnly');
    });

    test('a fact made discussion-only after the reader saved it becomes '
        'unavailable to them', () async {
      await saveOnly(_reader, [_fFlipped]);
      expect((await savedList(_reader)).single['available'], isTrue);
      await rows(
        'UPDATE public.beacon_fact_card SET visibility = @v WHERE id = @f',
        {'v': BeaconFactCardVisibilityBits.room, 'f': _fFlipped},
      );
      expect((await savedList(_reader)).single, onlyUnavailable(_fFlipped));
    });

    test('a fact removed after it was saved becomes unavailable', () async {
      await saveOnly(_a, [_fLaterRemoved]);
      expect((await savedList(_a)).single['available'], isTrue);
      await rows(
        'UPDATE public.beacon_fact_card SET status = @s WHERE id = @f',
        {'s': BeaconFactCardStatusBits.removed, 'f': _fLaterRemoved},
      );
      expect((await savedList(_a)).single, onlyUnavailable(_fLaterRemoved));
    });

    test('a member who left the discussion loses the fact', () async {
      await saveOnly(_leaver, [_fLeaver]);
      expect((await savedList(_leaver)).single['available'], isTrue);
      await rows(
        'DELETE FROM public.beacon_participant '
        'WHERE beacon_id = @b AND user_id = @u',
        {'b': _r2, 'u': _leaver},
      );
      expect((await savedList(_leaver)).single, onlyUnavailable(_fLeaver));
    });

    test('a blocked viewer loses the fact', () async {
      await saveOnly(_blocked, [_fBlockedSide]);
      expect((await savedList(_blocked)).single['available'], isTrue);
      await rows(
        'INSERT INTO public.user_block (blocker_id, blocked_id, origin_id) '
        'VALUES (@o, @u, @o)',
        {'o': _owner, 'u': _blocked},
      );
      expect(
        (await savedList(_blocked)).single,
        onlyUnavailable(_fBlockedSide),
      );
    });

    test('a fact of a deleted beacon is unavailable, also for its '
        'author', () async {
      await saveOnly(_a, [_fInGone]);
      await saveOnly(_owner, [_fInGone]);
      expect((await savedList(_a)).single['available'], isTrue);
      await rows('DELETE FROM public.beacon WHERE id = @g', {'g': _gone});
      expect((await savedList(_a)).single, onlyUnavailable(_fInGone));
      expect((await savedList(_owner)).single, onlyUnavailable(_fInGone));
    });
  });

  group('BeaconFactCardSavedList cost', () {
    test('200 saved facts across 3 beacons check beacon access at most '
        'three times', () async {
      // Counting-function setup: this wraps `beacon_fact_access(text, text)`
      // by name and signature. If that function is renamed or re-signatured
      // the setup breaks, which is not a behaviour regression: update the
      // wrapper to the new name instead.
      await rows('''
CREATE TABLE public.fact_access_calls (n serial PRIMARY KEY)
''');
      await rows(
        'ALTER FUNCTION public.beacon_fact_access(text, text) '
        'RENAME TO beacon_fact_access_orig',
      );
      await rows(r'''
CREATE FUNCTION public.beacon_fact_access(p_beacon_id text, p_user_id text)
RETURNS TABLE(
  beacon_exists boolean, kind integer, status integer, is_draft boolean,
  is_expired_post boolean, can_read boolean, can_use_room boolean
) LANGUAGE plpgsql VOLATILE AS $$
BEGIN
  INSERT INTO public.fact_access_calls DEFAULT VALUES;
  RETURN QUERY SELECT * FROM public.beacon_fact_access_orig(
    p_beacon_id, p_user_id);
END
$$
''');
      try {
        final list = await savedList(_bulk);
        expect(list, hasLength(200));
        expect(list.every((r) => r['available'] == true), isTrue);
        expect(
          {for (final r in list) r['beaconId']},
          {_bulk1, _bulk2, _bulk3},
        );
        final calls = (await rows(
          'SELECT count(*)::integer AS n FROM public.fact_access_calls',
        )).single['n']!;
        expect(calls, lessThanOrEqualTo(3));
      } finally {
        await rows('DROP FUNCTION public.beacon_fact_access(text, text)');
        await rows(
          'ALTER FUNCTION public.beacon_fact_access_orig(text, text) '
          'RENAME TO beacon_fact_access',
        );
        await rows('DROP TABLE public.fact_access_calls');
      }
    });
  });
}

Future<void> _seed(Connection w) async {
  Future<void> run(String sql, [Map<String, Object?>? p]) async {
    await w.execute(Sql.named(sql), parameters: p ?? {});
  }

  for (final (i, u) in [
    _owner,
    _a,
    _b,
    _reader,
    _empty,
    _blocked,
    _bulk,
    _leaver,
  ].indexed) {
    await run(
      'INSERT INTO public."user" (id, display_name, public_key) '
      'VALUES (@id, @n, @k)',
      {'id': u, 'n': 'User$i', 'k': pgTestPublicKey('flist', i + 1)},
    );
  }
  for (final (id, kind) in [
    (_r, 0),
    (_r2, 0),
    (_p, 1),
    (_gone, 0),
    (_bulk1, 0),
    (_bulk2, 0),
    (_bulk3, 0),
  ]) {
    await run(
      '''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, published_at,
   is_discoverable, expires_at)
VALUES (@id, @o, @title, @desc, 0, @kind::smallint, @t0, @disc,
        CASE WHEN @kind::smallint = 1 THEN now() + interval '2 days' END)
''',
      {
        'id': id,
        'o': _owner,
        'kind': kind,
        't0': _t0,
        // A Post has an empty title and description and is not discoverable.
        'title': kind == 1 ? '' : id,
        'desc': kind == 1 ? '' : 'd',
        'disc': kind == 0,
      },
    );
  }
  // A published Post has a root message; without one it is a draft.
  await run(
    'INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body) '
    "VALUES ('Mflistroot01', @p, @o, 'Root')",
    {'p': _p, 'o': _owner},
  );
  await run(
    "UPDATE public.beacon SET post_root_message_id = 'Mflistroot01' "
    'WHERE id = @p',
    {'p': _p},
  );
  var p = 0;
  for (final (beaconId, userId) in [
    (_r, _a),
    (_r, _b),
    (_r, _blocked),
    (_r2, _leaver),
    (_p, _a),
    (_gone, _a),
    (_bulk1, _bulk),
    (_bulk2, _bulk),
    (_bulk3, _bulk),
  ]) {
    await run(
      '''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES (@id, @b, @u, 0, 0, 3)
''',
      {'id': 'Pflist${p++}', 'b': beaconId, 'u': userId},
    );
  }
  // The reader sees R as a Request (forwarded) but is in no room.
  await run(
    'INSERT INTO public.beacon_forward_edge '
    '(beacon_id, sender_id, recipient_id) VALUES (@b, @o, @r)',
    {'b': _r, 'o': _owner, 'r': _reader},
  );

  Future<void> fact(
    String id,
    String beaconId, {
    int status = BeaconFactCardStatusBits.active,
    int visibility = BeaconFactCardVisibilityBits.public,
  }) async {
    await run(
      '''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, status, created_at,
   updated_at, revision_seq)
VALUES (@id, @b, 'text of ' || @id, @vis, @o, @status, @t0, @t0, 1)
''',
      {
        'id': id,
        'b': beaconId,
        'vis': visibility,
        'o': _owner,
        'status': status,
        't0': _t0,
      },
    );
    await run(
      '''
INSERT INTO public.beacon_fact_card_revision
  (fact_card_id, seq, fact_text, actor_id, kind, created_at, attachments_json)
VALUES (@id, 1, 'text of ' || @id, @o, @kind, @t0, '[]'::jsonb)
''',
      {
        'id': id,
        'o': _owner,
        'kind': BeaconFactCardRevisionKindBits.created,
        't0': _t0,
      },
    );
  }

  for (final id in [
    _fOne,
    _fTwo,
    _fThree,
    _fEdited,
    _fFlipped,
    _fBlockedSide,
    _fLaterRemoved,
    _fMine,
    _fTheirs,
  ]) {
    await fact(id, _r);
  }
  await fact(_fLeaver, _r2);
  await fact(_fRoomOnly, _r, visibility: BeaconFactCardVisibilityBits.room);
  await fact(_fRemoved, _r, status: BeaconFactCardStatusBits.removed);
  await fact(_fPost, _p);
  await fact(_fInGone, _gone);

  // 200 facts across three beacons, all saved by the bulk user.
  for (var i = 0; i < 200; i++) {
    final id = 'Fflistbulk${i.toString().padLeft(3, '0')}';
    await fact(id, [_bulk1, _bulk2, _bulk3][i % 3]);
    await run(
      'INSERT INTO public.user_saved_fact (user_id, fact_card_id, created_at) '
      'VALUES (@u, @f, @t)',
      {'u': _bulk, 'f': id, 't': _t0.add(Duration(minutes: i))},
    );
  }
}
