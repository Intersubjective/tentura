@Tags(['pg'])
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/owner_graph_unit_of_work.dart';
import 'package:tentura_server/domain/port/owner_graph_transaction_port.dart';

import '../../support/disposable_pg_target.dart';

const _ownerA = 'Uscopeowner01';
const _ownerB = 'Uscopeowner02';
const _ownerC = 'Uscopeowner03';
const _deletedOwner = 'Uscopeowner04';
const _previousVersion = '0331';
const _scopeMigrationVersion = '0332';

const _privateGraphTables = {
  'constellation_anchor',
  'constellation_anchor_cursor',
  'constellation_anchor_op_log',
  'constellation_anchor_target_watermark',
  'constellation_layout_snapshot',
  'person_tag',
  'person_tag_member',
  'person_tag_op_log',
  'person_tag_revision',
  'person_tag_suggestion_state',
  'person_auto_tag_pref',
  'constellation_tag_magnet',
  'person_field_first_seen',
  'person_note',
  'phantom',
  'phantom_merge',
  'phantom_tag_member',
};

const _enableEnforcement = "SET LOCAL tentura.owner_scope_enforce = 'on'";
const _disableEnforcement = "SET LOCAL tentura.owner_scope_enforce = 'off'";
const _insertTag = r'''
INSERT INTO public.person_tag (id, owner_id, name, glyph, color, ord)
VALUES ($1, $2, $1, 'T', 0, 1)
''';
const _renameTag = r'UPDATE public.person_tag SET name = $2 WHERE id = $1';
const _insertAnchor = r'''
INSERT INTO public.constellation_anchor
  (id, viewer_id, person_id, x_units, y_units,
   coordinate_space_version, revision, placed_at)
VALUES ($1, $2, $3, 1, 1, 1, 0, now())
''';
const _insertFirstSeen = r'''
INSERT INTO public.person_field_first_seen (viewer_id, peer_id)
VALUES ($1, $2)
''';

