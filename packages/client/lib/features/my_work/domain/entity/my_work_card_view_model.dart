import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/profile.dart';

part 'my_work_card_view_model.freezed.dart';

enum MyWorkCardRole { authored, committed }

enum MyWorkCardKind {
  authoredActive,
  authoredDraft,
  committedActive,
  authoredClosed,
  committedClosed,
}

enum MyWorkAttentionChip {
  /// Author: commitments waiting for review (beacon-level signal).
  reviewPending,

  /// Author: beacon in closed-review-open (evaluation window).
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
    @Default('') String commitMessage,
    CoordinationResponseType? authorResponseType,
    @Default([]) List<Profile> forwarderSenders,
    @Default(false) bool showReviewCommitmentsCta,
    @Default(false) bool showReadyForReviewChip,
    @Default(false) bool showReviewCta,
    @Default(false) bool showArchiveAffordance,
    MyWorkAttentionChip? attentionChip,
    /// Author has forwarded this beacon at least once (authored active cards).
    @Default(false) bool authorHasForwardedOnce,
  }) = _MyWorkCardViewModel;

  const MyWorkCardViewModel._();

  bool get isArchived =>
      kind == MyWorkCardKind.authoredClosed ||
      kind == MyWorkCardKind.committedClosed;
}
