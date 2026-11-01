import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_display_status_dto.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/open_blocker_cue.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_plan/domain/entity/plan_viewer_slice.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_room_card_hints.dart';

import 'my_work_last_event.dart';

part 'my_work_card_view_model.freezed.dart';

enum MyWorkCardRole { authored, helpOffered, obligation }

enum MyWorkCardKind {
  authoredActive,
  authoredDraft,
  helpOfferedActive,
  authoredFinished,
  helpOfferedFinished,
  authoredArchived,
  helpOfferedArchived,
  obligationActive,
  obligationArchived,
}

enum MyWorkMembershipSource { authored, helpOffered, obligation }

enum MyWorkAttentionChip {
  /// Author: beacon is wrapping up (closure open).
  wrappingUp,

  /// Author: beacon-level "more help needed".
  moreHelpNeeded,
}

@freezed
abstract class MyWorkCardViewModel with _$MyWorkCardViewModel {
  const factory MyWorkCardViewModel({
    required String beaconId,
    required MyWorkCardRole role,
    required MyWorkCardKind kind,
    required Beacon beacon,
    @Default('') String offerHelpMessage,
    CoordinationResponseType? authorResponseType,
    @Default(CommitmentStakeState.none) CommitmentStakeState stakeState,
    @Default([]) List<Profile> forwarderSenders,
    @Default(false) bool showReviewHelpOffersCta,
    @Default(false) bool showCloseNowCta,
    @Default(false) bool showArchiveAffordance,
    MyWorkAttentionChip? attentionChip,

    /// The viewer's next move in the admitted room (Phase 6 summary line).
    @Default('') String roomNextMove,

    /// Room current line for the NOW row (V2 inbox room context batch).
    @Default('') String roomCurrentLine,

    /// Open blocker title for NOW subline (V2 inbox room context batch).
    @Default('') String roomOpenBlockerTitle,

    /// Open blocker cue for phase / YOU blocked segment (V2 batch).
    OpenBlockerCue? roomOpenBlocker,

    /// Help-offered cards: `beacon_help_offers.updated_at` from My Work fetch.
    DateTime? helpOfferRowUpdatedAt,

    /// Help-offered cards: `beacon_help_offer_coordinations.updated_at`.
    DateTime? authorCoordinationUpdatedAt,

    /// Help-offered cards: who wrote that coordination response — the author
    /// or a steward (#507).
    Profile? coordinationAuthor,

    /// Latest meaningful coordination-log event (V2 batch).
    MyWorkLastEvent? lastActivityEvent,

    /// Explicit YOU-line counts for My Work cards.
    CoordinationResponsibility? youResponsibility,

    /// Server display-status projection (author gate fields).
    BeaconDisplayStatusDto? displayStatus,

    /// Membership sources that keep this Request in My Work scope.
    @Default(<MyWorkMembershipSource>{}) Set<MyWorkMembershipSource> sources,

    /// Viewer archive preference (orthogonal to [kind]; UNIT 05 reads this).
    @Default(false) bool viewerArchived,

    /// The viewer's plan steps and pending changes (#220 §5.8; V2 batch).
    PlanViewerSlice? planSlice,

    /// U087 — latest change in the discussion (message or system line,
    /// next-step edit, logged event such as a status change); V2 batch.
    DateTime? roomLastActivityAt,

    /// U087 — the latest member message, for the card's "latest" line.
    @Default('') String roomLatestMessageText,
    @Default('') String roomLatestMessageAuthorId,
    @Default('') String roomLatestMessageAuthorName,
    DateTime? roomLatestMessageAt,

    /// #498 — what the latest message carries when it has no text (`image`,
    /// `file`, `poll`, `fact`); empty for a text message.
    @Default('') String roomLatestMessageKind,

    /// U087 — unread discussion messages (the same count the header showed
    /// as "+N"), shown on the "latest" line.
    @Default(0) int roomUnreadCount,

    /// The viewer's server read watermark the unread count was taken at, so
    /// a newer local read clears it without a refetch.
    DateTime? roomLastSeenAt,

    /// #487 — the Request's immediate parent, when the viewer may read it
    /// (V2 batch); empty for a top-level Request. Shown as "Part of: …".
    @Default('') String parentBeaconId,
    @Default('') String parentTitle,
  }) = _MyWorkCardViewModel;

  const MyWorkCardViewModel._();

  bool get isArchived => viewerArchived;

  /// Admitted room coordination summary line (Phase 6). U087 — with a
  /// "latest" line the unread count rides on it ("2 new"); without one it
  /// stays here as "+N". A photo-, file-, poll- or fact-only message has a
  /// line too (#498).
  String get roomInboxSubtitle => [
    if (roomNextMove.isNotEmpty) roomNextMove,
    if (roomUnreadCount > 0 && !hasRoomLatestMessage) '+$roomUnreadCount',
  ].join(' · ');

  /// U087/#498 — whether the card shows a "latest" line: a message with text,
  /// or one with only a photo, file, poll or quoted fact.
  bool get hasRoomLatestMessage => isRoomLatestMessageShown(
    text: roomLatestMessageText,
    kind: roomLatestMessageKind,
  );

  /// U087 — what "Recent" orders by: the latest of when the Request entered
  /// the list ([entryAt]), the discussion's last activity and the latest
  /// logged event.
  DateTime recentActivityAt(DateTime entryAt) {
    var at = entryAt;
    for (final t in [roomLastActivityAt, lastActivityEvent?.event.createdAt]) {
      if (t != null && t.isAfter(at)) at = t;
    }
    return at;
  }

  bool get isFinishedCard =>
      kind == MyWorkCardKind.authoredFinished ||
      kind == MyWorkCardKind.helpOfferedFinished;
}
