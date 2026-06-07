import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/domain/entity/verified_contact_entity.dart';

import 'users.dart';

/// Verified email/phone contacts linked to an account for cross-credential
/// identity unification. Unique `(kind, value)` is enforced in migration m0083.
class AccountVerifiedContacts extends Table {
  late final id = text().clientDefault(() => VerifiedContactEntity.newId)();

  late final accountId = text().named('account_id').references(Users, #id)();

  late final kind = text()();

  late final value = text()();

  late final lastSource = text().named('last_source')();

  late final verifiedAt = customType(PgTypes.timestampWithTimezone)
      .named('verified_at')
      .clientDefault(() => PgDateTime(DateTime.timestamp()))();

  late final createdAt = customType(PgTypes.timestampWithTimezone)
      .named('created_at')
      .clientDefault(() => PgDateTime(DateTime.timestamp()))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'account_verified_contact';

  @override
  bool get withoutRowId => true;
}
