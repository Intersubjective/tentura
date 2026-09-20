import 'package:tentura/features/evaluation/domain/entity/evaluation_participant.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_summary.dart';
import 'package:tentura/features/evaluation/domain/entity/review_window_info.dart';
import 'package:tentura/features/evaluation/domain/review_package_state.dart';
import 'package:tentura/ui/bloc/state_base.dart';

part 'evaluation_state.freezed.dart';

@Freezed(makeCollectionsUnmodifiable: false)
abstract class EvaluationState extends StateBase with _$EvaluationState {
  const factory EvaluationState({
    required String beaconId,
    @Default('') String beaconTitle,
    @Default(false) bool isDraftMode,
    @Default(true) bool beaconIsInReview,
    @Default(false) bool beaconIsClosed,
    @Default([]) List<EvaluationParticipant> participants,
    /// True once a read succeeded and the screen can show the package's real
    /// state. A failed or refused load leaves it false, so §4's open-clear
    /// never fires on a screen that showed nothing.
    @Default(false) bool reviewContentLoaded,
    @Default(null) ReviewWindowInfo? windowInfo,
    @Default(null) EvaluationSummary? summary,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _EvaluationState;

  const EvaluationState._();

  /// The package state is the primary variable of every review surface (#162):
  /// checklist completeness is only progress and never decides the action.
  ReviewPackageState get packageState => deriveReviewPackageState(
    beaconIsInReview: beaconIsInReview,
    beaconIsClosed: beaconIsClosed,
    hasWindow: windowInfo?.hasWindow ?? false,
    windowComplete: windowInfo?.windowComplete ?? false,
    userReviewStatus: windowInfo?.userReviewStatus,
    sentAt: windowInfo?.sentAt,
    requiredTotal: requiredParticipants.length,
    requiredAnswered: requiredParticipants.where((p) => p.hasAnswer).length,
    totalTargets: participants.length,
  );

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
