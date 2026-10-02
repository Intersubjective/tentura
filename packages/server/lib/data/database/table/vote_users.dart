import 'package:drift/drift.dart';

import '../common_fields.dart';
import 'users.dart';

class VoteUsers extends Table with TimestampsFields, TickerFields {
  @ReferenceName('VoteUserSubject')
  late final subject = text().references(Users, #id)();

  @ReferenceName('VoteUserObject')
  late final object = text().references(Users, #id)();

  late final Column<int> amount =
      integer().check(amount.isBetweenValues(-1, 1))();

  @override
  Set<Column<Object>> get primaryKey => {subject, object};

  @override
  String get tableName => 'vote_user';
}
