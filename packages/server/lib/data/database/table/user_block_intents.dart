import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import '../common_fields.dart';
import 'users.dart';

class UserBlockIntents extends Table with TimestampsFields {
  @ReferenceName('UserBlockIntentBlocker')
  late final blockerId = text().named('blocker_id').references(Users, #id)();

  @ReferenceName('UserBlockIntentBlocked')
  late final blockedId = text().named('blocked_id').references(Users, #id)();

  late final Column<int> cascadeMode = integer()
      .named('cascade_mode')
      .withDefault(const Constant(0))();

  late final Column<int> cascadeStatus = integer()
      .named('cascade_status')
      .withDefault(const Constant(0))();

  late final cascadeCursor = text().named('cascade_cursor').nullable()();

  late final cascadeSnapshotAt = customType(PgTypes.timestampWithTimezone)
      .named('cascade_snapshot_at')
      .nullable()();

  late final Column<int> materializedCount = integer()
      .named('materialized_count')
      .withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {blockerId, blockedId};

  @override
  String get tableName => 'user_block_intent';

  @override
  bool get withoutRowId => true;
}
