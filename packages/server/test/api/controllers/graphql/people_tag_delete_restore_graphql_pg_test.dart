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

const _owner = 'Utagundoowner01';
const _person = 'Utagundoperson1';
const _active = 'PH000000000001';
const _merged = 'PH000000000002';
const _removed = 'PH000000000003';
const _orphaned = 'PH000000000004';

const _createDoc = r'''
mutation Create($clientOpId: String!) {
  personTagCreate(name: "Neighbours", clientOpId: $clientOpId) {
    id name glyph color ord
  }
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
    members { kind id membershipId source }
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

const _readDoc = '''
query {
  personTags { id count }
  personTagMemberships { tagId personIds }
}
''';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PEOPLE_TAG_DELETE_RESTORE_TEST_DB',
    defaultNamePrefix: 'tentura_test_people_tag_delete_restore',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  group('Deleting and restoring a people tag', () {
    late Connection writer;
    late GraphQL schema;
    late Map<String, dynamic> tag;
    late String tagId;
    var opCounter = 0;

    String nextOp() => 'tag-undo-${opCounter++}';

    Future<Map<String, dynamic>> run(
      String document, [
      Map<String, dynamic> variables = const {},
    ]) async =>
        await schema.parseAndExecute(
              document,
              variableValues: variables,
              globalVariables: {
                kGlobalInputQueryJwt: const JwtEntity(sub: _owner),
              },
            )
            as Map<String, dynamic>;

    Future<Result> scopedSql(String statement, Map<String, Object?> args) =>
        writer.executeWithOwnerScopes(
          [_owner],
          Sql.named(statement),
          parameters: args,
        );

    Future<void> addMembers(Map<String, int> sources) async {
      final data = await run(_applyDoc, {
        'ops': [
          for (final entry in sources.entries)
            {
              'tagId': tagId,
              'personId': entry.key,
              'op': 'add',
              'source': entry.value,
            },
        ],
        'clientOpId': nextOp(),
      });
      expect(data['personTagMembersApply'], isTrue);
    }

    Future<void> addPhantoms(List<String> ids) async {
      for (final id in ids) {
        await scopedSql(
          '''
INSERT INTO public.phantom (id, owner_id, display_name)
VALUES (@id, @owner, 'Neighbour')
''',
          {'id': id, 'owner': _owner},
        );
      }
      await addMembers({for (final id in ids) id: 0});
    }

    Future<Result> linkMember(String id) => scopedSql(
      '''
UPDATE public.phantom SET merged_at = now(), merged_user_id = @user,
  merge_origin = 2 WHERE id = @id
''',
      {'id': id, 'user': _person},
    );

    Future<Map<String, Map<String, Object?>>> storedMembers() async => {
      for (final row in await writer.execute(
        Sql.named('''
SELECT 'person' AS kind, person_id AS id, membership_id::text AS "membershipId",
       source
FROM public.person_tag_member WHERE tag_id = @tag
UNION ALL
SELECT 'phantom', phantom_id, membership_id::text, source
FROM public.phantom_tag_member WHERE tag_id = @tag
'''),
        parameters: {'tag': tagId},
      ))
        row[1]! as String: row.toColumnMap(),
    };

    Future<void> expectVisibleMembers(List<String> ids) async {
      final data = await run(_readDoc);
      expect(data['personTags'], [
        {'id': tagId, 'count': ids.length},
      ]);
      expect(data['personTagMemberships'], [
        {'tagId': tagId, 'personIds': unorderedEquals(ids)},
      ]);
    }

    Future<Map<String, dynamic>> deleteTag({String? clientOpId}) async {
      final data = await run(_deleteDoc, {
        'id': tagId,
        'clientOpId': clientOpId ?? nextOp(),
      });
      return data['personTagDelete'] as Map<String, dynamic>;
    }

    Future<void> restoreTag(Map<String, dynamic> snapshot) async {
      final data = await run(_restoreDoc, {
        'snapshot': snapshot,
        'clientOpId': nextOp(),
      });
      expect(data['personTagRestore'], tag);
    }

    setUpAll(() async {
      final session = await setUpDisposablePgWriter(target: target);
      addTearDown(() => tearDownDisposablePgWriter(session: session));
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
      addTearDown(getIt.reset);
      await getIt.allReady(ignorePendingAsyncCreation: true);
      schema = graphqlSchema;
    });

    setUp(() async {
      await writer.execute('TRUNCATE TABLE public."user" CASCADE');
      for (final id in [_owner, _person]) {
        await writer.execute(
          Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
          parameters: {'id': id, 'key': '$id-key'},
        );
      }
      // The owner has no visible peers. Use the real visibility cache so the
      // count queries need no shared MeritRank service.
      await writer.execute(
        Sql.named('''
INSERT INTO public.person_visible_set_cache
  (viewer_id, ctx, mr_epoch, trust_gen, peer_ids)
VALUES (
  @owner, '',
  coalesce((SELECT epoch FROM public.mr_publish_epoch WHERE id = true), 0),
  (SELECT generation FROM public.visibility_trust_generation WHERE id = true),
  '{}'::text[])
