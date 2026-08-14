import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/coordination/helper_offer_response_state.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';

void main() {
  group('deriveHelperOfferResponseState', () {
    test('awaitingAuthor when stake offered and beacon open', () {
      expect(
        deriveHelperOfferResponseState(
          stakeState: CommitmentStakeState.offered,
          authorResponseType: null,
          beaconStatus: BeaconStatus.open,
        ),
        HelperOfferResponseState.awaitingAuthor,
      );
    });

    test('awaitingAuthor when stake none and beacon open', () {
      expect(
        deriveHelperOfferResponseState(
          stakeState: CommitmentStakeState.none,
          authorResponseType: null,
          beaconStatus: BeaconStatus.enoughHelp,
        ),
        HelperOfferResponseState.awaitingAuthor,
      );
    });

    test('accepted when stake acknowledged', () {
      expect(
        deriveHelperOfferResponseState(
          stakeState: CommitmentStakeState.acknowledged,
          authorResponseType: CoordinationResponseType.useful,
          beaconStatus: BeaconStatus.open,
        ),
        HelperOfferResponseState.accepted,
      );
    });

    test('declined when author response is not acknowledging', () {
      expect(
        deriveHelperOfferResponseState(
          stakeState: CommitmentStakeState.offered,
          authorResponseType: CoordinationResponseType.notSuitable,
          beaconStatus: BeaconStatus.open,
        ),
        HelperOfferResponseState.declined,
      );
    });

    test('softened when stake softened', () {
      expect(
        deriveHelperOfferResponseState(
          stakeState: CommitmentStakeState.softened,
          authorResponseType: CoordinationResponseType.useful,
          beaconStatus: BeaconStatus.open,
        ),
        HelperOfferResponseState.softened,
      );
    });

    test('participationEnded when stake released', () {
      expect(
        deriveHelperOfferResponseState(
          stakeState: CommitmentStakeState.released,
          authorResponseType: CoordinationResponseType.useful,
          beaconStatus: BeaconStatus.open,
        ),
        HelperOfferResponseState.participationEnded,
      );
    });

    test('exited when stake exited', () {
      expect(
        deriveHelperOfferResponseState(
          stakeState: CommitmentStakeState.exited,
          authorResponseType: CoordinationResponseType.useful,
          beaconStatus: BeaconStatus.open,
        ),
        HelperOfferResponseState.exited,
      );
    });

    test('closedWithoutResponse when reviewOpen without author response', () {
      expect(
        deriveHelperOfferResponseState(
          stakeState: CommitmentStakeState.offered,
          authorResponseType: null,
          beaconStatus: BeaconStatus.reviewOpen,
        ),
        HelperOfferResponseState.closedWithoutResponse,
      );
    });

    test('released beats stale useful author response (not accepted)', () {
      expect(
        deriveHelperOfferResponseState(
          stakeState: CommitmentStakeState.released,
          authorResponseType: CoordinationResponseType.useful,
          beaconStatus: BeaconStatus.closed,
        ),
        isNot(HelperOfferResponseState.accepted),
      );
      expect(
        deriveHelperOfferResponseState(
          stakeState: CommitmentStakeState.released,
          authorResponseType: CoordinationResponseType.useful,
          beaconStatus: BeaconStatus.closed,
        ),
        HelperOfferResponseState.participationEnded,
      );
    });

    test('exited beats stale useful author response (not accepted)', () {
      expect(
        deriveHelperOfferResponseState(
          stakeState: CommitmentStakeState.exited,
          authorResponseType: CoordinationResponseType.useful,
          beaconStatus: BeaconStatus.open,
        ),
        isNot(HelperOfferResponseState.accepted),
      );
      expect(
        deriveHelperOfferResponseState(
          stakeState: CommitmentStakeState.exited,
          authorResponseType: CoordinationResponseType.useful,
          beaconStatus: BeaconStatus.open,
        ),
        HelperOfferResponseState.exited,
      );
    });
  });
}
