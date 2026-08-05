import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/features/my_work/domain/derive_offer_response_state.dart';

void main() {
  group('deriveMyWorkOfferResponseState', () {
    test('awaitingAuthor when stake offered and beacon open', () {
      expect(
        deriveMyWorkOfferResponseState(
          stakeState: CommitmentStakeState.offered,
          authorResponseType: null,
          beaconStatus: BeaconStatus.open,
        ),
        MyWorkOfferResponseState.awaitingAuthor,
      );
    });

    test('awaitingAuthor when stake none and beacon open', () {
      expect(
        deriveMyWorkOfferResponseState(
          stakeState: CommitmentStakeState.none,
          authorResponseType: null,
          beaconStatus: BeaconStatus.enoughHelp,
        ),
        MyWorkOfferResponseState.awaitingAuthor,
      );
    });

    test('accepted when stake acknowledged', () {
      expect(
        deriveMyWorkOfferResponseState(
          stakeState: CommitmentStakeState.acknowledged,
          authorResponseType: CoordinationResponseType.useful,
          beaconStatus: BeaconStatus.open,
        ),
        MyWorkOfferResponseState.accepted,
      );
    });

    test('declined when author response is not acknowledging', () {
      expect(
        deriveMyWorkOfferResponseState(
          stakeState: CommitmentStakeState.offered,
          authorResponseType: CoordinationResponseType.notSuitable,
          beaconStatus: BeaconStatus.open,
        ),
        MyWorkOfferResponseState.declined,
      );
    });

    test('softened when stake softened', () {
      expect(
        deriveMyWorkOfferResponseState(
          stakeState: CommitmentStakeState.softened,
          authorResponseType: CoordinationResponseType.useful,
          beaconStatus: BeaconStatus.open,
        ),
        MyWorkOfferResponseState.softened,
      );
    });

    test('participationEnded when stake released', () {
      expect(
        deriveMyWorkOfferResponseState(
          stakeState: CommitmentStakeState.released,
          authorResponseType: CoordinationResponseType.useful,
          beaconStatus: BeaconStatus.open,
        ),
        MyWorkOfferResponseState.participationEnded,
      );
    });

    test('exited when stake exited', () {
      expect(
        deriveMyWorkOfferResponseState(
          stakeState: CommitmentStakeState.exited,
          authorResponseType: CoordinationResponseType.useful,
          beaconStatus: BeaconStatus.open,
        ),
        MyWorkOfferResponseState.exited,
      );
    });

    test('closedWithoutResponse when reviewOpen without author response', () {
      expect(
        deriveMyWorkOfferResponseState(
          stakeState: CommitmentStakeState.offered,
          authorResponseType: null,
          beaconStatus: BeaconStatus.reviewOpen,
        ),
        MyWorkOfferResponseState.closedWithoutResponse,
      );
    });

    test('released beats stale useful author response (not accepted)', () {
      expect(
        deriveMyWorkOfferResponseState(
          stakeState: CommitmentStakeState.released,
          authorResponseType: CoordinationResponseType.useful,
          beaconStatus: BeaconStatus.closed,
        ),
        isNot(MyWorkOfferResponseState.accepted),
      );
      expect(
        deriveMyWorkOfferResponseState(
          stakeState: CommitmentStakeState.released,
          authorResponseType: CoordinationResponseType.useful,
          beaconStatus: BeaconStatus.closed,
        ),
        MyWorkOfferResponseState.participationEnded,
      );
    });

    test('exited beats stale useful author response (not accepted)', () {
      expect(
        deriveMyWorkOfferResponseState(
          stakeState: CommitmentStakeState.exited,
          authorResponseType: CoordinationResponseType.useful,
          beaconStatus: BeaconStatus.open,
        ),
        isNot(MyWorkOfferResponseState.accepted),
      );
      expect(
        deriveMyWorkOfferResponseState(
          stakeState: CommitmentStakeState.exited,
          authorResponseType: CoordinationResponseType.useful,
          beaconStatus: BeaconStatus.open,
        ),
        MyWorkOfferResponseState.exited,
      );
    });
  });
}
