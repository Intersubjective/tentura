import 'package:drift/drift.dart';

import 'package:tentura_server/domain/entity/invitation_entity.dart';

import '../common_fields.dart';
import 'users.dart';

class Invitations extends Table with TimestampsFields {
  late final id = text().clientDefault(() => InvitationEntity.newId)();

  @ReferenceName('subject')
  late final userId = text().references(Users, #id)();

  @ReferenceName('object')
  late final invitedId = text().nullable().unique().references(Users, #id)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'invitation';

  @override
  bool get withoutRowId => true;
}
