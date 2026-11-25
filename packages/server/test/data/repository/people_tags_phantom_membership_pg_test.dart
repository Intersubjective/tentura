@Tags(['pg', 'multi-connection'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:tentura_root/domain/entity/person_auto_tag_kind.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart' show TenturaDb;
import 'package:tentura_server/data/repository/people_tags_repository.dart';
import 'package:tentura_server/domain/entity/person_tag.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/utils/id.dart';

import '../../support/disposable_pg_target.dart';

const _owner = 'Uptagplaceown';
const _otherOwner = 'Uptagplaceoth';
const _person = 'Uptagplaceper';
const _otherPerson = 'Uptagplacealt';
const _displayName = 'Lyra Neighbour';

Matcher _sqlState(String code) => throwsA(
  isA<ServerException>().having((error) => error.code, 'SQLSTATE', code),
);

Matcher _tagError(PeopleTagsExceptionCode code) => throwsA(
  isA<PeopleTagsException>().having(
    (error) => error.peopleTagsCode,
    'code',
    code,
  ),
);

PersonTagMemberOp _op(String tag, String id, {bool add = true}) =>
    PersonTagMemberOp(tagId: tag, personId: id, add: add, source: 0);

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PEOPLE_TAGS_PHANTOM_TEST_DB',
    defaultNamePrefix: 'tentura_test_ptag_phantom',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  group('people tags for people not on Tentura yet', () {
    late Connection writer;
    late TenturaDb db;
    late PeopleTagsRepository repository;
    late String tag;
    var opNumber = 0;

    Future<Result> sql(String statement, Map<String, Object?> parameters) =>
        writer.execute(Sql.named(statement), parameters: parameters);

    Future<Result> scopedSql(
      String owner,
      String statement,
      Map<String, Object?> parameters,
    ) => writer.executeWithOwnerScopes(
      [owner],
      Sql.named(statement),
      parameters: parameters,
    );

    Future<String> createTag(String name) async => (await repository.create(
      ownerId: _owner,
      clientOpId: 'create-${opNumber++}',
      fingerprint: name,
      name: name,
      glyph: 'T',
    )).id;

    Future<void> apply(List<PersonTagMemberOp> ops) {
      final operation = 'apply-${opNumber++}';
      return repository.applyMembers(
        ownerId: _owner,
        clientOpId: operation,
        fingerprint: operation,
        ops: ops,
      );
    }

    Future<String> createPhantom({String owner = _owner}) async {
      final id = generateId('PH');
      await scopedSql(
        owner,
        '''
INSERT INTO public.phantom (id, owner_id, display_name)
VALUES (@id, @owner, @name)
''',
        {'id': id, 'owner': owner, 'name': _displayName},
      );
      return id;
    }

    Future<void> setMerged(String id, {required bool merged}) => scopedSql(
      _owner,
      '''
UPDATE public.phantom
SET merged_at = CASE WHEN @merged THEN now() END,
    merged_user_id = CASE WHEN @merged THEN @person::text END,
    merge_origin = CASE WHEN @merged THEN 2 END
WHERE id = @id
''',
      {'id': id, 'merged': merged, 'person': _otherPerson},
    );

    Future<void> seedPhantomMember(
      String tagId,
      String id, {
      String owner = _owner,
      int source = 0,
    }) => scopedSql(
      owner,
      '''
INSERT INTO public.phantom_tag_member (tag_id, owner_id, phantom_id, source)
VALUES (@tag, @owner, @id, @source)
''',
      {'tag': tagId, 'owner': owner, 'id': id, 'source': source},
    );

    Future<Result> phantomRows(String tagId) => sql(
      '''
SELECT tag_id, owner_id, phantom_id, source, membership_id::text AS membership_id
FROM public.phantom_tag_member WHERE tag_id = @tag
''',
      {'tag': tagId},
    );

    Future<Result> personRows(String tagId) => sql(
      'SELECT person_id FROM public.person_tag_member WHERE tag_id = @tag',
      {'tag': tagId},
    );

    Future<List<String>> members(String tagId) async =>
        (await repository.memberships(
          _owner,
        )).singleWhere((membership) => membership.tagId == tagId).personIds;

    Future<PersonTag> tagSummary(String tagId) async =>
        (await repository.list(_owner)).singleWhere((row) => row.id == tagId);

    Future<int> revision() async =>
        (await sql(
              '''
SELECT revision FROM public.person_tag_revision WHERE owner_id = @owner
''',
              {'owner': _owner},
            )).single.single!
            as int;

    Future<void> fillWith999People(String tagId) async {
      await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
SELECT 'U' || lpad(to_hex(n), 12, '0'), 'Member ' || n, 'bulk-key-' || n
FROM generate_series(1, 999) AS members(n)
''');
      final inserted = await scopedSql(
        _owner,
        '''
INSERT INTO public.person_tag_member (tag_id, owner_id, person_id, source)
SELECT @tag, @owner, 'U' || lpad(to_hex(n), 12, '0'), 0
FROM generate_series(1, 999) AS members(n)
RETURNING person_id
''',
        {'tag': tagId, 'owner': _owner},
      );
      expect(inserted, hasLength(999));
    }

    setUpAll(() async {
      final session = await setUpDisposablePgWriter(target: target);
      addTearDown(() => tearDownDisposablePgWriter(session: session));
      writer = session.writer;
      db = openDisposablePgDatabase(target);
      addTearDown(db.close);
      repository = PeopleTagsRepository(db);
    });

    setUp(() async {
      await writer.execute('TRUNCATE TABLE public."user" CASCADE');
      for (final id in [_owner, _otherOwner, _person, _otherPerson]) {
        await sql(
          '''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
''',
          {'id': id, 'key': 'key-$id'},
        );
      }
      // The fixture has no visible peers. Use the real visibility cache so
      // these tests can exercise counts without consulting shared MeritRank.
      await sql(
        '''
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
''',
        {'owner': _owner},
      );
      tag = await createTag('Neighbours');
    });

    test('registered members receive distinct UUIDs and a new UUID on '
        're-addition', () async {
      final columns = await writer.execute('''
SELECT data_type, is_nullable, column_default IS NOT NULL
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'person_tag_member'
  AND column_name = 'membership_id'
''');
      expect(
        columns.map((row) => row.toList()),
        [
          ['uuid', 'NO', true],
        ],
        reason: 'Registered tag members need a non-null UUID with a default.',
      );

      Future<Map<String, Object?>> memberIds() async => {
        for (final row in await sql(
          '''
SELECT person_id, membership_id::text
FROM public.person_tag_member WHERE tag_id = @tag
''',
          {'tag': tag},
        ))
          row[0]! as String: row[1],
      };

      await scopedSql(
        _owner,
        '''
INSERT INTO public.person_tag_member (tag_id, owner_id, person_id, source)
VALUES (@tag, @owner, @first, 0), (@tag, @owner, @second, 0)
''',
        {'tag': tag, 'owner': _owner, 'first': _person, 'second': _otherPerson},
      );
      final original = await memberIds();
      expect(original, {_person: isA<String>(), _otherPerson: isA<String>()});
      expect(original[_person], isNot(original[_otherPerson]));

      await apply([_op(tag, _person, add: false)]);
      expect(await memberIds(), {_otherPerson: original[_otherPerson]});
      await apply([_op(tag, _person)]);
      expect(await memberIds(), {
        _person: allOf(isA<String>(), isNot(original[_person])),
        _otherPerson: original[_otherPerson],
      });
    });

    test('valid stored memberships are listed and cascade with either '
        'parent while invalid sources and tag owners are rejected', () async {
      final id = await createPhantom();
      final secondTag = await createTag('Friends');
      for (final invalidSource in [-1, 5]) {
        await expectLater(
          seedPhantomMember(tag, id, source: invalidSource),
          _sqlState('23514'),
        );
      }
      await expectLater(
        seedPhantomMember(tag, id, owner: _otherOwner),
        _sqlState('23503'),
      );
      await seedPhantomMember(tag, id);
      await seedPhantomMember(secondTag, id, source: 4);
      await expectLater(seedPhantomMember(tag, id), _sqlState('23505'));
      final beforeDelete = await members(tag);

      await sql('DELETE FROM public.person_tag WHERE id = @id', {'id': tag});
      expect(await phantomRows(tag), isEmpty);
      expect(await phantomRows(secondTag), hasLength(1));

      await sql('DELETE FROM public.phantom WHERE id = @id', {'id': id});
      expect(await phantomRows(secondTag), isEmpty);
      expect(await members(secondTag), isEmpty);
      expect(beforeDelete, [id]);
    });

    test('adding a person outside Tentura stores and lists one manual '
        'membership', () async {
      final id = await createPhantom();
      await apply([_op(tag, id)]);

      expect(
        (await phantomRows(tag)).map((row) => row.toColumnMap()),
        [
          {
            'tag_id': tag,
            'owner_id': _owner,
            'phantom_id': id,
            'source': 0,
            'membership_id': matches(
              r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$',
            ),
          },
        ],
      );
      expect(await personRows(tag), isEmpty);
      expect(await members(tag), [id]);
      expect((await tagSummary(tag)).count, 1);
    });

    test('one batch can tag a registered person and a person outside '
        'Tentura together', () async {
      final id = await createPhantom();
      await apply([_op(tag, _person), _op(tag, id)]);

      expect((await personRows(tag)).map((row) => row.single), [_person]);
      expect((await phantomRows(tag)).map((row) => row[2]), [id]);
      expect(await members(tag), unorderedEquals([_person, id]));
      expect((await tagSummary(tag)).count, 2);
    });

    test('removing a person outside Tentura deletes the membership and '
        'decrements the count', () async {
      final id = await createPhantom();
      await apply([_op(tag, _person)]);
      await seedPhantomMember(tag, id);
      final previousCount = (await tagSummary(tag)).count;

      await apply([_op(tag, id, add: false)]);

      expect(await phantomRows(tag), isEmpty);
      expect(await members(tag), [_person]);
      expect((await tagSummary(tag)).count, previousCount - 1);
      expect(previousCount, 2);
    });

    test(
      'an unauthorized, merged or unknown person outside Tentura '
      'rejects the whole batch while an owned active person can be tagged',
      () async {
        final active = await createPhantom();
        final foreign = await createPhantom(owner: _otherOwner);
        final merged = await createPhantom();
        await setMerged(merged, merged: true);

        for (final rejected in [foreign, merged, generateId('PH')]) {
          await expectLater(
            apply([_op(tag, _person), _op(tag, active), _op(tag, rejected)]),
            _tagError(PeopleTagsExceptionCode.invalidTag),
            reason: 'Disallowed target $rejected rejects the entire batch.',
          );
          expect(await phantomRows(tag), isEmpty);
          expect(await personRows(tag), isEmpty);
        }

        await apply([_op(tag, _person), _op(tag, active)]);
        expect(await members(tag), unorderedEquals([_person, active]));
      },
    );

    test('merging hides a stored membership until the person is active '
        'again', () async {
      final id = await createPhantom();
      await apply([_op(tag, _person)]);
      await seedPhantomMember(tag, id);
      final row = (await phantomRows(tag)).single.toList();

      await setMerged(id, merged: true);
      expect((await phantomRows(tag)).single.toList(), row);
      expect(await members(tag), [_person]);
      expect((await tagSummary(tag)).count, 1);

      await setMerged(id, merged: false);
      expect(await members(tag), unorderedEquals([_person, id]));
      expect((await tagSummary(tag)).count, 2);
    });

    test('a tag accepts one person outside Tentura alongside 999 '
        'registered members', () async {
      final id = await createPhantom();
      await fillWith999People(tag);

      await apply([_op(tag, id)]);

      expect(await members(tag), hasLength(1000));
      expect(await members(tag), contains(id));
      expect((await phantomRows(tag)).map((row) => row[2]), [id]);
      expect((await tagSummary(tag)).count, 1000);
    });

    test('a tag with 1000 active members rejects another person outside '
        'Tentura without writing a row', () async {
      final first = await createPhantom();
      final extra = await createPhantom();
      await fillWith999People(tag);
      await apply([_op(tag, first)]);
      expect((await tagSummary(tag)).count, 1000);

      await expectLater(
        apply([_op(tag, extra)]),
        _tagError(PeopleTagsExceptionCode.memberLimitReached),
      );
      expect((await phantomRows(tag)).map((row) => row[2]), [first]);
      expect(await personRows(tag), hasLength(999));
    });

    test('adding two people outside Tentura to a tag with one slot '
        'remaining rejects the whole batch', () async {
      final first = await createPhantom();
      final second = await createPhantom();
      await fillWith999People(tag);

      await expectLater(
        apply([_op(tag, first), _op(tag, second)]),
        _tagError(PeopleTagsExceptionCode.memberLimitReached),
      );
      expect(await phantomRows(tag), isEmpty);
      expect(await personRows(tag), hasLength(999));
      expect((await tagSummary(tag)).count, 999);
    });

    test('a tag with 1000 active members rejects another registered '
        'person when a slot belongs to someone outside Tentura', () async {
      final id = await createPhantom();
      await fillWith999People(tag);
      await apply([_op(tag, id)]);

      await expectLater(
        apply([_op(tag, _person)]),
        _tagError(PeopleTagsExceptionCode.memberLimitReached),
      );
      expect((await phantomRows(tag)).map((row) => row[2]), [id]);
      expect(await personRows(tag), hasLength(999));
    });

    test('a hidden merged membership leaves room for an active member at '
        'the tag limit', () async {
      final merged = await createPhantom();
      final active = await createPhantom();
      await fillWith999People(tag);
      await apply([_op(tag, merged)]);
      await setMerged(merged, merged: true);

      await apply([_op(tag, active)]);

      expect(
        (await phantomRows(tag)).map((row) => row[2]),
        unorderedEquals([
          merged,
          active,
        ]),
      );
      final listed = await members(tag);
      expect(listed, hasLength(1000));
      expect(listed, contains(active));
      expect(listed, isNot(contains(merged)));
      expect((await tagSummary(tag)).count, 1000);
    });

    test('people outside Tentura count as tag members on the owner’s '
        'Field', () async {
      final first = await createPhantom();
      final second = await createPhantom();
      final phantomOnlyTag = await createTag('Local group');
      await apply([_op(tag, _person)]);
      for (final tagId in [tag, phantomOnlyTag]) {
        await seedPhantomMember(tagId, first);
        await seedPhantomMember(tagId, second);
      }

      final tags = {
        for (final row in await repository.list(_owner)) row.id: row,
      };
      expect(tags[tag]!.countOffField, 1);
      expect(tags[phantomOnlyTag]!.countOffField, 0);
      expect(tags[tag]!.count, 3);
      expect(tags[phantomOnlyTag]!.count, 2);
    });

    test('listing tags with only people outside Tentura skips the '
        'registered peer visibility lookup', () async {
      final id = await createPhantom();
      await seedPhantomMember(tag, id);

      Future<int> visibilityCalls() async =>
          (await writer.execute('''
SELECT coalesce(sum(calls), 0)::bigint
FROM pg_stat_user_functions
WHERE funcid = 'public.person_visible_peer_ids_tx(text,text)'::regprocedure
''')).single.single!
              as int;

      Future<T> trackCalls<T>(Future<T> Function() action) =>
          db.withTransaction(() async {
            await db.customStatement("SET LOCAL track_functions = 'all'");
            final result = await action();
            await db.customStatement('SELECT pg_stat_force_next_flush()');
            return result;
          });

      // A real registered membership supplies a positive control for tracking.
      await apply([_op(tag, _person)]);
      final initialCalls = await visibilityCalls();
      await trackCalls(() => tagSummary(tag));
      final trackedCalls = await visibilityCalls();
      expect(trackedCalls, greaterThan(initialCalls));
      await apply([_op(tag, _person, add: false)]);
      expect(await personRows(tag), isEmpty);

      final summary = await trackCalls(() => tagSummary(tag));

      expect(await visibilityCalls(), trackedCalls);
      expect(summary.count, 1);
      expect(summary.countOffField, 0);
    });

    for (final add in [true, false]) {
      test('${add ? 'adding' : 'removing'} a person outside Tentura sends '
          'one private hint for the committed revision', () async {
        final id = await createPhantom();
        if (!add) await seedPhantomMember(tag, id);
        final before = await revision();
        final listener = await Connection.open(
          target.databaseEnv.pgEndpoint,
          settings: target.databaseEnv.pgEndpointSettings,
        );
        addTearDown(listener.close);

        const marker = 'end-of-tag-notifications';
        final delivered = Completer<void>();
        final payloads = <String>[];
        final subscription = listener.channels['entity_changes'].listen((raw) {
          if (raw == marker) {
            delivered.complete();
          } else {
            payloads.add(raw);
          }
        });
        addTearDown(subscription.cancel);
        await listener.execute('LISTEN entity_changes');

        await apply([_op(tag, id, add: add)]);
        // PostgreSQL delivers notifications in commit order. A marker after
        // the mutation lets the test check cardinality without a sleep.
        await writer.channels.notify('entity_changes', marker);
        await delivered.future.timeout(const Duration(seconds: 5));

        final hints = [
          for (final raw in payloads)
            if ((jsonDecode(raw) as Map<String, dynamic>)['entity'] ==
                'person_tag')
              raw,
        ];
        expect(hints, hasLength(1));
        final raw = hints.single;
        final hint = jsonDecode(raw) as Map<String, dynamic>;
        expect(hint['id'], _owner);
        expect(hint['user_ids'], [_owner]);
        final committed = await revision();
        expect(committed, greaterThan(before));
        expect(hint['revision'], committed.toString());
        expect(raw, isNot(contains(_displayName)));
        expect(raw, isNot(contains(id)));
      });
    }

    test('manual tags for people outside Tentura leave every automatic tag '
        'unchanged', () async {
      final id = await createPhantom();
      await sql(
        '''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES (@owner, @person, 1, now(), now())
''',
        {'owner': _owner, 'person': _person},
      );

      Future<Map<int, int>> autoCounts() async => {
        for (final summary in await repository.autoTags(_owner))
          summary.kind: summary.count,
      };

      final trust = PersonAutoTagKind.iTrust.smallintValue;
      expect(await autoCounts(), {trust: 1});

      await apply([_op(tag, id)]);

      expect(await autoCounts(), {trust: 1});
      for (final kind in PersonAutoTagKind.values) {
        expect(
          await repository.autoTagMembers(_owner, kind.smallintValue),
          kind == PersonAutoTagKind.iTrust ? [_person] : isEmpty,
          reason: kind.name,
        );
      }
      expect(await members(tag), [id]);
    });
  });
}
