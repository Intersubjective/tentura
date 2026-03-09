import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'users.dart';

class P2pMessages extends Table {
  late final clientId = customType(PgTypes.uuid)();

  late final serverId = customType(
    PgTypes.uuid,
  ).clientDefault(const Uuid().v4obj)();

  late final senderId = text().references(Users, #id)();

  late final receiverId = text().references(Users, #id)();

  late final content = text()();

  late final createdAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp()))();

  late final deliveredAt = customType(
    PgTypes.timestampWithTimezone,
  ).nullable()();

  @override
  Set<Column<Object>> get primaryKey => {clientId, serverId};

  @override
  String get tableName => 'p2p_message';

  @override
  bool get withoutRowId => true;
}
