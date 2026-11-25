import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'users.dart';

class PhantomMergeJobs extends Table {
  late final id = text()();

  /// Queueing must avoid taking a lock on the phantom row.
  late final phantomId = text()();

  @ReferenceName('ownedPhantomMergeJobs')
  late final ownerId = text().references(
    Users,
    #id,
    onDelete: KeyAction.cascade,
  )();

  @ReferenceName('joinedPhantomMergeJobs')
  late final userId = text().references(
    Users,
    #id,
    onDelete: KeyAction.cascade,
  )();

  late final origin = integer()();
  late final invitationId = text().unique()();
  late final state = text().withDefault(const Constant('queued'))();
  late final reason = text().nullable()();
  late final attempts = integer().withDefault(const Constant(0))();
  late final leaseOwner = text().nullable()();
  late final leaseUntil = customType(
    PgTypes.timestampWithTimezone,
  ).nullable()();
  late final nextAttemptAt = customType(
    PgTypes.timestampWithTimezone,
  ).withDefault(const CustomExpression('now()'))();
  late final lastError = text().nullable()();
  late final createdAt = customType(
    PgTypes.timestampWithTimezone,
  ).withDefault(const CustomExpression('now()'))();
  late final doneAt = customType(PgTypes.timestampWithTimezone).nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'phantom_merge_job';
}
