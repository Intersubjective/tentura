import 'package:tentura_root/domain/entity/beacon_hierarchy_delivery_direction.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

/// Person-free hierarchy lifecycle notice copy (§4.4).
abstract final class BeaconHierarchyNoticeCopy {
  static String noticeBody({
    required BeaconHierarchyDeliveryDirection direction,
    required BeaconStatus toStatus,
    required DateTime occurredAt,
    required bool sourceDeleted,
  }) {
    final relation = switch (direction) {
      BeaconHierarchyDeliveryDirection.ancestor => 'An ancestor request',
      BeaconHierarchyDeliveryDirection.child => 'A child request',
    };
    final action = sourceDeleted && toStatus == BeaconStatus.deleted
        ? 'was deleted'
        : _statusAction(toStatus);
    final date = _formatEventDate(occurredAt);
    return '$relation $action on $date';
  }

  static String attentionTitle({
    required BeaconHierarchyDeliveryDirection direction,
  }) =>
      switch (direction) {
        BeaconHierarchyDeliveryDirection.ancestor =>
          'Ancestor request status changed',
        BeaconHierarchyDeliveryDirection.child =>
          'Child request status changed',
      };

  static String attentionBody({
    required BeaconHierarchyDeliveryDirection direction,
    required BeaconStatus toStatus,
    required DateTime occurredAt,
    required bool sourceDeleted,
  }) => noticeBody(
    direction: direction,
    toStatus: toStatus,
    occurredAt: occurredAt,
    sourceDeleted: sourceDeleted,
  );

  static String _statusAction(BeaconStatus status) => switch (status) {
    BeaconStatus.reviewOpen => 'entered Wrapping up',
    BeaconStatus.closed => 'was closed',
    BeaconStatus.cancelled => 'was cancelled',
    BeaconStatus.deleted => 'was deleted',
    _ => 'changed status',
  };

  static String _formatEventDate(DateTime occurredAt) {
    final utc = occurredAt.toUtc();
    final y = utc.year.toString().padLeft(4, '0');
    final m = utc.month.toString().padLeft(2, '0');
    final d = utc.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
