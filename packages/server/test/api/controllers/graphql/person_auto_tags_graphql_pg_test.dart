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

const _owner = 'Uatgqlowner0001';
const _peer = 'Uatgqlpeer00001';
const _stranger = 'Uatgqlstrang001';
const _mutualContact = 0;
const _iTrust = 1;

const _autoTagsDoc = '''
query { personAutoTags { kind count showInFilters } }
''';

const _prefSetDoc = r'''
mutation Pref($kind: Int!, $showInFilters: Boolean!) {
  personAutoTagPrefSet(kind: $kind, showInFilters: $showInFilters) {
    kind count showInFilters
  }
}
''';

const _membersDoc = r'''
query Members($kind: Int!) { personAutoTagMembers(kind: $kind) }
''';

const _tagsOfDoc = r'''
query TagsOf($personId: String!) {
  personTagsOf(personId: $personId) { own auto { kind n direction } }
}
''';

const _applyDoc = r'''
mutation Apply($ops: [PersonTagMemberOpInput!]!, $clientOpId: String!) {
  personTagMembersApply(ops: $ops, clientOpId: $clientOpId)
}
''';

const _mutationNamesDoc = '''
query { __schema { mutationType { fields { name } } } }
''';

/// Automatic tags over the real V2 schema: the per-kind list, the filter
/// preference toggle, the member list and the `auto` part of `personTagsOf`.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PERSON_AUTO_TAGS_GQL_TEST_DB',
    defaultNamePrefix: 'tentura_test_person_auto_tags_gql',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('automatic tags GraphQL', () {
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
      await writer.execute('TRUNCATE TABLE public."user" CASCADE');
      for (final id in [_owner, _peer, _stranger]) {
        await writer.execute(
          Sql.named(
            'INSERT INTO public."user" (id, display_name, public_key) '
            'VALUES (@id, @id, @key)',
          ),
          parameters: {'id': id, 'key': '$id-key'},
        );
      }
      await writer.execute(
        'INSERT INTO public.vote_user (subject, object, amount) VALUES '
        "('$_owner', '$_peer', 1), ('$_peer', '$_owner', 1)",
      );
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

    Future<Map<int, Map<String, dynamic>>> autoTags() async {
      final data = await run(_autoTagsDoc);
      return {
        for (final t
            in (data['personAutoTags']! as List<Object?>)
                .cast<Map<String, dynamic>>())
          t['kind']! as int: t,
      };
    }

    test('personAutoTags lists each present kind with its count', () async {
      final tags = await autoTags();
      expect(tags[_mutualContact]!['count'], 1);
      expect(tags.keys, isNot(contains(_iTrust)));
    });

    test('personAutoTagPrefSet toggles showInFilters', () async {
      final before = (await autoTags())[_mutualContact]!['showInFilters'];
      final off = await run(_prefSetDoc, {
        'kind': _mutualContact,
        'showInFilters': !(before! as bool),
      });
      expect(
        (off['personAutoTagPrefSet']! as Map)['showInFilters'],
        !(before as bool),
      );
      expect(
        (await autoTags())[_mutualContact]!['showInFilters'],
        !before,
      );
      final rows = await writer.execute(
        'SELECT show_in_filters FROM public.person_auto_tag_pref '
        "WHERE owner_id = '$_owner' AND kind = $_mutualContact",
      );
      expect(rows.single.single, !before);
    });

    test('personAutoTagMembers returns the peer ids of the kind', () async {
      final data = await run(_membersDoc, {'kind': _mutualContact});
      expect(data['personAutoTagMembers'], [_peer]);
    });

    test('personTagsOf reports the automatic tags of a person', () async {
      final data = await run(_tagsOfDoc, {'personId': _peer});
      final result = data['personTagsOf']! as Map<String, dynamic>;
      final auto = (result['auto']! as List<Object?>)
          .cast<Map<String, dynamic>>();
      expect(auto, [
        {'kind': _mutualContact, 'n': 1, 'direction': 0},
      ]);
    });

    group('another user', () {
      test('personAutoTagMembers lists only their own facts', () async {
        final data = await run(_membersDoc, {
          'kind': _mutualContact,
        }, _stranger);
        expect(data['personAutoTagMembers'], isEmpty);
        // The owner still sees the peer, so the empty list is not a failure.
        final own = await run(_membersDoc, {'kind': _mutualContact});
        expect(own['personAutoTagMembers'], [_peer]);
      });

      test('personTagsOf reveals none of the owner automatic tags', () async {
        final data = await run(_tagsOfDoc, {'personId': _peer}, _stranger);
        final result = data['personTagsOf']! as Map<String, dynamic>;
        expect(result['auto'], isEmpty);
        expect(result['own'], isEmpty);
      });

      test('personAutoTags counts none of the owner facts', () async {
        final data = await run(_autoTagsDoc, const {}, _stranger);
        expect(data['personAutoTags'], isEmpty);
      });
    });

    group('membership operations never take an automatic kind', () {
      var opCounter = 0;

      Future<String> failureOf(String tagId, String op) async {
        try {
          await run(_applyDoc, {
            'ops': [
              {'tagId': tagId, 'personId': _peer, 'op': op, 'source': 0},
            ],
            'clientOpId': 'auto-op-${opCounter++}',
          });
        } on Object catch (e) {
          return e.toString();
        }
        fail('expected $op on automatic tag "$tagId" to be rejected');
      }

      const kindNames = [
        'mutualContact',
        'iTrust',
        'trustsMe',
        'helpedMe',
        'iHelped',
        'workedTogether',
        'invited',
        'forwarded',
        'newOnField',
      ];
      final tagIds = [
        for (var kind = 0; kind < kindNames.length; kind++) ...[
          '$kind',
          kindNames[kind],
        ],
      ];
      for (final tagId in tagIds) {
        for (final op in ['add', 'remove']) {
          test('$op with automatic kind "$tagId" is rejected and the tag '
              'stays', () async {
            await failureOf(tagId, op);

            final stored = await writer.execute(
              'SELECT count(*) FROM public.person_tag_member',
            );
            expect(stored.single.single, 0);
            expect((await autoTags())[_mutualContact]!['count'], 1);
          });
        }
      }
    });

    test('no mutation removes an automatic tag', () async {
      final data = await run(_mutationNamesDoc);
      final names = [
        for (final f
            in ((data['__schema']! as Map)['mutationType']! as Map)['fields']!
                as List<Object?>)
          (f! as Map)['name']! as String,
      ];
      final auto = names.where((n) => n.toLowerCase().contains('autotag'));
      expect(auto, ['personAutoTagPrefSet']);
    });
  });
}
