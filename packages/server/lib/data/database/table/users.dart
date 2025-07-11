import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';

import '../common_fields.dart';

class Users extends Table
    with TitleDescriptionFields, TimestampsFields, ImageFields {
  late final id = text().clientDefault(() => UserEntity.newId)();

  late final publicKey = text()
      .withLength(min: kPublicKeyLength, max: kPublicKeyLength)
      .unique()();

  late final privileges = customType(PgTypes.jsonb).nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'user';

  @override
  bool get withoutRowId => true;
}
