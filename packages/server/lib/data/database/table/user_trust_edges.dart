import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import '../common_fields.dart';
import 'users.dart';

class UserTrustEdges extends Table with TimestampsFields {
  @ReferenceName('TrustEdgeSubject')
  late final subject = text().references(Users, #id)();

  @ReferenceName('TrustEdgeObject')
  late final object = text().references(Users, #id)();

  late final sVeryBad = real().named('s_very_bad').withDefault(const Constant(0))();

  late final sBad = real().named('s_bad').withDefault(const Constant(0))();

  late final sNoEffect = real().named('s_no_effect').withDefault(const Constant(0))();

  late final sGood = real().named('s_good').withDefault(const Constant(0))();

  late final sVeryGood = real().named('s_very_good').withDefault(const Constant(0))();

  late final anchorAt = customType(PgTypes.timestampWithTimezone)();

  late final prevSentWeight = real().named('prev_sent_weight').withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {subject, object};

  @override
  String get tableName => 'user_trust_edge';

  @override
  bool get withoutRowId => true;
}
