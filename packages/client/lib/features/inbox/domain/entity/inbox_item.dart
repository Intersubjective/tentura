import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/domain/entity/beacon.dart';

import '../enum.dart';
import 'inbox_provenance.dart';
import 'inbox_room_card_hints.dart';

part 'inbox_item.freezed.dart';

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
    InboxRoomCardHints? roomHints,
  }) = _InboxItem;

  const InboxItem._();

  bool get isBeforeResponseTombstone =>
      status == InboxItemStatus.closedBeforeResponse ||
      status == InboxItemStatus.deletedBeforeResponse;

  /// Shown in inbox tombstone section until dismissed.
  bool get isTombstoneVisible =>
      isBeforeResponseTombstone && tombstoneDismissedAt == null;

  /// Carries the private × on For You (card spec §8, plan amendment A1).
  ///
  /// **Every** answered outcome, not only the two before-response terminals:
  /// m0183 made the whole set dismissible server-side, and a tombstone is by
  /// definition already answered — nobody is waiting on it, so putting the
  /// memory away is a private act. [needsMe] is the one exclusion: an
  /// unanswered forward is a pinned decision, and E17 gives it named outcome
  /// buttons instead of the quiet gesture.
  bool get isDismissibleOutcome =>
      status != InboxItemStatus.needsMe && tombstoneDismissedAt == null;
}
