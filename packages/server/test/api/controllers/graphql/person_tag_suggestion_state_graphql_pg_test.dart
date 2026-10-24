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

const _owner = 'Uatsugowner00001';
const _other = 'Uatsugother00001';

const _stateDoc = '''
query { personTagSuggestionState { canSuggest silencedUntil disabled } }
''';

const _recordDoc = r'''
mutation Record($outcome: String!, $clientOpId: String!) {
  personTagSuggestionRecord(outcome: $outcome, clientOpId: $clientOpId) {
    canSuggest silencedUntil disabled
  }
}
''';

/// "Tag them?" suggestion frequency state over the real V2 schema: three
/// consecutive "Not now" answers silence suggestions for 30 days, an
/// acceptance resets the streak, and "Don't suggest again" can be switched
/// back on from the People tags screen.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PERSON_TAG_SUGGESTION_GQL_TEST_DB',
    defaultNamePrefix: 'tentura_test_person_tag_suggestion_gql',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('tag suggestion state GraphQL', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late GraphQL schema;
    var opCounter = 0;

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
      String document, [
      Map<String, dynamic> variables = const {},
      String sub = _owner,
    ]) async =>
        await schema.parseAndExecute(
              document,
              variableValues: variables,
              globalVariables: {kGlobalInputQueryJwt: JwtEntity(sub: sub)},
            )
            as Map<String, dynamic>;

    Future<Map<String, dynamic>> state([String sub = _owner]) async =>
        (await run(_stateDoc, const {}, sub))['personTagSuggestionState']!
            as Map<String, dynamic>;

    Future<Map<String, dynamic>> record(
      String outcome, {
      String? opId,
      String sub = _owner,
    }) async =>
        (await run(_recordDoc, {
              'outcome': outcome,
              'clientOpId': opId ?? 'suggestion-op-${opCounter++}',
            }, sub))['personTagSuggestionRecord']!
            as Map<String, dynamic>;

    Future<int> storedSkips([String owner = _owner]) async {
      final rows = await writer.execute(
        'SELECT consecutive_skips FROM public.person_tag_suggestion_state '
        "WHERE owner_id = '$owner'",
      );
      return rows.isEmpty ? 0 : rows.single.single! as int;
    }

    Future<void> skip(int times) async {
      for (var i = 0; i < times; i++) {
        await record('skipped');
      }
    }

    DateTime asDateTime(Object? value) =>
        value is DateTime ? value : DateTime.parse(value! as String);

    test('a person who never answered can be suggested to', () async {
      final s = await state();
      expect(s['canSuggest'], isTrue);
      expect(s['silencedUntil'], isNull);
      expect(s['disabled'], isFalse);
    });

    test('two skipped suggestions do not silence suggestions yet', () async {
      await skip(2);

      expect((await state())['canSuggest'], isTrue);
      expect((await state())['silencedUntil'], isNull);
      expect(await storedSkips(), 2);
    });

    group('three consecutive skipped suggestions', () {
      test('stop suggestions for 30 days and reset the streak', () async {
        await skip(2);
        final before = DateTime.now().toUtc();

        final result = await record('skipped');

        expect(result['canSuggest'], isFalse);
        expect(result['disabled'], isFalse);
        final until = asDateTime(result['silencedUntil']).toUtc();
        final gap = until.difference(before).inMinutes;
        expect(gap, inInclusiveRange(30 * 24 * 60 - 5, 30 * 24 * 60 + 5));
        final read = await state();
        expect(read['canSuggest'], isFalse);
        expect(asDateTime(read['silencedUntil']).toUtc(), until);
        expect(await storedSkips(), 0);
      });

      test('stay off while the silenced time is still in the future', () async {
        await skip(3);
        await writer.execute(
          'UPDATE public.person_tag_suggestion_state SET silenced_until = '
          "now() + interval '1 minute' WHERE owner_id = '$_owner'",
        );

        final s = await state();
        expect(s['canSuggest'], isFalse);
        expect(s['disabled'], isFalse);
        expect(s['silencedUntil'], isNotNull);
      });

      test('resume suggesting once the silenced time has passed', () async {
        await skip(3);
        expect((await state())['canSuggest'], isFalse);
        await writer.execute(
          'UPDATE public.person_tag_suggestion_state SET silenced_until = '
          "now() - interval '1 second' WHERE owner_id = '$_owner'",
        );

        final expired = await state();

        expect(expired['disabled'], isFalse);
        expect(expired['canSuggest'], isTrue);
      });

      test('start a fresh streak after the silence has expired', () async {
        await skip(3);
        await writer.execute(
          'UPDATE public.person_tag_suggestion_state SET silenced_until = '
          "now() - interval '1 second' WHERE owner_id = '$_owner'",
        );

        await skip(2);
        expect((await state())['canSuggest'], isTrue);
        expect(await storedSkips(), 2);

        await record('skipped');
        final s = await state();
        expect(s['canSuggest'], isFalse);
        expect(
          asDateTime(s['silencedUntil']).isAfter(DateTime.now().toUtc()),
          isTrue,
        );
      });
    });

    group('an accepted suggestion between skips', () {
      test('resets the stored skip counter', () async {
        await skip(2);
        expect(await storedSkips(), 2);

        final accepted = await record('accepted');

        expect(accepted['canSuggest'], isTrue);
        expect(accepted['silencedUntil'], isNull);
        expect(await storedSkips(), 0);
      });

      test('keeps later skips below the silencing threshold', () async {
        await skip(2);
        await record('accepted');

        await skip(2);

        final s = await state();
        expect(s['canSuggest'], isTrue);
        expect(s['silencedUntil'], isNull);
        expect(await storedSkips(), 2);
      });

      test('needs three fresh skips afterwards to silence', () async {
        await skip(2);
        await record('accepted');
        await skip(2);
        expect((await state())['canSuggest'], isTrue);

        await record('skipped');

        final s = await state();
        expect(s['canSuggest'], isFalse);
        expect(s['silencedUntil'], isNotNull);
      });
    });

    group("Don't suggest again", () {
      test('disabling stops suggestions and keeps them off', () async {
        final result = await record('disabled');

        expect(result['disabled'], isTrue);
        expect(result['canSuggest'], isFalse);
        final s = await state();
        expect(s['disabled'], isTrue);
        expect(s['canSuggest'], isFalse);
      });

      test('enabling clears the switch and any silenced time', () async {
        await skip(3);
        await record('disabled');
        expect((await state())['canSuggest'], isFalse);

        final result = await record('enabled');

        expect(result['disabled'], isFalse);
        expect(result['silencedUntil'], isNull);
        expect(result['canSuggest'], isTrue);
        final s = await state();
        expect(s['disabled'], isFalse);
        expect(s['silencedUntil'], isNull);
        expect(s['canSuggest'], isTrue);
      });

      test(
        'a person who disabled stays off after the silence expires',
        () async {
          await skip(3);
          await record('disabled');
          await writer.execute(
            'UPDATE public.person_tag_suggestion_state SET silenced_until = '
            "now() - interval '1 second' WHERE owner_id = '$_owner'",
          );

          expect((await state())['canSuggest'], isFalse);
        },
      );
    });

    test('a repeated clientOpId counts the skipped suggestion once', () async {
      await record('skipped', opId: 'same-op');
      await record('skipped', opId: 'same-op');
      await record('skipped', opId: 'same-op');

      expect((await state())['canSuggest'], isTrue);
      expect(await storedSkips(), 1);
    });

    test('a clientOpId reused for a different outcome is code 1906 and '
        'changes nothing', () async {
      await record('skipped', opId: 'same-op');

      Object? error;
      try {
        await record('disabled', opId: 'same-op');
      } on Object catch (e) {
        error = e;
      }

      expect(error, isNotNull, reason: 'reusing the id must be rejected');
      expect(error.toString(), contains('"code":"1906"'));
      final s = await state();
      expect(s['disabled'], isFalse);
      expect(s['canSuggest'], isTrue);
      expect(await storedSkips(), 1);
    });

    test('an unknown outcome is rejected and changes nothing', () async {
      await skip(1);

      await expectLater(record('maybe'), throwsA(anything));

      expect(await storedSkips(), 1);
    });

    test('suggestion state is kept per person', () async {
      await skip(3);
      await record('disabled', sub: _other);

      expect((await state())['canSuggest'], isFalse);
      expect((await state())['disabled'], isFalse);
      expect(await storedSkips(_other), 0);
      expect((await state(_other))['silencedUntil'], isNull);
      expect((await state(_other))['disabled'], isTrue);
    });
  });
}
