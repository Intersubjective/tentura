// The member-limit case inserts 1000 tag members, which fires per-row
// triggers; give the whole file the same headroom as the membership suite.
@Timeout(Duration(minutes: 3))
@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_new_people_repository.dart';
import 'package:tentura_server/data/repository/people_tags_repository.dart';
import 'package:tentura_server/domain/entity/person_tag.dart';

import '../../support/disposable_pg_target.dart';

const _viewer = 'Uinhviewer0001';
const _otherOwner = 'Uinhother00001';
const _bob = 'Uinhbob0000001';
const _carol = 'Uinhcarol00001';
const _dave = 'Uinhdave000001';

/// Membership source of a tag a newcomer inherited from their inviter.
const _inherited = 4;

/// When a person first appears on the viewer's Field, they join the viewer's
/// own tags that already hold their direct inviter. Only live first sightings
/// inherit (never the initial backfill, never a repeat), only the viewer's own
/// tag rows travel, and blocks or a self-invite stop it.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_NEW_PEOPLE_INHERITED_TAGS_TEST_DB',
    defaultNamePrefix: 'tentura_test_inhtags',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('newcomer inherits the viewer tags of their inviter', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb db;
    late ConstellationNewPeopleRepository newPeople;
    late PeopleTagsRepository tags;
    late PersonTag tagA;
    late PersonTag tagB;
    var opCounter = 0;

    String nextOp() => 'op-inh-${opCounter++}';

    Future<PersonTag> createTag(String owner, String name) => tags.create(
      ownerId: owner,
      clientOpId: nextOp(),
      fingerprint: 'fp-$opCounter',
      name: name,
      glyph: name.substring(0, 1),
    );

    Future<void> tag(
      String owner,
      List<(String, String)> tagPerson, {
      int source = 0,
    }) => tags.applyMembers(
      ownerId: owner,
      clientOpId: nextOp(),
      fingerprint: 'fp-$opCounter',
      ops: [
        for (final (tagId, person) in tagPerson)
          PersonTagMemberOp(
            tagId: tagId,
            personId: person,
            add: true,
            source: source,
          ),
      ],
    );

    /// `{tagName: source}` of [person] in [owner]'s tags.
    Future<Map<String, int>> membershipsOf(
      String person, {
      String owner = _viewer,
    }) async {
      final rows = await writer.execute(
        Sql.named('''
SELECT t.name, m.source::int
  FROM public.person_tag_member m
  JOIN public.person_tag t ON t.id = m.tag_id
 WHERE m.owner_id = @owner AND m.person_id = @person
 ORDER BY t.name
'''),
        parameters: {'owner': owner, 'person': person},
      );
      return {for (final r in rows) r[0]! as String: r[1]! as int};
    }

    Future<int> membersOwnedOtherThanViewer(String person) async {
      final rows = await writer.execute(
        Sql.named(
          'SELECT count(*)::int FROM public.person_tag_member '
          'WHERE person_id = @person AND owner_id <> @viewer',
        ),
        parameters: {'person': person, 'viewer': _viewer},
      );
      return rows.single.single! as int;
    }

    Future<BigInt> revisionOf(String owner) async {
      final rows = await writer.execute(
        Sql.named(
          'SELECT revision::text FROM public.person_tag_revision '
          'WHERE owner_id = @owner',
        ),
        parameters: {'owner': owner},
      );
      return rows.isEmpty
          ? BigInt.zero
          : BigInt.parse(rows.single.single! as String);
    }

    Future<void> insertUser(String id, int order) => writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES (@id, @id, @key,
        timestamptz '2026-01-01T00:00:00Z' + make_interval(days => @order),
        timestamptz '2026-01-01T00:00:00Z' + make_interval(days => @order))
'''),
      parameters: {'id': id, 'key': 'pk-$id', 'order': order},
    );

    /// [inviter]'s accepted invitation brought [newcomer] in.
    Future<void> invited(String inviter, String newcomer) => writer.execute(
      Sql.named('''
INSERT INTO public.invite_genealogy (
  descendant_node_key, ancestor_node_key, descendant_user_id, ancestor_user_id,
  ancestor_user_created_at, descendant_user_created_at)
SELECT 'nk-' || d.id, 'nk-' || a.id, d.id, a.id, a.created_at, d.created_at
  FROM public."user" a, public."user" d
 WHERE a.id = @inviter AND d.id = @newcomer
'''),
      parameters: {'inviter': inviter, 'newcomer': newcomer},
    );

    Future<void> block(String blocker, String blocked) => writer.execute(
      Sql.named(
        'INSERT INTO public.user_block (blocker_id, blocked_id, origin_id) '
        'VALUES (@blocker, @blocked, @blocked)',
      ),
      parameters: {'blocker': blocker, 'blocked': blocked},
    );

    Future<void> firstSeen(List<String> peers, {bool backfill = false}) =>
        newPeople.recordFirstSeen(
          viewerId: _viewer,
          peerIds: peers,
          backfill: backfill,
        );

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      db = openDisposablePgDatabase(target);
      newPeople = ConstellationNewPeopleRepository(db);
      tags = PeopleTagsRepository(db);
    });

    tearDownAll(() async {
      if (!session.setupComplete) return;
      await tearDownDisposablePgWriter(session: session, drift: db);
    });

    setUp(() async {
      await writer.execute('TRUNCATE TABLE public."user" CASCADE');
      // Creation order matters: an inviter must predate their invitee.
      for (final (i, id) in [
        _viewer,
        _otherOwner,
        _bob,
        _carol,
        _dave,
      ].indexed) {
        await insertUser(id, i);
      }
      tagA = await createTag(_viewer, 'Alpha');
      tagB = await createTag(_viewer, 'Beta');
      await tag(_viewer, [(tagA.id, _bob), (tagB.id, _bob)]);
    });

    test('a newcomer joins every viewer tag their inviter is in, marked as '
        'inherited', () async {
      await invited(_bob, _carol);

      await firstSeen([_carol]);

      expect(await membershipsOf(_carol), {
        'Alpha': _inherited,
        'Beta': _inherited,
      });
      // The inviter's own memberships are left as they were.
      expect(await membershipsOf(_bob), {'Alpha': 0, 'Beta': 0});
    });

    test('a tag the inviter itself inherited is passed on as well', () async {
      final gamma = await createTag(_viewer, 'Gamma');
      await tag(_viewer, [(gamma.id, _bob)], source: _inherited);
      await invited(_bob, _carol);

      await firstSeen([_carol]);

      expect(await membershipsOf(_carol), {
        'Alpha': _inherited,
        'Beta': _inherited,
        'Gamma': _inherited,
      });
    });

    group('an invitation chain', () {
      setUp(() async {
        await invited(_bob, _carol);
        await invited(_carol, _dave);
      });

      for (final (order, peers) in [
        ('inviter listed first', [_carol, _dave]),
        ('invitee listed first', [_dave, _carol]),
      ]) {
        test('passes the tags down when inviter and invitee are first seen '
            'in the same call ($order)', () async {
          await firstSeen(peers);

          expect(await membershipsOf(_carol), {
            'Alpha': _inherited,
            'Beta': _inherited,
          });
          expect(await membershipsOf(_dave), {
            'Alpha': _inherited,
            'Beta': _inherited,
          });
        });
      }

      test(
        'passes inherited tags on when the invitee is first seen later',
        () async {
          await firstSeen([_carol]);
          await firstSeen([_dave]);

          expect(await membershipsOf(_dave), {
            'Alpha': _inherited,
            'Beta': _inherited,
          });
        },
      );
    });

    test('the initial backfill of the Field inherits nothing', () async {
      await invited(_bob, _carol);

      await firstSeen([_carol], backfill: true);

      expect(await membershipsOf(_carol), isEmpty);
    });

    group('a person already first seen', () {
      late PersonTag tagC;

      setUp(() async {
        await invited(_bob, _carol);
        tagC = await createTag(_viewer, 'Gamma');
      });

      test('is not re-evaluated when the inviter later gains a tag', () async {
        await firstSeen([_carol]);
        await tag(_viewer, [(tagC.id, _bob)]);

        await firstSeen([_carol]);

        expect(await membershipsOf(_carol), {
          'Alpha': _inherited,
          'Beta': _inherited,
        });
      });

      test(
        'through the backfill never inherits on a later live call',
        () async {
          await firstSeen([_carol], backfill: true);
          await tag(_viewer, [(tagC.id, _bob)]);

          await firstSeen([_carol]);

          expect(await membershipsOf(_carol), isEmpty);
        },
      );
    });

    group('inherits nothing', () {
      test('when the viewer is the inviter', () async {
        await invited(_viewer, _carol);

        await firstSeen([_carol]);

        expect(await membershipsOf(_carol), isEmpty);
      });

      for (final (label, blocker, blocked) in [
        ('when the viewer blocked the inviter', _viewer, _bob),
        ('when the inviter blocked the viewer', _bob, _viewer),
        ('when the viewer blocked the newcomer', _viewer, _carol),
        ('when the newcomer blocked the viewer', _carol, _viewer),
      ]) {
        test(label, () async {
          await invited(_bob, _carol);
          await block(blocker, blocked);

          await firstSeen([_carol]);

          expect(await membershipsOf(_carol), isEmpty);
        });
      }

      test('when the inviter has been deleted', () async {
        await invited(_bob, _carol);
        await writer.execute(
          Sql.named('DELETE FROM public."user" WHERE id = @id'),
          parameters: {'id': _bob},
        );

        await firstSeen([_carol]);

        expect(await membershipsOf(_carol), isEmpty);
      });
    });

    test("only the viewer's own tags travel, never another owner's tags on "
        'the inviter', () async {
      final foreign = await createTag(_otherOwner, 'Foreign');
      await tag(_otherOwner, [(foreign.id, _bob)]);
      await invited(_bob, _carol);

      await firstSeen([_carol]);

      expect(await membershipsOf(_carol), {
        'Alpha': _inherited,
        'Beta': _inherited,
      });
      expect(await membershipsOf(_carol, owner: _otherOwner), isEmpty);
      expect(await membersOwnedOtherThanViewer(_carol), 0);
    });

    test('a tag at its member limit is skipped silently while the others are '
        'still copied', () async {
      const bulk = 'Uinhbulk';
      // Alpha already holds Bob; 999 more people fill it to the 1000 limit.
      await writer.execute(
        Sql.named(
          'INSERT INTO public."user" (id, display_name, public_key) '
          "SELECT @p || lpad(i::text, 6, '0'), 'bulk', @p || i::text "
          'FROM generate_series(1, 999) AS s(i)',
        ),
        parameters: {'p': bulk},
      );
      await writer.execute(
        Sql.named(
          'INSERT INTO public.person_tag_member '
          '(tag_id, owner_id, person_id, source) '
          "SELECT @tag, @owner, @p || lpad(i::text, 6, '0'), 0 "
          'FROM generate_series(1, 999) AS s(i)',
        ),
        parameters: {'tag': tagA.id, 'owner': _viewer, 'p': bulk},
      );
      await invited(_bob, _carol);

      await firstSeen([_carol]);

      expect(await membershipsOf(_carol), {'Beta': _inherited});
      final alphaSize = await writer.execute(
        Sql.named(
          'SELECT count(*)::int FROM public.person_tag_member '
          'WHERE tag_id = @tag',
        ),
        parameters: {'tag': tagA.id},
      );
      expect(alphaSize.single.single, 1000);
    });

    group('the viewer tag revision', () {
      test(
        'rises by exactly one for a call with one newcomer that inherits',
        () async {
          await invited(_bob, _carol);
          final before = await revisionOf(_viewer);

          await firstSeen([_carol]);

          expect(await revisionOf(_viewer), before + BigInt.one);
        },
      );

      test(
        'rises by exactly one for a call that inherits along a chain',
        () async {
          await invited(_bob, _carol);
          await invited(_carol, _dave);
          final before = await revisionOf(_viewer);

          await firstSeen([_carol, _dave]);

          expect(await revisionOf(_viewer), before + BigInt.one);
        },
      );

      test('rises by exactly one for each later call that inherits', () async {
        await invited(_bob, _carol);
        await invited(_carol, _dave);
        final before = await revisionOf(_viewer);

        await firstSeen([_carol]);
        await firstSeen([_dave]);

        expect(await revisionOf(_viewer), before + BigInt.two);
      });

      test('stays put for a call that inherits nothing', () async {
        await invited(_bob, _carol);
        final before = await revisionOf(_viewer);

        await firstSeen([_carol], backfill: true);

        expect(await revisionOf(_viewer), before);
      });
    });
  });
}
