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

const _owner = 'Uptsrcowner0001';
const _outsider = 'Uptsrcoutsider01';
const _alice = 'Uptsrcalice0001';
const _bob = 'Uptsrcbob000001';
const _carol = 'Uptsrccarol00001';
const _dave = 'Uptsrcdave00001';

const _iTrust = 1;
const _trustsMe = 2;

const _request = 'Bsrcrequest01';
const _post = 'Bsrcpost00001';

/// Source value stored on a membership row (spec: 2 = copied from an
/// automatic tag, 3 = copied from a Request).
const _sourceAutoTag = 2;
const _sourceRequest = 3;

const _createFromDoc = r'''
mutation Create(
  $name: String!, $clientOpId: String!, $fromAutoKind: Int,
  $fromBeaconId: String
) {
  personTagCreate(
    name: $name, clientOpId: $clientOpId,
    fromAutoKind: $fromAutoKind, fromBeaconId: $fromBeaconId
  ) { id }
}
''';

const _tagsDoc = '''
query { personTags { id } }
''';

/// Creating an owner's tag pre-filled from an automatic tag ("make it my
/// tag") or from the members of a Request, over the real V2 schema.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PEOPLE_TAG_CREATE_SOURCE_GQL_TEST_DB',
    defaultNamePrefix: 'tentura_test_people_tag_create_source_gql',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('person tag creation from an automatic tag or a Request', () {
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
      for (final id in [_owner, _outsider, _alice, _bob, _carol, _dave]) {
        await writer.execute(
          Sql.named(
            'INSERT INTO public."user" (id, display_name, public_key) '
            'VALUES (@id, @id, @key)',
          ),
          parameters: {'id': id, 'key': '$id-key'},
        );
      }
    });

    String nextOp() => 'op-${opCounter++}';

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

    Future<String> failureOf(
      Map<String, dynamic> variables, {
      String sub = _owner,
    }) async {
      try {
        await run(_createFromDoc, variables, sub: sub);
      } on Object catch (e) {
        return e.toString();
      }
      fail('expected the operation to fail');
    }

    Future<String> createFromAuto(int kind, {String sub = _owner}) async {
      final data = await run(_createFromDoc, {
        'name': 'From facts',
        'clientOpId': nextOp(),
        'fromAutoKind': kind,
      }, sub: sub);
      return (data['personTagCreate'] as Map<String, dynamic>)['id']! as String;
    }

    Future<String> createFromRequest(
      String beaconId, {
      String sub = _owner,
    }) async {
      final data = await run(_createFromDoc, {
        'name': 'From request',
        'clientOpId': nextOp(),
        'fromBeaconId': beaconId,
      }, sub: sub);
      return (data['personTagCreate'] as Map<String, dynamic>)['id']! as String;
    }

    Future<List<({String person, int source})>> stored(String tagId) async => [
      for (final r in await writer.execute(
        Sql.named(
          'SELECT person_id, source FROM public.person_tag_member '
          'WHERE tag_id = @tag ORDER BY person_id',
        ),
        parameters: {'tag': tagId},
      ))
        (person: r[0]! as String, source: r[1]! as int),
    ];

    Future<int> ownTagCount() async =>
        ((await run(_tagsDoc, {}))['personTags'] as List<Object?>).length;

    Future<void> trust(String from, String to) => writer.execute(
      Sql.named(
        'INSERT INTO public.vote_user (subject, object, amount) '
        'VALUES (@a, @b, 1)',
      ),
      parameters: {'a': from, 'b': to},
    );

    Future<void> untrust(String from, String to) => writer.execute(
      Sql.named(
        'DELETE FROM public.vote_user WHERE subject = @a AND object = @b',
      ),
      parameters: {'a': from, 'b': to},
    );

    Future<void> block(String blocker, String blocked) => writer.execute(
      Sql.named(
        'INSERT INTO public.user_block (blocker_id, blocked_id, origin_id) '
        'VALUES (@a, @b, @a)',
      ),
      parameters: {'a': blocker, 'b': blocked},
    );

    Future<void> insertRequest(String id, String authorId) => writer.execute(
      Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, published_at)
