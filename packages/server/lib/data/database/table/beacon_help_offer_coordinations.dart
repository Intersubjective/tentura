import 'package:drift/drift.dart';

import '../common_fields.dart';
import 'beacons.dart';
import 'users.dart';

/// Author's coordination response for one active help offer row.
class BeaconHelpOfferCoordinations extends Table with TimestampsFields {
  @ReferenceName('coordinationOfferBeacon')
  late final offerBeaconId = text().references(Beacons, #id)();

  @ReferenceName('coordinationOfferUser')
  late final offerUserId = text().references(Users, #id)();

  @ReferenceName('coordinationAuthor')
  late final authorUserId = text().references(Users, #id)();

  /// 0=useful, 1=overlapping, 2=need_different_skill, 3=need_coordination, 4=not_suitable
  late final Column<int> responseType = integer()();

  @override
  Set<Column<Object>> get primaryKey => {offerBeaconId, offerUserId};

  @override
  String get tableName => 'beacon_help_offer_coordination';

  @override
  bool get withoutRowId => true;
}
