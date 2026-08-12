import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'users.dart';

class CapabilityRoutingMutes extends Table {
  @ReferenceName('capabilityRoutingMuteUser')
  late final userId = text().references(Users, #id)();

  late final tagSlug = text()();

  late final createdAt = customType(
    PgTypes.timestampWithTimezone,
  ).named('created_at').clientDefault(() => PgDateTime(DateTime.timestamp()))();

  @override
  Set<Column<Object>> get primaryKey => {userId, tagSlug};

  @override
  String get tableName => 'capability_routing_mute';

  @override
  bool get withoutRowId => true;
}
