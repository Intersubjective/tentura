import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/domain/entity/beacon.dart';

import '../enum.dart';
import 'inbox_provenance.dart';

part 'inbox_item.freezed.dart';

/// Activity lines for the per-row NewStuff dot (see [InboxItem.newStuffReasons]).
enum InboxNewStuffReason {
  newForward,
  coordinationStatusChanged,
  beaconUpdated,
}

@freezed
abstract class InboxItem with _$InboxItem {
  const factory InboxItem({
    required String beaconId,
    required DateTime latestForwardAt,
    @Default(0) int forwardCount,
    @Default('') String latestNotePreview,
    @Default(InboxItemStatus.needsMe) InboxItemStatus status,
    @Default('') String rejectionMessage,
    @Default('') String context,
    @Default(InboxProvenance.empty) InboxProvenance provenance,
    @Default(false) bool isForwardedByMe,
    Beacon? beacon,
    DateTime? beforeResponseTerminalAt,
    DateTime? tombstoneDismissedAt,
  }) = _InboxItem;

  const InboxItem._();

  bool get isBeforeResponseTombstone =>
      status == InboxItemStatus.closedBeforeResponse ||
      status == InboxItemStatus.deletedBeforeResponse;

  /// Shown in inbox tombstone section until dismissed.
  bool get isTombstoneVisible =>
      isBeforeResponseTombstone && tombstoneDismissedAt == null;

  /// Max epoch ms of forward activity vs beacon content (for NewStuff cursors).
  int get newStuffActivityEpochMs {
    final f = latestForwardAt.millisecondsSinceEpoch;
    final bOnly = newStuffBeaconOnlyActivityEpochMs;
    return f > bOnly ? f : bOnly;
  }

  /// Beacon-side activity only (updated_at, coordination status), for row highlight.
  int get newStuffBeaconOnlyActivityEpochMs {
    final b = beacon;
    if (b == null) return 0;
    var max = b.updatedAt.millisecondsSinceEpoch;
    final cs = b.coordinationStatusUpdatedAt?.millisecondsSinceEpoch;
    if (cs != null && cs > max) {
      max = cs;
    }
    return max;
  }

  static const _inboxReasonDisplayOrder = <InboxNewStuffReason>[
    InboxNewStuffReason.newForward,
    InboxNewStuffReason.coordinationStatusChanged,
    InboxNewStuffReason.beaconUpdated,
  ];

  /// All distinct reasons for the dot when [lastSeenMs] matches the Inbox last-seen cursor.
  ///
  /// `InboxNewStuffReason.newForward` is only added when [forwardCount] > 0,
  /// so status-only inbox touches (e.g. withdraw→watching) are not misread as
  /// a new recipient forward.
  List<InboxNewStuffReason> newStuffReasons(int? lastSeenMs) {
    if (lastSeenMs == null) return [];
    final seen = lastSeenMs;
    final raw = <InboxNewStuffReason>[];
    if (forwardCount > 0 &&
        latestForwardAt.millisecondsSinceEpoch > seen) {
      raw.add(InboxNewStuffReason.newForward);
    }
    final b = beacon;
    if (b == null) {
      return _orderInboxReasons(raw);
    }
    if (newStuffBeaconOnlyActivityEpochMs <= seen) {
      return _orderInboxReasons(raw);
    }
    final u = b.updatedAt.millisecondsSinceEpoch;
    final cs = b.coordinationStatusUpdatedAt?.millisecondsSinceEpoch;
    if (cs != null && cs > seen) {
      raw.add(InboxNewStuffReason.coordinationStatusChanged);
    }
    if (u > seen && (cs == null || u != cs)) {
      raw.add(InboxNewStuffReason.beaconUpdated);
    }
    return _orderInboxReasons(raw);
  }

  static List<InboxNewStuffReason> _orderInboxReasons(
    List<InboxNewStuffReason> raw,
  ) {
    final out = <InboxNewStuffReason>[];
    for (final r in _inboxReasonDisplayOrder) {
      if (raw.contains(r)) {
        out.add(r);
      }
    }
    return out;
  }
}
