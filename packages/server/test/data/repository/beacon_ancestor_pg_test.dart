@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;

import '../../support/beacon_hierarchy_fixture.dart';
import 'beacon_hierarchy_pg_helpers.dart';

typedef _Row = (String, String, int);

const _a = BeaconHierarchyTopology.beaconA;
const _b = BeaconHierarchyTopology.beaconB;
const _c = BeaconHierarchyTopology.beaconC;
const _d = BeaconHierarchyTopology.beaconD;
const _e = 'BhierE000001';

Future<Set<_Row>> _ancestorRows(Connection writer) async {
  final result = await writer.execute(
    "SELECT beacon_id, ancestor_id, depth FROM public.beacon_ancestor "
    "WHERE beacon_id LIKE 'Bhier%'",
  );
  return {
    for (final r in result) (r[0]! as String, r[1]! as String, r[2]! as int),
  };
}

const _treeRows = <_Row>{(_b, _a, 1), (_c, _b, 1), (_c, _a, 2), (_d, _a, 1)};

Future<void> main() async {
  final reachable = await canConnectBeaconHierarchyPostgres();
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for beacon_ancestor PG test';

  group('beacon_ancestor closure — disposable Postgres', () {
    late BeaconHierarchyDisposablePgTarget target;
    late Connection writer;
    late BeaconHierarchyFixture fixture;

    setUpAll(() async {
      if (skipReason != false) {
        return;
      }
      target = BeaconHierarchyDisposablePgTarget.fromEnvironment();
      await target.recreate();
      final session = await openBeaconHierarchyPgSession(target);
      writer = session.writer;
      fixture = BeaconHierarchyFixture(writer: writer, db: session.db);
    });

    setUp(() async {
      if (skipReason != false) {
        return;
      }
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);
    });

    tearDown(() async {
      if (skipReason != false) {
        return;
      }
      await fixture.tearDown();
    });

    tearDownAll(() async {
      if (skipReason != false) {
        return;
      }
      await fixture.db.close();
      await writer.close();
      await target.drop();
    });

    test('insert trigger builds exact closure for A→B→C, A→D', () async {
      expect(await _ancestorRows(writer), _treeRows);
    }, skip: skipReason);

    test('new child under C gains the whole ancestor chain', () async {
      await insertPublishedChildBeacon(
        writer: writer,
        childId: _e,
        parentId: _c,
        ownerId: BeaconHierarchyTopology.frankId,
        title: 'Request E',
      );
      expect(await _ancestorRows(writer), {
        ..._treeRows,
        (_e, _c, 1),
        (_e, _b, 2),
        (_e, _a, 3),
      });
    }, skip: skipReason);

    test('hard-deleting a draft child cascades its closure rows', () async {
      const draftId = 'BhierDraftA1';
      await writer.execute(
        Sql.named(r'''
INSERT INTO public.beacon (
  id, user_id, title, description, status, parent_beacon_id,
  created_at, updated_at
) VALUES (
  @id, @ownerId, 'Draft child of A', '', 3, @parentId,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
'''),
        parameters: {
          'id': draftId,
          'ownerId': BeaconHierarchyTopology.bobId,
          'parentId': _a,
        },
      );
      expect(await _ancestorRows(writer), {..._treeRows, (draftId, _a, 1)});

      await writer.execute(
        Sql.named('DELETE FROM public.beacon WHERE id = @id'),
        parameters: {'id': draftId},
      );
      expect(await _ancestorRows(writer), _treeRows);
    }, skip: skipReason);
  });

  test('m0171 backfills closure for a tree that predates it', () async {
    final target = BeaconHierarchyDisposablePgTarget.fromEnvironment(
      databaseNameOverride:
          'tentura_test_bhier_anc_${DateTime.timestamp().microsecondsSinceEpoch}',
    );
    await target.recreate();
    final writer = await Connection.open(
      target.databaseEnv.pgEndpoint,
      settings: target.databaseEnv.pgEndpointSettings,
    );
    final db = TenturaDb(target.databaseEnv);
    try {
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchemaThrough(writer, '0170');
      final fixture = BeaconHierarchyFixture(writer: writer, db: db);
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);

      await migrateDbSchema(writer);
      expect(await _ancestorRows(writer), _treeRows);
    } finally {
      await db.close();
      await writer.close();
      await target.drop();
    }
  }, skip: skipReason);
}
