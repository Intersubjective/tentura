import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'users.dart';

/// Append-only participation facts for a help offer.
class BeaconCommitmentEvents extends Table {
  late final id = text()();

  late final seq = int64().customConstraint('UNIQUE NOT NULL')();

  late final beaconId = text()();

  @ReferenceName('commitmentUser')
  late final userId = text().references(Users, #id)();

  @ReferenceName('commitmentActorUser')
  late final actorUserId = text().references(Users, #id)();

  /// 0=offered … 8=unanswered_at_close (см. docs/plans/commitment-truth-rework-plan.md §2.1)
  late final kind = integer()();

  late final reason = text().nullable()();

  late final createdAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp()))();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {beaconId, userId, seq},
  ];

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'beacon_commitment_event';
}
