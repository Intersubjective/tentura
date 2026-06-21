import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/open_blocker_cue.dart';
import 'package:tentura/domain/entity/profile.dart';

import 'my_work_last_event.dart';

part 'my_work_card_view_model.freezed.dart';

enum MyWorkCardRole { authored, helpOffered }

enum MyWorkCardKind {
  authoredActive,
  authoredDraft,
  helpOfferedActive,
  authoredFinished,
  helpOfferedFinished,
  authoredArchived,
  helpOfferedArchived,
}

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
    @Default([]) List<Profile> forwarderSenders,
    @Default(false) bool showReviewHelpOffersCta,
    @Default(false) bool showReviewCta,
    @Default(false) bool showArchiveAffordance,
    MyWorkAttentionChip? attentionChip,
    /// Author has forwarded this beacon at least once (authored active cards).
    @Default(false) bool authorHasForwardedOnce,

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

    /// Latest message on an active item discussion thread for this beacon.
    DateTime? lastCoordinationItemMessageAt,

    /// Latest meaningful coordination-log event (V2 batch).
    MyWorkLastEvent? lastActivityEvent,

    /// Explicit YOU-line counts for My Work cards.
    CoordinationResponsibility? youResponsibility,
  }) = _MyWorkCardViewModel;

  const MyWorkCardViewModel._();

  bool get isArchived =>
      kind == MyWorkCardKind.authoredArchived ||
      kind == MyWorkCardKind.helpOfferedArchived;

  bool get isFinishedCard =>
      kind == MyWorkCardKind.authoredFinished ||
      kind == MyWorkCardKind.helpOfferedFinished;

  /// Max relevant backend activity for NewStuff (tab dot), in epoch ms.
  int get newStuffActivityEpochMs {
    final b = beacon;
    var max = b.createdAt.millisecondsSinceEpoch;
    if (b.updatedAt.millisecondsSinceEpoch > max) {
      max = b.updatedAt.millisecondsSinceEpoch;
    }
    final cs = b.coordinationStatusUpdatedAt?.millisecondsSinceEpoch;
    if (cs != null && cs > max) {
      max = cs;
    }
    if (role == MyWorkCardRole.helpOffered) {
      final cr = helpOfferRowUpdatedAt?.millisecondsSinceEpoch;
      if (cr != null && cr > max) {
        max = cr;
      }
      final ar = authorCoordinationUpdatedAt?.millisecondsSinceEpoch;
      if (ar != null && ar > max) {
        max = ar;
      }
    }
    final itemMsg = lastCoordinationItemMessageAt?.millisecondsSinceEpoch;
    if (itemMsg != null && itemMsg > max) {
      max = itemMsg;
    }
    return max;
  }
}
