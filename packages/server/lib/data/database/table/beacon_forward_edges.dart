import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';

import 'beacons.dart';
import 'users.dart';

class BeaconForwardEdges extends Table {
  late final id = text().clientDefault(() => ForwardEdgeEntity.newId)();

  late final beaconId = text().references(Beacons, #id)();

  late final context = text().nullable().withLength(
    min: kTitleMinLength,
    max: kTitleMaxLength,
  )();

  @ReferenceName('forwardSender')
  late final senderId = text().references(Users, #id)();

  @ReferenceName('forwardRecipient')
  late final recipientId = text().references(Users, #id)();

  late final note = text()
      .withLength(max: kDescriptionMaxLength)
      .withDefault(const Constant(''))();

  late final parentEdgeId = text().nullable().references(BeaconForwardEdges, #id)();

  late final batchId = text().nullable()();

  late final createdAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp()))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'beacon_forward_edge';

  @override
  bool get withoutRowId => true;
}
