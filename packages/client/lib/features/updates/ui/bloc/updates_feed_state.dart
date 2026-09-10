import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/features/updates/domain/entity/prompt_projection.dart';
import 'package:tentura/ui/bloc/state_base.dart';

part 'updates_feed_state.freezed.dart';

@freezed
abstract class UpdatesFeedState extends StateBase with _$UpdatesFeedState {
  const factory UpdatesFeedState({
    @Default(AttentionView.all) AttentionView view,
    @Default('') String searchText,
    @Default(AttentionSummary()) AttentionSummary summary,
    @Default(<AttentionReceipt>[]) List<AttentionReceipt> items,
    @Default(<String, PromptProjection>{})
    Map<String, PromptProjection> promptProjections,
    @Default(false) bool hasNextPage,
    @Default(StateIsLoading()) StateStatus status,
    Object? refreshError,
    Object? actionError,
  }) = _UpdatesFeedState;

  const UpdatesFeedState._();

  bool get isEmpty => items.isEmpty;
  bool get hasRefreshError => refreshError != null;
  bool get hasActionError => actionError != null;

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
