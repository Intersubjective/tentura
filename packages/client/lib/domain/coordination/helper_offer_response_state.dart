import 'package:tentura_root/domain/entity/beacon_status.dart';

import '../entity/commitment_stake_state.dart';
import '../entity/coordination_response_type.dart';

enum HelperOfferResponseState {
  awaitingAuthor,
  accepted,
  declined,
  softened,
  participationEnded,
  exited,
  closedWithoutResponse,
}

bool helperOfferResponseStateIsTerminal(HelperOfferResponseState state) =>
    switch (state) {
      HelperOfferResponseState.declined ||
      HelperOfferResponseState.softened ||
      HelperOfferResponseState.participationEnded ||
      HelperOfferResponseState.exited ||
      HelperOfferResponseState.closedWithoutResponse =>
        true,
      _ => false,
    };

bool helperOfferResponseStateHasStandingMessage(
  HelperOfferResponseState? state,
) =>
    state != null &&
    (state == HelperOfferResponseState.awaitingAuthor ||
        helperOfferResponseStateIsTerminal(state));

HelperOfferResponseState deriveHelperOfferResponseState({
  required CommitmentStakeState stakeState,
  required CoordinationResponseType? authorResponseType,
  required BeaconStatus beaconStatus,
}) {
  if (stakeState == CommitmentStakeState.released) {
    return HelperOfferResponseState.participationEnded;
  }
  if (stakeState == CommitmentStakeState.exited) {
    return HelperOfferResponseState.exited;
  }
  if (stakeState == CommitmentStakeState.softened) {
    return HelperOfferResponseState.softened;
  }
  if (stakeState == CommitmentStakeState.acknowledged) {
    return HelperOfferResponseState.accepted;
  }
  if (authorResponseType == null && !beaconStatus.isOpenFamily) {
    return HelperOfferResponseState.closedWithoutResponse;
  }
  if (authorResponseType != null &&
      !authorResponseType.allowsInviteToRoom) {
    return HelperOfferResponseState.declined;
  }
  return HelperOfferResponseState.awaitingAuthor;
}
