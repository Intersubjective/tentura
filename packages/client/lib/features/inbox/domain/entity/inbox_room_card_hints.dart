import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/domain/entity/open_blocker_cue.dart';
import 'package:tentura/features/beacon_plan/domain/entity/plan_viewer_slice.dart';

part 'inbox_room_card_hints.freezed.dart';

/// Extra inbox / My Work lines from V2 inbox room context batch (room + public fact).
@freezed
abstract class InboxRoomCardHints with _$InboxRoomCardHints {
  const factory InboxRoomCardHints({
    required bool isRoomMember,
    required int roomUnreadCount,
    DateTime? lastSeenAt,
    @Default('') String currentLineSnippet,
    @Default('') String lastRoomMeaningfulChange,
    @Default('') String myNextMove,
    @Default('') String openBlockerTitle,
    OpenBlockerCue? openBlocker,
    @Default('') String publicFactSnippet,

    /// The viewer's share of the Request plan (#220 §4.9); null without one.
    PlanViewerSlice? planSlice,
  }) = _InboxRoomCardHints;
}
