// #489 (round 7): when the author ends a helper's participation
// (`CoordinationCase.releaseCommitment`) and the helper was in the room, the
// room gets a NEUTRAL system line ("{name} is no longer in the request"),
// the counterpart of a voluntary leave's `participantLeft` line (B084).
// Before the fix nothing was posted: the others saw the helper vanish
// silently. Per U41 (docs/plans/episode-closure-implementation-plan.md l.69)
// colleagues are not told who initiated a departure, so the line carries no
// actor and no reason; the reason stays on the author-side removal records
// (`removeFromRoom` -> admission event / participantRemoved activity).
//
// Contract pinned here: `BeaconRoomRepositoryPort.recordParticipantRemoved(
//   beaconId:, userId: <removed helper>)` (no actor, no reason), called once
// per real removal, in every status that allows coordination (Wrapping up
// included); never for a helper who was not in the room, never on an
// idempotent repeat, and never as the helper's own `participantLeft` line.

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/coordination_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/recording_commitment_repository.dart';
import '../../support/test_attention_harness.dart';
import 'help_offer_case_mocks.mocks.dart';

void main() {
  const beaconId = 'B-removal-line';
  const authorId = 'U-author';
  const helperId = 'U784390f7cdc3';
  final now = DateTime.utc(2026, 10, 21);

  late MockBeaconRepositoryPort beaconRepo;
  late MockHelpOfferRepositoryPort helpOfferRepo;
  late MockCoordinationRepositoryPort coordinationRepo;
  late MockBeaconRoomRepositoryPort roomRepo;
  late RecordingCommitmentRepository commitmentRepo;
  late CoordinationCase coordinationCase;

  BeaconEntity beacon(BeaconStatus status) => BeaconEntity(
    id: beaconId,
    title: 't',
    author: const UserEntity(id: authorId),
    createdAt: now,
    updatedAt: now,
    status: status,
  );

  BeaconParticipantRecord admitted() => BeaconParticipantRecord(
    id: 'participant-1',
    beaconId: beaconId,
    userId: helperId,
    role: 2,
    status: 0,
    roomAccess: RoomAccessBits.admitted,
    createdAt: now,
    updatedAt: now,
  );

  Future<void> build({
    required BeaconStatus status,
    BeaconParticipantRecord? participant,
  }) async {
    beaconRepo = MockBeaconRepositoryPort();
    helpOfferRepo = MockHelpOfferRepositoryPort();
    coordinationRepo = MockCoordinationRepositoryPort();
    roomRepo = MockBeaconRoomRepositoryPort();
    commitmentRepo = RecordingCommitmentRepository();
    await commitmentRepo.record(
      beaconId: beaconId,
      userId: helperId,
      actorUserId: helperId,
      kind: CommitmentEventKind.offered,
    );
    await commitmentRepo.record(
      beaconId: beaconId,
      userId: helperId,
      actorUserId: authorId,
      kind: CommitmentEventKind.acknowledged,
    );
    when(
      beaconRepo.getBeaconById(beaconId: beaconId),
    ).thenAnswer((_) async => beacon(status));
    when(
      coordinationRepo.beaconStatusSnapshot(beaconId),
    ).thenAnswer((_) async => (status: status, statusChangedAt: now));
    when(
      coordinationRepo.removeFromRoom(
        beaconId: anyNamed('beaconId'),
        offerUserId: anyNamed('offerUserId'),
        actorUserId: anyNamed('actorUserId'),
        reason: anyNamed('reason'),
      ),
    ).thenAnswer((_) async => (status: status, statusChangedAt: now));
    when(
      roomRepo.findParticipant(beaconId: beaconId, userId: helperId),
    ).thenAnswer((_) async => participant);
    // #489: an admitted helper's removal posts a room line; strict mocks
    // need it stubbed.
    when(
      roomRepo.recordParticipantRemoved(
        beaconId: anyNamed('beaconId'),
        userId: anyNamed('userId'),
      ),
    ).thenAnswer((_) async {});
    when(helpOfferRepo.fetchAllByBeaconId(beaconId)).thenAnswer(
      (_) async => [
        HelpOfferEntity(
          beaconId: beaconId,
          userId: helperId,
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
    final attention = TestAttentionHarness();
    coordinationCase = CoordinationCase(
      beaconRepo,
      helpOfferRepo,
      coordinationRepo,
      roomRepo,
      FakeUserBlockRepository(),
      commitmentRepo,
      CommitmentQueryCase(
        commitmentRepo,
        helpOfferRepo,
        env: Env(environment: Environment.test),
        logger: Logger('CoordinationCaseRemovalLineTest'),
      ),
      FakeBeaconHierarchyRepository(),
      attentionIntents: attention.intents,
      attention: attention.transactional,
      guard: FakeBeaconAccessGuard(),
      env: Env(environment: Environment.test),
      logger: Logger('CoordinationCaseRemovalLineTest'),
    );
  }

  Future<void> release({String reason = 'No-show twice'}) =>
      coordinationCase.releaseCommitment(
        beaconId: beaconId,
        offerUserId: helperId,
        authorUserId: authorId,
        reason: reason,
      );

  for (final status in [
    BeaconStatus.open,
    BeaconStatus.enoughHelp,
    BeaconStatus.reviewOpen,
  ]) {
    test(
      '${status.name}: ending an admitted helper posts the removal line',
      () async {
        await build(status: status, participant: admitted());

        await release(reason: '  No-show twice  ');

        verify(
          roomRepo.recordParticipantRemoved(
            beaconId: beaconId,
            userId: helperId,
          ),
        ).called(1);
        // The reason is still logged on the author-side removal path
        // (admission event + participantRemoved activity), not in the room.
        verify(
          coordinationRepo.removeFromRoom(
            beaconId: beaconId,
            offerUserId: helperId,
            actorUserId: authorId,
            reason: 'No-show twice',
          ),
        ).called(1);
        // Not dressed up as the helper leaving on their own.
        verifyNever(
          roomRepo.recordParticipantLeft(
            beaconId: anyNamed('beaconId'),
            userId: anyNamed('userId'),
            withdrawReason: anyNamed('withdrawReason'),
            note: anyNamed('note'),
          ),
        );
      },
    );
  }

  test('a helper who was never in the room gets no removal line', () async {
    await build(status: BeaconStatus.reviewOpen);

    await release();

    verifyNever(
      roomRepo.recordParticipantRemoved(
        beaconId: anyNamed('beaconId'),
        userId: anyNamed('userId'),
      ),
    );
  });

  test('a repeated release posts no second line', () async {
    await build(status: BeaconStatus.reviewOpen, participant: admitted());

    await release();
    await release();

    verify(
      roomRepo.recordParticipantRemoved(
        beaconId: anyNamed('beaconId'),
        userId: anyNamed('userId'),
      ),
    ).called(1);
  });
}
