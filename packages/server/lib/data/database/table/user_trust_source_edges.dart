import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import '../common_fields.dart';
import 'users.dart';

class UserTrustSourceEdges extends Table with TimestampsFields {
  late final trustContext = text().named('trust_context')();

  @ReferenceName('TrustSourceEdgeSubject')
  late final subject = text().references(Users, #id)();

  @ReferenceName('TrustSourceEdgeObject')
  late final object = text().references(Users, #id)();

  late final sVeryBad = real().named('s_very_bad').withDefault(const Constant(0))();

  late final sBad = real().named('s_bad').withDefault(const Constant(0))();

  late final sNoEffect = real().named('s_no_effect').withDefault(const Constant(0))();

  late final sGood = real().named('s_good').withDefault(const Constant(0))();

  late final sVeryGood = real().named('s_very_good').withDefault(const Constant(0))();

  late final anchorAt = customType(PgTypes.timestampWithTimezone)();

  @override
  Set<Column<Object>> get primaryKey => {trustContext, subject, object};

  @override
  String get tableName => 'user_trust_source_edge';

  @override
  bool get withoutRowId => true;
}
