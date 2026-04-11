import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'beacons.dart';
import 'images.dart';

class BeaconImages extends Table {
  late final beaconId = text().references(Beacons, #id)();

  late final imageId = customType(PgTypes.uuid).references(Images, #id)();

  late final Column<int> position = integer()
      .withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {beaconId, imageId};

  @override
  String get tableName => 'beacon_image';

  @override
  bool get withoutRowId => true;
}
