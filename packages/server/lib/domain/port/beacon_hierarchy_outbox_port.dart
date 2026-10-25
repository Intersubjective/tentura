import 'package:tentura_root/domain/entity/beacon_hierarchy_delivery_direction.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_event.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/domain/entity/beacon_kind.dart';

/// Durable hierarchy lifecycle outbox writes and worker claims.
abstract class BeaconHierarchyOutboxPort {
  Future<BeaconHierarchyEvent> recordEvent({
    required String sourceBeaconId,
    required BeaconStatus fromStatus,
    required BeaconStatus toStatus,
    required DateTime occurredAt,
    String? actorUserId,
  });

  Future<void> insertDeliveryTargets({
    required BeaconHierarchyEvent event,
    required List<BeaconHierarchyDeliveryTarget> targets,
  });

  /// Set-based recursive parent-edge traversal for lifecycle delivery targets
  /// (§4.3 step 3). Deduplicates by `(event, target)` via the table PK.
  Future<void> insertTopologyDeliveryTargets({
    required String sourceBeaconId,
    required String eventId,
  });

  Future<BeaconHierarchyEvent?> loadEvent(String eventId);

  Future<BeaconStatus?> loadDestinationBeaconStatus(String targetBeaconId);

  /// Null when the beacon row is gone.
  Future<BeaconKind?> loadDestinationBeaconKind(String targetBeaconId);

  /// Current title of [beaconId]; null when the row is gone (#450b).
  Future<String?> loadBeaconTitle(String beaconId);

  Future<String> insertHierarchyLifecycleNotice({
    required String eventId,
    required String targetBeaconId,
    required BeaconHierarchyDeliveryDirection direction,
    required BeaconStatus toStatus,
    required DateTime occurredAt,
    required String noticeBody,
    required bool sourceDeleted,

    /// Title snapshot of the source request, written into the JSON payload
    /// only (#450b); omitted from the payload when null.
    String? sourceTitle,
  });

  Future<List<BeaconHierarchyDeliveryTarget>> claimDueDeliveries({
    required String leaseOwner,
    required DateTime now,
    required int limit,
  });

  Future<void> markDeliveryDelivered({
    required String eventId,
    required String targetBeaconId,
    required String leaseOwner,
    String? noticeMessageId,
  });

  Future<void> markDeliverySuppressed({
    required String eventId,
    required String targetBeaconId,
    required String leaseOwner,
  });

  Future<void> markDeliveryParked({
    required String eventId,
    required String targetBeaconId,
    required String leaseOwner,
    required String safeErrorCode,
  });

  /// Owner-qualified retry scheduling after a materialization transaction rolls
  /// back. [attemptCount] is the post-claim attempt count on the leased row.
  Future<void> scheduleDeliveryRetry({
    required String eventId,
    required String targetBeaconId,
    required String leaseOwner,
    required DateTime now,
    required int attemptCount,
    required String safeErrorCode,
  });

  /// Audited operator action for poisoned rows — never called by the sweep.
  Future<bool> operatorParkPoisonedDelivery({
    required String eventId,
    required String targetBeaconId,
  });

  Future<int?> loadDeliveryAttemptCount({
    required String eventId,
    required String targetBeaconId,
  });
}
