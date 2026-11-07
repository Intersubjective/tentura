import 'package:drift/drift.dart' show QueryRow;
import 'package:drift_postgres/drift_postgres.dart' show PgDateTime;

/// Reads a timestamp column from a raw `customSelect` row: a [DateTime], a
/// [PgDateTime] or its string form. Null when the column is null. The value
/// keeps the time zone it was read with; call `toUtc()` where UTC is needed.
DateTime? readRowTimestamp(QueryRow row, String column) {
  final value = row.data[column];
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value;
  }
  if (value is PgDateTime) {
    return value.dateTime;
  }
  return DateTime.parse(value.toString());
}
