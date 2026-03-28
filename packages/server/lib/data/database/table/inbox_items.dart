import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/consts.dart';

import 'beacons.dart';
import 'users.dart';

class InboxItems extends Table {
  @ReferenceName('inboxUser')
  late final userId = text().references(Users, #id)();

  late final beaconId = text().references(Beacons, #id)();

  late final context = text().nullable().withLength(
    min: kTitleMinLength,
    max: kTitleMaxLength,
  )();

  late final forwardCount = integer()
      .withDefault(const Constant(0))();

  late final latestForwardAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp()))();

  late final latestNotePreview = text()
      .withDefault(const Constant(''))();

  late final isHidden = boolean()
      .withDefault(const Constant(false))();

  late final isWatching = boolean()
      .withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {userId, beaconId};

  @override
  String get tableName => 'inbox_item';

  @override
  bool get withoutRowId => true;
}
