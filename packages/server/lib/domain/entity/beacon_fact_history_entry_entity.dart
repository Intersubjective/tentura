import 'package:freezed_annotation/freezed_annotation.dart';

part 'beacon_fact_history_entry_entity.freezed.dart';

/// One row of a fact card's history timeline (issue #181 plan §14.2):
/// a text revision or a visibility/unpin event.
@freezed
sealed class BeaconFactHistoryEntry with _$BeaconFactHistoryEntry {
  /// A text version; [kind] is a `BeaconFactCardRevisionKindBits` value.
  const factory BeaconFactHistoryEntry.revision({
    required int seq,
    required int kind,
    required String factText,
    required String actorTitle,
    required DateTime createdAt,
    int? restoredFromSeq,
    String? actorId,
  }) = BeaconFactHistoryRevision;

  /// A visibility change or unpin event; [type] is the activity event type.
  /// [activityEventId] is `beacon_activity_event.id` (history `entry_key` `e||id`).
  const factory BeaconFactHistoryEntry.event({
    required String activityEventId,
    required int type,
    required String actorTitle,
    required DateTime createdAt,
    int? visibilityFrom,
    int? visibilityTo,
    String? actorId,
  }) = BeaconFactHistoryEvent;
}
