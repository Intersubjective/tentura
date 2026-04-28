import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'beacon_room_messages.dart';
import 'images.dart';

class BeaconRoomMessageAttachments extends Table {
  late final id = text()();

  late final messageId =
      text().references(BeaconRoomMessages, #id, onDelete: KeyAction.cascade)();

  late final kind = integer()();

  late final imageId = customType(PgTypes.uuid).nullable().references(Images, #id)();

  late final fileUrl = text().nullable()();

  late final mime = text().withDefault(const Constant('application/octet-stream'))();

  late final sizeBytes = integer().withDefault(const Constant(0))();

  late final width = integer().nullable()();

  late final height = integer().nullable()();

  late final position = integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'beacon_room_message_attachment';

  @override
  bool get withoutRowId => true;
}
