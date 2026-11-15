@Tags(['pg', 'multi-connection'])
@Timeout(Duration(minutes: 3))
library;

// Fact search over the V2 GraphQL endpoint: `BeaconFactCardSearch` on the
// real request path from HTTP through the resolver, use case and
// repository to Postgres. Server only: input devices, locale and viewport are
// n/a.
import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql_controller.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/data/database/main_db_pool.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/pg_test_public_keys.dart';
import '../../../support/session_database_di_harness.dart';

const _owner = 'Ufsrch000001'; // author of every beacon
const _a = 'Ufsrch000002'; // member of B1 and B2
const _rl = 'Ufsrch000003'; // member of B1, used for the rate limit
const _short = 'Ufsrch000004'; // member of B1, only short queries

const _b1 = 'Bfsrch00001';
const _b2 = 'Bfsrch00002';
const _b3 = 'Bfsrch00003'; // nobody but the owner reads it

const _f1 = 'Ffsrch000001'; // apple, in B1, saved by A
const _f2 = 'Ffsrch000002'; // apple, in B2, not saved
const _f3 = 'Ffsrch000003'; // apple, in B3: unreadable for A

const _searchQuery = r'''
query ($q: String!, $x: String) {
  BeaconFactCardSearch(query: $q, excludeBeaconId: $x) {
    factCardId beaconId beaconKind factText attachmentsJson saved
  }
}
''';

const _shapeQuery = '''
{
  __schema { queryType { fields { name args { name type {
    kind name ofType { kind name } } } type {
    kind ofType { kind name ofType { kind name ofType { kind name } } }
  } } } }
}
''';

const _rowShapeQuery = r'''
query ($n: String!) {
  __type(name: $n) { fields { name type { kind name ofType { name } } } }
}
''';

final _t0 = DateTime.utc(2026, 11, 1, 12);

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FACT_SEARCH_ENDPOINT_TEST_DB',
    defaultNamePrefix: 'tentura_test_fact_search_endpoint',
  );
  final unavailable = await pgSkipReason(target);
  if (unavailable != null) {
    test('fact search endpoint tests require reachable Postgres', () {
      fail(unavailable);
    });
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;
  late Handler graphql;
  late Handler anonymous;
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
      factSearchRateMax: 5,
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
    anonymous = controller.handler;
  });

  tearDownAll(() async {
    getIt.skipDoubleRegistration = false;
    await getIt.reset();
    await tearDownDisposablePgWriter(session: session);
  });

  Future<Map<String, dynamic>> post(
    String query,
    Map<String, Object?> variables, {
    String? as,
  }) async {
    final handler = as == null ? anonymous : graphql;
    if (as != null) caller = as;
    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/v2/graphql'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'query': query, 'variables': variables}),
      ),
    );
    return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> search(
    String user,
    String q, {
    String? exclude,
  }) async {
    final body = await post(_searchQuery, {'q': q, 'x': exclude}, as: user);
    expect(body['errors'], isNull, reason: jsonEncode(body));
    final list =
        (body['data'] as Map<String, dynamic>)['BeaconFactCardSearch']
            as List<dynamic>?;
    expect(list, isNotNull, reason: 'a list, never null: ${jsonEncode(body)}');
    return list!.cast<Map<String, dynamic>>();
  }

  group('BeaconFactCardSearch in the schema', () {
    test('takes a required query and an optional excludeBeaconId and '
        'returns a non-null list of non-null rows', () async {
      final body = await post(_shapeQuery, const {}, as: _a);
      expect(body['errors'], isNull, reason: jsonEncode(body));
      final fields =
          (((body['data'] as Map)['__schema'] as Map)['queryType']
                  as Map)['fields']
              as List<dynamic>;
      final field = fields
          .cast<Map<String, dynamic>>()
          .where((f) => f['name'] == 'BeaconFactCardSearch')
          .toList();
      expect(field, hasLength(1), reason: 'Query.BeaconFactCardSearch');
      final args = {
        for (final a
            in (field.single['args'] as List).cast<Map<String, dynamic>>())
          a['name']! as String: a['type'] as Map<String, dynamic>,
      };
      expect(args.keys.toSet(), {'query', 'excludeBeaconId'});
      expect(args['query']!['kind'], 'NON_NULL');
      expect(args['query']!['ofType'], containsPair('name', 'String'));
      expect(args['excludeBeaconId']!['kind'], 'SCALAR');
      expect(args['excludeBeaconId']!['name'], 'String');

      var type = field.single['type'] as Map<String, dynamic>;
      expect(type['kind'], 'NON_NULL');
      type = type['ofType'] as Map<String, dynamic>;
      expect(type['kind'], 'LIST');
      type = type['ofType'] as Map<String, dynamic>;
      expect(type['kind'], 'NON_NULL');
      type = type['ofType'] as Map<String, dynamic>;
      expect(type['name'], 'BeaconFactCardSearchRow');

      final shape = await post(_rowShapeQuery, {
        'n': 'BeaconFactCardSearchRow',
      }, as: _a);
      expect(shape['errors'], isNull, reason: jsonEncode(shape));
      final row = {
        for (final f
            in (((shape['data'] as Map)['__type'] as Map)['fields'] as List)
                .cast<Map<String, dynamic>>())
          f['name']! as String: f['type'] as Map<String, dynamic>,
      };
      expect(row.keys.toSet(), {
        'factCardId',
        'beaconId',
        'beaconKind',
        'factText',
        'attachmentsJson',
        'saved',
      });
      for (final e in row.entries) {
        expect(e.value['kind'], 'NON_NULL', reason: e.key);
      }
      expect(
        (row['saved']!['ofType'] as Map<String, dynamic>)['name'],
        'Boolean',
      );
    });
  });

  group('BeaconFactCardSearch results', () {
    test('excludeBeaconId leaves that Request out; without it both '
        'readable facts come back with the six fields and saved flags, '
        'never an unreadable one', () async {
      final excluded = await search(_a, 'apple', exclude: _b1);
      expect([for (final r in excluded) r['factCardId']], [_f2]);

      final both = await search(_a, 'apple');
      expect({for (final r in both) r['factCardId']}, {_f1, _f2});
      expect(both.map((r) => r['factCardId']), isNot(contains(_f3)));
      final one = both.firstWhere((r) => r['factCardId'] == _f1);
      final two = both.firstWhere((r) => r['factCardId'] == _f2);
      expect(one, {
        'factCardId': _f1,
        'beaconId': _b1,
        'beaconKind': 0,
        'factText': 'apple pie $_f1',
        'attachmentsJson': '[]',
        'saved': true,
      });
      expect(two['saved'], isFalse);
      expect(two['beaconId'], _b2);
    });

    test('a query that matches nothing answers an empty list', () async {
      expect(await search(_a, 'zzqqxx'), isEmpty);
    });

    test(
      'a one-letter query answers an empty list and costs nothing',
      () async {
        for (var i = 0; i < 10; i++) {
          expect(await search(_short, 'a'), isEmpty);
        }
        // Still the full allowance afterwards.
        for (var i = 0; i < 5; i++) {
          expect(await search(_short, 'apple'), isNotEmpty);
        }
      },
    );

    test('an unauthenticated call is rejected without rows', () async {
      final body = await post(_searchQuery, {'q': 'apple', 'x': null});
      expect(body['errors'], isNotNull, reason: jsonEncode(body));
      final data = body['data'];
      if (data is Map) {
        expect(data['BeaconFactCardSearch'], anyOf(isNull, isEmpty));
      }
    });

    test('the search after the allowance answers the rate-limit code '
        '1320', () async {
      for (var i = 0; i < 5; i++) {
        await search(_rl, 'apple');
      }
      final body = await post(_searchQuery, {'q': 'apple', 'x': null}, as: _rl);
      final errors = body['errors'] as List<dynamic>?;
      expect(errors, isNotNull, reason: jsonEncode(body));
      expect(
        (errors!.first as Map<String, dynamic>)['extensions'],
        containsPair('code', '1320'),
        reason: jsonEncode(body),
      );
    });
  });
}

