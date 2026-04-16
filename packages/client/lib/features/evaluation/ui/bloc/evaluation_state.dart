
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

  int get reviewedCount =>
      participants.where((p) => p.currentValue != null).length;

  int get totalCount => participants.length;

  bool get canFinalize =>
      participants.isNotEmpty &&
      participants.every((p) => p.currentValue != null);
}
