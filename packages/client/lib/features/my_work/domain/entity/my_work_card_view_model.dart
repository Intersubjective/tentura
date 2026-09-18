import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_display_status_dto.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/open_blocker_cue.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/evaluation/domain/review_package_state.dart';

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
  /// Author: beacon in review window (Wrapping up).
  reviewWindowOpen,

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
    @Default(false) bool showReviewCta,
    @Default(false) bool showCloseNowCta,

    /// Viewer's review package on a reviewOpen card; null until the batch
    /// window read enriches the card.
    ReviewPackageState? reviewPackageState,

    /// Window-level: every required package is in (author waiting copy).
    @Default(false) bool reviewAllRequiredSent,
    @Default(false) bool showArchiveAffordance,
    MyWorkAttentionChip? attentionChip,

    /// Admitted room coordination summary line (Phase 6).
    @Default('') String roomInboxSubtitle,

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
  }) = _MyWorkCardViewModel;

  const MyWorkCardViewModel._();

  bool get isArchived => viewerArchived;

  bool get isFinishedCard =>
      kind == MyWorkCardKind.authoredFinished ||
      kind == MyWorkCardKind.helpOfferedFinished;
}
