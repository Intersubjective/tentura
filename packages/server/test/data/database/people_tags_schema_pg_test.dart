@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';

/// People tags schema: an owner's private tags, their members, auto-tag
/// preferences, first-seen markers, suggestion state and the idempotency log.
/// Every size and ownership rule is enforced by the schema, not by callers.
const _owner = 'Uptagsowner001';
const _other = 'Uptagsother0001';
const _person = 'Uptagsperson001';
const _person2 = 'Uptagsperson002';

const _checkViolation = '23514';
const _uniqueViolation = '23505';
const _foreignKeyViolation = '23503';

const _newTables = [
  'person_tag',
  'person_tag_member',
  'person_auto_tag_pref',
  'person_field_first_seen',
  'person_tag_suggestion_state',
  'person_tag_op_log',
  'person_tag_revision',
];

Matcher _throwsSqlState(String code) => throwsA(
  isA<ServerException>().having((e) => e.code, 'sqlstate', code),
);

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PEOPLE_TAGS_SCHEMA_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_people_tags',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('upgrade from the previous schema version', () {
    late DisposablePgWriterSession session;
    late Connection writer;

    Future<bool> tableExists(String name) async {
      final rows = await writer.execute(
        "SELECT to_regclass('public.$name') IS NOT NULL",
      );
      return rows.single.single! as bool;
    }

    Future<void> insertTag(
      String id, {
      String owner = _owner,
      String name = 'Friends',
      String glyph = 'F',
      int color = 0,
      int ord = 1,
    }) => writer.execute(
      Sql.named('''
INSERT INTO public.person_tag (id, owner_id, name, glyph, color, ord)
VALUES (@id, @owner, @name, @glyph, @color, @ord)
'''),
      parameters: {
        'id': id,
        'owner': owner,
        'name': name,
        'glyph': glyph,
        'color': color,
        'ord': ord,
      },
    );

    Future<void> insertMember({
      required String tagId,
      String owner = _owner,
      String person = _person,
      int source = 0,
    }) => writer.execute(
      Sql.named('''
INSERT INTO public.person_tag_member (tag_id, owner_id, person_id, source)
VALUES (@tag, @owner, @person, @source)
'''),
      parameters: {
        'tag': tagId,
        'owner': owner,
        'person': person,
        'source': source,
      },
    );

    Future<int> count(String table, String column, String id) async {
      final rows = await writer.execute(
        "SELECT count(*) FROM public.$table WHERE $column = '$id'",
      );
      return rows.single.single! as int;
    }

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
        lastInclusiveVersion: '0260',
      );
      writer = session.writer;
      for (final id in [_owner, _other, _person, _person2]) {
        await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
''');
      }
      for (final table in _newTables) {
        expect(await tableExists(table), isFalse, reason: '$table pre-exists');
      }
      await migrateDbSchema(writer);
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    test('creates every people-tags table and keeps existing users', () async {
      for (final table in _newTables) {
        expect(await tableExists(table), isTrue, reason: '$table missing');
      }
      expect(await count('user', 'id', _owner), 1);
    });

    group('person tag', () {
      test('accepts a valid row with defaulted timestamps', () async {
        await insertTag('Tvalid000001', name: 'a', glyph: 'a' * 8, color: 7);
        final rows = await writer.execute(
          'SELECT created_at IS NOT NULL, updated_at IS NOT NULL '
          "FROM public.person_tag WHERE id = 'Tvalid000001'",
        );
        expect(rows.single[0], isTrue);
        expect(rows.single[1], isTrue);
      });

      test('name must be 1 to 32 characters', () async {
        await expectLater(
          insertTag('Tname0000001', name: ''),
          _throwsSqlState(_checkViolation),
        );
        await expectLater(
          insertTag('Tname0000002', name: 'x' * 33),
          _throwsSqlState(_checkViolation),
        );
        await insertTag('Tname0000003', name: 'x' * 32);
      });

      test('glyph must be 1 to 8 characters', () async {
        await expectLater(
          insertTag('Tglyph000001', name: 'glyph-empty', glyph: ''),
          _throwsSqlState(_checkViolation),
        );
        await expectLater(
          insertTag('Tglyph000002', name: 'glyph-long', glyph: 'g' * 9),
          _throwsSqlState(_checkViolation),
        );
      });

      test('colour must be between 0 and 7', () async {
        await expectLater(
          insertTag('Tcolor000001', name: 'color-neg', color: -1),
          _throwsSqlState(_checkViolation),
        );
        await expectLater(
          insertTag('Tcolor000002', name: 'color-high', color: 8),
          _throwsSqlState(_checkViolation),
        );
      });

      test(
        'a name differing only in case is taken for the same owner',
        () async {
          await insertTag('Tcase0000001', name: 'Colleagues', ord: 2);
          await expectLater(
            insertTag('Tcase0000002', name: 'cOLLEAGUES', ord: 3),
            _throwsSqlState(_uniqueViolation),
          );
        },
      );

      test('another owner may reuse a name', () async {
        await insertTag('Tshare000001', name: 'Shared');
        await insertTag('Tshare000002', owner: _other, name: 'shared');
      });

      test('an id is unique across owners', () async {
        await expectLater(
          insertTag('Tshare000001', owner: _other, name: 'Another'),
          _throwsSqlState(_uniqueViolation),
        );
      });

      test('rejects an owner that is not a user', () async {
        await expectLater(
          insertTag('Tghost000001', owner: 'Unobodyhere001'),
          _throwsSqlState(_foreignKeyViolation),
        );
      });
    });

    group('person tag member', () {
      setUpAll(() async {
        await insertTag('Tmember00001', name: 'Members');
        await insertTag('Tmember00002', owner: _other, name: 'Members');
      });

      test('source must be between 0 and 4', () async {
        await expectLater(
          insertMember(tagId: 'Tmember00001', source: -1),
          _throwsSqlState(_checkViolation),
        );
        await expectLater(
          insertMember(tagId: 'Tmember00001', source: 5),
          _throwsSqlState(_checkViolation),
        );
        await insertMember(tagId: 'Tmember00001', source: 4);
        final rows = await writer.execute(
          'SELECT added_at IS NOT NULL FROM public.person_tag_member '
          "WHERE tag_id = 'Tmember00001' AND person_id = '$_person'",
        );
        expect(rows.single.single, isTrue);
      });

      test('an owner cannot tag themselves', () async {
        await expectLater(
          insertMember(tagId: 'Tmember00001', person: _owner),
          _throwsSqlState(_checkViolation),
        );
      });

      test('a person sits in a tag once', () async {
        await expectLater(
          insertMember(tagId: 'Tmember00001'),
          _throwsSqlState(_uniqueViolation),
        );
      });

      test(
        'a member row cannot name an owner other than its tag owner',
        () async {
          await expectLater(
            insertMember(tagId: 'Tmember00002', person: _person2),
            _throwsSqlState(_foreignKeyViolation),
          );
          await expectLater(
            insertMember(
              tagId: 'Tmember00001',
              owner: _other,
              person: _person2,
            ),
            _throwsSqlState(_foreignKeyViolation),
          );
        },
      );

      test('rejects a tagged person that is not a user', () async {
        await expectLater(
          insertMember(tagId: 'Tmember00001', person: 'Unobodyhere002'),
          _throwsSqlState(_foreignKeyViolation),
        );
      });
    });

    group('cascades', () {
      test('deleting a tag removes its members only', () async {
        await insertTag('Tcascade0001', name: 'Cascade one', ord: 10);
        await insertTag('Tcascade0002', name: 'Cascade two', ord: 11);
        await insertMember(tagId: 'Tcascade0001');
        await insertMember(tagId: 'Tcascade0002');

        await writer.execute(
          "DELETE FROM public.person_tag WHERE id = 'Tcascade0001'",
        );

        expect(await count('person_tag_member', 'tag_id', 'Tcascade0001'), 0);
        expect(await count('person_tag_member', 'tag_id', 'Tcascade0002'), 1);
      });

      test('deleting a tagged person removes their member rows only', () async {
        const doomed = 'Uptagsdoomed001';
        await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$doomed', 'd', 'pk-$doomed', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
''');
        await insertTag('Tperson00001', name: 'People', ord: 20);
        await insertMember(tagId: 'Tperson00001', person: doomed);
        await insertMember(tagId: 'Tperson00001', person: _person2);

        await writer.execute(
          'DELETE FROM public."user" WHERE id = \'$doomed\'',
        );

        expect(await count('person_tag_member', 'person_id', doomed), 0);
        expect(await count('person_tag_member', 'person_id', _person2), 1);
        expect(await count('person_tag', 'id', 'Tperson00001'), 1);
      });

      test('deleting the owner removes every row they own', () async {
        const doomed = 'Uptagsdoomed002';
        await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$doomed', 'd', 'pk-$doomed', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
''');
        await insertTag('Towner0000001', owner: doomed, name: 'Owned');
        await insertMember(
          tagId: 'Towner0000001',
          owner: doomed,
        );
        await writer.execute('''
INSERT INTO public.person_auto_tag_pref (owner_id, kind, show_in_filters)
VALUES ('$doomed', 1, true)
''');
        await writer.execute('''
INSERT INTO public.person_field_first_seen (viewer_id, peer_id)
VALUES ('$doomed', '$_person')
''');
        await writer.execute('''
INSERT INTO public.person_tag_suggestion_state (owner_id)
VALUES ('$doomed')
''');
        await writer.execute('''
INSERT INTO public.person_tag_op_log (owner_id, client_op_id, fingerprint, result)
VALUES ('$doomed', 'op-1', 'fp', '{}'::jsonb)
''');
        await writer.execute('''
INSERT INTO public.person_tag_revision (owner_id)
VALUES ('$doomed')
''');

        await writer.execute(
          'DELETE FROM public."user" WHERE id = \'$doomed\'',
        );

        expect(await count('person_tag', 'owner_id', doomed), 0);
        expect(await count('person_tag_member', 'owner_id', doomed), 0);
        expect(await count('person_auto_tag_pref', 'owner_id', doomed), 0);
        expect(await count('person_field_first_seen', 'viewer_id', doomed), 0);
        expect(
          await count('person_tag_suggestion_state', 'owner_id', doomed),
          0,
        );
        expect(await count('person_tag_op_log', 'owner_id', doomed), 0);
        expect(await count('person_tag_revision', 'owner_id', doomed), 0);
      });

      test(
        'deleting the peer removes first-seen rows that point at them',
        () async {
          const peer = 'Uptagspeer00001';
          await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$peer', 'p', 'pk-$peer', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
''');
          await writer.execute('''
INSERT INTO public.person_field_first_seen (viewer_id, peer_id)
VALUES ('$_owner', '$peer')
''');

          await writer.execute(
            'DELETE FROM public."user" WHERE id = \'$peer\'',
          );

          expect(await count('person_field_first_seen', 'peer_id', peer), 0);
        },
      );
    });

    group('per-owner state tables', () {
      test('an auto-tag preference is one row per owner and kind', () async {
        Future<void> insertPref(int kind) => writer.execute('''
INSERT INTO public.person_auto_tag_pref (owner_id, kind, show_in_filters)
VALUES ('$_owner', $kind, false)
''');
        await insertPref(2);
        await insertPref(3);
        await expectLater(insertPref(2), _throwsSqlState(_uniqueViolation));
      });

      test('first-seen is one row per viewer and peer', () async {
        Future<void> insertSeen() => writer.execute('''
INSERT INTO public.person_field_first_seen (viewer_id, peer_id)
VALUES ('$_other', '$_person')
''');
        await insertSeen();
        await expectLater(insertSeen(), _throwsSqlState(_uniqueViolation));
      });

      test('suggestion state defaults to not skipped, not disabled', () async {
        await writer.execute('''
INSERT INTO public.person_tag_suggestion_state (owner_id)
VALUES ('$_owner')
''');
        final rows = await writer.execute('''
SELECT consecutive_skips, silenced_until, disabled
FROM public.person_tag_suggestion_state WHERE owner_id = '$_owner'
''');
        expect(rows.single[0], 0);
        expect(rows.single[1], isNull);
        expect(rows.single[2], isFalse);
        await expectLater(
          writer.execute('''
INSERT INTO public.person_tag_suggestion_state (owner_id)
VALUES ('$_owner')
'''),
          _throwsSqlState(_uniqueViolation),
        );
      });

      test('the op log rejects a repeated (owner, client op id)', () async {
        Future<void> insertOp() => writer.execute('''
INSERT INTO public.person_tag_op_log (owner_id, client_op_id, fingerprint, result)
VALUES ('$_owner', 'op-dup', 'fp', '{"ok":true}'::jsonb)
''');
        await insertOp();
        await expectLater(insertOp(), _throwsSqlState(_uniqueViolation));
      });
    });
  });
}
