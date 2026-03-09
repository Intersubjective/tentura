import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';

import '../common_fields.dart';
import 'images.dart';
import 'pollings.dart';
import 'users.dart';

class Beacons extends Table
    with TitleDescriptionFields, TimestampsFields, TickerFields {
  late final id = text().clientDefault(() => BeaconEntity.newId)();

  @ReferenceName('author')
  late final userId = text().references(Users, #id)();

  late final isEnabled = boolean()
      .named('enabled')
      .withDefault(const Constant(true))();

  late final imageId = customType(
    PgTypes.uuid,
  ).nullable().references(Images, #id)();

  late final context = text().nullable().withLength(
    min: kTitleMinLength,
    max: kTitleMaxLength,
  )();

  late final lat = real().nullable()();

  late final long = real().nullable()();

  late final startAt = customType(PgTypes.timestampWithTimezone).nullable()();

  late final endAt = customType(PgTypes.timestampWithTimezone).nullable()();

  late final pollingId = text().nullable().references(Pollings, #id)();

  late final tags = text().withDefault(const Constant(''))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'beacon';

  @override
  bool get withoutRowId => true;
}