Future<void> _seed(Connection w) async {
  Future<void> run(String sql, [Map<String, Object?>? p]) async {
    await w.execute(Sql.named(sql), parameters: p ?? {});
  }

  for (final (i, u) in [_owner, _a, _rl, _short].indexed) {
    await run(
      'INSERT INTO public."user" (id, display_name, public_key) '
      'VALUES (@id, @n, @k)',
      {'id': u, 'n': 'User$i', 'k': pgTestPublicKey('fsrch', i + 1)},
    );
  }
  for (final id in [_b1, _b2, _b3]) {
    await run(
      '''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, published_at,
   is_discoverable)
VALUES (@id, @o, @id, 'd', 0, 0, @t0, false)
''',
      {'id': id, 'o': _owner, 't0': _t0},
    );
  }
  var p = 0;
  for (final (beaconId, userId) in [
    (_b1, _a),
    (_b2, _a),
    (_b1, _rl),
    (_b1, _short),
  ]) {
    await run(
      '''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES (@id, @b, @u, 0, 0, 3)
''',
      {'id': 'Pfsrch${p++}', 'b': beaconId, 'u': userId},
    );
  }
  for (final (id, beaconId) in [(_f1, _b1), (_f2, _b2), (_f3, _b3)]) {
    await run(
      '''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, status, created_at,
   updated_at, revision_seq)
VALUES (@id, @b, 'apple pie ' || @id, 0, @o, 0, @t0, @t0, 1)
''',
      {'id': id, 'b': beaconId, 'o': _owner, 't0': _t0},
    );
    await run(
      '''
INSERT INTO public.beacon_fact_card_revision
  (fact_card_id, seq, fact_text, actor_id, kind, created_at, attachments_json)
VALUES (@id, 1, 'apple pie ' || @id, @o, 0, @t0, '[]'::jsonb)
''',
      {'id': id, 'o': _owner, 't0': _t0},
    );
  }
  await run(
    'INSERT INTO public.user_saved_fact (user_id, fact_card_id, created_at) '
    'VALUES (@u, @f, @t)',
    {'u': _a, 'f': _f1, 't': _t0},
  );
}
