import 'package:drift/drift.dart';

import 'package:tentura_server/consts.dart';

import '../common_fields.dart';
import 'beacons.dart';
import 'users.dart';

class BeaconHelpOffers extends Table with TimestampsFields {
  late final beaconId = text().references(Beacons, #id)();

  @ReferenceName('helpOfferUser')
  late final userId = text().references(Users, #id)();

  late final message = text()
      .withLength(max: kDescriptionMaxLength)
      .withDefault(const Constant(''))();

  late final helpType = text().nullable()();

  late final withdrawReason = text().nullable()();

  // 0=active, 1=withdrawn
  late final Column<int> status = integer()
      .withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {beaconId, userId};

  @override
  String get tableName => 'beacon_help_offer';

  @override
  bool get withoutRowId => true;
}
