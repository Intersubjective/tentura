import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/help_offer_admission_action.dart';

/// Why a help offer is no longer open, as far as the viewer can tell.
///
/// `helpOffersWithCoordination` clears `admissionAction` (and the reasons)
/// on other people's rows for anyone who is not the author, a steward, or
/// the offerer. `status`, `withdrawReason`, `responseType` and `stakeState`
/// stay. Those four are enough: a helper's withdraw writes `withdrawReason`
/// and stake `exited`; the author ending participation writes stake
/// `released` (and, when they were in the discussion, admission `remove`);
/// declining a pending offer writes `notSuitable` and deactivates the row
/// without a withdraw reason. Stake `acknowledged` or `softened` on a
/// deactivated row is the same removal with the admission field stripped.
enum HelpOfferEndKind {
  none,
  withdrew,
  participationEnded,
  declined,
}

HelpOfferEndKind helpOfferEndKind({
  required bool isWithdrawn,
  HelpOfferAdmissionAction? admissionAction,
  CommitmentStakeState stakeState = CommitmentStakeState.none,
  String? withdrawReason,
  CoordinationResponseType? coordinationResponse,
}) {
  final helperWithdrew =
      withdrawReason != null && withdrawReason.trim().isNotEmpty;
  if (helperWithdrew) return HelpOfferEndKind.withdrew;

  if (stakeState == CommitmentStakeState.released ||
      admissionAction == HelpOfferAdmissionAction.remove ||
      (isWithdrawn &&
          (stakeState == CommitmentStakeState.acknowledged ||
              stakeState == CommitmentStakeState.softened))) {
    return HelpOfferEndKind.participationEnded;
  }

  final authorDeclined =
      isWithdrawn &&
      (admissionAction == HelpOfferAdmissionAction.decline ||
          coordinationResponse == CoordinationResponseType.notSuitable);
  if (authorDeclined) return HelpOfferEndKind.declined;

  if (isWithdrawn) return HelpOfferEndKind.withdrew;
  return HelpOfferEndKind.none;
}
