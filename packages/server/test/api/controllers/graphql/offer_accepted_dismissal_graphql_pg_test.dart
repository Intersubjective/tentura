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

const _beaconId = 'Bofferdismiss1';
const _otherBeaconId = 'Bofferdismiss2';
const _authorId = 'Uodauthor0001';
const _helperId = 'Uodhelper0001';
const _otherHelperId = 'Uodhelper0002';
const _strangerId = 'Uodstranger01';

const _dismiss = r'''
mutation DismissOfferAccepted($beaconId: String!) {
  DismissOfferAccepted(beaconId: $beaconId) {
    userId
    beaconIds
  }
}
''';

const _list = r'''
query OfferAcceptedDismissals {
  offerAcceptedDismissals {
    userId
    beaconIds
  }
}
''';

/// B077b — the helper's × on the «Your help was accepted» sub-card is kept
/// on the server per account, so every device of that account hides it.
/// End to end over the real GraphQL schema (real DI, disposable Postgres).
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_OFFER_ACCEPTED_DISMISSAL_GQL_TEST_DB',
    defaultNamePrefix: 'tentura_test_offer_dismiss_gql',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('offer-accepted dismissal GraphQL (B077b)', () {
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
      await writer.execute('''
TRUNCATE TABLE
  public.offer_accepted_dismissal,
  public.beacon_help_offer,
  public.beacon,
  public."user"
CASCADE
''');
      for (final id in [_authorId, _helperId, _otherHelperId, _strangerId]) {
        await writer.execute(
          Sql.named(
            'INSERT INTO public."user" (id, display_name, public_key) '
            'VALUES (@id, @id, @key)',
          ),
          parameters: {'id': id, 'key': '$id-key'},
        );
      }
      for (final b in [_beaconId, _otherBeaconId]) {
        await writer.execute(
          Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@b, @author, 'Request', 'Needs help', 0)
'''),
          parameters: {'b': b, 'author': _authorId},
        );
      }
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_help_offer (beacon_id, user_id, message, status)
VALUES (@b, @h1, 'I can help', 0), (@b, @h2, 'Me too', 0),
       (@b2, @h1, 'Here too', 0)
'''),
        parameters: {
          'b': _beaconId,
          'b2': _otherBeaconId,
          'h1': _helperId,
          'h2': _otherHelperId,
        },
      );
    });

    Future<Map<String, dynamic>> run(
      String userId,
      String document, [
      Map<String, dynamic> variables = const {},
    ]) async =>
        await schema.parseAndExecute(
              document,
              variableValues: variables,
              globalVariables: {kGlobalInputQueryJwt: JwtEntity(sub: userId)},
            )
            as Map<String, dynamic>;

    Future<Map<String, dynamic>> dismiss(
      String userId,
      String beaconId,
    ) async =>
        (await run(userId, _dismiss, {
              'beaconId': beaconId,
            }))['DismissOfferAccepted']
            as Map<String, dynamic>;

    Future<Map<String, dynamic>> list(String userId) async =>
        (await run(userId, _list))['offerAcceptedDismissals']
            as Map<String, dynamic>;

    test('nothing dismissed yet: an empty list for the viewer', () async {
      final result = await list(_helperId);
      expect(result['userId'], _helperId);
      expect(result['beaconIds'], isEmpty);
    });

    test(
      'a helper dismisses; any later read (another device) sees it',
      () async {
        final result = await dismiss(_helperId, _beaconId);
        expect(result['userId'], _helperId);
        expect(result['beaconIds'], [_beaconId]);

        final again = await list(_helperId);
        expect(again['beaconIds'], [_beaconId]);
      },
    );

    test('dismissing twice is harmless', () async {
      await dismiss(_helperId, _beaconId);
      final result = await dismiss(_helperId, _beaconId);
      expect(result['beaconIds'], [_beaconId]);
    });

    test('dismissals are per account and per Request', () async {
      await dismiss(_helperId, _beaconId);
      expect((await list(_otherHelperId))['beaconIds'], isEmpty);

      await dismiss(_helperId, _otherBeaconId);
      expect(
        ((await list(_helperId))['beaconIds'] as List).toSet(),
        {_beaconId, _otherBeaconId},
      );
    });

    test('someone with no offer on the Request cannot record one', () async {
      await expectLater(dismiss(_strangerId, _beaconId), throwsA(anything));
      expect((await list(_strangerId))['beaconIds'], isEmpty);
    });
  }, skip: skipReason);
}
