@Tags(['pg'])
library;

import 'package:graphql_server2/graphql_server2.dart' show GraphQL;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/capability/capability_tag.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';

const _authorId = 'Uconvertgql001';
const _otherId = 'Uconvertgql002';

const _kindRequest = 0;
const _kindPost = 1;
const _policyClosed = 0;
const _policyOpen = 1;

const _convert = r'''
mutation Convert(
  $id: String!
  $title: String!
  $description: String
  $needs: String
  $primaryNeedSlug: String
  $startAt: String
  $endAt: String
  $isDiscoverable: Boolean
  $helperIds: [String!]
) {
  beaconConvertToRequest(
    id: $id
    title: $title
    description: $description
    needs: $needs
    primaryNeedSlug: $primaryNeedSlug
    startAt: $startAt
    endAt: $endAt
    isDiscoverable: $isDiscoverable
    helperIds: $helperIds
  ) {
    id
  }
}
''';

const _unauthorized = AuthExceptionCodes(
  AuthExceptionCode.authUnauthorizedException,
);
const _beaconCreateError = BeaconExceptionCodes(
  BeaconExceptionCode.beaconCreateException,
);

/// `beaconConvertToRequest` over the real V2 schema and real repositories: the
/// arguments and the caller's identity reach `BeaconCase.convertToRequest`.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONVERT_GQL_TEST_DB',
    defaultNamePrefix: 'tentura_test_convert_gql',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('beaconConvertToRequest', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late GraphQL schema;
    final slugs = kCapabilitySlugOrder.take(2).toList();

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
      for (final id in [_authorId, _otherId]) {
        await writer.execute(
          Sql.named(
            'INSERT INTO public."user" (id, display_name, public_key) '
            'VALUES (@id, @id, @key)',
          ),
          parameters: {'id': id, 'key': '$id-key'},
        );
      }
    });

    Future<void> insertPost(String id) => writer.execute(
      Sql.named(
        'INSERT INTO public.beacon '
        '(id, user_id, title, description, status, kind, forward_policy, '
        'is_discoverable, published_at) '
        "VALUES (@id, @author, '', '', 0, $_kindPost, $_policyClosed, false, "
        'now())',
      ),
      parameters: {'id': id, 'author': _authorId},
    );

    Future<ResultRow> beaconRow(String id) async => (await writer.execute(
      Sql.named(
        'SELECT kind, forward_policy, is_discoverable, title, description, '
        'needs, primary_need_slug, start_at, end_at '
        'FROM public.beacon WHERE id = @id',
      ),
      parameters: {'id': id},
    )).single;

    Future<Map<String, dynamic>> convertAs(
      String userId,
      String beaconId, {
      bool isDiscoverable = true,
    }) async =>
        await schema.parseAndExecute(
              _convert,
              variableValues: {
                'id': beaconId,
                'title': 'Help me move a piano',
                'description': 'Third floor, no lift, Saturday.',
                'needs': slugs.join(','),
                'primaryNeedSlug': slugs.last,
                'startAt': '2030-05-01T09:00:00Z',
                'endAt': '2030-05-03T18:00:00Z',
                'isDiscoverable': isDiscoverable,
                'helperIds': const <String>[],
              },
              globalVariables: {kGlobalInputQueryJwt: JwtEntity(sub: userId)},
            )
            as Map<String, dynamic>;

    Matcher rejectedWith(ExceptionCodes expected) => throwsA(
      predicate<Object>(
        (e) => e is ExceptionBase
            ? e.code.codeNumber == expected.codeNumber
            : e.toString().contains('"code":"${expected.codeNumber}"'),
        'fails with exception code ${expected.codeNumber}',
      ),
    );

    test(
      'passes Request fields and an empty helper selection through and returns '
      'the converted Request',
      () async {
        await insertPost('Bconvertgql01');

        final data = await convertAs(_authorId, 'Bconvertgql01');

        final beacon = data['beaconConvertToRequest']! as Map<String, dynamic>;
        expect(beacon['id'], 'Bconvertgql01');
        final row = await beaconRow('Bconvertgql01');
        expect(row[0], _kindRequest);
        expect(row[1], _policyOpen);
        expect(row[2], isTrue);
        expect(row[3], 'Help me move a piano');
        expect(row[4], 'Third floor, no lift, Saturday.');
        expect((row[5]! as String).split(',').toSet(), slugs.toSet());
        expect(row[6], slugs.last);
        expect((row[7]! as DateTime).toUtc(), DateTime.utc(2030, 5, 1, 9));
        expect((row[8]! as DateTime).toUtc(), DateTime.utc(2030, 5, 3, 18));
      },
    );

    test('passes isDiscoverable false through as false', () async {
      await insertPost('Bconvertgql02');

      await convertAs(_authorId, 'Bconvertgql02', isDiscoverable: false);

      final row = await beaconRow('Bconvertgql02');
      expect(row[0], _kindRequest);
      expect(row[2], isFalse);
    });

    test('acts as the caller from the credentials: a non-author is refused '
        'and the Post is unchanged', () async {
      await insertPost('Bconvertgql03');
      final before = await beaconRow('Bconvertgql03');

      await expectLater(
        convertAs(_otherId, 'Bconvertgql03'),
        rejectedWith(_unauthorized),
      );

      expect(await beaconRow('Bconvertgql03'), before);
    });

    test(
      'a validation failure surfaces as a BeaconCreateException code',
      () async {
        await insertPost('Bconvertgql04');

        await expectLater(
          schema.parseAndExecute(
            _convert,
            variableValues: {
              'id': 'Bconvertgql04',
              'title': '   ',
              'helperIds': const <String>[],
            },
            globalVariables: {
              kGlobalInputQueryJwt: const JwtEntity(sub: _authorId),
            },
          ),
          rejectedWith(_beaconCreateError),
        );

        expect((await beaconRow('Bconvertgql04'))[0], _kindPost);
      },
    );
  });
}
