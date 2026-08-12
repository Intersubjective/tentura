import 'package:drift/drift.dart';

import 'users.dart';

class CapabilityEvidenceGenerations extends Table {
  @ReferenceName('capabilityGenerationObserver')
  late final observerUserId = text().references(Users, #id)();

  @ReferenceName('capabilityGenerationSubject')
  late final subjectUserId = text().references(Users, #id)();

  late final tagSlug = text()();

  late final generation = int64().withDefault(Constant(BigInt.zero))();

  @override
  Set<Column<Object>> get primaryKey =>
      {observerUserId, subjectUserId, tagSlug};

  @override
  String get tableName => 'capability_evidence_generation';

  @override
  bool get withoutRowId => true;
}
