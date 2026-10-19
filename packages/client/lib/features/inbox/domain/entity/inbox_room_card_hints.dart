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

    /// U087 — latest change in the discussion (message, next step, logged
    /// event) and the latest member message.
    DateTime? lastActivityAt,
    DateTime? lastMessageAt,
    @Default('') String lastMessageText,
    @Default('') String lastMessageAuthorId,
    @Default('') String lastMessageAuthorName,

    /// #498 — what the latest message carries when it has no text: `image`,
    /// `file`, `poll` or `fact` ([kRoomLatestMessageKinds]); empty for text.
    @Default('') String lastMessageKind,

    /// #487 — the Request's immediate parent (id and title), only when the
    /// viewer may read it; empty for a top-level Request. Not a room detail:
    /// it is sent whether or not the viewer is in the room.
    @Default('') String parentBeaconId,
    @Default('') String parentTitle,
  }) = _InboxRoomCardHints;
}

/// #498 — the kinds of a no-text latest message the Requests card can label
/// ("📷 Photo", "📎 File", "📊 Poll", "📌 Fact").
const kRoomLatestMessageKinds = {'image', 'file', 'poll', 'fact'};

/// Whether a Requests card has a "latest" line to show: the message has text,
/// or it has none but carries something the card can label (#498).
bool isRoomLatestMessageShown({required String text, required String kind}) =>
    text.trim().isNotEmpty || kRoomLatestMessageKinds.contains(kind);
