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

const _owner = 'Uptgqlowner0001';
const _other = 'Uptgqlother0001';

const _createDoc = r'''
mutation Create($name: String!, $glyph: String, $color: Int, $clientOpId: String!) {
  personTagCreate(name: $name, glyph: $glyph, color: $color, clientOpId: $clientOpId) {
    id name glyph color ord
  }
}
''';

const _updateDoc = r'''
mutation Update($id: String!, $name: String, $glyph: String, $color: Int, $ord: Int, $clientOpId: String!) {
  personTagUpdate(id: $id, name: $name, glyph: $glyph, color: $color, ord: $ord, clientOpId: $clientOpId) {
    id name glyph color ord
  }
}
''';

const _deleteDoc = r'''
mutation Delete($id: String!, $clientOpId: String!) {
  personTagDelete(id: $id, clientOpId: $clientOpId) {
    tag { id name glyph color ord }
    memberIds
    sources
  }
}
''';

const _restoreDoc = r'''
mutation Restore($snapshot: PersonTagSnapshotInput!, $clientOpId: String!) {
  personTagRestore(snapshot: $snapshot, clientOpId: $clientOpId) {
    id name glyph color ord
  }
}
''';

const _listDoc = '''
query { personTags { id name glyph color ord } }
''';

/// `personTags` and the create / update mutations over the real V2 schema.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PEOPLE_TAGS_GQL_TEST_DB',
    defaultNamePrefix: 'tentura_test_people_tags_gql',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('personTags GraphQL', () {
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

    /// Executes [document] and returns the response data; a failing
    /// execution throws, like every other V2 GraphQL test.
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

    /// Runs a successful operation and returns its object result under [key].
    Future<Map<String, dynamic>> field(
      String document,
      Map<String, dynamic> variables,
      String key, {
      String sub = _owner,
    }) async {
      final data = await run(document, variables, sub: sub);
      expect(data[key], isA<Map<String, dynamic>>(), reason: '$key result');
      return data[key] as Map<String, dynamic>;
    }

    Future<Map<String, dynamic>> create(
      String name, {
      String? glyph,
      int? color,
      String? opId,
      String sub = _owner,
    }) => field(
      _createDoc,
      {
        'name': name,
        'glyph': ?glyph,
        'color': ?color,
        'clientOpId': opId ?? 'op-${opCounter++}',
      },
      'personTagCreate',
      sub: sub,
    );

    Future<List<Map<String, dynamic>>> listed({String sub = _owner}) async {
      final data = await run(_listDoc, {}, sub: sub);
      expect(data['personTags'], isA<List<Object?>>());
      return (data['personTags'] as List<Object?>)
          .cast<Map<String, dynamic>>()
          .toList();
    }

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

    Future<int> rowCount(String where) async =>
        (await writer.execute(
              'SELECT count(*) FROM public.person_tag WHERE $where',
            )).single.first!
            as int;

    test('create then personTags returns the new tag with defaults', () async {
      final tag = await create(' Friends ', opId: 'op-1');

      expect(tag['name'], 'Friends');
      expect(tag['glyph'], 'F');
      expect(tag['color'], 0);
      expect(tag['ord'], 1);
      expect(await listed(), [tag]);
    });

    test('update renames, changes glyph and colour, and reorders', () async {
      final a = await create('A');
      final b = await create('B');

      final updated = await field(_updateDoc, {
        'id': b['id'],
        'name': 'Bee',
        'glyph': 'Z',
        'color': 6,
        'ord': 1,
        'clientOpId': 'op-u',
      }, 'personTagUpdate');

      expect(updated['id'], b['id']);
      expect(updated['name'], 'Bee');
      expect(updated['glyph'], 'Z');
      expect(updated['color'], 6);
      expect(updated['ord'], 1);
      expect((await listed()).map((t) => t['id']), [b['id'], a['id']]);
    });

    test('a repeated create replays the first result', () async {
      final first = await create('Friends', opId: 'same');
      final second = await create('Friends', opId: 'same');

      expect(second, first);
      expect(await listed(), hasLength(1));
    });

    test('a repeated update replays the first result', () async {
      final tag = await create('Friends');
      final vars = {'id': tag['id'], 'color': 2, 'clientOpId': 'op-u'};

      final first = await field(_updateDoc, vars, 'personTagUpdate');
      final second = await field(_updateDoc, vars, 'personTagUpdate');

      expect(first['color'], 2);
      expect(second, first);
    });

    test(
      'a reused clientOpId with a changed update payload is code 1906',
      () async {
        final tag = await create('Friends');
        await field(_updateDoc, {
          'id': tag['id'],
          'color': 2,
          'clientOpId': 'op-u',
        }, 'personTagUpdate');

        final error = await failureOf(_updateDoc, {
          'id': tag['id'],
          'color': 3,
          'clientOpId': 'op-u',
        });

        expect(error, contains('"code":"1906"'));
      },
    );

    test(
      'delete returns the snapshot and restore recreates the same id',
      () async {
        final tag = await create('Friends', glyph: 'Q', color: 3);
        await writer.execute(
          Sql.named(
            'INSERT INTO public.person_tag_member '
            '(tag_id, owner_id, person_id, source) '
            'VALUES (@tag, @owner, @person, 2)',
          ),
          parameters: {'tag': tag['id'], 'owner': _owner, 'person': _other},
        );

        final deleted = await field(_deleteDoc, {
          'id': tag['id'],
          'clientOpId': 'op-d',
        }, 'personTagDelete');

        expect(deleted['tag'], tag);
        expect(deleted['memberIds'], [_other]);
        expect(deleted['sources'], [2]);
        expect(await listed(), isEmpty);

        final restored = await field(_restoreDoc, {
          'snapshot': deleted,
          'clientOpId': 'op-r',
        }, 'personTagRestore');

        expect(restored, tag);
        expect(await listed(), [tag]);
        final members = await writer.execute(
          "SELECT person_id FROM public.person_tag_member WHERE tag_id = '${tag['id']}'",
        );
        expect(members.single.single, _other);
      },
    );

    test(
      'a repeated delete and a repeated restore replay their results',
      () async {
        final tag = await create('Friends');
        final deleteVars = {'id': tag['id'], 'clientOpId': 'op-d'};

        final deleted = await field(_deleteDoc, deleteVars, 'personTagDelete');
        final deletedAgain = await field(
          _deleteDoc,
          deleteVars,
          'personTagDelete',
        );
        expect(deletedAgain, deleted);

        final restoreVars = {'snapshot': deleted, 'clientOpId': 'op-r'};
        final restored = await field(
          _restoreDoc,
          restoreVars,
          'personTagRestore',
        );
        final restoredAgain = await field(
          _restoreDoc,
          restoreVars,
          'personTagRestore',
        );
        expect(restoredAgain, restored);
        expect(await listed(), [restored]);
      },
    );

    test('the 51st tag is refused with code 1901', () async {
      for (var i = 0; i < 50; i++) {
        await create('tag $i');
      }

      final error = await failureOf(_createDoc, {
        'name': 'one too many',
        'clientOpId': 'op-extra',
      });

      expect(error, contains('"code":"1901"'));
      expect(await listed(), hasLength(50));
    });

    test('errors carry codes from space 1900', () async {
      await create('Friends', opId: 'op-1');

      expect(
        await failureOf(_createDoc, {'name': 'friends', 'clientOpId': 'op-2'}),
        contains('"code":"1900"'),
      );
      expect(
        await failureOf(_createDoc, {'name': 'Other', 'clientOpId': 'op-1'}),
        contains('"code":"1906"'),
      );
      expect(
        await failureOf(_createDoc, {
          'name': 'Bad glyph',
          'glyph': 'a b',
          'clientOpId': 'op-3',
        }),
        contains('"code":"1905"'),
      );
    });

    test('restore of a reused name is code 1900', () async {
      final tag = await create('Friends');
      final deleted = await field(_deleteDoc, {
        'id': tag['id'],
        'clientOpId': 'op-d',
      }, 'personTagDelete');
      await create('friends');

      final error = await failureOf(_restoreDoc, {
        'snapshot': deleted,
        'clientOpId': 'op-r',
      });

      expect(error, contains('"code":"1900"'));
    });

    test('another user never sees, edits or deletes the tag', () async {
      final tag = await create('Private');

      expect(await listed(sub: _other), isEmpty);
      expect(
        await failureOf(_updateDoc, {
          'id': tag['id'],
          'name': 'Hijack',
          'clientOpId': 'op-2',
        }, sub: _other),
        contains('"code":"1903"'),
      );
      expect(
        await failureOf(_deleteDoc, {
          'id': tag['id'],
          'clientOpId': 'op-3',
        }, sub: _other),
        contains('"code":"1903"'),
      );
      expect((await listed()).single['name'], 'Private');
    });

    test(
      'another user restoring a snapshot never touches the owner tags',
      () async {
        final live = await create('Live');
        final gone = await create('Gone');
        final snapshot = await field(_deleteDoc, {
          'id': gone['id'],
          'clientOpId': 'op-d',
        }, 'personTagDelete');
        final liveSnapshot = {
          'tag': live,
          'memberIds': <String>[],
          'sources': <int>[],
        };

        // Restoring over a tag that still exists must fail and change nothing.
        await failureOf(_restoreDoc, {
          'snapshot': liveSnapshot,
          'clientOpId': 'op-r1',
        }, sub: _other);
        expect((await listed()).single, live);

        // Restoring the owner's deleted snapshot must not resurrect it for the
        // owner.
        try {
          await run(_restoreDoc, {
            'snapshot': snapshot,
            'clientOpId': 'op-r2',
          }, sub: _other);
        } on Object {
          // Refusing is fine; creating a copy for the caller is fine too.
        }
        expect(
          await rowCount("owner_id = '$_owner' AND id = '${gone['id']}'"),
          0,
        );
        expect((await listed()).map((t) => t['id']), [live['id']]);
      },
    );

    test('error text never contains the submitted tag name or glyph', () async {
      const secret = 'Zorblax-secret-name';
      const secretGlyph = '☃';
      final tag = await create(secret, glyph: secretGlyph, opId: 'op-1');
      final errors = <String>[
        await failureOf(_createDoc, {
          'name': secret.toUpperCase(),
          'glyph': secretGlyph,
          'clientOpId': 'op-2',
        }),
        await failureOf(_createDoc, {
          'name': 'different',
          'glyph': secretGlyph,
          'clientOpId': 'op-1',
        }),
        await failureOf(_updateDoc, {
          'id': tag['id'],
          'name': secret,
          'glyph': secretGlyph,
          'clientOpId': 'op-3',
        }, sub: _other),
        await failureOf(_createDoc, {
          'name': '$secret${'x' * 40}',
          'clientOpId': 'op-4',
        }),
        await failureOf(_createDoc, {
          'name': 'Another',
          'glyph': '$secretGlyph ',
          'clientOpId': 'op-5',
        }),
      ];

      for (final error in errors) {
        expect(error, contains('"code":"19'));
        expect(error.toLowerCase(), isNot(contains(secret.toLowerCase())));
        expect(error, isNot(contains(secretGlyph)));
      }
    });
  });
}
