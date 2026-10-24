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

const _owner = 'Uptmemowner0001';
const _other = 'Uptmemother0001';
const _alice = 'Uptmemalice0001';
const _bob = 'Uptmembob000001';
const _carol = 'Uptmemcarol00001';

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

const _tagsDoc = '''
query { personTags { id count countOffField } }
''';

const _tagsOfDoc = r'''
query TagsOf($personId: String!) {
  personTagsOf(personId: $personId) { own }
}
''';

const _membershipsDoc = '''
query { personTagMemberships { tagId personIds } }
''';

/// Applying people to an owner's tags, the counts on `personTags`, and the
/// owner-only membership readers, over the real V2 schema.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PEOPLE_TAGS_MEMBERSHIP_GQL_TEST_DB',
    defaultNamePrefix: 'tentura_test_people_tags_member_gql',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('person tag membership GraphQL', () {
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
      for (final id in [_owner, _other, _alice, _bob, _carol]) {
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

    Future<String> createTag(String name, {String sub = _owner}) async {
      final data = await run(
        _createDoc,
        {'name': name, 'clientOpId': nextOp()},
        sub: sub,
      );
      return (data['personTagCreate'] as Map<String, dynamic>)['id']! as String;
    }

    Map<String, dynamic> op(
      String tagId,
      String personId, {
      String kind = 'add',
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
      String sub = _owner,
    }) => run(
      _applyDoc,
      {'ops': ops, 'clientOpId': opId ?? nextOp()},
      sub: sub,
    );

    Future<Map<String, Map<String, int>>> counts({String sub = _owner}) async {
      final data = await run(_tagsDoc, {}, sub: sub);
      return {
        for (final t
            in (data['personTags'] as List<Object?>)
                .cast<Map<String, dynamic>>())
          t['id']! as String: {
            'count': t['count']! as int,
            'countOffField': t['countOffField']! as int,
          },
      };
    }

    Future<Map<String, List<String>>> memberships({
      String sub = _owner,
    }) async {
      final data = await run(_membershipsDoc, {}, sub: sub);
      return {
        for (final m
            in (data['personTagMemberships'] as List<Object?>)
                .cast<Map<String, dynamic>>())
          m['tagId']! as String: (m['personIds']! as List<Object?>)
              .cast<String>(),
      };
    }

    Future<List<String>> tagsOf(String personId, {String sub = _owner}) async {
      final data = await run(_tagsOfDoc, {'personId': personId}, sub: sub);
      final result = data['personTagsOf'] as Map<String, dynamic>;
      return (result['own']! as List<Object?>).cast<String>();
    }

    Future<List<String>> storedMembers(String tagId) async => [
      for (final r in await writer.execute(
        Sql.named(
          'SELECT person_id FROM public.person_tag_member '
          'WHERE tag_id = @tag ORDER BY person_id',
        ),
        parameters: {'tag': tagId},
      ))
        r.single! as String,
    ];

    Future<int> memberRowCount() async =>
        (await writer.execute(
              'SELECT count(*) FROM public.person_tag_member',
            )).single.first!
            as int;

    Future<void> block(String blocker, String blocked) => writer.execute(
      Sql.named(
        'INSERT INTO public.user_block (blocker_id, blocked_id, origin_id) '
        'VALUES (@a, @b, @a)',
      ),
      parameters: {'a': blocker, 'b': blocked},
    );

    Future<void> insertManyUsers(String prefix, int n) => writer.execute(
      Sql.named(
        'INSERT INTO public."user" (id, display_name, public_key) '
        "SELECT @p || lpad(i::text, 6, '0'), 'bulk', @p || i::text "
        'FROM generate_series(1, @n::int) AS s(i)',
      ),
      parameters: {'p': prefix, 'n': n},
    );

    /// Stores [peers] as the owner's visible set the way the visibility
    /// function reads it back, so no MeritRank call is involved. Call it
    /// after the last trust or block change of the test: those invalidate
    /// the stored set.
    Future<void> seedVisibleSet(String viewer, List<String> peers) async {
      final array = peers.isEmpty
          ? "'{}'::text[]"
          : 'ARRAY[${peers.map((p) => "'$p'").join(',')}]::text[]';
      await writer.execute('''
INSERT INTO public.person_visible_set_cache
  (viewer_id, ctx, mr_epoch, trust_gen, peer_ids)
VALUES (
  '$viewer', '',
  coalesce((SELECT epoch FROM public.mr_publish_epoch WHERE id = true), 0),
  (SELECT generation FROM public.visibility_trust_generation WHERE id = true),
  $array)
ON CONFLICT (viewer_id, ctx) DO UPDATE
SET mr_epoch = EXCLUDED.mr_epoch,
    trust_gen = EXCLUDED.trust_gen,
    peer_ids = EXCLUDED.peer_ids
''');
    }

    group('adding and removing people', () {
      test('add stores each person with the op source', () async {
        final tag = await createTag('Friends');

        final result = await apply([
          op(tag, _alice, source: 1),
          op(tag, _bob, source: 3),
        ]);

        expect(result['personTagMembersApply'], isTrue);
        expect(await storedMembers(tag), [_alice, _bob]);
        final sources = await writer.execute(
          Sql.named(
            'SELECT person_id, source FROM public.person_tag_member '
            'WHERE tag_id = @tag ORDER BY person_id',
          ),
          parameters: {'tag': tag},
        );
        expect(
          {for (final r in sources) r[0]! as String: r[1]! as int},
          {_alice: 1, _bob: 3},
        );
        expect(await memberships(), {
          tag: unorderedEquals([_alice, _bob]),
        });
      });

      test('adding a person who is already a member changes nothing', () async {
        final tag = await createTag('Friends');
        await apply([op(tag, _alice, source: 1)]);

        final result = await apply([op(tag, _alice, source: 4)]);

        expect(result['personTagMembersApply'], isTrue);
        final rows = await writer.execute(
          'SELECT source FROM public.person_tag_member',
        );
        expect(rows.single.single, 1);
      });

      test('remove deletes the member and tolerates an absent one', () async {
        final tag = await createTag('Friends');
        await apply([op(tag, _alice), op(tag, _bob)]);

        final result = await apply([
          op(tag, _alice, kind: 'remove'),
          op(tag, _carol, kind: 'remove'),
        ]);

        expect(result['personTagMembersApply'], isTrue);
        expect(await storedMembers(tag), [_bob]);
      });

      test('one call can add and remove across several tags', () async {
        final friends = await createTag('Friends');
        final work = await createTag('Work');
        await apply([op(friends, _alice)]);

        await apply([
          op(friends, _alice, kind: 'remove'),
          op(friends, _bob),
          op(work, _alice),
          op(work, _carol),
        ]);

        expect(await storedMembers(friends), [_bob]);
        expect(await storedMembers(work), [_alice, _carol]);
      });

      test('a person can belong to several tags', () async {
        final friends = await createTag('Friends');
        final work = await createTag('Work');

        await apply([op(friends, _alice), op(work, _alice)]);

        expect(await tagsOf(_alice), [friends, work]);
        expect(await tagsOf(_bob), isEmpty);
      });

      test(
        'a person who does not exist is refused and nothing is written',
        () async {
          final tag = await createTag('Friends');
          expect(
            (await apply([op(tag, _carol)]))['personTagMembersApply'],
            isTrue,
          );

          await failureOf(_applyDoc, {
            'ops': [op(tag, _alice), op(tag, 'Unosuchperson001')],
            'clientOpId': nextOp(),
          });

          expect(await storedMembers(tag), [_carol]);
        },
      );

      test('a source outside the stored range is refused and nothing is '
          'written', () async {
        final tag = await createTag('Friends');
        expect(
          (await apply([op(tag, _carol)]))['personTagMembersApply'],
          isTrue,
        );

        await failureOf(_applyDoc, {
          'ops': [op(tag, _alice), op(tag, _bob, source: 9)],
          'clientOpId': nextOp(),
        });

        expect(await storedMembers(tag), [_carol]);
      });
    });

    group('tagging yourself', () {
      test(
        'is refused with code 1905 and nothing in the call is written',
        () async {
          final tag = await createTag('Friends');

          final error = await failureOf(_applyDoc, {
            'ops': [op(tag, _alice), op(tag, _owner)],
            'clientOpId': nextOp(),
          });

          expect(error, contains('"code":"1905"'));
          expect(await memberRowCount(), 0);
        },
      );
    });

    group("another owner's tags", () {
      test(
        'an op on their tag is code 1903 and the call writes nothing',
        () async {
          final mine = await createTag('Mine');
          final theirs = await createTag('Theirs', sub: _other);

          final error = await failureOf(_applyDoc, {
            'ops': [op(mine, _alice), op(theirs, _alice)],
            'clientOpId': nextOp(),
          });

          expect(error, contains('"code":"1903"'));
          expect(await memberRowCount(), 0);
        },
      );

      test(
        'removing from their tag is code 1903 and keeps their member',
        () async {
          final theirs = await createTag('Theirs', sub: _other);
          await apply([op(theirs, _alice)], sub: _other);

          final error = await failureOf(_applyDoc, {
            'ops': [op(theirs, _alice, kind: 'remove')],
            'clientOpId': nextOp(),
          });

          expect(error, contains('"code":"1903"'));
          expect(await storedMembers(theirs), [_alice]);
        },
      );

      test('a tag id that does not exist is code 1903', () async {
        final error = await failureOf(_applyDoc, {
          'ops': [op('PTnosuchtag0001', _alice)],
          'clientOpId': nextOp(),
        });

        expect(error, contains('"code":"1903"'));
      });

      test(
        'memberships, tag lists and tagsOf never include their tags',
        () async {
          final mine = await createTag('Mine');
          final theirs = await createTag('Theirs', sub: _other);
          await apply([op(mine, _alice)]);
          await apply([op(theirs, _alice), op(theirs, _bob)], sub: _other);

          expect(await memberships(), {
            mine: [_alice],
          });
          expect((await counts()).keys, [mine]);
          expect(await tagsOf(_alice), [mine]);
          expect(await tagsOf(_bob), isEmpty);
          expect(await memberships(sub: _other), {
            theirs: unorderedEquals([_alice, _bob]),
          });
        },
      );
    });

    group('idempotency by clientOpId', () {
      test(
        'a repeated call replays the first result without re-applying',
        () async {
          final tag = await createTag('Friends');
          final ops = [op(tag, _alice)];
          final first = await apply(ops, opId: 'same-op');
          await apply([op(tag, _alice, kind: 'remove')]);

          final second = await apply(ops, opId: 'same-op');

          expect(second, first);
          expect(await storedMembers(tag), isEmpty);
        },
      );

      test(
        'a changed payload under the same clientOpId is code 1906',
        () async {
          final tag = await createTag('Friends');
          await apply([op(tag, _alice)], opId: 'same-op');

          final error = await failureOf(_applyDoc, {
            'ops': [op(tag, _bob)],
            'clientOpId': 'same-op',
          });

          expect(error, contains('"code":"1906"'));
          expect(await storedMembers(tag), [_alice]);
        },
      );
    });

    group('one transaction per call', () {
      const poisoned = 'Uptmempoison0001';

      /// Makes the database reject the insert of one specific person, so a
      /// call fails only after the ops before it have already written.
      setUp(() async {
        await writer.execute(
          Sql.named(
            'INSERT INTO public."user" (id, display_name, public_key) '
            'VALUES (@id, @id, @key)',
          ),
          parameters: {'id': poisoned, 'key': '$poisoned-key'},
        );
        await writer.execute('''
CREATE FUNCTION public.test_reject_poisoned_member() RETURNS trigger
LANGUAGE plpgsql AS \$\$
BEGIN
  IF NEW.person_id = '$poisoned' THEN
    RAISE EXCEPTION 'injected failure after earlier ops wrote';
  END IF;
  RETURN NEW;
END;
\$\$
''');
        await writer.execute('''
CREATE TRIGGER test_reject_poisoned_member_trg
BEFORE INSERT ON public.person_tag_member
FOR EACH ROW EXECUTE FUNCTION public.test_reject_poisoned_member()
''');
      });

      tearDown(() async {
        await writer.execute(
          'DROP TRIGGER IF EXISTS test_reject_poisoned_member_trg '
          'ON public.person_tag_member',
        );
        await writer.execute(
          'DROP FUNCTION IF EXISTS public.test_reject_poisoned_member()',
        );
      });

      test(
        'a failure after earlier adds were written rolls them back',
        () async {
          final tag = await createTag('Friends');
          final work = await createTag('Work');
          expect(
            (await apply([op(tag, _carol)]))['personTagMembersApply'],
            isTrue,
          );

          await failureOf(_applyDoc, {
            'ops': [
              op(tag, _alice),
              op(work, _bob),
              op(tag, poisoned),
            ],
            'clientOpId': nextOp(),
          });

          expect(await storedMembers(tag), [_carol]);
          expect(await storedMembers(work), isEmpty);
        },
      );

      test(
        'a failure after an earlier removal restores the removed member',
        () async {
          final tag = await createTag('Friends');
          await apply([op(tag, _alice), op(tag, _bob)]);

          await failureOf(_applyDoc, {
            'ops': [
              op(tag, _alice, kind: 'remove'),
              op(tag, poisoned),
            ],
            'clientOpId': nextOp(),
          });

          expect(await storedMembers(tag), [_alice, _bob]);
        },
      );

      test('a failed call does not use up its clientOpId', () async {
        final tag = await createTag('Friends');
        final ops = [op(tag, _alice), op(tag, poisoned)];
        await failureOf(_applyDoc, {'ops': ops, 'clientOpId': 'retry-op'});
        await writer.execute(
          'DROP TRIGGER test_reject_poisoned_member_trg '
          'ON public.person_tag_member',
        );

        final result = await apply(ops, opId: 'retry-op');

        expect(result['personTagMembersApply'], isTrue);
        expect(await storedMembers(tag), [_alice, poisoned]);
      });
    });

    group('size limits', () {
      test('a call of 400 ops is applied in one go', () async {
        const bulk = 'Uptmembulk';
        await insertManyUsers(bulk, 400);
        final tag = await createTag('Everyone');

        final result = await apply([
          for (var i = 1; i <= 400; i++)
            op(tag, '$bulk${i.toString().padLeft(6, '0')}'),
        ]);

        expect(result['personTagMembersApply'], isTrue);
        expect(await memberRowCount(), 400);
        expect((await counts())[tag]!['count'], 400);
      });

      test('a call of 401 ops is refused and writes nothing', () async {
        const bulk = 'Uptmembulk';
        await insertManyUsers(bulk, 401);
        final tag = await createTag('Everyone');
        expect(
          (await apply([op(tag, _carol)]))['personTagMembersApply'],
          isTrue,
        );

        await failureOf(_applyDoc, {
          'ops': [
            for (var i = 1; i <= 401; i++)
              op(tag, '$bulk${i.toString().padLeft(6, '0')}'),
          ],
          'clientOpId': nextOp(),
        });

        expect(await storedMembers(tag), [_carol]);
      });

      group('with 1000 members already in the tag', () {
        const bulk = 'Uptmemfull';
        late String tag;

        setUp(() async {
          await insertManyUsers(bulk, 1000);
          tag = await createTag('Full');
          await writer.execute(
            Sql.named(
              'INSERT INTO public.person_tag_member '
              '(tag_id, owner_id, person_id, source) '
              "SELECT @tag, @owner, @p || lpad(i::text, 6, '0'), 0 "
              'FROM generate_series(1, 1000) AS s(i)',
            ),
            parameters: {'tag': tag, 'owner': _owner, 'p': bulk},
          );
        });

        test('the 1001st person is code 1902 and nothing is written', () async {
          final error = await failureOf(_applyDoc, {
            'ops': [op(tag, _alice)],
            'clientOpId': nextOp(),
          });

          expect(error, contains('"code":"1902"'));
          expect(await memberRowCount(), 1000);
          expect(await tagsOf(_alice), isEmpty);
        });

        test('a call that ends over the limit fails as a whole, including '
            'its removals', () async {
          const first = '${bulk}000001';

          final error = await failureOf(_applyDoc, {
            'ops': [
              op(tag, first, kind: 'remove'),
              op(tag, _alice),
              op(tag, _bob),
            ],
            'clientOpId': nextOp(),
          });

          expect(error, contains('"code":"1902"'));
          expect(await memberRowCount(), 1000);
          expect(await tagsOf(first), [tag]);
        });

        test(
          'a call that stays within the limit after a removal succeeds',
          () async {
            final result = await apply([
              op(tag, '${bulk}000001', kind: 'remove'),
              op(tag, _alice),
            ]);

            expect(result['personTagMembersApply'], isTrue);
            expect(await memberRowCount(), 1000);
            expect(await tagsOf(_alice), [tag]);
          },
        );

        test(
          'adding someone who is already a member is not over the limit',
          () async {
            final result = await apply([op(tag, '${bulk}000001')]);

            expect(result['personTagMembersApply'], isTrue);
            expect(await memberRowCount(), 1000);
          },
        );
      });
    });

    group('blocked people', () {
      test('adding a person the owner blocked looks like a normal add but '
          'writes nothing', () async {
        final tag = await createTag('Friends');
        await block(_owner, _alice);

        final skipped = await apply([op(tag, _alice)]);
        final normal = await apply([op(tag, _bob)]);

        expect(normal['personTagMembersApply'], isTrue);
        expect(skipped['personTagMembersApply'], isTrue);
        expect(skipped, normal);
        expect(await storedMembers(tag), [_bob]);
      });

      test('adding a person who blocked the owner looks like a normal add '
          'but writes nothing', () async {
        final tag = await createTag('Friends');
        await block(_alice, _owner);

        final skipped = await apply([op(tag, _alice)]);
        final normal = await apply([op(tag, _bob)]);

        expect(normal['personTagMembersApply'], isTrue);
        expect(skipped['personTagMembersApply'], isTrue);
        expect(skipped, normal);
        expect(await storedMembers(tag), [_bob]);
      });

      test(
        'a blocked op in a batch is skipped and the rest is applied',
        () async {
          final tag = await createTag('Friends');
          await block(_owner, _alice);

          final result = await apply([
            op(tag, _alice),
            op(tag, _bob),
            op(tag, _carol),
          ]);

          expect(result['personTagMembersApply'], isTrue);
          expect(await storedMembers(tag), [_bob, _carol]);
        },
      );

      test('a skipped add does not change the tag counts', () async {
        final tag = await createTag('Friends');
        await block(_owner, _alice);

        final result = await apply([op(tag, _alice)]);

        expect(result['personTagMembersApply'], isTrue);
        expect((await counts())[tag]!['count'], 0);
      });

      group('after an existing member is blocked', () {
        late String tag;

        setUp(() async {
          tag = await createTag('Friends');
          await apply([op(tag, _alice), op(tag, _bob)]);
          await block(_owner, _alice);
        });

        test('they are left out of the count', () async {
          expect((await counts())[tag]!['count'], 1);
        });

        test('they are left out of personTagMemberships', () async {
          expect(await memberships(), {
            tag: [_bob],
          });
        });

        test('personTagsOf reports no tags for them', () async {
          expect(await tagsOf(_alice), isEmpty);
          expect(await tagsOf(_bob), [tag]);
        });

        test('the same holds when they blocked the owner', () async {
          await writer.execute('DELETE FROM public.user_block');
          await block(_bob, _owner);

          expect((await counts())[tag]!['count'], 1);
          expect(await memberships(), {
            tag: [_alice],
          });
          expect(await tagsOf(_bob), isEmpty);
        });

        test('removing them still works', () async {
          await apply([op(tag, _alice, kind: 'remove')]);

          expect(await storedMembers(tag), [_bob]);
        });

        test('unblocking brings them back', () async {
          await writer.execute('DELETE FROM public.user_block');

          expect((await counts())[tag]!['count'], 2);
          expect(await memberships(), {
            tag: unorderedEquals([_alice, _bob]),
          });
          expect(await tagsOf(_alice), [tag]);
        });
      });
    });

    group('memberships', () {
      test('lists every own tag, empty ones included', () async {
        final full = await createTag('Full');
        final empty = await createTag('Empty');
        await apply([op(full, _alice)]);

        expect(await memberships(), {
          full: [_alice],
          empty: isEmpty,
        });
      });

      test('is empty for an owner without tags', () async {
        expect(await memberships(sub: _alice), isEmpty);
      });

      test('a deleted tag is no longer listed', () async {
        final tag = await createTag('Gone');
        await apply([op(tag, _alice)]);
        await run(
          r'''
mutation Delete($id: String!, $clientOpId: String!) {
  personTagDelete(id: $id, clientOpId: $clientOpId) { memberIds }
}
''',
          {'id': tag, 'clientOpId': nextOp()},
        );

        expect(await memberships(), isEmpty);
        expect(await tagsOf(_alice), isEmpty);
      });
    });

    group('tag counts', () {
      test('a new tag has no members', () async {
        final tag = await createTag('Friends');

        expect(await counts(), {
          tag: {'count': 0, 'countOffField': 0},
        });
      });

      test('count is the number of members', () async {
        final tag = await createTag('Friends');
        final other = await createTag('Work');
        await apply([op(tag, _alice), op(tag, _bob), op(other, _alice)]);

        final byTag = await counts();

        expect(byTag[tag]!['count'], 2);
        expect(byTag[other]!['count'], 1);
      });

      group('off the Field', () {
        const visible = 'Uptmemvisible01';
        const stranger = 'Uptmemstranger1';
        const contact = 'Uptmemcontact001';
        const bonded = 'Uptmembonded0001';
        const pinned = 'Uptmempinned0001';
        const blockedStranger = 'Uptmemblockedst1';
        late String tag;

        setUp(() async {
          for (final id in [
            visible,
            stranger,
            contact,
            bonded,
            pinned,
            blockedStranger,
          ]) {
            await writer.execute(
              Sql.named(
                'INSERT INTO public."user" (id, display_name, public_key) '
                'VALUES (@id, @id, @key)',
              ),
              parameters: {'id': id, 'key': '$id-key'},
            );
          }
          tag = await createTag('Everyone');
          await apply([
            for (final p in [
              visible,
              stranger,
              contact,
              bonded,
              pinned,
              blockedStranger,
            ])
              op(tag, p),
          ]);

          // A contact: the owner trusts them directly.
          await writer.execute('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$_owner', '$contact', 1, now(), now())
''');
          // A bond: they take part in an active Request of the owner.
          await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, is_discoverable, published_at)
VALUES ('Bptmembond001', '$_owner', 'Bond', 'd', 0, false, now())
''');
          await writer.execute('''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, room_access)
VALUES ('Bptmembond001', '$bonded', 1, 0)
''');
          // A pinned person on the owner's Field.
          await writer.execute('''
INSERT INTO public.constellation_anchor_cursor (viewer_id)
VALUES ('$_owner')
''');
          await writer.execute('''
INSERT INTO public.constellation_anchor
  (id, viewer_id, person_id, x_units, y_units,
   coordinate_space_version, revision, placed_at)
VALUES ('Aptmempin0001', '$_owner', '$pinned', 0, 0, 1, 1, now())
''');
          await block(_owner, blockedStranger);
        });

        test('counts only members outside the visible set who are not a '
            'bond, a contact or pinned', () async {
          await seedVisibleSet(_owner, [visible]);

          final byTag = await counts();

          expect(byTag[tag]!['count'], 5);
          expect(byTag[tag]!['countOffField'], 1);
        });

        test('a member who lost visibility becomes off the Field', () async {
          await seedVisibleSet(_owner, [visible]);
          expect((await counts())[tag]!['countOffField'], 1);

          await seedVisibleSet(_owner, []);

          final byTag = await counts();
          expect(byTag[tag]!['count'], 5);
          expect(byTag[tag]!['countOffField'], 2);
        });

        test(
          'a member who gained visibility is no longer off the Field',
          () async {
            await seedVisibleSet(_owner, [visible, stranger]);

            expect((await counts())[tag]!['countOffField'], 0);
          },
        );
      });
    });
  });
}
