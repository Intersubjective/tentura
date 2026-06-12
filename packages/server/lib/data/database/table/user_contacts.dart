import 'package:drift/drift.dart';

import 'package:tentura_server/consts.dart';

import '../common_fields.dart';
import 'users.dart';

/// Per-viewer private contact names (subjective profiles).
/// The subject must never be able to read what others call them — the table
/// is not tracked in Hasura and is only reachable via viewer-scoped resolvers.
class UserContacts extends Table with TimestampsFields {
  @ReferenceName('viewer')
  late final viewerId = text().references(Users, #id)();

  @ReferenceName('subject')
  late final subjectId = text().references(Users, #id)();

  late final contactName = text().withLength(
    min: kTitleMinLength,
    max: kTitleMaxLength,
  )();

  @override
  Set<Column<Object>> get primaryKey => {viewerId, subjectId};

  @override
  String get tableName => 'user_contact';

  @override
  bool get withoutRowId => true;
}
