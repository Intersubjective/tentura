import 'package:tentura/domain/attention/attention_dismissible_membership.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/updates/domain/entity/prompt_projection.dart';
import 'package:tentura/ui/bloc/state_base.dart';

part 'updates_feed_state.freezed.dart';

@freezed
abstract class UpdatesFeedState extends StateBase with _$UpdatesFeedState {
  const factory UpdatesFeedState({
    @Default(AttentionView.all) AttentionView view,
    @Default(false) bool firstLoadDone,
    @Default('') String searchText,
    @Default(AttentionSummary()) AttentionSummary summary,

    /// The server's "would Dismiss all take anything" (#258): Read all runs
    /// that same sweep.
    @Default(false) bool sweepEligible,
    @Default(<AttentionReceipt>[]) List<AttentionReceipt> items,
    @Default(<String, PromptProjection>{})
    Map<String, PromptProjection> promptProjections,
    @Default(<String, Profile>{}) Map<String, Profile> actors,
    @Default(false) bool hasNextPage,
    @Default(StateIsLoading()) StateStatus status,
    Object? refreshError,
    Object? actionError,
  }) = _UpdatesFeedState;

  const UpdatesFeedState._();

  bool get isEmpty => items.isEmpty;
  bool get hasRefreshError => refreshError != null;
  bool get hasActionError => actionError != null;

  /// «Read all» has something to do (#258): the sweep would take rows, or a
  /// loaded row on Unread ([isInUnreadView]) is unseen or an
  /// [isReadAllLeftover]. `summary.unreadTotal` is not the gate: it also
  /// counts unanswered forwards, which Read all never clears. Rows off
  /// Unread (Dismiss all clears without reading) do not count.
  bool get canReadAll =>
      sweepEligible ||
      items.any(
        (r) =>
            isInUnreadView(r) &&
            (!r.isSeen || isReadAllLeftover(r, sweepCompleted: false)),
      );

  PromptProjection promptProjectionFor(String subjectId) =>
      promptProjections[subjectId] ?? const PromptProjection.unknown();

  bool canPinInvitePrompt(AttentionReceipt receipt) {
    final subjectId = inviteAcceptedPromptSubjectId(receipt);
    if (subjectId == null) return false;
    return isInvitePromptPinCandidate(
      receipt: receipt,
      projection: promptProjectionFor(subjectId),
    );
  }
}
