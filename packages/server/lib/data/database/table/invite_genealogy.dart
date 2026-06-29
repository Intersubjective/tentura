import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'invitations.dart';
import 'users.dart';

class InviteGenealogy extends Table {
  late final descendantNodeKey = text().named('descendant_node_key')();

  late final ancestorNodeKey = text().named('ancestor_node_key')();

  @ReferenceName('genealogyDescendant')
  late final descendantUserId = text()
      .nullable()
      .unique()
      .named('descendant_user_id')
      .references(Users, #id)();

  @ReferenceName('genealogyAncestor')
  late final ancestorUserId = text()
      .nullable()
      .named('ancestor_user_id')
      .references(Users, #id)();

  late final invitationId = text()
      .nullable()
      .named('invitation_id')
      .references(Invitations, #id)();

  late final descendantDeletedAt = customType(
    PgTypes.timestampWithTimezone,
  ).nullable().named('descendant_deleted_at')();

  late final ancestorDeletedAt = customType(
    PgTypes.timestampWithTimezone,
  ).nullable().named('ancestor_deleted_at')();

  late final ancestorUserCreatedAt = customType(
    PgTypes.timestampWithTimezone,
  ).named('ancestor_user_created_at')();

  late final descendantUserCreatedAt = customType(
    PgTypes.timestampWithTimezone,
  ).named('descendant_user_created_at')();

  late final createdAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp())).named('created_at')();

  @override
  Set<Column<Object>> get primaryKey => {descendantNodeKey};

  @override
  String get tableName => 'invite_genealogy';

  @override
  bool get withoutRowId => true;
}
