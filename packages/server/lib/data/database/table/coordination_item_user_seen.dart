import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'coordination_items.dart';
import 'users.dart';

class CoordinationItemUserSeen extends Table {
  late final userId = text().references(Users, #id)();
  late final itemId =
      text().references(CoordinationItems, #id, onDelete: KeyAction.cascade)();
  late final lastSeenAt = customType(PgTypes.timestampWithTimezone)();

  @override
  Set<Column<Object>> get primaryKey => {userId, itemId};

  @override
  String get tableName => 'coordination_item_user_seen';

  @override
  bool get withoutRowId => true;
}
