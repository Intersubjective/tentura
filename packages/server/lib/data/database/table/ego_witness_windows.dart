import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'users.dart';

class EgoWitnessWindows extends Table {
  @ReferenceName('egoWitnessEgo')
  late final egoUserId = text().references(Users, #id)();

  late final context = text()();

  @ReferenceName('egoWitnessWitness')
  late final witnessUserId = text().references(Users, #id)();

  late final m = real()();

  late final admitted = boolean()();

  late final computedAt = customType(
    PgTypes.timestampWithTimezone,
  ).named('computed_at').clientDefault(() => PgDateTime(DateTime.timestamp()))();

  late final mrEpoch = int64().named('mr_epoch')();

  @override
  Set<Column<Object>> get primaryKey => {egoUserId, context, witnessUserId};

  @override
  String get tableName => 'ego_witness_window';

  @override
  bool get withoutRowId => true;
}
