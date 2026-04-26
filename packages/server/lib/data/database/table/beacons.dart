import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';

import '../common_fields.dart';
import 'pollings.dart';
import 'users.dart';

class Beacons extends Table
    with TitleDescriptionFields, TimestampsFields, TickerFields {
  late final id = text().clientDefault(() => BeaconEntity.newId)();

  @ReferenceName('author')
  late final userId = text().references(Users, #id)();

  late final context = text().nullable().withLength(
    min: kTitleMinLength,
    max: kTitleMaxLength,
  )();

  late final lat = real().nullable()();

  late final long = real().nullable()();

  late final startAt = customType(PgTypes.timestampWithTimezone).nullable()();

  late final endAt = customType(PgTypes.timestampWithTimezone).nullable()();

  late final pollingId = text().nullable().references(Pollings, #id)();

  late final tags = text().withDefault(const Constant(''))();

  // 0=OPEN, 1=CLOSED, 2=DELETED, 3=DRAFT, 4=PENDING_REVIEW, 5=CLOSED_REVIEW_OPEN, 6=CLOSED_REVIEW_COMPLETE
  late final Column<int> state = integer()
      .withDefault(const Constant(0))();

  /// 0=no commitments, 1=waiting for review, 2=more help needed, 3=enough help
  late final Column<int> coordinationStatus = integer()
      .withDefault(const Constant(0))();

  late final coordinationStatusUpdatedAt = customType(
    PgTypes.timestampWithTimezone,
  ).nullable()();

  /// Curated symbolic icon key (client catalog); null = default tile.
  late final iconCode = text().nullable()();

  /// ARGB background for identity tile from constrained palette; null with iconCode.
  late final iconBackground = integer().nullable()();

  /// Short canonical statement of what must be solved (nullable for legacy rows).
  late final needSummary = text().nullable()();

  /// Optional "done when" criteria (nullable).
  late final successCriteria = text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'beacon';

  @override
  bool get withoutRowId => true;
}