ON CONFLICT (viewer_id, ctx) DO UPDATE
SET mr_epoch = EXCLUDED.mr_epoch,
    trust_gen = EXCLUDED.trust_gen,
    peer_ids = EXCLUDED.peer_ids
'''),
        parameters: {'owner': _owner},
      );
      final data = await run(_createDoc, {'clientOpId': nextOp()});
      tag = data['personTagCreate'] as Map<String, dynamic>;
      tagId = tag['id'] as String;
      await addMembers({_person: 2});
    });

    test('delete returns the kind, id, membership UUID and source for each '
        'member', () async {
      await addPhantoms([_active]);
      final before = await storedMembers();
      expect(before.keys, unorderedEquals([_person, _active]));

      final snapshot = await deleteTag();

      expect(await storedMembers(), isEmpty);
      expect(snapshot['members'], unorderedEquals(before.values));
    });

    test(
      'delete captures a linked member hidden from the list and count',
      () async {
        await addPhantoms([_active, _merged]);
        await linkMember(_merged);
        await expectVisibleMembers([_person, _active]);
        final before = await storedMembers();
        expect(before.keys, unorderedEquals([_person, _active, _merged]));

        final snapshot = await deleteTag();

        expect(snapshot['members'], unorderedEquals(before.values));
      },
    );

    test(
      'restoring a registered member preserves its UUID and source',
      () async {
        final before = await storedMembers();
        expect(before.keys, [_person]);

        await restoreTag(await deleteTag());

        expect(await storedMembers(), before);
      },
    );

    test('undo restores an active member with its original UUID and source '
        'and brings the list and count back', () async {
      await addPhantoms([_active]);
      await expectVisibleMembers([_person, _active]);
      final before = await storedMembers();
      expect(before.keys, unorderedEquals([_person, _active]));

      await restoreTag(await deleteTag());

      expect(await storedMembers(), before);
      await expectVisibleMembers([_person, _active]);
    });

    test('undo restores the original memberships, skips a removed person and '
        'reveals a linked member when unlinked', () async {
      await addPhantoms([_active, _merged, _removed]);
      await linkMember(_merged);
      await expectVisibleMembers([_person, _active, _removed]);
      final before = await storedMembers();
      expect(
        before.keys,
        unorderedEquals([_person, _active, _merged, _removed]),
      );

      final snapshot = await deleteTag();
      expect(snapshot['members'], unorderedEquals(before.values));
      expect(await storedMembers(), isEmpty);
      final removed = await scopedSql(
        'DELETE FROM public.phantom WHERE id = @id RETURNING id',
        {'id': _removed},
      );
      expect(removed.single.single, _removed);
      await restoreTag(snapshot);

      final restored = await storedMembers();
      final originalMerged = before[_merged]!;
      expect(
        restored.remove(_merged),
        {
          'kind': 'phantom',
          'id': _merged,
          'membershipId': originalMerged['membershipId'],
          'source': originalMerged['source'],
        },
        reason:
            'Undo must preserve the linked member’s row while it is hidden.',
      );
      expect(restored, {
        _person: before[_person],
        _active: before[_active],
      });
      await expectVisibleMembers([_person, _active]);

      await scopedSql(
        '''
UPDATE public.phantom SET merged_at = NULL, merged_user_id = NULL,
  merge_origin = NULL, current_merge_id = NULL WHERE id = @id
''',
        {'id': _merged},
      );

      await expectVisibleMembers([_person, _active, _merged]);
    });

    test(
      'undo skips an orphaned membership and restores the other members',
      () async {
        await addPhantoms([_active, _orphaned]);
        await linkMember(_orphaned);
        final before = await storedMembers();
        expect(before.keys, unorderedEquals([_person, _active, _orphaned]));

        final snapshot = await deleteTag();
        expect(snapshot['members'], unorderedEquals(before.values));
        final orphan = await scopedSql(
          '''
UPDATE public.phantom SET merged_user_id = NULL, current_merge_id = NULL
WHERE id = @id
RETURNING merged_at IS NOT NULL, merged_user_id, current_merge_id
''',
          {'id': _orphaned},
        );
        expect(orphan.single.toList(), [true, null, null]);
        await restoreTag(snapshot);

        expect(await storedMembers(), {
          _person: before[_person],
          _active: before[_active],
        });
        await expectVisibleMembers([_person, _active]);
      },
    );

    test('retrying delete returns the original entries, including a linked '
        'member hidden from the tag', () async {
      await addPhantoms([_active, _merged]);
      await linkMember(_merged);
      await expectVisibleMembers([_person, _active]);
      final before = await storedMembers();
      expect(before.keys, unorderedEquals([_person, _active, _merged]));
      final opId = nextOp();

      final first = await deleteTag(clientOpId: opId);
      expect(await storedMembers(), isEmpty);
      final replay = await deleteTag(clientOpId: opId);

      expect(first['members'], unorderedEquals(before.values));
      expect(replay, first);
    });
  });
}
