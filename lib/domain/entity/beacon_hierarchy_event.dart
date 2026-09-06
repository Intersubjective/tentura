import 'beacon_hierarchy_delivery_direction.dart';
import 'beacon_status.dart';

/// Immutable hierarchy lifecycle notice source record.
class BeaconHierarchyEvent {
  const BeaconHierarchyEvent({
    required this.eventId,
    required this.sourceBeaconId,
    required this.sourceSequence,
    required this.fromStatus,
    required this.toStatus,
    required this.occurredAt,
    this.actorUserId,
  });

  final String eventId;
  final String sourceBeaconId;
  final int sourceSequence;
  final BeaconStatus fromStatus;
  final BeaconStatus toStatus;
  final DateTime occurredAt;
  final String? actorUserId;
}

/// Delivery work row derived from [BeaconHierarchyEvent].
class BeaconHierarchyDeliveryTarget {
  const BeaconHierarchyDeliveryTarget({
    required this.eventId,
    required this.targetBeaconId,
    required this.direction,
  });

  final String eventId;
  final String targetBeaconId;
  final BeaconHierarchyDeliveryDirection direction;
}
