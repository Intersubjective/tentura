import 'package:freezed_annotation/freezed_annotation.dart';

import 'evaluation_value.dart';

part 'evaluation_participant.freezed.dart';

enum EvaluationParticipantRole {
  author,
  committer,
  forwarder,
}

@freezed
abstract class EvaluationParticipant with _$EvaluationParticipant {
  const factory EvaluationParticipant({
    required String userId,
    required String title,
    @Default('') String imageId,
    required EvaluationParticipantRole role,
    required String contributionSummary,
    required String causalHint,
    EvaluationValue? currentValue,
    @Default([]) List<String> reasonTags,
    @Default('') String note,
  }) = _EvaluationParticipant;

  const EvaluationParticipant._();

  bool get hasAnswered => currentValue != null;
}
