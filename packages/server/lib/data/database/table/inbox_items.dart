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

  /// 0 = needs_me, 1 = watching, 2 = rejected,
  /// 3 = closed_before_response, 4 = deleted_before_response
  late final status = integer().withDefault(const Constant(0))();

  late final rejectionMessage = text()
      .withDefault(const Constant(''))();

  late final beforeResponseTerminalAt = customType(
    PgTypes.timestampWithTimezone,
  ).nullable()();

  late final tombstoneDismissedAt = customType(
    PgTypes.timestampWithTimezone,
  ).nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId, beaconId};

  @override
  String get tableName => 'inbox_item';

  @override
  bool get withoutRowId => true;
}
