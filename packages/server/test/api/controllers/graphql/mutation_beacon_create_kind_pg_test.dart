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

const _authorId = 'Ukindcreate01';

const _createPost = r'''
mutation CreatePost($kind: Int, $forwardPolicy: Int) {
  beaconCreate(kind: $kind, forwardPolicy: $forwardPolicy) { id }
}
''';

const _createPostWithTitle = r'''
mutation CreatePostWithTitle($kind: Int, $title: String) {
  beaconCreate(kind: $kind, title: $title) { id }
}
''';

const _createNoKindNoTitle = '''
mutation CreateNoKindNoTitle {
  beaconCreate { id }
}
''';

const _missingTitleMessage =
    'Missing value for argument "title" of field "beaconCreate".';

String _errorText(Object e) => e.toString();

const _createDiscoverablePost = r'''
mutation CreateDiscoverablePost($kind: Int, $isDiscoverable: Boolean) {
  beaconCreate(kind: $kind, isDiscoverable: $isDiscoverable) { id }
}
''';

const _createRequestNoDescription = r'''
mutation CreateRequestNoDescription($title: String) {
  beaconCreate(title: $title) { id }
}
''';

const _createUntitledRequest = r'''
mutation CreateUntitled($description: String) {
  beaconCreate(description: $description) { id }
}
''';

const _createRequest = r'''
mutation CreateRequest($title: String, $description: String) {
  beaconCreate(title: $title, description: $description) { id }
}
''';

/// Kind-aware `beaconCreate` over the real V2 schema and real repositories.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_BEACON_CREATE_KIND_GQL_TEST_DB',
    defaultNamePrefix: 'tentura_test_beacon_create_kind_gql',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('beaconCreate kind argument', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late GraphQL schema;

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
      await writer.execute(
        'TRUNCATE TABLE public.beacon, public."user" CASCADE',
      );
      await writer.execute(
        Sql.named(
          'INSERT INTO public."user" (id, display_name, public_key) '
          'VALUES (@id, @id, @key)',
        ),
        parameters: {'id': _authorId, 'key': '$_authorId-key'},
      );
    });

    Future<Map<String, dynamic>> run(
      String document,
      Map<String, dynamic> variables,
    ) async =>
        await schema.parseAndExecute(
              document,
              variableValues: variables,
              globalVariables: {
                kGlobalInputQueryJwt: const JwtEntity(sub: _authorId),
              },
            )
            as Map<String, dynamic>;

    Future<int> beaconCount() async {
      final r = await writer.execute('SELECT count(*) FROM public.beacon');
      return r.single.first! as int;
    }

    test('creates an untitled Post draft with its forward policy', () async {
      final data = await run(_createPost, {'kind': 1, 'forwardPolicy': 0});
      final id = (data['beaconCreate'] as Map)['id'] as String;
      final rows = await writer.execute(
        Sql.named(
          'SELECT kind, forward_policy, status, title, description, '
          'is_discoverable '
          'FROM public.beacon WHERE id = @id',
        ),
        parameters: {'id': id},
      );
      expect(rows.single.toList(), [1, 0, 3, '', '', false]);
    });

    test('rejects a Post that carries a title', () async {
      await expectLater(
        run(_createPostWithTitle, {'kind': 1, 'title': 'Hello post'}),
        throwsA(
          predicate<Object>(
            (e) =>
                RegExp('post', caseSensitive: false).hasMatch(_errorText(e)) &&
                RegExp('title', caseSensitive: false).hasMatch(_errorText(e)) &&
                !_errorText(e).contains('Unknown argument') &&
                !_errorText(e).contains('Type coercion') &&
                !_errorText(e).contains(_missingTitleMessage),
            'rejects because a Post must not have a title',
          ),
        ),
      );
      expect(await beaconCount(), 0);
    });

    test('rejects a discoverable Post', () async {
      await expectLater(
        run(_createDiscoverablePost, {'kind': 1, 'isDiscoverable': true}),
        throwsA(
          predicate<Object>(
            (e) =>
                RegExp(
                  'discoverable',
                  caseSensitive: false,
                ).hasMatch(_errorText(e)) &&
                !_errorText(e).contains('Unknown argument'),
            'rejects because a Post must not be discoverable',
          ),
        ),
      );
      expect(await beaconCount(), 0);
    });

    test('rejects a titled Request without a description', () async {
      await expectLater(
        run(_createRequestNoDescription, {'title': 'Need a ride'}),
        throwsA(
          predicate<Object>(
            (e) => _errorText(e).contains('Description is required'),
            'reports the missing description',
          ),
        ),
      );
      expect(await beaconCount(), 0);
    });

    test('rejects a Request without a title', () async {
      await expectLater(
        run(_createUntitledRequest, {'description': 'Needs help'}),
        throwsA(
          predicate<Object>(
            (e) => _errorText(e).contains(_missingTitleMessage),
            'reports the missing title argument',
          ),
        ),
      );
      expect(await beaconCount(), 0);
    });

    test('rejects beaconCreate with neither kind nor title', () async {
      await expectLater(
        run(_createNoKindNoTitle, {}),
        throwsA(
          predicate<Object>(
            (e) => _errorText(e).contains(_missingTitleMessage),
            'reports the missing title argument',
          ),
        ),
      );
      expect(await beaconCount(), 0);
    });

    test('still creates a titled Request as kind 0', () async {
      final data = await run(_createRequest, {
        'title': 'Need a ride',
        'description': 'Needs help',
      });
      final id = (data['beaconCreate'] as Map)['id'] as String;
      final rows = await writer.execute(
        Sql.named('SELECT kind, title FROM public.beacon WHERE id = @id'),
        parameters: {'id': id},
      );
      expect(rows.single.toList(), [0, 'Need a ride']);
    });
  });
}
