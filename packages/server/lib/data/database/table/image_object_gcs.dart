import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

/// Durable outbox for remote object deletion after image-row commit.
///
/// No FK to [Images]: the image row is deleted in the same transaction that
/// enqueues this row.
class ImageObjectGcs extends Table {
  late final imageId = customType(PgTypes.uuid)();

  late final authorId = text()();

  late final enqueuedAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp()))();

  late final nextAttemptAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp()))();

  late final Column<int> attempts = integer().withDefault(const Constant(0))();

  late final lastError = text().nullable()();

  late final leaseOwner = text().nullable()();

  late final leaseUntil = customType(PgTypes.timestampWithTimezone).nullable()();

  @override
  Set<Column<Object>> get primaryKey => {imageId};

  @override
  String get tableName => 'image_object_gc';

  @override
  bool get withoutRowId => true;
}
