import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';

enum MyWorkOfferResponseState {
  awaitingAuthor,
  accepted,
  declined,
  softened,
  participationEnded,
  exited,
  closedWithoutResponse,
}

MyWorkOfferResponseState deriveMyWorkOfferResponseState({
  required CommitmentStakeState stakeState,
  required CoordinationResponseType? authorResponseType,
  required BeaconStatus beaconStatus,
}) {
  if (stakeState == CommitmentStakeState.released) {
    return MyWorkOfferResponseState.participationEnded;
  }
  if (stakeState == CommitmentStakeState.exited) {
    return MyWorkOfferResponseState.exited;
  }
  if (stakeState == CommitmentStakeState.softened) {
    return MyWorkOfferResponseState.softened;
  }
  if (stakeState == CommitmentStakeState.acknowledged) {
    return MyWorkOfferResponseState.accepted;
  }
  if (authorResponseType == null && !beaconStatus.isOpenFamily) {
    return MyWorkOfferResponseState.closedWithoutResponse;
  }
  if (authorResponseType != null &&
      !authorResponseType.allowsInviteToRoom) {
    return MyWorkOfferResponseState.declined;
  }
  return MyWorkOfferResponseState.awaitingAuthor;
}