VALUES (@id, @author, 'Request', 'd', 0, 0, now())
'''),
      parameters: {'id': id, 'author': authorId},
    );

    Future<void> insertPost(String id, String authorId) => writer.execute(
      Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES (@id, @author, '', '', 0, 1, 1, false, now())
'''),
      parameters: {'id': id, 'author': authorId},
    );

    Future<void> steward(String beaconId, String userId) => writer.execute(
      Sql.named(
        'INSERT INTO public.beacon_steward (beacon_id, user_id) '
        'VALUES (@b, @u)',
      ),
      parameters: {'b': beaconId, 'u': userId},
    );

    Future<void> admittedHelper(String beaconId, String userId) =>
        writer.execute(
          Sql.named(
            'INSERT INTO public.beacon_participant '
            '(beacon_id, user_id, role, room_access) '
            'VALUES (@b, @u, 1, 3)',
          ),
          parameters: {'b': beaconId, 'u': userId},
        );

    Future<void> insertManyUsers(String prefix, int n) => writer.execute(
      Sql.named(
        'INSERT INTO public."user" (id, display_name, public_key) '
        "SELECT @p || lpad(i::text, 6, '0'), 'bulk', @p || i::text "
        'FROM generate_series(1, @n::int) AS s(i)',
      ),
      parameters: {'p': prefix, 'n': n},
    );

    // A source the caller may not read from is refused as an invalid tag
    // request (1905), the same for a missing Request, a Request the caller is
    // not in and a Post, so the refusal does not tell them which it was.
    final refusedAsInvalidTag = contains('"code":"1905"');

    group('from an automatic tag', () {
      test(
        'copies the people the automatic tag has now, as source 2',
        () async {
          await trust(_owner, _alice);
          await trust(_owner, _bob);
          await trust(_carol, _owner);

          final tag = await createFromAuto(_iTrust);

          expect(await stored(tag), [
            (person: _alice, source: _sourceAutoTag),
            (person: _bob, source: _sourceAutoTag),
          ]);
        },
      );

      test('the copy does not follow later changes to the facts', () async {
        await trust(_owner, _alice);
        await trust(_owner, _bob);
        final tag = await createFromAuto(_iTrust);

        await untrust(_owner, _alice);
        await trust(_owner, _carol);

        expect(await stored(tag), [
          (person: _alice, source: _sourceAutoTag),
          (person: _bob, source: _sourceAutoTag),
        ]);
      });

      test('copies only the chosen automatic kind', () async {
        await trust(_owner, _alice);
        await trust(_bob, _owner);

        final tag = await createFromAuto(_trustsMe);

        expect(await stored(tag), [
          (person: _bob, source: _sourceAutoTag),
        ]);
      });

      test('an automatic tag nobody carries gives an empty tag', () async {
        final tag = await createFromAuto(_iTrust);

        expect(await stored(tag), isEmpty);
        expect(await ownTagCount(), 1);
      });

      test('a source with 1001 people is refused with code 1902 as a whole, '
          'not truncated, and no tag is created', () async {
        const bulk = 'Uptsrcover';
        await insertManyUsers(bulk, 1001);
        await writer.execute(
          Sql.named(
            'INSERT INTO public.vote_user (subject, object, amount) '
            "SELECT @owner, @p || lpad(i::text, 6, '0'), 1 "
            'FROM generate_series(1, 1001) AS s(i)',
          ),
          parameters: {'owner': _owner, 'p': bulk},
        );

        final error = await failureOf({
          'name': 'Too many',
          'clientOpId': nextOp(),
          'fromAutoKind': _iTrust,
        });

        expect(error, contains('"code":"1902"'));
        expect(await ownTagCount(), 0);
        expect(
          await writer.execute('SELECT 1 FROM public.person_tag_member'),
          isEmpty,
        );
      });

      test('exactly 1000 people are copied and 1001 are refused with code '
          '1902 without creating a tag', () async {
        const bulk = 'Uptsrcfull';
        await insertManyUsers(bulk, 1001);
        await writer.execute(
          Sql.named(
            'INSERT INTO public.vote_user (subject, object, amount) '
            "SELECT @owner, @p || lpad(i::text, 6, '0'), 1 "
            'FROM generate_series(1, 1000) AS s(i)',
          ),
          parameters: {'owner': _owner, 'p': bulk},
        );
        final full = await createFromAuto(_iTrust);
        expect((await stored(full)).length, 1000);

        await trust(_owner, '${bulk}001001');
        final error = await failureOf({
          'name': 'Too many',
          'clientOpId': nextOp(),
          'fromAutoKind': _iTrust,
        });

        expect(error, contains('"code":"1902"'));
        expect(await ownTagCount(), 1);
      });
    });

    group('from a Request', () {
      test('a member copies the other members as source 3, without '
          'themselves', () async {
        await insertRequest(_request, _alice);
        await steward(_request, _owner);
        await admittedHelper(_request, _bob);
        await admittedHelper(_request, _carol);

        final tag = await createFromRequest(_request);

        expect(await stored(tag), [
          (person: _alice, source: _sourceRequest),
          (person: _bob, source: _sourceRequest),
          (person: _carol, source: _sourceRequest),
        ]);
      });

      test(
        'the author of the Request is a member and copies the others',
        () async {
          await insertRequest(_request, _owner);
          await steward(_request, _bob);
          await admittedHelper(_request, _carol);

          final tag = await createFromRequest(_request);

          expect(await stored(tag), [
            (person: _bob, source: _sourceRequest),
            (person: _carol, source: _sourceRequest),
          ]);
        },
      );

      test(
        'a member who is only an admitted helper can copy the others',
        () async {
          await insertRequest(_request, _alice);
          await steward(_request, _carol);
          await admittedHelper(_request, _bob);

          final tag = await createFromRequest(_request, sub: _bob);

          expect(await stored(tag), [
            (person: _alice, source: _sourceRequest),
            (person: _carol, source: _sourceRequest),
          ]);
        },
      );

      test('skips members the owner blocked and members who blocked the '
          'owner', () async {
        await insertRequest(_request, _alice);
        await steward(_request, _owner);
        await admittedHelper(_request, _bob);
        await admittedHelper(_request, _carol);
        await admittedHelper(_request, _dave);
        await block(_owner, _bob);
        await block(_carol, _owner);

        final tag = await createFromRequest(_request);

        expect(await stored(tag), [
          (person: _alice, source: _sourceRequest),
          (person: _dave, source: _sourceRequest),
        ]);
      });

      test(
        'a user who is not a member is refused and no tag is created',
        () async {
          await insertRequest(_request, _alice);
          await steward(_request, _bob);

          final error = await failureOf({
            'name': 'Not mine',
            'clientOpId': nextOp(),
            'fromBeaconId': _request,
          }, sub: _outsider);

          expect(error, refusedAsInvalidTag);
          expect(
            ((await run(_tagsDoc, {}, sub: _outsider))['personTags']
                    as List<Object?>)
                .length,
            0,
          );
        },
      );

      test('a Request that does not exist is refused', () async {
        final error = await failureOf({
          'name': 'Nowhere',
          'clientOpId': nextOp(),
          'fromBeaconId': 'Bsrcnothere001',
        });

        expect(error, refusedAsInvalidTag);
        expect(await ownTagCount(), 0);
      });

      test('a Post id is refused even for its author, and no tag is '
          'created', () async {
        await insertPost(_post, _owner);
        await steward(_post, _bob);

        final error = await failureOf({
          'name': 'From post',
          'clientOpId': nextOp(),
          'fromBeaconId': _post,
        });

        expect(error, refusedAsInvalidTag);
        expect(await ownTagCount(), 0);
      });

      test('a Request with 1001 other members is refused with code 1902 as '
          'a whole, not truncated, and no tag is created', () async {
        const bulk = 'Uptsrcrover';
        await insertManyUsers(bulk, 1001);
        await insertRequest(_request, _owner);
        await writer.execute(
          Sql.named(
            'INSERT INTO public.beacon_participant '
            '(beacon_id, user_id, role, room_access) '
            "SELECT @b, @p || lpad(i::text, 6, '0'), 1, 3 "
            'FROM generate_series(1, 1001) AS s(i)',
          ),
          parameters: {'b': _request, 'p': bulk},
        );

        final error = await failureOf({
          'name': 'Too many',
          'clientOpId': nextOp(),
          'fromBeaconId': _request,
        });

        expect(error, contains('"code":"1902"'));
        expect(await ownTagCount(), 0);
        expect(
          await writer.execute('SELECT 1 FROM public.person_tag_member'),
          isEmpty,
        );
      });

      test('a steward with no participant row is copied as a member', () async {
        await insertRequest(_request, _alice);
        await steward(_request, _bob);
        await admittedHelper(_request, _carol);

        final tag = await createFromRequest(_request, sub: _carol);

        expect(await stored(tag), [
          (person: _alice, source: _sourceRequest),
          (person: _bob, source: _sourceRequest),
        ]);
      });

      test('1000 other members are copied and 1001 are refused with code '
          '1902 without creating a tag', () async {
        const bulk = 'Uptsrcreq';
        await insertManyUsers(bulk, 1001);
        await insertRequest(_request, _owner);
        await writer.execute(
          Sql.named(
            'INSERT INTO public.beacon_participant '
            '(beacon_id, user_id, role, room_access) '
            "SELECT @b, @p || lpad(i::text, 6, '0'), 1, 3 "
            'FROM generate_series(1, 1000) AS s(i)',
          ),
          parameters: {'b': _request, 'p': bulk},
        );
        final full = await createFromRequest(_request);
        expect((await stored(full)).length, 1000);

        await admittedHelper(_request, '${bulk}001001');
        final error = await failureOf({
          'name': 'Too many',
          'clientOpId': nextOp(),
          'fromBeaconId': _request,
        });

        expect(error, contains('"code":"1902"'));
        expect(await ownTagCount(), 1);
      });
    });
  });
}
