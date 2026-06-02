import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/domain/entity/email_auth_transaction_entity.dart';

/// Single-use email magic-link transaction (server-internal).
class EmailAuthTransactions extends Table {
  late final id =
      text().clientDefault(() => EmailAuthTransactionEntity.newId)();

  late final tokenHash = text().named('token_hash').unique()();

  late final normalizedEmail = text().named('normalized_email')();

  late final inviteCode = text().named('invite_code').nullable()();

  late final createdAt = customType(PgTypes.timestampWithTimezone)
      .named('created_at')
      .clientDefault(() => PgDateTime(DateTime.timestamp()))();

  late final expiresAt = customType(PgTypes.timestampWithTimezone)
      .named('expires_at')();

  late final consumedAt = customType(PgTypes.timestampWithTimezone)
      .named('consumed_at')
      .nullable()();

  late final userAgentHash = text().named('user_agent_hash')();

  late final ipHash = text().named('ip_hash')();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'email_auth_transaction';

  @override
  bool get withoutRowId => true;
}
