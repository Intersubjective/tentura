import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'users.dart';

/// Backed by `public.constellation_anchor_cursor` (see `m0167`).
class ConstellationAnchorCursors extends Table {
  late final viewerId = text().references(Users, #id)();

  late final revision = int64().withDefault(Constant(BigInt.zero))();

  late final lastPlacedAt =
      customType(PgTypes.timestampWithTimezone).nullable()();

  @override
  Set<Column<Object>> get primaryKey => {viewerId};

  @override
  String get tableName => 'constellation_anchor_cursor';

  @override
  bool get withoutRowId => true;
}
