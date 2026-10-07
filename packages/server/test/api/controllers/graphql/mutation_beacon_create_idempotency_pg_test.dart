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

const _authorId = 'Uidemcreate01';
const _otherAuthorId = 'Uidemcreate02';

const _createWithOpId = r"""
mutation CreateWithOpId($title: String, $description: String, $clientOpId: String) {
  beaconCreate(title: $title, description: $description, clientOpId: $clientOpId) { id }
}
""";

const _createWithoutOpId = r"""
mutation CreateWithoutOpId($title: String, $description: String) {
  beaconCreate(title: $title, description: $description) { id }
}
""";

const _opId = '6f1c1c4e-0a53-4a3e-9d5b-0b7d3f2f9a11';

/// Idempotent `beaconCreate` over the real V2 schema and real repositories.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_BEACON_CREATE_IDEMPOTENCY_GQL_TEST_DB',
    defaultNamePrefix: 'tentura_test_beacon_create_idem_gql',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('beaconCreate clientOpId idempotency', () {
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
      for (final id in [_authorId, _otherAuthorId]) {
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
      String author = _authorId,
    }) async =>
        await schema.parseAndExecute(
              document,
              variableValues: variables,
              globalVariables: {
                kGlobalInputQueryJwt: JwtEntity(sub: author),
              },
            )
            as Map<String, dynamic>;

    Future<int> beaconCount() async {
      final r = await writer.execute('SELECT count(*) FROM public.beacon');
      return r.single.first! as int;
    }

    Map<String, dynamic> vars([String? opId]) => {
      'title': 'Need a ride',
      'description': 'Needs help',
      'clientOpId': ?opId,
    };

    String idOf(Map<String, dynamic> data) =>
        (data['beaconCreate'] as Map)['id'] as String;

    test('a repeat with the same author and clientOpId returns the first '
        'Request and creates nothing new', () async {
      final first = idOf(await run(_createWithOpId, vars(_opId)));
      final second = idOf(await run(_createWithOpId, vars(_opId)));

      expect(second, first);
      expect(await beaconCount(), 1);
    });

    test('the same clientOpId from a different author creates a separate '
        'Request', () async {
      final mine = idOf(await run(_createWithOpId, vars(_opId)));
      final theirs = idOf(
        await run(_createWithOpId, vars(_opId), author: _otherAuthorId),
      );

      expect(theirs, isNot(mine));
      expect(await beaconCount(), 2);
    });

    test('a different clientOpId from the same author creates a separate '
        'Request', () async {
      final a = idOf(await run(_createWithOpId, vars(_opId)));
      final b = idOf(
        await run(
          _createWithOpId,
          vars('0c2b7a38-5d1e-4c55-8a3e-2f6f1d9b7e42'),
        ),
      );

      expect(b, isNot(a));
      expect(await beaconCount(), 2);
    });

    test('omitting clientOpId creates a new Request every time', () async {
      final a = idOf(await run(_createWithoutOpId, vars()));
      final b = idOf(await run(_createWithoutOpId, vars()));

      expect(b, isNot(a));
      expect(await beaconCount(), 2);
    });
  });
}
