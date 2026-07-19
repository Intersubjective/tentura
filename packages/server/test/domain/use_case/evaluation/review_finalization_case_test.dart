import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/entity/review_close_snapshot.dart';
import 'package:tentura_server/domain/trust/trust_bin.dart';
import 'package:tentura_server/domain/trust/trust_context.dart';
import 'package:tentura_server/domain/trust/trust_source_type.dart';
import 'package:tentura_server/domain/use_case/evaluation/review_finalization_case.dart';

import '../../../support/review_finalization_test_support.dart';

void main() {
  const beaconId = 'B-finalize01';
  const authorId = 'U-author';
  const committerId = 'U-committer';
  const forwarderId = 'U-forwarder';

  late FakeEvaluationRepo evalRepo;
  late FakeForwardEdges forwardEdges;
  late FakeHelpOffers helpOffers;
  late RecordingTrustEvidence trustEvidence;
  late ReviewFinalizationCase case_;

  final windowOpened = DateTime.utc(2026, 1, 1);
  final commitmentAt = DateTime.utc(2026, 1, 5);

  setUp(() {
    evalRepo = FakeEvaluationRepo();
    forwardEdges = FakeForwardEdges();
    helpOffers = FakeHelpOffers();
    trustEvidence = RecordingTrustEvidence();

    case_ = buildReviewFinalizationCase(
      evaluationRepo: evalRepo,
      forwardEdges: forwardEdges,
      helpOffers: helpOffers,
      trustEvidence: trustEvidence,
    );

    forwardEdges.edges = [
      ForwardEdgeEntity(
        id: 'F1',
        beaconId: beaconId,
        senderId: authorId,
        recipientId: forwarderId,
        createdAt: DateTime.utc(2026, 1, 2),
        batchId: 'B1',
      ),
      ForwardEdgeEntity(
        id: 'F2',
        beaconId: beaconId,
        senderId: forwarderId,
        recipientId: committerId,
        createdAt: DateTime.utc(2026, 1, 3),
        parentEdgeId: 'F1',
        batchId: 'B2',
      ),
    ];

    helpOffers.offers = [
      HelpOfferEntity(
        beaconId: beaconId,
        userId: committerId,
        createdAt: commitmentAt,
        updatedAt: commitmentAt,
      ),
    ];

    evalRepo.snapshotOnClose = ReviewCloseSnapshot(
      beaconId: beaconId,
      beaconAuthorId: authorId,
      windowOpenedAt: windowOpened,
      finalizedEvaluations: [
        const FinalizedEvaluation(
          evaluatorId: authorId,
          evaluatedUserId: committerId,
          value: 5,
        ),
        const FinalizedEvaluation(
          evaluatorId: committerId,
          evaluatedUserId: authorId,
          value: 4,
        ),
      ],
    );
  });

  test('closeAndFinalize records commitment and forward evidence', () async {
    final ok = await case_.closeAndFinalize(beaconId, reason: 'expired');
    expect(ok, isTrue);
    expect(trustEvidence.recorded, isNotEmpty);

    final commitmentItems = trustEvidence.recorded
        .expand((b) => b.items)
        .where((i) => i.context == TrustContext.commitment)
        .toList();
    expect(commitmentItems, isNotEmpty);
    expect(
      commitmentItems.any(
        (i) =>
            i.sourceType == TrustSourceType.finalizedRequestEvaluation &&
            i.bin == TrustBin.good,
      ),
      isTrue,
    );

    final forwardItems = trustEvidence.recorded
        .expand((b) => b.items)
        .where((i) => i.context == TrustContext.forward)
        .toList();
    expect(forwardItems, isNotEmpty);
    expect(
      forwardItems.any(
        (i) =>
            i.sourceType == TrustSourceType.propagatedAuthorEvaluatedCommitment,
      ),
      isTrue,
    );
  });

  test('re-close is idempotent when forward episode already exists', () async {
    await case_.closeAndFinalize(beaconId, reason: 'expired');
    final firstForwardCount = trustEvidence.recorded
        .expand((b) => b.items)
        .where((i) => i.context == TrustContext.forward)
        .length;

    trustEvidence.forwardAlreadyRecorded = true;
    evalRepo.snapshotOnClose = ReviewCloseSnapshot(
      beaconId: beaconId,
      beaconAuthorId: authorId,
      windowOpenedAt: windowOpened,
      finalizedEvaluations: [
        const FinalizedEvaluation(
          evaluatorId: authorId,
          evaluatedUserId: committerId,
          value: 5,
        ),
      ],
    );

    await case_.closeAndFinalize(beaconId, reason: 'retry');
    final secondForwardCount = trustEvidence.recorded
        .expand((b) => b.items)
        .where((i) => i.context == TrustContext.forward)
        .length;
    expect(secondForwardCount, firstForwardCount);
  });

  test('returns false when review window already closed', () async {
    evalRepo.snapshotOnClose = null;
    final ok = await case_.closeAndFinalize(beaconId, reason: 'expired');
    expect(ok, isFalse);
    expect(trustEvidence.recorded, isEmpty);
  });
}
