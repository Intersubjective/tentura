import 'package:tentura_root/domain/entity/beacon_hierarchy_delivery_direction.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_event.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/domain/port/beacon_hierarchy_outbox_port.dart';

/// In-memory outbox for lifecycle producer unit tests.
final class RecordingBeaconHierarchyOutbox implements BeaconHierarchyOutboxPort {
  final recordedEvents = <BeaconHierarchyEvent>[];
  final topologyInserts = <({String sourceBeaconId, String eventId})>[];
  var failOnTopologyInsert = false;
  int recordEventCalls = 0;

  @override
  Future<BeaconHierarchyEvent> recordEvent({
    required String sourceBeaconId,
    required BeaconStatus fromStatus,
    required BeaconStatus toStatus,
    required DateTime occurredAt,
    String? actorUserId,
  }) async {
    recordEventCalls++;
    final event = BeaconHierarchyEvent(
      eventId: 'HE-test-${recordedEvents.length + 1}',
      sourceBeaconId: sourceBeaconId,
      sourceSequence: recordedEvents.length + 1,
      fromStatus: fromStatus,
      toStatus: toStatus,
      occurredAt: occurredAt,
      actorUserId: actorUserId,
    );
    recordedEvents.add(event);
    return event;
  }

  @override
  Future<void> insertDeliveryTargets({
    required BeaconHierarchyEvent event,
    required List<BeaconHierarchyDeliveryTarget> targets,
  }) async {}

  @override
  Future<void> insertTopologyDeliveryTargets({
    required String sourceBeaconId,
    required String eventId,
  }) async {
    if (failOnTopologyInsert) {
      throw StateError('injected topology insert failure');
    }
    topologyInserts.add((sourceBeaconId: sourceBeaconId, eventId: eventId));
  }

  @override
  Future<List<BeaconHierarchyDeliveryTarget>> claimDueDeliveries({
    required String leaseOwner,
    required int limit,
  }) async =>
      const [];

  @override
  Future<void> markDeliveryDelivered({
    required String eventId,
    required String targetBeaconId,
    required String leaseOwner,
    String? noticeMessageId,
  }) async {}

  @override
  Future<void> markDeliverySuppressed({
    required String eventId,
    required String targetBeaconId,
    required String leaseOwner,
  }) async {}

  @override
  Future<void> markDeliveryParked({
    required String eventId,
    required String targetBeaconId,
    required String leaseOwner,
    required String safeErrorCode,
  }) async {}
}

/// Decorator that fails mid-transaction for PG rollback proofs.
final class ThrowingBeaconHierarchyOutbox extends BeaconHierarchyOutboxPort {
  ThrowingBeaconHierarchyOutbox(this._inner);

  final BeaconHierarchyOutboxPort _inner;
  var failOnTopologyInsert = false;

  @override
  Future<BeaconHierarchyEvent> recordEvent({
    required String sourceBeaconId,
    required BeaconStatus fromStatus,
    required BeaconStatus toStatus,
    required DateTime occurredAt,
    String? actorUserId,
  }) =>
      _inner.recordEvent(
        sourceBeaconId: sourceBeaconId,
        fromStatus: fromStatus,
        toStatus: toStatus,
        occurredAt: occurredAt,
        actorUserId: actorUserId,
      );

  @override
  Future<void> insertDeliveryTargets({
    required BeaconHierarchyEvent event,
    required List<BeaconHierarchyDeliveryTarget> targets,
  }) =>
      _inner.insertDeliveryTargets(event: event, targets: targets);

  @override
  Future<void> insertTopologyDeliveryTargets({
    required String sourceBeaconId,
    required String eventId,
  }) async {
    if (failOnTopologyInsert) {
      throw StateError('injected topology insert failure');
    }
    await _inner.insertTopologyDeliveryTargets(
      sourceBeaconId: sourceBeaconId,
      eventId: eventId,
    );
  }

  @override
  Future<List<BeaconHierarchyDeliveryTarget>> claimDueDeliveries({
    required String leaseOwner,
    required int limit,
  }) =>
      _inner.claimDueDeliveries(leaseOwner: leaseOwner, limit: limit);

  @override
  Future<void> markDeliveryDelivered({
    required String eventId,
    required String targetBeaconId,
    required String leaseOwner,
    String? noticeMessageId,
  }) =>
      _inner.markDeliveryDelivered(
        eventId: eventId,
        targetBeaconId: targetBeaconId,
        leaseOwner: leaseOwner,
        noticeMessageId: noticeMessageId,
      );

  @override
  Future<void> markDeliverySuppressed({
    required String eventId,
    required String targetBeaconId,
    required String leaseOwner,
  }) =>
      _inner.markDeliverySuppressed(
        eventId: eventId,
        targetBeaconId: targetBeaconId,
        leaseOwner: leaseOwner,
      );

  @override
  Future<void> markDeliveryParked({
    required String eventId,
    required String targetBeaconId,
    required String leaseOwner,
    required String safeErrorCode,
  }) =>
      _inner.markDeliveryParked(
        eventId: eventId,
        targetBeaconId: targetBeaconId,
        leaseOwner: leaseOwner,
        safeErrorCode: safeErrorCode,
      );
}
