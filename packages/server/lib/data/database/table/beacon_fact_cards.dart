import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/domain/entity/beacon_fact_card_entity.dart';

import '../common_fields.dart';
import 'beacons.dart';
import 'users.dart';

/// Backed by `public.beacon_fact_card` (see `m0039`).
class BeaconFactCards extends Table with TimestampsFields {
  late final id = text().clientDefault(() => BeaconFactCardEntity.newId)();

  late final beaconId = text().references(Beacons, #id)();

  late final factText = text()();

  /// [BeaconFactCardVisibilityBits]
  late final Column<int> visibility = integer()();

  @ReferenceName('pinnedByUser')
  late final pinnedBy = text().references(Users, #id)();

  /// Optional originating room message.
  late final sourceMessageId = text().nullable()();

  /// [BeaconFactCardStatusBits]
  late final Column<int> status = integer().withDefault(const Constant(0))();

  /// Head revision `seq` in `beacon_fact_card_revision` (see `m0199`).
  late final revisionSeq = integer().withDefault(const Constant(1))();

  @ReferenceName('lastEditedByUser')
  late final lastEditedBy = text().nullable().references(Users, #id)();

  late final lastEditedAt = customType(
    PgTypes.timestampWithTimezone,
  ).nullable()();

  /// Distinct editors other than [pinnedBy].
  late final otherEditorCount = integer().withDefault(const Constant(0))();

  /// True when earlier text versions were not recorded (pre-`m0199` edits).
  late final historyTruncated = boolean().withDefault(
    const Constant(false),
  )();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'beacon_fact_card';

  @override
  bool get withoutRowId => true;
}
