import 'package:tentura/domain/entity/room_baton_data.dart';

/// The outcome of the author's «Who'll take it?» pick (`RoomCubit.batonSelect`).
sealed class BatonSelectResult {
  const BatonSelectResult();
}

/// The pick did not go through (the error has been shown).
final class BatonSelectFailed extends BatonSelectResult {
  const BatonSelectFailed();
}

/// The pick went through. [taker] is the person the server resolved (null
/// only when its answer could not be read). [planStepOffer] is set when the
/// author may be offered a plan step for it (#479, D9): a Request whose plan
/// they may edit.
final class BatonSelected extends BatonSelectResult {
  const BatonSelected({this.taker, this.planStepOffer});

  final RoomBatonTaker? taker;
  final BatonPlanStepOffer? planStepOffer;
}

/// «Create a plan step with {name}?» after a baton is taken (#479, D9).
///
/// [stepId] is minted once for this offer and reused on every save attempt,
/// so a retry never adds a second step.
final class BatonPlanStepOffer {
  const BatonPlanStepOffer({
    required this.beaconId,
    required this.batonId,
    required this.stepId,
    required this.assigneeId,
    required this.assigneeName,
    required this.title,
  });

  final String beaconId;
  final String batonId;
  final String stepId;
  final String assigneeId;
  final String assigneeName;

  /// Prefill for the step title: the baton's ask (or the quoted message).
  final String title;
}
