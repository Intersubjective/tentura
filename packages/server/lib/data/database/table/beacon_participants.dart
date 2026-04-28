import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import '../common_fields.dart';
import 'beacons.dart';
import 'users.dart';

/// Per-user involvement in a beacon (room access, role, status, next move).
class BeaconParticipants extends Table with TimestampsFields {
  late final id = text()();

  late final beaconId = text().references(Beacons, #id,
      onDelete: KeyAction.cascade)();

  late final userId =
      text().references(Users, #id, onDelete: KeyAction.cascade)();

  late final role = integer()();

  late final status = integer().withDefault(const Constant(0))();

  late final roomAccess = integer().withDefault(const Constant(0))();

  late final nextMoveText = text().nullable()();

  late final nextMoveStatus = integer().nullable()();

  late final nextMoveSource = integer().nullable()();

  late final linkedMessageId = text().nullable()();

  late final offerNote = text().nullable()();

  /// When the user last opened/read the Room (Phase 6 unread).
  late final lastSeenRoomAt =
      customType(PgTypes.timestampWithTimezone).nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'beacon_participant';
}
