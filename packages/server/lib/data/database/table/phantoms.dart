import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/utils/id.dart';

import '../common_fields.dart';
import 'phantom_merges.dart';
import 'users.dart';

class Phantoms extends Table with TimestampsFields {
  late final id = text().clientDefault(() => generateId('PH'))();

  @ReferenceName('ownedPhantoms')
  late final ownerId = text().references(
    Users,
    #id,
    onDelete: KeyAction.cascade,
  )();

  late final displayName = text()();
  late final emoji = text().nullable()();

  @ReferenceName('mergedPhantoms')
  late final mergedUserId = text().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();

  late final mergedAt = customType(PgTypes.timestampWithTimezone).nullable()();
  late final mergeOrigin = integer().nullable()();

  @ReferenceName('currentPhantoms')
  late final currentMergeId = text().nullable().references(
    PhantomMerges,
    #id,
    onDelete: KeyAction.setNull,
  )();

  late final revision = int64().withDefault(Constant(BigInt.zero))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'phantom';
}
