import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import '../common_fields.dart';
import 'users.dart';

class UserTrustEdges extends Table with TimestampsFields {
  @ReferenceName('TrustEdgeSubject')
  late final subject = text().references(Users, #id)();

  @ReferenceName('TrustEdgeObject')
  late final object = text().references(Users, #id)();

  late final cVeryBad = real().named('c_very_bad').withDefault(const Constant(0))();

  late final cBad = real().named('c_bad').withDefault(const Constant(0))();

  late final cNoEffect = real().named('c_no_effect').withDefault(const Constant(0))();

  late final cGood = real().named('c_good').withDefault(const Constant(0))();

  late final cVeryGood = real().named('c_very_good').withDefault(const Constant(0))();

  late final lastDecayAt = customType(PgTypes.timestampWithTimezone)();

  late final prevSentWeight = real().named('prev_sent_weight').withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {subject, object};

  @override
  String get tableName => 'user_trust_edge';

  @override
  bool get withoutRowId => true;
}
