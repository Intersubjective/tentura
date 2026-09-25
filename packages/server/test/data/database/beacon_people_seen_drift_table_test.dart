import 'package:drift_postgres/drift_postgres.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;

/// m0197: the Drift schema must know `beacon_people_seen` (mirrors
/// `beacon_items_seen`). The pool is never opened — only metadata is read.
void main() {
  late TenturaDb db;

  setUp(() {
    db = TenturaDb.forTest(
      database: PgDatabase.opened(
        Pool<dynamic>.withEndpoints([
          Endpoint(host: 'localhost', database: 'unused'),
        ]),
      ),
    );
  });

  tearDown(() => db.close());

  test('beacon_people_seen is registered in TenturaDb', () {
    final names = db.allTables.map((table) => table.actualTableName).toSet();
    expect(names, contains('beacon_items_seen'));
    expect(names, contains('beacon_people_seen'));
  });

  test('beacon_people_seen columns and composite primary key', () {
    final table = db.allTables.singleWhere(
      (table) => table.actualTableName == 'beacon_people_seen',
    );
    expect(
      table.$columns.map((column) => column.name).toSet(),
      {'user_id', 'beacon_id', 'last_seen_at'},
    );
    expect(
      table.$primaryKey.map((column) => column.name).toSet(),
      {'user_id', 'beacon_id'},
    );
  });

  test(
    'beacon_people_seen columns match the BeaconItemsSeen model: non-null, '
    'text ids with cascading references, timestamptz last_seen_at',
    () {
      TableInfo<Table, dynamic> byName(String name) =>
          db.allTables.singleWhere((table) => table.actualTableName == name);
      final people = byName('beacon_people_seen');
      final items = byName('beacon_items_seen');

      String definition(GeneratedColumn<Object> column) {
        final context = GenerationContext.fromDb(db);
        column.writeColumnDefinition(context);
        return context.sql;
      }

      for (final name in ['user_id', 'beacon_id', 'last_seen_at']) {
        final column = people.columnsByName[name]!;
        final model = items.columnsByName[name]!;
        expect(column.$nullable, isFalse, reason: '$name must be NOT NULL');
        expect(column.type, model.type, reason: '$name type');
        expect(
          column.requiredDuringInsert,
          isTrue,
          reason: '$name must be required',
        );
        expect(
          definition(column),
          definition(model),
          reason: '$name column definition must mirror beacon_items_seen',
        );
      }

      expect(
        people.columnsByName['last_seen_at']!.type,
        PgTypes.timestampWithTimezone,
      );
      expect(
        definition(people.columnsByName['user_id']!),
        allOf(contains('REFERENCES'), contains('ON DELETE CASCADE')),
      );
      expect(
        definition(people.columnsByName['beacon_id']!),
        allOf(
          contains('REFERENCES beacon'),
          contains('ON DELETE CASCADE'),
        ),
      );
    },
  );
}
