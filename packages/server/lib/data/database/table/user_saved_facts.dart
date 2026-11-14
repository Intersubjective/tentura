import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'users.dart';

/// Backed by `public.user_saved_fact` (see `m0314`): a user's saved fact
/// pointers. `factCardId` has no foreign key on purpose (plan R4).
class UserSavedFacts extends Table {
  late final userId = text().references(
    Users,
    #id,
    onDelete: KeyAction.cascade,
    onUpdate: KeyAction.cascade,
  )();

  late final factCardId = text()();

  late final createdAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp()))();

  @override
  Set<Column<Object>> get primaryKey => {userId, factCardId};

  @override
  String get tableName => 'user_saved_fact';
}
