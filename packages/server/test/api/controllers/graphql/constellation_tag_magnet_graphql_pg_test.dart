@Tags(['pg'])
library;

import 'package:graphql_server2/graphql_server2.dart' show GraphQL;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';

const _owner = 'Utmgqlowner0001';
const _other = 'Utmgqlother0001';

const _createTagDoc = r'''
mutation($name: String!, $clientOpId: String!) {
  personTagCreate(name: $name, clientOpId: $clientOpId) { id }
}
''';

const _listDoc = '''
query { constellationTagMagnets { tagId xUnits yUnits revision } }
''';

const _upsertDoc = r'''
mutation($tagId: String!, $x: Float!, $y: Float!, $op: String!) {
  constellationTagMagnetUpsert(tagId: $tagId, xUnits: $x, yUnits: $y, clientOpId: $op) {
    tagId xUnits yUnits revision
  }
}
''';

const _removeDoc = r'''
mutation($tagId: String!, $op: String!) {
  constellationTagMagnetRemove(tagId: $tagId, clientOpId: $op)
}
''';

/// Tag magnets over the production V2 schema: list, upsert and remove are
/// registered on it, resolve the viewer from the JWT only, require a valid
/// `clientOpId` and coordinates in the resolvers, and keep another user out.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_TAG_MAGNET_GQL_TEST_DB',
    defaultNamePrefix: 'tentura_test_tagmagnet_gql',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('tag magnets GraphQL', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late GraphQL schema;
    var opCounter = 0;

    String nextOp() => 'op-${opCounter++}';

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      final db = target.databaseEnv;
      await configureDependencies(
        Env(
          environment: Environment.dev,
          serverUri: Uri.parse('http://127.0.0.1:2080'),
          publicKey: Env.kJwtPublicKey,
          privateKey: Env.kJwtPrivateKey,
          pgHost: db.pgHost,
          pgPort: db.pgPort,
          pgDatabase: db.pgDatabase,
          pgUsername: db.pgUsername,
          pgPassword: db.pgPassword,
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
      await writer.execute('TRUNCATE TABLE public."user" CASCADE');
      for (final id in [_owner, _other]) {
        await writer.execute(
          Sql.named(
            'INSERT INTO public."user" (id, display_name, public_key) '
            'VALUES (@id, @id, @key)',
          ),
          parameters: {'id': id, 'key': '$id-key'},
        );
      }
    });

    Future<Map<String, dynamic>> run(
      String document,
      Map<String, dynamic> variables, {
      String sub = _owner,
    }) async =>
        await schema.parseAndExecute(
              document,
              variableValues: variables,
              globalVariables: {kGlobalInputQueryJwt: JwtEntity(sub: sub)},
            )
            as Map<String, dynamic>;

    /// Runs an operation that must fail and returns the error text (the wire
    /// form `{"message":…,"extensions":{"code":"<n>"}}`).
    Future<String> failureOf(
      String document,
      Map<String, dynamic> variables, {
      String sub = _owner,
    }) async {
      try {
        await run(document, variables, sub: sub);
      } on Object catch (e) {
        return e.toString();
      }
      fail('expected the operation to fail');
    }

    Future<String> createTag(String name, {String sub = _owner}) async {
      final data = await run(_createTagDoc, {
        'name': name,
        'clientOpId': nextOp(),
      }, sub: sub);
      return (data['personTagCreate'] as Map<String, dynamic>)['id']! as String;
    }

    Future<Map<String, dynamic>> upsert(
      String tagId,
      double x,
      double y, {
      String? op,
      String sub = _owner,
    }) async {
      final data = await run(_upsertDoc, {
        'tagId': tagId,
        'x': x,
        'y': y,
        'op': op ?? nextOp(),
      }, sub: sub);
      return data['constellationTagMagnetUpsert'] as Map<String, dynamic>;
    }

    Future<List<Map<String, dynamic>>> listed({String sub = _owner}) async {
      final data = await run(_listDoc, {}, sub: sub);
      return (data['constellationTagMagnets'] as List<Object?>)
          .cast<Map<String, dynamic>>()
          .toList();
    }

    Future<int> rowCount() async =>
        (await writer.execute(
              'SELECT count(*) FROM public.constellation_tag_magnet',
            )).single.first!
            as int;

    test('upsert then list returns the magnet', () async {
      final tagId = await createTag('Neighbours');

      final created = await upsert(tagId, 3.5, -2.25);

      expect(created['tagId'], tagId);
      expect(created['xUnits'], 3.5);
      expect(created['yUnits'], -2.25);
      expect(await listed(), [created]);
    });

    test('a second upsert moves the magnet and raises its revision', () async {
      final tagId = await createTag('Neighbours');
      final first = await upsert(tagId, 1, 1);

      final moved = await upsert(tagId, -4, 6);

      expect(moved['xUnits'], -4);
      expect(moved['revision'] as int, greaterThan(first['revision'] as int));
      expect(await listed(), [moved]);
    });

    test('remove deletes the magnet', () async {
      final tagId = await createTag('Neighbours');
      await upsert(tagId, 1, 1);

      final data = await run(_removeDoc, {'tagId': tagId, 'op': nextOp()});

      expect(data['constellationTagMagnetRemove'], isTrue);
      expect(await listed(), isEmpty);
    });

    test('a repeated upsert replays the first result', () async {
      final tagId = await createTag('Neighbours');
      final first = await upsert(tagId, 2, 3, op: 'same-op');

      final second = await upsert(tagId, 2, 3, op: 'same-op');

      expect(second, first);
    });

    test('a reused clientOpId with another position is code 1906', () async {
      final tagId = await createTag('Neighbours');
      await upsert(tagId, 2, 3, op: 'same-op');

      final error = await failureOf(_upsertDoc, {
        'tagId': tagId,
        'x': 9.0,
        'y': 9.0,
        'op': 'same-op',
      });

      expect(error, contains('"code":"1906"'));
    });

    test('an empty or over-long clientOpId is code 1700', () async {
      final tagId = await createTag('Neighbours');
      for (final op in ['', 'x' * 65]) {
        expect(
          await failureOf(_upsertDoc, {
            'tagId': tagId,
            'x': 1.0,
            'y': 1.0,
            'op': op,
          }),
          contains('"code":"1700"'),
          reason: 'upsert with op length ${op.length}',
        );
        expect(
          await failureOf(_removeDoc, {'tagId': tagId, 'op': op}),
          contains('"code":"1700"'),
          reason: 'remove with op length ${op.length}',
        );
      }
      expect(await rowCount(), 0);
    });

    test('out-of-range coordinates are code 1701', () async {
      final tagId = await createTag('Neighbours');
      for (final (x, y) in [(1e9, 0.0), (0.0, -1e9)]) {
        expect(
          await failureOf(_upsertDoc, {
            'tagId': tagId,
            'x': x,
            'y': y,
            'op': nextOp(),
          }),
          contains('"code":"1701"'),
          reason: '($x, $y)',
        );
      }
      expect(await rowCount(), 0);
    });

    test('an unknown tag is code 1903', () async {
      expect(
        await failureOf(_upsertDoc, {
          'tagId': 'PTnosuchtag',
          'x': 0.0,
          'y': 0.0,
          'op': nextOp(),
        }),
        contains('"code":"1903"'),
      );
    });

    group('another user', () {
      late String tagId;
      late Map<String, dynamic> mine;

      setUp(() async {
        tagId = await createTag('Neighbours');
        mine = await upsert(tagId, 1, 1);
      });

      test('lists nothing of the owner', () async {
        expect(await listed(sub: _other), isEmpty);
      });

      test('cannot place a magnet on the owner tag', () async {
        expect(
          await failureOf(_upsertDoc, {
            'tagId': tagId,
            'x': 8.0,
            'y': 8.0,
            'op': nextOp(),
          }, sub: _other),
          contains('"code":"1903"'),
        );
        expect(await listed(), [mine]);
      });

      test('cannot remove the owner magnet', () async {
        expect(
          await failureOf(_removeDoc, {
            'tagId': tagId,
            'op': nextOp(),
          }, sub: _other),
          contains('"code":"1903"'),
        );
        expect(await listed(), [mine]);
      });

      test('has no way to name another viewer', () async {
        expect(
          await failureOf(
            r'''
query { constellationTagMagnets(viewerId: "Utmgqlowner0001") { tagId } }
''',
            {},
            sub: _other,
          ),
          isNotEmpty,
        );
      });
    });

    test(
      'deleting the tag through V2 removes its magnet from the list',
      () async {
        final tagId = await createTag('Neighbours');
        await upsert(tagId, 1, 1);

        await run(
          r'''
mutation($id: String!, $op: String!) {
  personTagDelete(id: $id, clientOpId: $op) { memberIds }
}
''',
          {'id': tagId, 'op': nextOp()},
        );

        expect(await listed(), isEmpty);
        expect(await rowCount(), 0);
      },
    );
  });
}
