import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import '../custom_types/mentions_text_array_type.dart';
import 'beacons.dart';
import 'coordination_items.dart';
import 'pollings.dart';
import 'users.dart';

class BeaconRoomMessages extends Table {
  late final id = text()();

  late final beaconId = text().references(Beacons, #id)();

  late final authorId = text().references(Users, #id)();

  late final body = text().withDefault(const Constant(''))();

  late final replyToMessageId = text().nullable()();

  late final linkedNextMoveId = text().nullable()();

  late final linkedFactCardId = text().nullable()();

  late final linkedPollingId =
      text().nullable().references(Pollings, #id)();

  late final linkedItemId =
      text().nullable().references(CoordinationItems, #id)();

  late final linkedEventKind = integer().nullable()();

  late final semanticMarker = integer().nullable()();

  late final systemPayload = customType(
    PgTypes.jsonb,
  ).nullable()();

  late final createdAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp()))();

  late final editedAt = customType(
    PgTypes.timestampWithTimezone,
  ).nullable()();

  /// Mentioned user ids (server-resolved from @handle in body).
  late final mentions = customType(kMentionsTextArrayType).withDefault(
    const Constant(<String>[], kMentionsTextArrayType),
  )();

  /// NULL = main beacon room; non-null = coordination item thread.
  late final threadItemId = text()
      .nullable()
      .references(CoordinationItems, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'beacon_room_message';

  @override
  bool get withoutRowId => true;
}
