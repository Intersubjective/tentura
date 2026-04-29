import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/consts/beacon_blocker_consts.dart';
import 'package:tentura_server/domain/entity/beacon_blocker_entity.dart';

import 'beacon_participants.dart';
import 'beacons.dart';
import 'users.dart';

/// Backed by `public.beacon_blocker` (see `m0040`).
class BeaconBlockers extends Table {
  late final id =
      text().clientDefault(() => BeaconBlockerEntity.newId)();

  late final beaconId = text().references(Beacons, #id)();

  late final title = text()();

  /// [BeaconBlockerStatusBits]
  late final Column<int> status =
      integer().withDefault(const Constant(0))();

  /// 0 public, 1 room (matches fact_card visibility semantics).
  late final Column<int> visibility =
      integer().withDefault(const Constant(1))();

  @ReferenceName('blockerOpenedBy')
  late final openedBy = text().references(Users, #id)();

  late final openedFromMessageId = text().nullable()();

  late final affectedParticipantId =
      text().nullable().references(BeaconParticipants, #id)();

  late final resolverParticipantId =
      text().nullable().references(BeaconParticipants, #id)();

  late final resolvedBy = text().nullable().references(Users, #id)();

  late final resolvedFromMessageId = text().nullable()();

  late final createdAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp()))();

  late final resolvedAt =
      customType(PgTypes.timestampWithTimezone).nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'beacon_blocker';

  @override
  bool get withoutRowId => true;
}
