import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/coordination/coordination_response_type.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';

import '../../support/commitment_gates_harness.dart';

void main() {
  group('P3.12 commitment gate scenarios', () {
    group('Cancel gate', () {
      test('1 — offer without response allows Cancel', () async {
        final harness = CommitmentGatesHarness();
        await harness.offerHelp();

        final result = await harness.beaconCase.beaconCancel(
          beaconId: harness.beaconId,
          userId: harness.authorId,
        );

        expect(result.status, BeaconStatus.cancelled.smallintValue);
      });

      test('2 — offer plus accept forbids Cancel', () async {
        final harness = CommitmentGatesHarness();
        await harness.offerHelp();
        await harness.acceptOffer();

        await expectLater(
          harness.beaconCase.beaconCancel(
            beaconId: harness.beaconId,
            userId: harness.authorId,
          ),
          throwsA(
            isA<EvaluationException>().having(
              (e) => e.code.codeNumber,
              'codeNumber',
              const EvaluationExceptionCodes(
                EvaluationExceptionCode.beaconNotClosable,
              ).codeNumber,
            ),
          ),
        );
      });

      test('3 — accept then withdraw after 30h still forbids Cancel', () async {
        final harness = CommitmentGatesHarness();
        await harness.offerHelp();
        await harness.acceptOffer();
        await harness.withdrawOffer(advanceBefore: const Duration(hours: 30));

        await expectLater(
          harness.beaconCase.beaconCancel(
            beaconId: harness.beaconId,
            userId: harness.authorId,
          ),
          throwsA(
            isA<EvaluationException>().having(
              (e) => e.description,
              'description',
              'Cannot cancel a request that ever had a committer',
            ),
          ),
        );
      });

      test('4 — accept then withdraw within grace allows Cancel', () async {
        final harness = CommitmentGatesHarness();
        await harness.offerHelp();
        await harness.acceptOffer();
        await harness.withdrawOffer(advanceBefore: const Duration(hours: 1));

        final result = await harness.beaconCase.beaconCancel(
          beaconId: harness.beaconId,
          userId: harness.authorId,
        );

        expect(result.status, BeaconStatus.cancelled.smallintValue);
      });
    });

    group('Delete gate', () {
      test('5 — accept then withdraw after 30h forbids Delete', () async {
        final harness = CommitmentGatesHarness();
        await harness.offerHelp();
        await harness.acceptOffer();
        await harness.withdrawOffer(advanceBefore: const Duration(hours: 30));

        await expectLater(
          harness.beaconCase.deleteById(
            beaconId: harness.beaconId,
            userId: harness.authorId,
          ),
          throwsA(
            isA<EvaluationException>().having(
              (e) => e.description,
              'description',
              'Cannot delete a request that ever had a committer',
            ),
          ),
        );
      });

      test('6 — accept then user-block cleanup forbids Delete', () async {
        final harness = CommitmentGatesHarness();
        await harness.offerHelp();
        await harness.acceptOffer();
        await harness.blockHelper();

        expect(
          harness.commitmentRepo.recordCalls.map((c) => c.kind),
          contains(CommitmentEventKind.blockedCleanup),
        );

        await expectLater(
          harness.beaconCase.deleteById(
            beaconId: harness.beaconId,
            userId: harness.authorId,
          ),
          throwsA(isA<EvaluationException>()),
        );
      });
    });

    group('Coordination invariants', () {
      test('7 — decline after accept throws commitmentAlreadyAcknowledged',
          () async {
        final harness = CommitmentGatesHarness();
        await harness.offerHelp();
        await harness.acceptOffer();

        await expectLater(
          harness.declineOffer(),
          throwsA(
            isA<HelpOfferCoordinationException>().having(
              (e) =>
                  (e.code as HelpOfferCoordinationExceptionCodes).exceptionCode,
              'code',
              HelpOfferCoordinationExceptionCode.commitmentAlreadyAcknowledged,
            ),
          ),
        );
      });

      test(
        '8 — setCoordinationResponse(notSuitable) after accept throws commitmentAlreadyAcknowledged',
        () async {
          final harness = CommitmentGatesHarness();
          await harness.offerHelp();
          await harness.acceptOffer();

          await expectLater(
            harness.setCoordinationResponse(
              responseType: CoordinationResponseType.notSuitable.smallintValue,
            ),
            throwsA(
              isA<HelpOfferCoordinationException>().having(
                (e) =>
                    (e.code as HelpOfferCoordinationExceptionCodes)
                        .exceptionCode,
                'code',
                HelpOfferCoordinationExceptionCode
                    .commitmentAlreadyAcknowledged,
              ),
            ),
          );
        },
      );

      test(
        '9 — notSuitable with inviteToRoom throws admissionRequiresAcknowledgement',
        () async {
          final harness = CommitmentGatesHarness();
          await harness.offerHelp();

          await expectLater(
            harness.setCoordinationResponse(
              responseType: CoordinationResponseType.notSuitable.smallintValue,
              inviteToRoom: true,
            ),
            throwsA(
              isA<HelpOfferCoordinationException>().having(
                (e) =>
                    (e.code as HelpOfferCoordinationExceptionCodes)
                        .exceptionCode,
                'code',
                HelpOfferCoordinationExceptionCode
                    .admissionRequiresAcknowledgement,
              ),
            ),
          );
        },
      );
    });

    group('Withdraw in Wrapping up', () {
      test('15 — beaconWithdraw in reviewOpen throws beaconWithdrawForbidden',
          () async {
        final harness = CommitmentGatesHarness();
        await harness.offerHelp();
        harness.beaconRepo.beacon = harness.beaconRepo.beacon.copyWith(
          status: BeaconStatus.reviewOpen,
        );

        await expectLater(
          harness.helpOfferCase.withdraw(
            beaconId: harness.beaconId,
            userId: harness.helperId,
            withdrawReason: 'other',
          ),
          throwsA(
            isA<HelpOfferCoordinationException>().having(
              (e) =>
                  (e.code as HelpOfferCoordinationExceptionCodes).exceptionCode,
              'code',
              HelpOfferCoordinationExceptionCode.beaconWithdrawForbidden,
            ),
          ),
        );
      });
    });

    group('D13 release reversibility', () {
      test(
        '16 — release then setCoordinationResponse(useful) restores current stake',
        () async {
          final harness = CommitmentGatesHarness();
          await harness.offerHelp();
          await harness.acceptOffer();
          await harness.recordReleasedByAuthor();

          await harness.setCoordinationResponse(
            responseType: CoordinationResponseType.useful.smallintValue,
          );

          expect(await harness.currentStakeIsAcknowledged(), isTrue);
          final kinds = (await harness.commitmentRepo.eventsForPair(
            beaconId: harness.beaconId,
            userId: harness.helperId,
          ))
              .map((e) => e.kind)
              .toList();
          expect(kinds, contains(CommitmentEventKind.releasedByAuthor));
          expect(kinds, contains(CommitmentEventKind.acknowledged));
        },
      );
    });
  });
}
