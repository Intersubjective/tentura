import 'package:freezed_annotation/freezed_annotation.dart';

import 'evaluation_value.dart';

part 'evaluation_participant.freezed.dart';

enum EvaluationParticipantRole {
  author,
  committer,
  forwarder,
  formerCommitter,
}

@freezed
abstract class EvaluationParticipant with _$EvaluationParticipant {
  const factory EvaluationParticipant({
    required String userId,
    required String displayName,
    required EvaluationParticipantRole role,
    @Default('') String contributionSummary,
    @Default('') String causalHint,
    @Default('') String imageId,
    /// Server: `full` or `handoff` (forwarder → committer).
    @Default('full') String promptVariant,
    EvaluationValue? currentValue,
    @Default([]) List<String> reasonTags,
    @Default('') String note,
    @Default([]) List<String> acknowledgedHelpTags,
    @Default([]) List<String> acknowledgeableHelpTags,
    @Default(0) int maxAcknowledgedHelpTags,
    @Default(false) bool isSubmitted,
    @Default(false) bool isOptional,
    @Default(-1) int rowStatus,
    DateTime? committedAt,
    @Default('') String offerMessage,
    String? forwarderDisplayName,
  }) = _EvaluationParticipant;

  const EvaluationParticipant._();

  bool get hasAnswered => currentValue != null;

  /// A stored row exists for this target, in any state the server counts as an
  /// answer. Mirrors evaluationFinalize's readiness predicate: draft(0),
  /// submitted(1), final(2). Do not widen this to `rowStatus >= 0`.
  bool get hasAnswer => rowStatus == 0 || rowStatus == 1 || rowStatus == 2;
}
