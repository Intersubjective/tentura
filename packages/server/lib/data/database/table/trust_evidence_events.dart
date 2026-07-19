import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

class TrustEvidenceEvents extends Table {
  late final id = text()();

  late final trustContext = text().named('trust_context')();

  late final subjectUserId = text().named('subject_user_id')();

  late final objectUserId = text().named('object_user_id')();

  late final bin = text()();

  late final count = real()();

  late final sourceType = text().named('source_type')();

  late final sourceId = text().named('source_id').nullable()();

  late final requestId = text().named('request_id').nullable()();

  late final occurredAt = customType(
    PgTypes.timestampWithTimezone,
  ).named('occurred_at')();

  late final appliedAt = customType(
    PgTypes.timestampWithTimezone,
  ).named('applied_at').clientDefault(() => PgDateTime(DateTime.timestamp()))();

  late final metadata = customType(PgTypes.jsonb)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'trust_evidence_event';

  @override
  bool get withoutRowId => true;
}
