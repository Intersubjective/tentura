import 'package:tentura/features/evaluation/domain/entity/evaluation_participant.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_summary.dart';
import 'package:tentura/features/evaluation/domain/entity/review_window_info.dart';
import 'package:tentura/ui/bloc/state_base.dart';

part 'evaluation_state.freezed.dart';

@Freezed(makeCollectionsUnmodifiable: false)
abstract class EvaluationState extends StateBase with _$EvaluationState {
  const factory EvaluationState({
    required String beaconId,
    @Default('') String beaconTitle,
    @Default(false) bool isDraftMode,
    @Default([]) List<EvaluationParticipant> participants,
    @Default(null) ReviewWindowInfo? windowInfo,
    @Default(null) EvaluationSummary? summary,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _EvaluationState;

  const EvaluationState._();

  int get reviewedCount => isDraftMode
      ? participants.where((p) => p.hasAnswered).length
      : participants.where((p) => p.isSubmitted).length;

  int get totalCount => participants.length;

  Iterable<EvaluationParticipant> get requiredParticipants =>
      participants.where((p) => !p.isOptional);

  Iterable<EvaluationParticipant> get optionalParticipants =>
      participants.where((p) => p.isOptional);

  /// A package whose targets are all optional is finalizable with nothing
  /// answered: intended, because sending settles the reviewer's own
  /// obligation (#180).
  bool get canFinalize {
    if (participants.isEmpty) return false;
    if (isDraftMode) {
      return participants.every((p) => p.hasAnswered);
    }
    return requiredParticipants.every((p) => p.hasAnswer);
  }
}
