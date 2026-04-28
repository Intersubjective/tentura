import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'beacon_room_messages.dart';
import 'users.dart';

class BeaconRoomMessageReactions extends Table {
  late final id = text()();

  late final messageId =
      text().references(BeaconRoomMessages, #id, onDelete: KeyAction.cascade)();

  late final userId = text().references(Users, #id)();

  late final emoji = text()();

  late final createdAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp()))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'beacon_room_message_reaction';

  @override
  bool get withoutRowId => true;
}
