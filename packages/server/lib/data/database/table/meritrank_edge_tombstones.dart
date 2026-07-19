import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

class MeritrankEdgeTombstones extends Table {
  late final subject = text()();

  late final object = text()();

  late final createdAt = customType(
    PgTypes.timestampWithTimezone,
  ).named('created_at').clientDefault(() => PgDateTime(DateTime.timestamp()))();

  late final lastError = text().named('last_error').nullable()();

  @override
  Set<Column<Object>> get primaryKey => {subject, object};

  @override
  String get tableName => 'meritrank_edge_tombstone';

  @override
  bool get withoutRowId => true;
}
