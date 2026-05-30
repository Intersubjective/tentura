import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/domain/entity/account_credential_entity.dart';

import 'users.dart';

/// Auth credentials linked to an account (`user` row). Phase 1: one account,
/// many credentials. The real identity is the unique `(type, identifier)` pair
/// (enforced by the `account_credential__type_identifier` index created in the
/// `m0080` migration — Drift does not manage the schema here).
class AccountCredentials extends Table {
  late final id = text().clientDefault(() => AccountCredentialEntity.newId)();

  late final accountId = text().named('account_id').references(Users, #id)();

  late final type = text()();

  late final identifier = text()();

  late final publicData = customType(
    PgTypes.jsonb,
  ).named('public_data').nullable()();

  late final createdAt = customType(PgTypes.timestampWithTimezone)
      .named('created_at')
      .clientDefault(() => PgDateTime(DateTime.timestamp()))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'account_credential';

  @override
  bool get withoutRowId => true;
}
