import 'package:drift/drift.dart';

/// Subjective profiles: the account's private contact names, synced from the
/// server (`myContacts`). Keyed per account — one device can hold several.
class Contacts extends Table {
  TextColumn get accountId => text()();

  TextColumn get subjectId => text()();

  TextColumn get contactName => text().named('contact_name')();

  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  bool get withoutRowId => true;

  @override
  Set<Column> get primaryKey => {accountId, subjectId};
}
