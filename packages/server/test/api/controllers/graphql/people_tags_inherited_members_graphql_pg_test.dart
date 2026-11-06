@Timeout(Duration(minutes: 3))
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

const _owner = 'Uptinhowner0001';
const _bob = 'Uptinhbob000001';
const _carol = 'Uptinhcarol0001';
const _eve = 'Uptinheve000001';

/// Membership source of a person who joined a tag by inheriting it from
/// their inviter (the «set automatically» marker).
const _inherited = 4;

const _createDoc = r'''
mutation Create($name: String!, $clientOpId: String!) {
  personTagCreate(name: $name, clientOpId: $clientOpId) { id }
}
''';

const _applyDoc = r'''
mutation Apply($ops: [PersonTagMemberOpInput!]!, $clientOpId: String!) {
  personTagMembersApply(ops: $ops, clientOpId: $clientOpId)
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
  personTagRestore(snapshot: $snapshot, clientOpId: $clientOpId) { id }
}
''';

const _membershipsDoc = '''
query {
  personTagMemberships {
    tagId
    personIds
    inherited { personId inviterId }
  }
}
''';

/// Which members of an own tag were put there automatically (inherited from
/// their inviter), who that inviter is, and the `keep` op that turns such a
/// member into a manual one, over the real V2 schema.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PEOPLE_TAGS_INHERITED_GQL_TEST_DB',
    defaultNamePrefix: 'tentura_test_people_tags_inh_gql',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('inherited tag members over GraphQL', () {
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
      await writer.execute('TRUNCATE TABLE public.invite_genealogy');
      for (final id in [_owner, _bob, _carol, _eve]) {
        await writer.execute(
          Sql.named(
            'INSERT INTO public."user" (id, display_name, public_key) '
            'VALUES (@id, @id, @key)',
          ),
          parameters: {'id': id, 'key': '$id-key'},
        );
      }
    });

    String nextOp() => 'op-inh-${opCounter++}';

    Future<Map<String, dynamic>> run(
      String document,
      Map<String, dynamic> variables,
    ) async =>
        await schema.parseAndExecute(
              document,
              variableValues: variables,
              globalVariables: {
                kGlobalInputQueryJwt: const JwtEntity(sub: _owner),
              },
            )
            as Map<String, dynamic>;

    Future<String> createTag(String name) async {
      final data = await run(_createDoc, {
        'name': name,
        'clientOpId': nextOp(),
      });
      return (data['personTagCreate'] as Map<String, dynamic>)['id']! as String;
    }

    Map<String, dynamic> memberOp(
      String tagId,
      String personId,
      String kind, {
      int source = 0,
    }) => {
      'tagId': tagId,
      'personId': personId,
      'op': kind,
      'source': source,
    };

    Future<Map<String, dynamic>> apply(
      List<Map<String, dynamic>> ops, {
      String? opId,
    }) => run(_applyDoc, {'ops': ops, 'clientOpId': opId ?? nextOp()});

    /// [inviter]'s accepted invitation brought [newcomer] in.
    Future<void> invited(String inviter, String newcomer) => writer.execute(
      Sql.named('''
INSERT INTO public.invite_genealogy (
  descendant_node_key, ancestor_node_key, descendant_user_id, ancestor_user_id,
  ancestor_user_created_at, descendant_user_created_at)
VALUES ('nk-' || @newcomer, 'nk-' || @inviter, @newcomer, @inviter,
        '2020-01-01T00:00:00Z', '2021-01-01T00:00:00Z')
'''),
      parameters: {'inviter': inviter, 'newcomer': newcomer},
    );

    /// A tag holding Carol as an inherited member (inviter Bob) and Eve as a
    /// manual one.
    Future<String> tagWithCarolInheritedAndEveManual() async {
      await invited(_bob, _carol);
      final tagId = await createTag('Neighbours');
      await apply([
        memberOp(tagId, _carol, 'add', source: _inherited),
        memberOp(tagId, _eve, 'add'),
      ]);
      return tagId;
    }

    Future<Map<String, dynamic>> membershipOf(String tagId) async {
      final data = await run(_membershipsDoc, {});
      return (data['personTagMemberships'] as List<Object?>)
          .cast<Map<String, dynamic>>()
          .singleWhere((m) => m['tagId'] == tagId);
    }

    Future<List<Map<String, dynamic>>> inheritedOf(String tagId) async =>
        ((await membershipOf(tagId))['inherited']! as List<Object?>)
            .cast<Map<String, dynamic>>();

    Future<List<String>> personIdsOf(String tagId) async =>
        ((await membershipOf(tagId))['personIds']! as List<Object?>)
            .cast<String>();

    Future<List<(String, int)>> storedRows(String tagId) async => [
      for (final r in await writer.execute(
        Sql.named(
          'SELECT person_id, source FROM public.person_tag_member '
          'WHERE tag_id = @tag ORDER BY person_id',
        ),
        parameters: {'tag': tagId},
      ))
        (r[0]! as String, r[1]! as int),
    ];

    test('lists only the members who joined by inheritance, with their '
        'inviter, while all members stay in personIds', () async {
      final tagId = await tagWithCarolInheritedAndEveManual();

      expect(await inheritedOf(tagId), [
        {'personId': _carol, 'inviterId': _bob},
      ]);
      expect(await personIdsOf(tagId), [_carol, _eve]);
    });

    test('an inherited member whose inviter is gone is listed with a null '
        'inviter', () async {
      final tagId = await tagWithCarolInheritedAndEveManual();
      await writer.execute('DELETE FROM public.invite_genealogy');

      expect(await inheritedOf(tagId), [
        {'personId': _carol, 'inviterId': null},
      ]);
    });

    group('inherited tag membership hides blocked inviters', () {
      for (final (blocker, blocked, direction) in [
        (_owner, _bob, 'the owner blocked the inviter'),
        (_bob, _owner, 'the inviter blocked the owner'),
      ]) {
        test(
          'inviter identity is null when $direction while members remain visible',
          () async {
            final tagId = await tagWithCarolInheritedAndEveManual();
            expect(await inheritedOf(tagId), [
              {'personId': _carol, 'inviterId': _bob},
            ]);
            await writer.execute(
              Sql.named('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES (@blocker, @blocked, @blocker)
'''),
              parameters: {'blocker': blocker, 'blocked': blocked},
            );

            final membership = await membershipOf(tagId);

            expect(membership['personIds'], [_carol, _eve]);
            expect(membership['inherited'], [
              {'personId': _carol, 'inviterId': null},
            ]);
          },
        );
      }
    });

    test('keep turns an inherited member into a manual one: no longer '
        'listed as inherited, still in the tag', () async {
      final tagId = await tagWithCarolInheritedAndEveManual();

      final result = await apply([memberOp(tagId, _carol, 'keep')]);

      expect(result['personTagMembersApply'], isTrue);
      expect(await inheritedOf(tagId), isEmpty);
      expect(await personIdsOf(tagId), [_carol, _eve]);
      expect(await storedRows(tagId), [(_carol, 0), (_eve, 0)]);
    });

    test('repeating a keep with the same clientOpId is ok and writes '
        'nothing again', () async {
      final tagId = await tagWithCarolInheritedAndEveManual();
      await apply([memberOp(tagId, _carol, 'keep')], opId: 'keep-once');
      // Make Carol inherited again behind the API; a replayed op must not
      // touch her, a fresh op would.
      await writer.execute(
        Sql.named(
          'UPDATE public.person_tag_member SET source = 4 '
          'WHERE tag_id = @tag AND person_id = @carol',
        ),
        parameters: {'tag': tagId, 'carol': _carol},
      );

      final again = await apply([
        memberOp(tagId, _carol, 'keep'),
      ], opId: 'keep-once');

      expect(again['personTagMembersApply'], isTrue);
      expect(await storedRows(tagId), [(_carol, _inherited), (_eve, 0)]);
    });

    test('keep on a manual member changes nothing', () async {
      final tagId = await tagWithCarolInheritedAndEveManual();

      final result = await apply([memberOp(tagId, _eve, 'keep')]);

      expect(result['personTagMembersApply'], isTrue);
      expect(await storedRows(tagId), [(_carol, _inherited), (_eve, 0)]);
      expect(await inheritedOf(tagId), [
        {'personId': _carol, 'inviterId': _bob},
      ]);
    });

    test('keep on a person who is not in the tag adds nobody', () async {
      final tagId = await tagWithCarolInheritedAndEveManual();

      final result = await apply([memberOp(tagId, _bob, 'keep')]);

      expect(result['personTagMembersApply'], isTrue);
      expect(await storedRows(tagId), [(_carol, _inherited), (_eve, 0)]);
    });

    test('remove still deletes an inherited member', () async {
      final tagId = await tagWithCarolInheritedAndEveManual();

      await apply([memberOp(tagId, _carol, 'remove')]);

      expect(await inheritedOf(tagId), isEmpty);
      expect(await personIdsOf(tagId), [_eve]);
    });

    test('deleting and restoring the tag keeps an inherited member '
        'inherited', () async {
      final tagId = await tagWithCarolInheritedAndEveManual();

      final deleted =
          (await run(_deleteDoc, {
                'id': tagId,
                'clientOpId': nextOp(),
              }))['personTagDelete']
              as Map<String, dynamic>;
      await run(_restoreDoc, {
        'snapshot': deleted,
        'clientOpId': nextOp(),
      });

      expect(await inheritedOf(tagId), [
        {'personId': _carol, 'inviterId': _bob},
      ]);
      expect(await personIdsOf(tagId), [_carol, _eve]);
    });
  });
}
