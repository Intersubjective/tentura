import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'beacons.dart';
import 'images.dart';

/// Invisible staged uploads awaiting [beaconSetMedia] publication.
class BeaconImageStages extends Table {
  late final imageId = customType(PgTypes.uuid).references(
    Images,
    #id,
    onDelete: KeyAction.cascade,
  )();

  late final beaconId = text().references(
    Beacons,
    #id,
    onDelete: KeyAction.cascade,
  )();

  late final stagedAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp()))();

  @override
  Set<Column<Object>> get primaryKey => {imageId};

  @override
  String get tableName => 'beacon_image_stage';

  @override
  bool get withoutRowId => true;
}
