import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/coordination/helper_offer_response_state.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';

export 'package:tentura/domain/coordination/helper_offer_response_state.dart'
    show
        HelperOfferResponseState,
        deriveHelperOfferResponseState,
        helperOfferResponseStateHasStandingMessage,
        helperOfferResponseStateIsTerminal;

typedef MyWorkOfferResponseState = HelperOfferResponseState;

MyWorkOfferResponseState deriveMyWorkOfferResponseState({
  required CommitmentStakeState stakeState,
  required CoordinationResponseType? authorResponseType,
  required BeaconStatus beaconStatus,
}) =>
    deriveHelperOfferResponseState(
      stakeState: stakeState,
      authorResponseType: authorResponseType,
      beaconStatus: beaconStatus,
    );
