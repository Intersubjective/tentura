import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/domain/entity/phantom_pending_forward.dart';

import 'beacon_forward_edges.dart';
import 'beacons.dart';
import 'phantom_merges.dart';
import 'phantoms.dart';
import 'users.dart';

@DataClassName('PhantomPendingForwardRow')
class PhantomPendingForwards extends Table {
  late final id = text()();
  late final phantomId = text().references(
    Phantoms,
    #id,
    onDelete: KeyAction.cascade,
  )();
  @ReferenceName('sentPhantomPendingForwards')
  late final senderId = text().references(
    Users,
    #id,
    onDelete: KeyAction.cascade,
  )();
  late final beaconId = text().references(
    Beacons,
    #id,
    onDelete: KeyAction.cascade,
  )();

  /// Keep the original parent ID even if the chain is removed before delivery.
  late final parentForwardEdgeId = text().nullable()();
  late final note = text()();
  late final createdAt = customType(
    PgTypes.timestampWithTimezone,
  ).withDefault(const CustomExpression('now()'))();
  late final state = textEnum<PhantomPendingForwardState>().withDefault(
    const Constant('pending'),
  )();
  late final mergeId = text().nullable().references(
    PhantomMerges,
    #id,
    onDelete: KeyAction.setNull,
  )();
  @ReferenceName('receivedPhantomPendingForwards')
  late final recipientId = text().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  late final forwardEdgeId = text().nullable().references(
    BeaconForwardEdges,
    #id,
    onDelete: KeyAction.setNull,
  )();
  late final lapseReason = text().nullable()();
  late final resolvedAt = customType(
    PgTypes.timestampWithTimezone,
  ).nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'phantom_pending_forward';
}
