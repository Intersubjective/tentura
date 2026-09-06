@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../support/beacon_hierarchy_fixture.dart';

Future<void> main() async {
  final reachable = await canConnectBeaconHierarchyPostgres();
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for beacon hierarchy fixture';

  group('BeaconHierarchyFixture — disposable Postgres', () {
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

    test(
      'disposable target uses an isolated tentura_test_* database name',
      () {
        expect(target.databaseName, startsWith('tentura_test_'));
        expect(target.databaseName, isNot('postgres'));
      },
      skip: skipReason,
    );

    test(
      'current_database matches allocated disposable name after migrate',
      () async {
        final row = await writer.execute('SELECT current_database()');
        expect(row.first.first, target.databaseName);
      },
      skip: skipReason,
    );

    test(
      'seedFullTopology inserts A/B/C/D users, beacons, admissions, offers, items',
      () async {
        await fixture.seedFullTopology();

        final beacons = await writer.execute(
          Sql.named(
            'SELECT id FROM public.beacon WHERE id = ANY(@ids) ORDER BY id',
          ),
          parameters: {'ids': BeaconHierarchyTopology.allBeaconIds},
        );
        expect(beacons, hasLength(5));

        final admissions = await writer.execute(
          Sql.named(r'''
SELECT beacon_id, user_id
FROM public.beacon_participant
WHERE beacon_id = ANY(@ids) AND room_access = 3
ORDER BY beacon_id, user_id
'''),
          parameters: {
            'ids': [
              BeaconHierarchyTopology.beaconA,
              BeaconHierarchyTopology.beaconB,
              BeaconHierarchyTopology.beaconC,
            ],
          },
        );
        expect(admissions, hasLength(3));

        final forward = await writer.execute(
          Sql.named(r'''
SELECT 1 FROM public.beacon_forward_edge
WHERE beacon_id = @beaconId AND recipient_id = @recipientId
'''),
          parameters: {
            'beaconId': BeaconHierarchyTopology.beaconB,
            'recipientId': BeaconHierarchyTopology.aliceId,
          },
        );
        expect(forward, hasLength(1));

        final items = await writer.execute(
          Sql.named(r'''
SELECT kind FROM public.coordination_item
WHERE beacon_id = @beaconId ORDER BY kind
'''),
          parameters: {'beaconId': BeaconHierarchyTopology.beaconA},
        );
        expect(items.map((r) => r.first), [1, 2]);
      },
      skip: skipReason,
    );

    test(
      'pg_constraint inventory: every public.user(id) FK has assigned disposition',
      () async {
        final rows = await writer.execute(r'''
SELECT
  c.conrelid::regclass::text AS table_name,
  a.attname AS column_name,
  CASE c.confdeltype
    WHEN 'a' THEN 'NO ACTION'
    WHEN 'r' THEN 'RESTRICT'
    WHEN 'c' THEN 'CASCADE'
    WHEN 'n' THEN 'SET NULL'
    WHEN 'd' THEN 'SET DEFAULT'
  END AS on_delete
FROM pg_constraint c
JOIN pg_class ref ON ref.oid = c.confrelid
JOIN pg_namespace nref ON nref.oid = ref.relnamespace
JOIN pg_attribute a
  ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
WHERE c.contype = 'f'
  AND nref.nspname = 'public'
  AND ref.relname = 'user'
ORDER BY 1, 2
''');
        expect(rows.length, greaterThanOrEqualTo(50));
        for (final row in rows) {
          final table = row[0] as String;
          final column = row[1] as String;
          final onDelete = row[2] as String;
          expect(table, isNotEmpty);
          expect(column, isNotEmpty);
          expect(
            onDelete,
            isIn(['NO ACTION', 'RESTRICT', 'CASCADE', 'SET NULL', 'SET DEFAULT']),
          );
        }
      },
      skip: skipReason,
    );
  });
}
