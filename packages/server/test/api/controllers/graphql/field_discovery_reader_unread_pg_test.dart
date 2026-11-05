@Tags(['pg'])
library;

import 'package:graphql_server2/graphql_server2.dart' show GraphQL;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/query/query_constellation_field.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/pg_test_public_keys.dart';

const _viewer = 'Ufielddisc001';
const _author = 'Ufielddisc002';
const _request = 'Bfielddisc001';

// Coverage: production DI (the real room use case and Field resolver) and
// migrated PostgreSQL. A reader who can discover a Request but has no room
// access (no forward, no admission) must not be stuck with an unread flag they
// have no way to clear. Input device, viewport and locale are n/a (server only).
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FIELD_DISCOVERY_READER_UNREAD_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_field_discovery_reader_unread',
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

  setUp(() async {
    await writer.execute('TRUNCATE public."user" CASCADE');
    for (final (index, id) in [_viewer, _author].indexed) {
      await writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
        parameters: {
          'id': id,
          'key': pgTestPublicKey('field-discovery-unread', index + 1),
        },
      );
    }
    await writer.execute(
      Sql.named('''
INSERT INTO public.vote_user (subject, object, amount)
VALUES (@viewer, @author, 1), (@author, @viewer, 1)
'''),
      parameters: {'viewer': _viewer, 'author': _author},
    );
    // Discoverable only: no forward edge, no participant row.
    await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, is_discoverable,
   published_at, expires_at)
VALUES ('$_request', '$_author', 'Help with the garden', '', 0, 0, true, now(), NULL)
''');
  });

  Future<Map<String, dynamic>> fieldRow() async {
    final payload =
        await QueryConstellationField().constellationField.resolve!(null, {
              kGlobalInputQueryJwt: const JwtEntity(sub: _viewer),
              'showClosed': false,
              'participatedOnly': false,
              'projection': 'FULL',
            })
            as Map<String, dynamic>;
    return (payload['requests'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((row) => row['id'] == _request);
  }

  // The operations the app sends when a signed-in reader opens a Request they
  // can see but hold no room seat in: the room screen is never mounted for
  // them, so only the open-time acknowledgements are sent.
  Future<void> openRequestAsDiscoveryReader() async {
    for (final operation in [
      'beaconForwardMarkRead(id: "$_request")',
      'attentionMarkSeenForBeacon(beaconId: "$_request")',
    ]) {
      final result =
          await schema.parseAndExecute(
                'mutation { $operation }',
                globalVariables: {
                  kGlobalInputQueryJwt: const JwtEntity(sub: _viewer),
                },
              )
              as Map<String, dynamic>;
      expect(result.keys.single, isNotEmpty, reason: '$operation: $result');
    }
  }

  group('Field unread flag for a discovery-only reader', () {
    test('opening the Request leaves it read', () async {
      final access = await writer.execute('''
SELECT public.beacon_effective_admission('$_request', '$_viewer')
''');
      expect(access.single.single, isFalse, reason: 'fixture: no room access');
      expect(
        await fieldRow(),
        containsPair('has_unread', true),
        reason: 'fixture: an unopened Request by someone else starts unread',
      );
      await openRequestAsDiscoveryReader();
      expect(
        await fieldRow(),
        containsPair('has_unread', false),
        reason: 'a Request the reader opened must stop showing as unread',
      );
    });

    test('a Request nobody opened stays unread for other readers', () async {
      await openRequestAsDiscoveryReader();
      const other = 'Ufielddisc003';
      await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$other', '$other', '${pgTestPublicKey('field-discovery-unread', 3)}')
''');
      await writer.execute('''
INSERT INTO public.vote_user (subject, object, amount)
VALUES ('$other', '$_author', 1), ('$_author', '$other', 1)
''');
      final payload =
          await QueryConstellationField().constellationField.resolve!(null, {
                kGlobalInputQueryJwt: const JwtEntity(sub: other),
                'showClosed': false,
                'participatedOnly': false,
                'projection': 'FULL',
              })
              as Map<String, dynamic>;
      final row = (payload['requests'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((row) => row['id'] == _request);
      expect(row, containsPair('has_unread', true));
    });
  });
}
