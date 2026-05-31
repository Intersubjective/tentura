import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/domain/entity/account_session_entity.dart';

import 'account_credentials.dart';
import 'users.dart';

/// Revocable browser session for the app-host HttpOnly cookie (server-internal).
class AccountSessions extends Table {
  late final id = text().clientDefault(() => AccountSessionEntity.newId)();

  late final accountId = text().named('account_id').references(Users, #id)();

  late final tokenHash = text().named('token_hash').unique()();

  late final credentialId = text()
      .named('credential_id')
      .nullable()
      .references(AccountCredentials, #id)();

  late final createdAt = customType(PgTypes.timestampWithTimezone)
      .named('created_at')
      .clientDefault(() => PgDateTime(DateTime.timestamp()))();

  late final expiresAt = customType(PgTypes.timestampWithTimezone)
      .named('expires_at')();

  late final revokedAt = customType(PgTypes.timestampWithTimezone)
      .named('revoked_at')
      .nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'account_session';

  @override
  bool get withoutRowId => true;
}
