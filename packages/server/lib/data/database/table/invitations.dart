import 'package:drift/drift.dart';

import 'package:tentura_server/domain/entity/invitation_entity.dart';

import '../common_fields.dart';
import 'beacon_forward_edges.dart';
import 'beacons.dart';
import 'users.dart';

class Invitations extends Table with TimestampsFields {
  late final id = text().clientDefault(() => InvitationEntity.newId)();

  @ReferenceName('subject')
  late final userId = text().references(Users, #id)();

  @ReferenceName('object')
  late final invitedId = text().nullable().unique().references(Users, #id)();

  late final beaconId = text().nullable().references(Beacons, #id)();

  late final parentForwardEdgeId = text()
      .nullable()
      .references(BeaconForwardEdges, #id)();

  /// Inviter's private name for the invitee; copied to `user_contact` on
  /// consumption. Nullable for legacy rows only — required for new invites.
  late final addresseeName = text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'invitation';

  @override
  bool get withoutRowId => true;
}
