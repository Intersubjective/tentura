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
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';

const _authorId = 'Uforwardopen01';
const _otherId = 'Uforwardopen02';

const _statusOpen = 0;
const _statusDraft = 3;
const _statusDeleted = 2;
const _kindRequest = 0;
const _kindPost = 1;
const _policyClosed = 0;
const _policyOpen = 1;

const _openForwarding = r'''
mutation OpenForwarding($id: String!) {
  beaconForwardingOpen(id: $id)
}
''';

const _unauthorized = AuthExceptionCodes(
  AuthExceptionCode.authUnauthorizedException,
);
const _beaconCreateError = BeaconExceptionCodes(
  BeaconExceptionCode.beaconCreateException,
);

/// Author-only, one-way `beaconForwardingOpen` over the real V2 schema and
/// real repositories.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FWD_OPEN_GQL_TEST_DB',
    defaultNamePrefix: 'tentura_test_fwd_open_gql',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('beaconForwardingOpen', () {
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

    Future<void> insertBeacon({
      required String id,
      required int kind,
      required int policy,
      int status = _statusOpen,
    }) => writer.execute(
      Sql.named(
        'INSERT INTO public.beacon '
        '(id, user_id, title, description, status, kind, forward_policy, '
        'is_discoverable, published_at) '
        'VALUES (@id, @author, @title, @description, @status, @kind, '
        '@policy, false, now())',
      ),
      parameters: {
        'id': id,
        'author': _authorId,
        'title': kind == _kindPost ? '' : 'Request title',
        'description': kind == _kindPost ? '' : 'Request description',
        'status': status,
        'kind': kind,
        'policy': policy,
      },
    );

    Future<int> policyOf(String id) async {
      final rows = await writer.execute(
        Sql.named('SELECT forward_policy FROM public.beacon WHERE id = @id'),
        parameters: {'id': id},
      );
      return rows.single.single! as int;
    }

    Future<Map<String, dynamic>> openAs(String userId, String beaconId) async =>
        await schema.parseAndExecute(
              _openForwarding,
              variableValues: {'id': beaconId},
              globalVariables: {kGlobalInputQueryJwt: JwtEntity(sub: userId)},
            )
            as Map<String, dynamic>;

    /// The call failed with exactly the exception [expected]: either the
    /// exception itself or its wire form `{"extensions":{"code":"<n>"}}`.
    Matcher rejectedWith(ExceptionCodes expected) => throwsA(
      predicate<Object>(
        (e) => e is ExceptionBase
            ? e.code.codeNumber == expected.codeNumber
            : e.toString().contains('"code":"${expected.codeNumber}"'),
        'fails with exception code ${expected.codeNumber}',
      ),
    );

    /// Proves the mutation exists and works, so a rejection test cannot pass
    /// merely because the field is missing.
    Future<void> expectMutationWorksOnControlPost() async {
      await insertBeacon(
        id: 'Bfwdopenctrl1',
        kind: _kindPost,
        policy: _policyClosed,
      );
      final data = await openAs(_authorId, 'Bfwdopenctrl1');
      expect(data['beaconForwardingOpen'], isTrue);
      expect(await policyOf('Bfwdopenctrl1'), _policyOpen);
    }

    test(
      'lets the author open forwarding on a Post with closed forwarding',
      () async {
        await insertBeacon(
          id: 'Bfwdopenpost1',
          kind: _kindPost,
          policy: _policyClosed,
        );

        final data = await openAs(_authorId, 'Bfwdopenpost1');

        expect(data['beaconForwardingOpen'], isTrue);
        expect(await policyOf('Bfwdopenpost1'), _policyOpen);
      },
    );

    test('errors on a second call once forwarding is open', () async {
      await insertBeacon(
        id: 'Bfwdopenpost1',
        kind: _kindPost,
        policy: _policyClosed,
      );
      final first = await openAs(_authorId, 'Bfwdopenpost1');
      expect(first['beaconForwardingOpen'], isTrue);

      await expectLater(
        openAs(_authorId, 'Bfwdopenpost1'),
        rejectedWith(_beaconCreateError),
      );
      expect(await policyOf('Bfwdopenpost1'), _policyOpen);
    });

    test('rejects a non-author and leaves forwarding closed', () async {
      await insertBeacon(
        id: 'Bfwdopenpost1',
        kind: _kindPost,
        policy: _policyClosed,
      );

      await expectLater(
        openAs(_otherId, 'Bfwdopenpost1'),
        rejectedWith(_unauthorized),
      );

      expect(await policyOf('Bfwdopenpost1'), _policyClosed);
      await expectMutationWorksOnControlPost();
    });

    test('rejects a Request even for its author', () async {
      await insertBeacon(
        id: 'Bfwdopenreq01',
        kind: _kindRequest,
        policy: _policyOpen,
      );

      await expectLater(
        openAs(_authorId, 'Bfwdopenreq01'),
        rejectedWith(_beaconCreateError),
      );

      expect(await policyOf('Bfwdopenreq01'), _policyOpen);
      await expectMutationWorksOnControlPost();
    });

    test('rejects a Post that is still a draft', () async {
      await insertBeacon(
        id: 'Bfwdopendraft',
        kind: _kindPost,
        policy: _policyClosed,
        status: _statusDraft,
      );

      await expectLater(
        openAs(_authorId, 'Bfwdopendraft'),
        rejectedWith(_beaconCreateError),
      );

      expect(await policyOf('Bfwdopendraft'), _policyClosed);
      await expectMutationWorksOnControlPost();
    });

    test('rejects a Post that has been deleted', () async {
      await insertBeacon(
        id: 'Bfwdopendel01',
        kind: _kindPost,
        policy: _policyClosed,
        status: _statusDeleted,
      );

      await expectLater(
        openAs(_authorId, 'Bfwdopendel01'),
        rejectedWith(_beaconCreateError),
      );

      expect(await policyOf('Bfwdopendel01'), _policyClosed);
      await expectMutationWorksOnControlPost();
    });
  });
}
