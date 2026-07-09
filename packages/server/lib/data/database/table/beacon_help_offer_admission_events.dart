import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'users.dart';

/// Append-only admission/decline/remove log for a help offer.
class BeaconHelpOfferAdmissionEvents extends Table {
  late final id = text()();

  /// Database-owned monotonic order. Latest event uses `ORDER BY seq DESC`.
  late final seq = int64().customConstraint('UNIQUE NOT NULL')();

  late final beaconId = text()();

  @ReferenceName('admissionOfferUser')
  late final offerUserId = text().references(Users, #id)();

  @ReferenceName('admissionActorUser')
  late final actorUserId = text().references(Users, #id)();

  /// 0=auto_admit, 1=accept, 2=decline, 3=remove
  late final action = integer()();

  late final reason = text().nullable()();

  late final createdAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp()))();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {beaconId, offerUserId, seq},
  ];

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'beacon_help_offer_admission_event';
}
