import 'package:drift/drift.dart';

import '../common_fields.dart';
import 'users.dart';

class UserTrustEdges extends Table with TimestampsFields {
  @ReferenceName('TrustEdgeSubject')
  late final subject = text().references(Users, #id)();

  @ReferenceName('TrustEdgeObject')
  late final object = text().references(Users, #id)();

  late final prevSentWeight = real().named('prev_sent_weight').withDefault(const Constant(0))();

  late final trustW = real().named('trust_w').withDefault(const Constant(0))();

  late final wallD = real().named('wall_d').withDefault(const Constant(0))();

  late final targetW = real().named('target_w').withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {subject, object};

  @override
  String get tableName => 'user_trust_edge';
}
