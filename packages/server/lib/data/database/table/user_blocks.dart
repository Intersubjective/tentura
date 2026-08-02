import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'users.dart';

class UserBlocks extends Table {
  @ReferenceName('UserBlockBlocker')
  late final blockerId = text().named('blocker_id').references(Users, #id)();

  @ReferenceName('UserBlockBlocked')
  late final blockedId = text().named('blocked_id').references(Users, #id)();

  @ReferenceName('UserBlockOrigin')
  late final originId = text().named('origin_id').references(Users, #id)();

  late final createdAt = customType(PgTypes.timestampWithTimezone)
      .named('created_at')
      .clientDefault(() => PgDateTime(DateTime.timestamp()))();

  @override
  Set<Column<Object>> get primaryKey => {blockerId, blockedId, originId};

  @override
  String get tableName => 'user_block';

  @override
  bool get withoutRowId => true;
}
