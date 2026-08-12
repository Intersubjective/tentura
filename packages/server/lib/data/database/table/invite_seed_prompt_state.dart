import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'users.dart';

class InviteSeedPromptStates extends Table {
  @ReferenceName('seedPromptInviter')
  late final inviterUserId = text()
      .named('inviter_user_id')
      .references(Users, #id)();

  @ReferenceName('seedPromptInvitee')
  late final inviteeUserId = text()
      .named('invitee_user_id')
      .references(Users, #id)();

  late final state = integer().withDefault(const Constant(0))();

  late final updatedAt = customType(
    PgTypes.timestampWithTimezone,
  ).named('updated_at').clientDefault(() => PgDateTime(DateTime.timestamp()))();

  @override
  Set<Column<Object>> get primaryKey => {inviteeUserId};

  @override
  String get tableName => 'invite_seed_prompt_state';

  @override
  bool get withoutRowId => true;
}
