@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/people_tags_repository.dart';
import 'package:tentura_server/domain/entity/person_tag.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/domain/use_case/user_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/user_erasure_test_stack.dart';

const _ownerA = 'Upthintownera1';
const _ownerB = 'Upthintownerb1';
const _personP = 'Upthintpersonp1';
const _personQ = 'Upthintpersonq1';
const _users = [_ownerA, _ownerB, _personP, _personQ];

// Distinctive so that a leak into a realtime payload is unmistakable.
const _nameA = 'Zebra Confidants';
const _nameB = 'Quokka Neighbours';
const _glyphA = 'Ж';
const _glyphB = 'Ω';

/// Person-tag realtime hints come from deferred constraint triggers: one
/// `person_tag` `update` per owner per committed transaction, addressed to
/// that owner only and carrying the owner's committed revision, never a tag
/// name or glyph. Erasing a tag owner or a tagged person must still commit.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PERSON_TAG_DEFERRED_NOTIFY_TEST_DB',
    defaultNamePrefix: 'tentura_test_ptdefnotify',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  group('person tag deferred notifications', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late Connection listener;
    late StreamSubscription<String> notificationSubscription;
    late TenturaDb db;
    late PeopleTagsRepository tags;
    late UserCase userCase;
    late PersonTag tagA;
    late PersonTag tagB;
    final rawNotifications = <String>[];
    var opCounter = 0;

    String nextOp() => 'op-hint-${opCounter++}';

    List<Map<String, dynamic>> hints([String? owner]) => [
      for (final raw in rawNotifications)
        if ((jsonDecode(raw) as Map<String, dynamic>) case final m
            when m['entity'] == 'person_tag')
          if (owner == null || m['id'] == owner) m,
    ];

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 200));

    Future<String?> committedRevision(String owner) async {
      final rows = await writer.execute(
        Sql.named(
          'SELECT revision FROM public.person_tag_revision '
          'WHERE owner_id = @owner',
        ),
        parameters: {'owner': owner},
      );
      return rows.isEmpty ? null : rows.single.single.toString();
    }

    /// Row operations on `person_tag_revision` since the last reset, as
    /// `{owner: [ops]}` (an erased owner's cascade shows up as `DELETE`).
    Future<Map<String, List<String>>> revisionOps() async {
      final rows = await writer.execute(
        'SELECT owner_id, op FROM public.person_tag_revision_probe ORDER BY seq',
      );
      final ops = <String, List<String>>{};
      for (final row in rows) {
        ops.putIfAbsent(row[0]! as String, () => []).add(row[1]! as String);
      }
      return ops;
    }

    Future<BigInt> revisionNumber(String owner) async =>
        BigInt.parse((await committedRevision(owner))!);

    Future<PersonTag> createTag(String owner, String name, String glyph) =>
        tags.create(
          ownerId: owner,
          clientOpId: nextOp(),
          fingerprint: 'fp-${opCounter}',
          name: name,
          glyph: glyph,
        );

    Future<void> applyMembers(
      String owner,
      List<PersonTagMemberOp> ops,
    ) => tags.applyMembers(
      ownerId: owner,
      clientOpId: nextOp(),
      fingerprint: 'fp-${opCounter}',
      ops: ops,
    );

    PersonTagMemberOp add(String tagId, String personId) => PersonTagMemberOp(
      tagId: tagId,
      personId: personId,
      add: true,
      source: 0,
    );

    PersonTagMemberOp remove(String tagId, String personId) =>
        PersonTagMemberOp(
          tagId: tagId,
          personId: personId,
          add: false,
          source: 0,
        );

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      listener = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      // Records every row operation on the revision table, so a bump that
      // replaces the row (delete + insert) is told apart from an update.
      await writer.execute('''
CREATE TABLE public.person_tag_revision_probe (
  seq bigserial PRIMARY KEY,
  owner_id text NOT NULL,
  op text NOT NULL
)
''');
      await writer.execute(r'''
CREATE FUNCTION public.person_tag_revision_probe_fn() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.person_tag_revision_probe (owner_id, op)
  VALUES (COALESCE(NEW.owner_id, OLD.owner_id), TG_OP);
  RETURN NULL;
END;
$$
''');
      await writer.execute('''
CREATE TRIGGER person_tag_revision_probe_trg
AFTER INSERT OR UPDATE OR DELETE ON public.person_tag_revision
FOR EACH ROW EXECUTE FUNCTION public.person_tag_revision_probe_fn()
''');
      await listener.execute('LISTEN entity_changes');
      notificationSubscription = listener.channels['entity_changes'].listen(
        rawNotifications.add,
      );
      await settle();

      db = openDisposablePgDatabase(target);
      tags = PeopleTagsRepository(db);
      final env = Env(environment: Environment.test);
      final logger = Logger('PersonTagDeferredNotificationPgTest');
      userCase = buildUserErasureTestStack(
        db: db,
        userRepository: buildDefaultUserRepository(db),
        lifecycleEffects: BeaconLifecycleEffectsCase(
          BeaconHierarchyOutboxRepository(db),
          env: env,
          logger: logger,
        ),
        attention: TransactionalAttentionCase(
          MutatingUnitOfWork(db),
          AttentionDispatchRepository(db, logger),
        ),
        logger: logger,
      ).userCase;
    });

    setUp(() async {
      await writer.execute('TRUNCATE TABLE public."user" CASCADE');
      for (var i = 0; i < _users.length; i++) {
        await writer.execute(
          Sql.named(
            'INSERT INTO public."user" (id, display_name, public_key) '
            'VALUES (@id, @id, @key)',
          ),
          parameters: {
            'id': _users[i],
            'key': pgTestPublicKey('pthint', i + 1),
          },
        );
      }
      tagA = await createTag(_ownerA, _nameA, _glyphA);
      tagB = await createTag(_ownerB, _nameB, _glyphB);
      await settle();
      rawNotifications.clear();
      await writer.execute('TRUNCATE public.person_tag_revision_probe');
    });

    tearDownAll(() async {
      if (!session.setupComplete) {
        return;
      }
      await notificationSubscription.cancel();
      await listener.close();
      await tearDownDisposablePgWriter(session: session, drift: db);
    });

    test(
      'one membership batch delivers exactly one hint to the owner with the '
      'committed revision and no tag name or glyph',
      () async {
        final before = await committedRevision(_ownerA);
        final beforeNumber = await revisionNumber(_ownerA);

        await applyMembers(_ownerA, [
          add(tagA.id, _personP),
          add(tagA.id, _personQ),
          remove(tagA.id, _personP),
          add(tagA.id, _personP),
        ]);
        await settle();

        final committed = await committedRevision(_ownerA);
        expect(committed, isNotNull);
        expect(committed, isNot(before));
        expect(await revisionNumber(_ownerA), beforeNumber + BigInt.one);
        // The bump is a single UPDATE of the existing row: never an insert.
        expect(await revisionOps(), {
          _ownerA: ['UPDATE'],
        });
        final delivered = hints();
        expect(delivered, hasLength(1));
        final hint = delivered.single;
        expect(hint['id'], _ownerA);
        expect(hint['event'], 'update');
        expect(hint['user_ids'], [_ownerA]);
        expect(hint['revision'].toString(), committed);
        expect(hint.containsKey('name'), isFalse);
        expect(hint.containsKey('glyph'), isFalse);
        final raw = rawNotifications.firstWhere(
          (r) => (jsonDecode(r) as Map)['entity'] == 'person_tag',
        );
        for (final secret in [_nameA, _glyphA, _personP, _personQ, tagA.id]) {
          expect(raw, isNot(contains(secret)), reason: 'payload leaks $secret');
        }
      },
    );

    for (final (label, statement) in [
      (
        'renaming a tag',
        "UPDATE public.person_tag SET name = 'Renamed' WHERE id = '%TAG%'",
      ),
      (
        'changing an automatic tag preference',
        'INSERT INTO public.person_auto_tag_pref (owner_id, kind, '
            "show_in_filters) VALUES ('%OWNER%', 1, true)",
      ),
      (
        'changing the suggestion state',
        'INSERT INTO public.person_tag_suggestion_state (owner_id, '
            "consecutive_skips) VALUES ('%OWNER%', 2)",
      ),
    ]) {
      test('$label delivers one hint to the owner', () async {
        final before = await committedRevision(_ownerA);

        await writer.execute(
          statement.replaceAll('%TAG%', tagA.id).replaceAll('%OWNER%', _ownerA),
        );
        await settle();

        final committed = await committedRevision(_ownerA);
        expect(committed, isNot(before));
        expect(await revisionOps(), {
          _ownerA: ['UPDATE'],
        });
        final delivered = hints();
        expect(delivered, hasLength(1));
        expect(delivered.single['id'], _ownerA);
        expect(delivered.single['user_ids'], [_ownerA]);
        expect(delivered.single['revision'].toString(), committed);
      });
    }

    test(
      'the publisher bumps the revision with UPDATE ... RETURNING and never '
      'inserts or re-reads the row',
      () async {
        // Inside a transaction the bump is indistinguishable from an UPDATE
        // followed by a SELECT by behaviour alone, so the function body is
        // what pins the contract.
        final rows = await writer.execute(
          "SELECT pg_get_functiondef('public.notify_person_tag_change'::regproc)",
        );
        final body = (rows.single.single! as String)
            .replaceAll(RegExp(r'\s+'), ' ')
            .toLowerCase();

        expect(
          body,
          matches(
            RegExp(
              r'update (public\.)?person_tag_revision set revision = '
              r'(person_tag_revision\.|r\.)?revision \+ 1 .*returning '
              r'(\w+\.)?revision',
            ),
          ),
          reason: 'the bump must be a single UPDATE ... RETURNING revision',
        );
        expect(
          body,
          isNot(matches(RegExp(r'insert into (public\.)?person_tag_revision'))),
        );
        expect(body, isNot(contains('on conflict')));
        expect(
          body,
          isNot(matches(RegExp(r'from (public\.)?person_tag_revision'))),
          reason: 'the revision must not be read back with a separate SELECT',
        );
      },
    );

    test('a rolled back membership change delivers no hint', () async {
      final before = await committedRevision(_ownerA);

      await expectLater(
        writer.runTx((tx) async {
          await tx.execute(
            Sql.named(
              'INSERT INTO public.person_tag_member '
              '(tag_id, owner_id, person_id, source) '
              'VALUES (@tag, @owner, @person, 0)',
            ),
            parameters: {'tag': tagA.id, 'owner': _ownerA, 'person': _personP},
          );
          throw StateError('abort batch');
        }),
        throwsA(isA<StateError>()),
      );
      await settle();

      expect(hints(), isEmpty);
      expect(await committedRevision(_ownerA), before);
    });

    test(
      'one transaction touching two owners delivers one hint per owner, '
      'each to that owner only',
      () async {
        await writer.runTx((tx) async {
          for (final (tag, owner, person) in [
            (tagA.id, _ownerA, _personP),
            (tagA.id, _ownerA, _personQ),
            (tagB.id, _ownerB, _personP),
          ]) {
            await tx.execute(
              Sql.named(
                'INSERT INTO public.person_tag_member '
                '(tag_id, owner_id, person_id, source) '
                'VALUES (@tag, @owner, @person, 0)',
              ),
              parameters: {'tag': tag, 'owner': owner, 'person': person},
            );
          }
        });
        await settle();

        final mine = hints(_ownerA);
        final theirs = hints(_ownerB);
        expect(hints(), hasLength(2));
        expect(mine, hasLength(1));
        expect(theirs, hasLength(1));
        expect(mine.single['user_ids'], [_ownerA]);
        expect(theirs.single['user_ids'], [_ownerB]);
        expect(await revisionOps(), {
          _ownerA: ['UPDATE'],
          _ownerB: ['UPDATE'],
        });
        expect(
          mine.single['revision'].toString(),
          await committedRevision(_ownerA),
        );
        expect(
          theirs.single['revision'].toString(),
          await committedRevision(_ownerB),
        );
      },
    );

    test(
      'erasing a tag owner commits, emits nothing for them and leaves '
      'other owners notifiable',
      () async {
        await applyMembers(_ownerA, [add(tagA.id, _personP)]);
        await applyMembers(_ownerB, [add(tagB.id, _personP)]);
        await settle();
        rawNotifications.clear();
        await writer.execute('TRUNCATE public.person_tag_revision_probe');

        expect(await userCase.deleteById(id: _ownerA), isTrue);
        await settle();

        expect(hints(_ownerA), isEmpty);
        expect(hints(), isEmpty);
        expect(await committedRevision(_ownerA), isNull);
        // Only the cascade removes the erased owner's revision row; no bump
        // tried to insert or update one.
        expect(await revisionOps(), {
          _ownerA: ['DELETE'],
        });
        final leftovers = await writer.execute(
          Sql.named(
            'SELECT (SELECT count(*) FROM public.person_tag '
            '        WHERE owner_id = @owner)::int, '
            '       (SELECT count(*) FROM public.person_tag_member '
            '        WHERE owner_id = @owner)::int',
          ),
          parameters: {'owner': _ownerA},
        );
        expect(leftovers.single.toList(), [0, 0]);

        // The remaining owner still gets exactly one hint for a new batch.
        await writer.execute('TRUNCATE public.person_tag_revision_probe');
        await applyMembers(_ownerB, [add(tagB.id, _personQ)]);
        await settle();
        expect(hints(), hasLength(1));
        expect(hints(_ownerB), hasLength(1));
      },
    );

    test(
      'erasing a tagged person commits and notifies each surviving owner '
      'once',
      () async {
        await applyMembers(_ownerA, [
          add(tagA.id, _personP),
          add(tagA.id, _personQ),
        ]);
        await applyMembers(_ownerB, [add(tagB.id, _personP)]);
        await settle();
        final revisionA = await revisionNumber(_ownerA);
        final revisionB = await revisionNumber(_ownerB);
        rawNotifications.clear();
        await writer.execute('TRUNCATE public.person_tag_revision_probe');

        expect(await userCase.deleteById(id: _personP), isTrue);
        await settle();

        expect(hints(), hasLength(2));
        final mine = hints(_ownerA);
        final theirs = hints(_ownerB);
        expect(mine, hasLength(1));
        expect(theirs, hasLength(1));
        expect(mine.single['user_ids'], [_ownerA]);
        expect(theirs.single['user_ids'], [_ownerB]);
        expect(await revisionNumber(_ownerA), revisionA + BigInt.one);
        expect(await revisionNumber(_ownerB), revisionB + BigInt.one);
        // Each surviving owner's existing revision row is updated once; no
        // row is inserted or replaced while the person is erased.
        expect(await revisionOps(), {
          _ownerA: ['UPDATE'],
          _ownerB: ['UPDATE'],
        });
        expect(
          mine.single['revision'].toString(),
          await committedRevision(_ownerA),
        );
        expect(
          theirs.single['revision'].toString(),
          await committedRevision(_ownerB),
        );
        final members = await writer.execute(
          Sql.named(
            'SELECT count(*)::int FROM public.person_tag_member '
            'WHERE person_id = @person',
          ),
          parameters: {'person': _personP},
        );
        expect(members.single.single, 0);
      },
    );
  });
}