Future<Result> _execute(Session session, String sql, List<String> parameters) =>
    session.execute(
      Sql(sql, types: List.filled(parameters.length, Type.text)),
      parameters: parameters,
    );

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PRIVATE_GRAPH_OWNER_SCOPE_TEST_DB',
    defaultNamePrefix: 'tentura_test_private_graph_scope',
  );
  final skipReason = await pgSkipReason(target);

  group('Private graph owner scopes', () {
    late Connection writer;
    late TenturaDb db;
    late OwnerGraphTransactionPort graph;

    Future<Result> underEnforcement(
      String sql,
      List<String> parameters,
    ) => writer.runTx((tx) async {
      await tx.execute(_enableEnforcement);
      return _execute(tx, sql, parameters);
    });

    Future<Object?> tagOwner(String tagId) async => (await _execute(
      writer,
      r'SELECT owner_id FROM public.person_tag WHERE id = $1',
      [tagId],
    )).single.single;

    setUpAll(() async {
      // Request a fresh schema build through the registry head.
      final session = await setUpDisposablePgWriter(
        target: target,
        lastInclusiveVersion: migrationsForTesting.last.version,
      );
      writer = session.writer;
      db = openDisposablePgDatabase(target);
      graph = OwnerGraphUnitOfWork(db);
      addTearDown(
        () => tearDownDisposablePgWriter(session: session, drift: db),
      );

      for (final id in [_ownerA, _ownerB, _ownerC, _deletedOwner]) {
        await _execute(
          writer,
          r'''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ($1, $1, $2)
''',
          [id, 'pk-$id'],
        );
      }
      const viewers = [_ownerA, _ownerC, _deletedOwner];
      await withPgOwnerScopes(writer, viewers, (tx) async {
        for (final viewer in viewers) {
          await _execute(
            tx,
            r'''
INSERT INTO public.constellation_anchor_cursor (viewer_id) VALUES ($1)
''',
            [viewer],
          );
        }
      });
    });

    test('rejects unscoped tag inserts only when enforcement is on', () async {
      final fresh = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      addTearDown(fresh.close);
      await expectLater(
        _execute(fresh, _insertTag, ['default-enforcement', _ownerA]),
        throwsA(
          isA<ServerException>().having(
            (error) => error.message,
            'message',
            contains('Owner scope required for INSERT on public.person_tag'),
          ),
        ),
      );

      await fresh.runTx((tx) async {
        await tx.execute(_disableEnforcement);
        await _execute(
          tx,
          _insertTag,
          ['disabled-enforcement', _ownerA],
        );
      });
      expect(await tagOwner('disabled-enforcement'), _ownerA);

      await expectLater(
        underEnforcement(_insertTag, ['enabled-enforcement', _ownerA]),
        throwsA(isA<ServerException>()),
      );
    });

    test('allows tag inserts only for owners in a JSON scope', () async {
      Future<Result> insertWithScope(String tagId, String owner) =>
          writer.runTx((tx) async {
            await tx.execute(_enableEnforcement);
            await _execute(
              tx,
              r"SELECT set_config('tentura.owner_scopes', $1, true)",
              [
                jsonEncode([_ownerB]),
              ],
            );
            return _execute(
              tx,
              _insertTag,
              [tagId, owner],
            );
          });

      await insertWithScope('json-scope-member', _ownerB);
      expect(await tagOwner('json-scope-member'), _ownerB);
      await expectLater(
        insertWithScope('json-scope-outsider', _ownerA),
        throwsA(isA<ServerException>()),
      );
    });

    test('requires scope for tag updates and permits direct deletes', () async {
      await writer.runTx((tx) async {
        await tx.execute(_disableEnforcement);
        for (final id in ['renamable-tag', 'deletable-tag']) {
          await _execute(tx, _insertTag, [id, _ownerA]);
        }
      });

      await graph.run({_ownerA}, _ownerA, (_) async {
        await db.customStatement(_enableEnforcement);
        await db.customStatement(_renameTag, ['renamable-tag', 'Scoped name']);
      });
      final renamed = await writer.execute(
        "SELECT name FROM public.person_tag WHERE id = 'renamable-tag'",
      );
      expect(renamed.single.single, 'Scoped name');

      final deleted = await underEnforcement(
        r'DELETE FROM public.person_tag WHERE id = $1 RETURNING owner_id',
        ['deletable-tag'],
      );
      expect(deleted.single.single, _ownerA);
      final remaining = await writer.execute(
        "SELECT id FROM public.person_tag WHERE id = 'deletable-tag'",
      );
      expect(remaining, isEmpty);

      await expectLater(
        underEnforcement(_renameTag, ['renamable-tag', 'Unscoped name']),
        throwsA(isA<ServerException>()),
      );
    });

    test('requires the anchor viewer in a repeatable-read scope', () async {
      await graph.runRepeatableRead(_ownerA, _ownerA, (_) async {
        await db.customStatement(_enableEnforcement);
        await db.customStatement(
          _insertAnchor,
          ['scoped-anchor', _ownerA, _ownerB],
        );
      });
      final anchor = await writer.execute('''
SELECT viewer_id, person_id FROM public.constellation_anchor
WHERE id = 'scoped-anchor'
''');
      expect(anchor.single.toList(), [_ownerA, _ownerB]);

      await expectLater(
        underEnforcement(_insertAnchor, ['unscoped-anchor', _ownerA, _ownerC]),
        throwsA(isA<ServerException>()),
      );
    });

    test('requires the first-seen viewer in a mutation scope', () async {
      await graph.run({_ownerA}, _ownerA, (_) async {
        await db.customStatement(_enableEnforcement);
        await db.customStatement(_insertFirstSeen, [_ownerA, _ownerB]);
      });
      final seen = await _execute(
        writer,
        r'''
SELECT peer_id FROM public.person_field_first_seen
WHERE viewer_id = $1 AND peer_id = $2
''',
        [_ownerA, _ownerB],
      );
      expect(seen.single.single, _ownerB);

      await expectLater(
        underEnforcement(_insertFirstSeen, [_ownerA, _ownerC]),
        throwsA(isA<ServerException>()),
      );
    });

    test('limits tag inserts to both owners in a shared scope', () async {
      final rejection = await graph.run({_ownerA, _ownerB}, _ownerA, (_) async {
        await db.customStatement(_enableEnforcement);
        await db.customStatement(_insertTag, ['shared-scope-a', _ownerA]);
        await db.customStatement(_insertTag, ['shared-scope-b', _ownerB]);

        // A savepoint lets the first two inserts commit after a rejected one.
        try {
          await db.transaction(
            () => db.customStatement(
              _insertTag,
              ['shared-scope-c', _ownerC],
            ),
          );
          return null;
        } on ServerException catch (error) {
          return error;
        }
      });
      expect(await tagOwner('shared-scope-a'), _ownerA);
      expect(await tagOwner('shared-scope-b'), _ownerB);
      expect(rejection, isA<ServerException>());
    });

    test(
      'unscoped account deletion cascades through the private graph',
      () async {
        await writer.runTx((tx) async {
          await tx.execute(_disableEnforcement);
          await _execute(
            tx,
            _insertTag,
            ['owner-to-delete', _deletedOwner],
          );
          await _execute(
            tx,
            r'''
INSERT INTO public.person_tag_member (tag_id, owner_id, person_id, source)
VALUES ('owner-to-delete', $1, $2, 0)
''',
            [_deletedOwner, _ownerB],
          );
          await _execute(
            tx,
            _insertAnchor,
            ['anchor-to-delete', _deletedOwner, _ownerB],
          );
          await _execute(
            tx,
            _insertAnchor,
            ['anchor-to-tombstone', _ownerC, _deletedOwner],
          );
          await _execute(
            tx,
            _insertFirstSeen,
            [_deletedOwner, _ownerB],
          );
        });

        Future<List<Object?>> ownedRowCounts() async => (await _execute(
          writer,
          r'''
SELECT
  (SELECT count(*) FROM public.person_tag WHERE owner_id = $1),
  (SELECT count(*) FROM public.person_tag_member WHERE owner_id = $1),
  (SELECT count(*) FROM public.constellation_anchor WHERE viewer_id = $1),
  (SELECT count(*) FROM public.person_field_first_seen WHERE viewer_id = $1)
''',
          [_deletedOwner],
        )).single.toList();

        expect(await ownedRowCounts(), [1, 1, 1, 1]);
        final deleted = await underEnforcement(
          r'DELETE FROM public."user" WHERE id = $1 RETURNING id',
          [_deletedOwner],
        );
        expect(deleted.single.single, _deletedOwner);
        expect(await ownedRowCounts(), [0, 0, 0, 0]);

        final survivor = await writer.execute('''
SELECT viewer_id, person_id, tombstone_at FROM public.constellation_anchor
WHERE id = 'anchor-to-tombstone'
''');
        expect(survivor.single.toList(), [_ownerC, isNull, isNotNull]);
        await expectLater(
          underEnforcement(
            r'UPDATE public.constellation_anchor SET x_units = 2 WHERE id = $1',
            ['anchor-to-tombstone'],
          ),
          throwsA(isA<ServerException>()),
          reason: 'The same unscoped viewer is protected on a direct update.',
        );
      },
    );

    test('every private graph table guards row inserts and updates', () async {
      // pg_trigger.tgtype uses 1 for ROW, 2 for BEFORE, 4 for INSERT and
      // 16 for UPDATE. Accept either timing, with no other trigger events.
      final triggers = await writer.execute('''
SELECT c.relname::text, t.tgtype::int, t.tgenabled IN ('O', 'A')
FROM pg_trigger AS t
JOIN pg_class AS c ON c.oid = t.tgrelid
JOIN pg_namespace AS n ON n.oid = c.relnamespace
JOIN pg_proc AS p ON p.oid = t.tgfoid
WHERE n.nspname = 'public' AND p.proname = 'assert_owner_scope'
  AND NOT t.tgisinternal
''');
      expect(
        triggers.map((row) => row[0]),
        unorderedEquals(_privateGraphTables),
      );
      for (final row in triggers) {
        expect(row[1], isIn([21, 23]), reason: row[0]! as String);
        expect(row[2], isTrue, reason: row[0]! as String);
      }
    });

    test(
      'a fresh database applies the next registered scope migration',
      () async {
        final applied = await _execute(
          writer,
          r'''
SELECT version FROM public.schema_version WHERE version = $1
''',
          [_scopeMigrationVersion],
        );
        expect(applied.map((row) => row.single), [_scopeMigrationVersion]);

        final versions = migrationsForTesting.map((m) => m.version).toList();
        expect(
          versions.where((version) => version == _scopeMigrationVersion),
          hasLength(1),
        );
        expect(
          versions.indexOf(_scopeMigrationVersion),
          versions.indexOf(_previousVersion) + 1,
        );
      },
    );
  }, skip: skipReason);
}
