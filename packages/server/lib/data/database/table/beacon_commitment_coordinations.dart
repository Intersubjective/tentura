import 'package:drift/drift.dart';

import '../common_fields.dart';
import 'beacons.dart';
import 'users.dart';

/// Author's coordination response for one active commitment row.
class BeaconCommitmentCoordinations extends Table with TimestampsFields {
  @ReferenceName('coordinationCommitBeacon')
  late final commitBeaconId = text().references(Beacons, #id)();

  @ReferenceName('coordinationCommitUser')
  late final commitUserId = text().references(Users, #id)();

  @ReferenceName('coordinationAuthor')
  late final authorUserId = text().references(Users, #id)();

  /// 0=useful, 1=overlapping, 2=need_different_skill, 3=need_coordination, 4=not_suitable
  late final Column<int> responseType = integer()();

  @override
  Set<Column<Object>> get primaryKey => {commitBeaconId, commitUserId};

  @override
  String get tableName => 'beacon_commitment_coordination';

  @override
  bool get withoutRowId => true;
}
