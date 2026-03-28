import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/consts.dart';

import '../common_fields.dart';
import 'beacons.dart';
import 'users.dart';

class BeaconCommitments extends Table with TimestampsFields {
  late final beaconId = text().references(Beacons, #id)();

  @ReferenceName('commitUser')
  late final userId = text().references(Users, #id)();

  late final message = text()
      .withLength(max: kDescriptionMaxLength)
      .withDefault(const Constant(''))();

  // 0=active, 1=withdrawn
  late final Column<int> status = integer()
      .withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {beaconId, userId};

  @override
  String get tableName => 'beacon_commitment';

  @override
  bool get withoutRowId => true;
}
