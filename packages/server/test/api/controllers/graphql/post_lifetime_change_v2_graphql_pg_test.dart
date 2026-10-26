@Tags(['pg'])
library;

import 'dart:convert';

import 'package:graphql_server2/graphql_server2.dart' show GraphQL;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';

const _authorId = 'Uchgqlauthor1';
const _otherId = 'Uchgqlother01';
const _post = 'Bchgqlpost001';

const _statusOpen = 0;
const _statusClosed = 6;

const _shortenDocument = r'''
mutation Shorten($id: String!, $expiresAt: String!) {
  postShorten(id: $id, expiresAt: $expiresAt)
}
''';

const _closeDocument = r'''
mutation Close($id: String!) {
  postClose(id: $id)
}
''';

/// `postShorten` and `postClose` reached through the registered V2 schema
/// (the aggregate of every mutation) over the real repositories.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_LIFETIME_CHANGE_GQL_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_lifetime_change_gql',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('postShorten and postClose in the V2 schema', () {
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
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at, expires_at, expiry_warning_eligible)
VALUES (@id, @author, '', '', 0, 1, 1, false,
        now() - interval '1 hour', now() + interval '71 hours', true)
'''),
        parameters: {'id': _post, 'author': _authorId},
      );
    });

    Future<Map<String, dynamic>> run(
      String document,
      Map<String, dynamic> variables, {
      String userId = _authorId,
    }) async =>
        await schema.parseAndExecute(
              document,
              variableValues: variables,
              globalVariables: {kGlobalInputQueryJwt: JwtEntity(sub: userId)},
            )
            as Map<String, dynamic>;

    Future<DateTime> expiresAt() async =>
        (await writer.execute(
              "SELECT expires_at FROM public.beacon WHERE id = '$_post'",
            )).single.single!
            as DateTime;

    Future<int> status() async =>
        (await writer.execute(
              "SELECT status FROM public.beacon WHERE id = '$_post'",
            )).single.single!
            as int;

    /// The call failed with exactly the exception code [expected]: either the
    /// exception itself or its wire form `{"extensions":{"code":"<n>"}}`.
    Matcher rejectedWith(ExceptionCodes expected) => throwsA(
      predicate<Object>(
        (e) => e is ExceptionBase
            ? e.code.codeNumber == expected.codeNumber
            : e.toString().contains('"code":"${expected.codeNumber}"'),
        'fails with exception code ${expected.codeNumber}',
      ),
    );

    String iso(Duration fromNow) =>
        DateTime.now().toUtc().add(fromNow).toIso8601String();

    Future<void> setPost({required int status, required String expires}) =>
        writer.execute('''
UPDATE public.beacon
SET status = $status, published_at = now() - interval '10 hours',
    expires_at = $expires
WHERE id = '$_post'
''');

    Future<List<Map<String, Object?>>> lifecycleDiffs() async {
      final rows = await writer.execute('''
SELECT diff FROM public.beacon_activity_event
WHERE beacon_id = '$_post'
  AND type = ${BeaconActivityEventTypeBits.beaconLifecycleChanged}
''');
      return [
        for (final row in rows)
          switch (row[0]) {
            final Map<String, Object?> map => map,
            final String text => jsonDecode(text) as Map<String, Object?>,
            _ => throw StateError('Not JSON: ${row[0]}'),
          },
      ];
    }

    const unauthorized = UnauthorizedException();
    const notOpen = PostNotOpenException();
    const invalidLifetime = PostLifetimeInvalidException();
    const extendLifetime = PostLifetimeExtendException();

    test(
      'postShorten moves the end of the Post to the requested time',
      () async {
        final target = DateTime.now().toUtc().add(const Duration(hours: 6));

        final data = await run(_shortenDocument, {
          'id': _post,
          'expiresAt': target.toIso8601String(),
        });

        expect(data['postShorten'], isTrue);
        expect(
          (await expiresAt()).difference(target).abs(),
          lessThan(const Duration(milliseconds: 1)),
        );
        expect(await status(), _statusOpen);
      },
    );

    test('postShorten refuses a later end with the lifetime-extend error and '
        'leaves the Post unchanged', () async {
      final before = await expiresAt();

      await expectLater(
        run(_shortenDocument, {
          'id': _post,
          'expiresAt': before
              .add(const Duration(hours: 1))
              .toUtc()
              .toIso8601String(),
        }),
        rejectedWith(extendLifetime.code),
      );

      expect(await expiresAt(), before);
    });

    test('postShorten refuses an end in the past with the invalid-lifetime '
        'error and leaves the Post unchanged', () async {
      final before = await expiresAt();

      await expectLater(
        run(_shortenDocument, {
          'id': _post,
          'expiresAt': iso(const Duration(hours: -1)),
        }),
        rejectedWith(invalidLifetime.code),
      );

      expect(await expiresAt(), before);
      expect(await status(), _statusOpen);
    });

    test('postShorten refuses someone who is not the author with the '
        'unauthorized error', () async {
      final before = await expiresAt();

      await expectLater(
        run(_shortenDocument, {
          'id': _post,
          'expiresAt': iso(const Duration(hours: 6)),
        }, userId: _otherId),
        rejectedWith(unauthorized.code),
      );

      expect(await expiresAt(), before);
    });

    test(
      'postShorten refuses a closed Post with the Post-not-open error',
      () async {
        await setPost(
          status: _statusClosed,
          expires: "now() - interval '1 minute'",
        );
        final before = await expiresAt();

        await expectLater(
          run(_shortenDocument, {
            'id': _post,
            'expiresAt': iso(const Duration(hours: 1)),
          }),
          rejectedWith(notOpen.code),
        );

        expect(await expiresAt(), before);
      },
    );

    test('postShorten refuses an expired Post that is not yet swept with the '
        'Post-not-open error', () async {
      await setPost(
        status: _statusOpen,
        expires: "now() - interval '1 minute'",
      );

      await expectLater(
        run(_shortenDocument, {
          'id': _post,
          'expiresAt': iso(const Duration(hours: 1)),
        }),
        rejectedWith(notOpen.code),
      );

      expect(await status(), _statusOpen);
    });

    test(
      'postClose closes the Post and records that the author closed it',
      () async {
        final data = await run(_closeDocument, {'id': _post});

        expect(data['postClose'], isTrue);
        expect(await status(), _statusClosed);
        final diffs = await lifecycleDiffs();
        expect(diffs, hasLength(1));
        expect(diffs.single['reason'], 'postClosedByAuthor');
        expect(diffs.single['toStatus'], _statusClosed);
      },
    );

    test(
      'postClose refuses a second close with the Post-not-open error',
      () async {
        await run(_closeDocument, {'id': _post});

        await expectLater(
          run(_closeDocument, {'id': _post}),
          rejectedWith(notOpen.code),
        );
        expect(await lifecycleDiffs(), hasLength(1));
      },
    );

    test('postClose refuses an expired Post that is not yet swept with the '
        'Post-not-open error', () async {
      await setPost(
        status: _statusOpen,
        expires: "now() - interval '1 minute'",
      );

      await expectLater(
        run(_closeDocument, {'id': _post}),
        rejectedWith(notOpen.code),
      );

      expect(await status(), _statusOpen);
    });

    test('postClose refuses someone who is not the author with the '
        'unauthorized error', () async {
      await expectLater(
        run(_closeDocument, {'id': _post}, userId: _otherId),
        rejectedWith(unauthorized.code),
      );

      expect(await status(), _statusOpen);
      expect(await lifecycleDiffs(), isEmpty);
    });
  });
}
