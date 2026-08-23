import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

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
  late final invitedId = text().nullable().references(Users, #id)();

  late final beaconId = text().nullable().references(Beacons, #id)();

  late final parentForwardEdgeId = text()
      .nullable()
      .references(BeaconForwardEdges, #id)();

  /// Inviter's private name for the invitee; copied to `user_contact` on
  /// consumption. Nullable for legacy rows only — required for new invites.
  late final addresseeName = text().nullable()();

  /// 'new_account' | 'existing_account' (see `InviteOrigin`). Null while
  /// pending. CHECK-enforced in Postgres (m0152) — no Dart TypeConverter,
  /// mirrors the TrustSourceType idiom (plain enum + manual string write).
  late final inviteOrigin = text().nullable()();

  /// When this invitation was consumed. Null while pending. Distinct from
  /// `updatedAt`, which a DB trigger touches on any update to this row.
  late final acceptedAt = customType(
    PgTypes.timestampWithTimezone,
  ).nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'invitation';

  @override
  bool get withoutRowId => true;
}
