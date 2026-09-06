import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_event.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/entity/beacon_status_transition.dart';

import 'package:tentura_server/domain/policy/beacon_hierarchy_policy.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_outbox_port.dart';

import '_use_case_base.dart';

/// Records durable hierarchy lifecycle events and delivery targets (§4.3).
///
/// Callers must invoke this inside their existing transaction after
/// [BeaconHierarchyRepositoryPort.lockMutationScope] and the source row lock.
@Singleton(order: 2)
final class BeaconLifecycleEffectsCase extends UseCaseBase {
  BeaconLifecycleEffectsCase(
    this._outbox, {
    required super.env,
    required super.logger,
  });

  final BeaconHierarchyOutboxPort _outbox;

  /// No-ops when [fromStatus] → [toStatus] is ineligible (draft delete, local
  /// reopen, noop). Otherwise increments source sequence, inserts the event row,
  /// and set-inserts topology delivery targets.
  Future<BeaconHierarchyEvent?> recordEligibleSourceTransition({
    required String sourceBeaconId,
    required BeaconStatus fromStatus,
    required BeaconStatus toStatus,
    required DateTime occurredAt,
    String? actorUserId,
    BeaconStatusTransitionReason? reason,
  }) async {
    if (!BeaconHierarchyPolicy.isHierarchyLifecycleNoticeEligible(
      from: fromStatus,
      to: toStatus,
      reason: reason,
    )) {
      return null;
    }

    final event = await _outbox.recordEvent(
      sourceBeaconId: sourceBeaconId,
      fromStatus: fromStatus,
      toStatus: toStatus,
      occurredAt: occurredAt,
      actorUserId: actorUserId,
    );
    await _outbox.insertTopologyDeliveryTargets(
      sourceBeaconId: sourceBeaconId,
      eventId: event.eventId,
    );
    return event;
  }
}
