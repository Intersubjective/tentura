import 'package:test/test.dart';

import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/coordination/coordination_response_type.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';

import '../../support/commitment_gates_harness.dart';

// #401: a helper the author removes must stop counting as an active offer
// (the request no longer reads "Coordinating the plan"), and letting them back
// in must count them again.
Matcher _throwsCoordination(HelpOfferCoordinationExceptionCode code) => throwsA(
  isA<HelpOfferCoordinationException>().having(
    (e) => (e.code as HelpOfferCoordinationExceptionCodes).exceptionCode,
    'code',
    code,
  ),
);

void main() {
  group('removal deactivates the offer, re-admission re-activates it', () {
    test('remove drops the active count; accepting again restores it',
        () async {
      final h = CommitmentGatesHarness();
      await h.offerHelp();
      await h.acceptOffer();
      expect(await h.activeOfferCount(), 1);

      await h.removeFromRoom();
      expect(await h.activeOfferCount(), 0);
      final removed = (await h.helpOfferRepo.fetchAllByBeaconId(
        h.beaconId,
      )).single;
      expect(removed.isWithdrawn, isTrue);
      expect(removed.withdrawReason, isNull);

      await h.acceptOffer();
      expect(await h.activeOfferCount(), 1);
      final events = await h.commitmentRepo.eventsForPair(
        beaconId: h.beaconId,
        userId: h.helperId,
      );
      expect(
        events.map((e) => e.kind),
        containsAllInOrder([
          CommitmentEventKind.removedFromChat,
          CommitmentEventKind.readmittedToChat,
        ]),
      );
    });

    test('inviting a removed helper back via setCoordinationResponse '
        're-activates the offer', () async {
      final h = CommitmentGatesHarness();
      await h.offerHelp();
      await h.acceptOffer();
      await h.removeFromRoom();
      expect(await h.activeOfferCount(), 0);

      await h.setCoordinationResponse(
        responseType: CoordinationResponseType.useful.smallintValue,
        inviteToRoom: true,
      );
      expect(await h.activeOfferCount(), 1);
    });

    test('remove, re-admit, remove again keeps the count right', () async {
      final h = CommitmentGatesHarness();
      await h.offerHelp();
      await h.acceptOffer();
      await h.removeFromRoom();
      await h.acceptOffer();
      await h.removeFromRoom();
      expect(await h.activeOfferCount(), 0);
      await h.acceptOffer();
      expect(await h.activeOfferCount(), 1);
    });

    test('a removed helper who then withdrew cannot be accepted back',
        () async {
      final h = CommitmentGatesHarness();
      await h.offerHelp();
      await h.acceptOffer();
      await h.removeFromRoom();
      await h.withdrawOffer();

      await expectLater(
        h.acceptOffer(),
        _throwsCoordination(
          HelpOfferCoordinationExceptionCode.helpOfferNotActive,
        ),
      );
      expect(await h.activeOfferCount(), 0);
    });

    test('a declined offer still cannot be accepted', () async {
      final h = CommitmentGatesHarness();
      await h.offerHelp();
      await h.declineOffer();

      await expectLater(
        h.acceptOffer(),
        _throwsCoordination(
          HelpOfferCoordinationExceptionCode.helpOfferNotActive,
        ),
      );
      expect(await h.activeOfferCount(), 0);
    });
  });
}
