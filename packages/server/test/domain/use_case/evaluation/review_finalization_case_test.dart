import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';

import '../../../support/recording_beacon_hierarchy_outbox.dart';
import 'package:tentura_server/domain/entity/review_close_snapshot.dart';
import 'package:tentura_server/domain/use_case/evaluation/review_finalization_case.dart';

import '../../../support/review_finalization_test_support.dart';

void main() {
  const beaconId = 'B-finalize01';
  const authorId = 'U-author';
  const committerId = 'U-committer';

  late FakeEvaluationRepo evalRepo;
  late ReviewFinalizationCase case_;

  final windowOpened = DateTime.utc(2026, 1, 1);

  setUp(() {
    evalRepo = FakeEvaluationRepo();

    case_ = buildReviewFinalizationCase(
      evaluationRepo: evalRepo,
    );

    evalRepo.snapshotOnClose = ReviewCloseSnapshot(
      beaconId: beaconId,
      beaconAuthorId: authorId,
      beaconTitle: 'Finalize test request',
      windowOpenedAt: windowOpened,
      finalizedEvaluations: [
        const FinalizedEvaluation(
          evaluatorId: authorId,
          evaluatedUserId: committerId,
          value: 5,
          role: 0,
        ),
        const FinalizedEvaluation(
          evaluatorId: committerId,
          evaluatedUserId: authorId,
          value: 4,
          role: 1,
        ),
      ],
    );
  });

  test('closeAndFinalize returns the finalized pairs', () async {
    final result = await case_.closeAndFinalize(beaconId, reason: 'expired');
    expect(result.didClose, isTrue);
    expect(result.beaconTitle, 'Finalize test request');
    expect(result.pairs, hasLength(2));
  });

  test('returns false when review window already closed', () async {
    evalRepo.snapshotOnClose = null;
    final result = await case_.closeAndFinalize(beaconId, reason: 'expired');
    expect(result.didClose, isFalse);
    expect(result.beaconTitle, isNull);
    expect(result.pairs, isEmpty);
  });

  test(
    'forwards requireAllRequiredPackagesSent and aborts when lock recheck fails',
    () async {
      evalRepo.abortWhenRequireAllRequiredPackagesSent = true;
      final result = await case_.closeAndFinalize(
        beaconId,
        reason: 'author_close_now',
        requireAllRequiredPackagesSent: true,
      );
      expect(evalRepo.lastRequireAllRequiredPackagesSent, isTrue);
      expect(result.didClose, isFalse);
      },
  );

  test('manual and expiry finalization share the same hierarchy closed shape', () async {
    final manualOutbox = RecordingBeaconHierarchyOutbox();
    final expiryOutbox = RecordingBeaconHierarchyOutbox();
    final manualCase = buildReviewFinalizationCase(
      evaluationRepo: evalRepo,
      lifecycleOutbox: manualOutbox,
    );
    final expiryCase = buildReviewFinalizationCase(
      evaluationRepo: evalRepo,
      lifecycleOutbox: expiryOutbox,
    );

    await manualCase.closeAndFinalize(
      beaconId,
      reason: BeaconLifecycleChangeReason.authorCloseNow,
      actorUserId: authorId,
    );
    await expiryCase.closeAndFinalize(
      beaconId,
      reason: BeaconLifecycleChangeReason.reviewExpired,
    );

    expect(manualOutbox.recordedEvents.single.toStatus, BeaconStatus.closed);
    expect(expiryOutbox.recordedEvents.single.toStatus, BeaconStatus.closed);
    expect(
      manualOutbox.recordedEvents.single.fromStatus,
      expiryOutbox.recordedEvents.single.fromStatus,
    );
  });

  test('closeAndFinalize does not record hierarchy event when window already closed', () async {
    final outbox = RecordingBeaconHierarchyOutbox();
    final localCase = buildReviewFinalizationCase(
      evaluationRepo: evalRepo,
      lifecycleOutbox: outbox,
    );
    evalRepo.snapshotOnClose = null;
    await localCase.closeAndFinalize(beaconId, reason: 'expired');
    expect(outbox.recordedEvents, isEmpty);
  });
}
