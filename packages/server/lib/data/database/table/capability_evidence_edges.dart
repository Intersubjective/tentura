import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'users.dart';

class CapabilityEvidenceEdges extends Table {
  @ReferenceName('capabilityEvidenceObserver')
  late final observerUserId = text().references(Users, #id)();

  @ReferenceName('capabilityEvidenceSubject')
  late final subjectUserId = text().references(Users, #id)();

  late final tagSlug = text()();

  late final sOut = real().named('s_out').withDefault(const Constant(0))();

  late final sSeed = real().named('s_seed').withDefault(const Constant(0))();

  late final anchorAt = customType(
    PgTypes.timestampWithTimezone,
  ).named('anchor_at').clientDefault(() => PgDateTime(DateTime.timestamp()))();

  late final builtFromGen = int64()
      .named('built_from_gen')
      .withDefault(Constant(BigInt.zero))();

  late final nextExpiryAt = customType(
    PgTypes.timestampWithTimezone,
  ).named('next_expiry_at').nullable()();

  late final updatedAt = customType(
    PgTypes.timestampWithTimezone,
  ).named('updated_at').clientDefault(() => PgDateTime(DateTime.timestamp()))();

  @override
  Set<Column<Object>> get primaryKey =>
      {observerUserId, subjectUserId, tagSlug};

  @override
  String get tableName => 'capability_evidence_edge';

  @override
  bool get withoutRowId => true;
}
