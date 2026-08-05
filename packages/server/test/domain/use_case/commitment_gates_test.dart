import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/coordination/coordination_response_type.dart';
import 'package:tentura_server/domain/entity/evaluation/beacon_evaluation_record.dart';
import 'package:tentura_server/domain/evaluation/evaluation_participant_role.dart';
import 'package:tentura_server/domain/evaluation/evaluation_visibility_rules.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';

import '../../support/commitment_gates_harness.dart';

Set<(String, String)> _visibilityPairSet(List<EvaluationVisibilityPair> vis) => {
      for (final p in vis) (p.evaluatorId, p.participantId),
    };

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

    group('Close and review window', () {
      test('10 — accept then withdraw after 30h opens review window on Close',
          () async {
        final harness = CommitmentGatesHarness();
        await harness.offerHelp();
        await harness.acceptOffer();
        await harness.withdrawOffer(advanceBefore: const Duration(hours: 30));

        final result = await harness.evaluationCase.beaconClose(
          beaconId: harness.beaconId,
          userId: harness.authorId,
          expectedRequiresReviewWindow: true,
        );

        expect(result.status, BeaconStatus.reviewOpen.smallintValue);
        expect(harness.evalRepo.insertReviewWindowCalls, 1);
      });

      test(
        '11 — departed helper appears as formerCommitter in review composition',
        () async {
          final harness = CommitmentGatesHarness();
          await harness.offerHelp();
          await harness.acceptOffer();
          await harness.withdrawOffer(advanceBefore: const Duration(hours: 30));

          final graph = await harness.graphBuilder.build(
            beaconId: harness.beaconId,
            authorId: harness.authorId,
            preClosure: false,
          );

          final helper = graph.participants.singleWhere(
            (p) => p.userId == harness.helperId,
          );
          expect(helper.role, EvaluationParticipantRole.formerCommitter);
          expect(helper.role.dbValue, 3);
        },
      );
    });

    group('closeNow', () {
      test('12 — incomplete formerCommitter review does not block closeNow',
          () async {
        final harness = CommitmentGatesHarness(
          initialStatus: BeaconStatus.reviewOpen,
        );
        harness.evalRepo
          ..reviewWindowResult = harness.openReviewWindow()
          ..participantsResult = [
            BeaconEvaluationParticipantRecord(
              beaconId: harness.beaconId,
              userId: harness.authorId,
              role: EvaluationParticipantRole.author.dbValue,
              contributionSummary: 'author',
              causalHint: 'h',
            ),
            BeaconEvaluationParticipantRecord(
              beaconId: harness.beaconId,
              userId: harness.helperId,
              role: EvaluationParticipantRole.formerCommitter.dbValue,
              contributionSummary: 'former',
              causalHint: 'h',
            ),
          ]
          ..reviewStatusesResult = {
            harness.authorId: 2,
            harness.helperId: 1,
          };

        final result = await harness.evaluationCase.closeNow(
          beaconId: harness.beaconId,
          userId: harness.authorId,
        );

        expect(result.status, BeaconStatus.closed.smallintValue);
        expect(harness.reviewFinalization.closeAndFinalizeCalls, isNotEmpty);
      });

      test('13 — incomplete current committer review blocks closeNow', () async {
        final harness = CommitmentGatesHarness(
          initialStatus: BeaconStatus.reviewOpen,
        );
        harness.evalRepo
          ..reviewWindowResult = harness.openReviewWindow()
          ..participantsResult = [
            BeaconEvaluationParticipantRecord(
              beaconId: harness.beaconId,
              userId: harness.authorId,
              role: EvaluationParticipantRole.author.dbValue,
              contributionSummary: 'author',
              causalHint: 'h',
            ),
            BeaconEvaluationParticipantRecord(
              beaconId: harness.beaconId,
              userId: harness.helperId,
              role: EvaluationParticipantRole.committer.dbValue,
              contributionSummary: 'helper',
              causalHint: 'h',
            ),
          ]
          ..reviewStatusesResult = {
            harness.authorId: 2,
            harness.helperId: 1,
          };

        await expectLater(
          harness.evaluationCase.closeNow(
            beaconId: harness.beaconId,
            userId: harness.authorId,
          ),
          throwsA(
            isA<EvaluationException>().having(
              (e) => e.code.codeNumber,
              'codeNumber',
              const EvaluationExceptionCodes(
                EvaluationExceptionCode.notEligible,
              ).codeNumber,
            ),
          ),
        );
        expect(harness.reviewFinalization.closeAndFinalizeCalls, isEmpty);
      });
    });

    group('Reopen limit', () {
      test('14 — second reopen throws reopen limit error', () async {
        final harness = CommitmentGatesHarness(
          initialStatus: BeaconStatus.reviewOpen,
          reviewReopenCount: 1,
        );
        harness.evalRepo.reviewWindowResult = harness.openReviewWindow();

        await expectLater(
          harness.evaluationCase.reopenFromReview(
            beaconId: harness.beaconId,
            userId: harness.authorId,
          ),
          throwsA(
            isA<EvaluationException>().having(
              (e) => e.description,
              'description',
              'Reopen limit reached',
            ),
          ),
        );
      });
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

    group('Close branch alignment (P3.11)', () {
      test(
        '17 — Close after accept→withdraw(30h) with client-shaped expected does not throw closeBranchConflict',
        () async {
          final harness = CommitmentGatesHarness();
          await harness.offerHelp();
          await harness.acceptOffer();
          await harness.withdrawOffer(advanceBefore: const Duration(hours: 30));

          await expectLater(
            harness.evaluationCase.beaconClose(
              beaconId: harness.beaconId,
              userId: harness.authorId,
              expectedRequiresReviewWindow: true,
            ),
            completes,
          );

          expect(harness.beaconRepo.beacon.status, BeaconStatus.reviewOpen);
        },
      );

      test(
        '18 — scenario-17 composition gives formerCommitter visibility per P3.3',
        () async {
          final harness = CommitmentGatesHarness();
          await harness.offerHelp(userId: harness.helperId);
          await harness.acceptOffer(userId: harness.helperId);
          await harness.offerHelp(userId: harness.helper2Id);
          await harness.acceptOffer(userId: harness.helper2Id);
          await harness.withdrawOffer(
            userId: harness.helperId,
            advanceBefore: const Duration(hours: 30),
          );

          final graph = await harness.graphBuilder.build(
            beaconId: harness.beaconId,
            authorId: harness.authorId,
            preClosure: false,
          );

          final former = graph.participants.singleWhere(
            (p) => p.userId == harness.helperId,
          );
          expect(former.role, EvaluationParticipantRole.formerCommitter);
          expect(former.role.dbValue, 3);

          final visibility = buildEvaluationVisibility(
            authorId: harness.authorId,
            participants: [
              for (final p in graph.participants)
                EvaluationVisibilityParticipant(
                  userId: p.userId,
                  role: p.role,
                ),
            ],
            latestEdgeToCommitter: const {},
          );

          expect(
            _visibilityPairSet(visibility),
            containsAll({
              (harness.authorId, harness.helperId),
              (harness.helperId, harness.authorId),
              (harness.helper2Id, harness.helperId),
              (harness.helperId, harness.helper2Id),
            }),
          );
        },
      );
    });
  });
}
