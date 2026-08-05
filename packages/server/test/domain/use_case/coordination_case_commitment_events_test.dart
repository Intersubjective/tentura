import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/commitment/commitment_event.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/coordination/coordination_response_type.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/evaluation_repository_port.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/coordination_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/coordination_item_record_fixtures.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/recording_commitment_repository.dart';
import '../../support/test_attention_harness.dart';
import 'help_offer_case_mocks.mocks.dart';

class _MinimalEvaluationRepo extends Fake implements EvaluationRepositoryPort {}

void main() {
  const beaconId = 'B-commitment';
  const authorId = 'U-author';
  const helperId = 'U-helper';
  final now = DateTime.utc(2026);

  BeaconEntity beacon({BeaconStatus status = BeaconStatus.open}) =>
      BeaconEntity(
        id: beaconId,
        title: 't',
        author: UserEntity(id: authorId),
        createdAt: now,
        updatedAt: now,
        status: status,
      );

  HelpOfferEntity activeOffer() => HelpOfferEntity(
        beaconId: beaconId,
        userId: helperId,
        createdAt: now,
        updatedAt: now,
        status: 0,
      );

  CommitmentEvent event({
    required int seq,
    required CommitmentEventKind kind,
    String? reason,
  }) =>
      CommitmentEvent(
        id: 'CE-$seq',
        seq: seq,
        beaconId: beaconId,
        userId: helperId,
        actorUserId: authorId,
        kind: kind,
        reason: reason,
        createdAt: now.add(Duration(minutes: seq)),
      );

  late MockBeaconRepositoryPort beaconRepo;
  late MockHelpOfferRepositoryPort helpOfferRepo;
  late MockCoordinationRepositoryPort coordinationRepo;
  late MockBeaconRoomRepositoryPort roomRepo;
  late RecordingCommitmentRepository commitmentRepo;
  late CommitmentQueryCase commitmentQueryCase;
  late TestAttentionHarness attention;
  late CoordinationCase case_;

  void buildCase() {
    attention = TestAttentionHarness();
    commitmentQueryCase = CommitmentQueryCase(
      commitmentRepo,
      helpOfferRepo,
      env: Env(environment: Environment.test),
      logger: Logger('CoordinationCaseCommitmentEventsTest'),
    );
    case_ = CoordinationCase(
      beaconRepo,
      helpOfferRepo,
      coordinationRepo,
      roomRepo,
      _MinimalEvaluationRepo(),
      FakeUserBlockRepository(),
      commitmentRepo,
      commitmentQueryCase,
      attentionIntents: attention.intents,
      attention: attention.transactional,
      guard: FakeBeaconAccessGuard(),
      env: Env(environment: Environment.test),
      logger: Logger('CoordinationCaseCommitmentEventsTest'),
    );
  }

  void stubAdmissionPrereqs() {
    when(
      beaconRepo.getBeaconById(beaconId: beaconId),
    ).thenAnswer((_) async => beacon());
    when(
      helpOfferRepo.fetchByBeaconId(beaconId),
    ).thenAnswer((_) async => [activeOffer()]);
    when(
      roomRepo.findParticipant(beaconId: beaconId, userId: helperId),
    ).thenAnswer(
      (_) async => testBeaconParticipant(
        beaconId: beaconId,
        userId: helperId,
        roomAccess: RoomAccessBits.requested,
      ),
    );
  }

  setUp(() {
    beaconRepo = MockBeaconRepositoryPort();
    helpOfferRepo = MockHelpOfferRepositoryPort();
    coordinationRepo = MockCoordinationRepositoryPort();
    roomRepo = MockBeaconRoomRepositoryPort();
    commitmentRepo = RecordingCommitmentRepository();
    buildCase();
  });

  group('acceptHelpOffer', () {
    test('records acknowledged after successful accept', () async {
      stubAdmissionPrereqs();
      when(
        coordinationRepo.acceptHelpOffer(
          beaconId: beaconId,
          offerUserId: helperId,
          actorUserId: authorId,
        ),
      ).thenAnswer(
        (_) async => (status: BeaconStatus.open, statusChangedAt: now),
      );

      await case_.acceptHelpOffer(
        beaconId: beaconId,
        offerUserId: helperId,
        actorUserId: authorId,
      );

      expect(commitmentRepo.recordCalls, [
        (
          beaconId: beaconId,
          userId: helperId,
          actorUserId: authorId,
          kind: CommitmentEventKind.acknowledged,
          reason: null,
        ),
      ]);
    });

    test('does not duplicate acknowledged on repeated accept', () async {
      commitmentRepo = RecordingCommitmentRepository(
        eventsByPair: {
          commitmentPairKey(beaconId, helperId): [
            event(seq: 1, kind: CommitmentEventKind.offered),
            event(seq: 2, kind: CommitmentEventKind.acknowledged),
          ],
        },
      );
      buildCase();
      stubAdmissionPrereqs();
      when(
        coordinationRepo.acceptHelpOffer(
          beaconId: beaconId,
          offerUserId: helperId,
          actorUserId: authorId,
        ),
      ).thenAnswer(
        (_) async => (status: BeaconStatus.open, statusChangedAt: now),
      );

      await case_.acceptHelpOffer(
        beaconId: beaconId,
        offerUserId: helperId,
        actorUserId: authorId,
      );

      expect(commitmentRepo.recordCalls, isEmpty);
    });
  });

  group('declineHelpOffer', () {
    test('writes nothing when pair was never acknowledged', () async {
      stubAdmissionPrereqs();
      when(
        coordinationRepo.declineHelpOffer(
          beaconId: beaconId,
          offerUserId: helperId,
          actorUserId: authorId,
          reason: 'no',
        ),
      ).thenAnswer(
        (_) async => (status: BeaconStatus.open, statusChangedAt: now),
      );

      await case_.declineHelpOffer(
        beaconId: beaconId,
        offerUserId: helperId,
        actorUserId: authorId,
        reason: 'no',
      );

      expect(commitmentRepo.recordCalls, isEmpty);
    });

    test('decline after acknowledgement throws commitmentAlreadyAcknowledged',
        () async {
      commitmentRepo = RecordingCommitmentRepository(
        eventsByPair: {
          commitmentPairKey(beaconId, helperId): [
            event(seq: 1, kind: CommitmentEventKind.offered),
            event(seq: 2, kind: CommitmentEventKind.acknowledged),
          ],
        },
      );
      buildCase();
      stubAdmissionPrereqs();

      await expectLater(
        case_.declineHelpOffer(
          beaconId: beaconId,
          offerUserId: helperId,
          actorUserId: authorId,
          reason: 'no',
        ),
        throwsA(
          isA<HelpOfferCoordinationException>().having(
            (e) =>
                (e.code as HelpOfferCoordinationExceptionCodes).exceptionCode,
            'code',
            HelpOfferCoordinationExceptionCode.commitmentAlreadyAcknowledged,
          ),
        ),
      );
      verifyNever(
        coordinationRepo.declineHelpOffer(
          beaconId: anyNamed('beaconId'),
          offerUserId: anyNamed('offerUserId'),
          actorUserId: anyNamed('actorUserId'),
          reason: anyNamed('reason'),
        ),
      );
    });
  });

  group('removeFromRoom', () {
    test('records removedFromChat with trimmed reason', () async {
      stubAdmissionPrereqs();
      when(
        roomRepo.findParticipant(beaconId: beaconId, userId: helperId),
      ).thenAnswer(
        (_) async => testBeaconParticipant(
          beaconId: beaconId,
          userId: helperId,
          roomAccess: RoomAccessBits.admitted,
        ),
      );
      when(
        coordinationRepo.removeFromRoom(
          beaconId: beaconId,
          offerUserId: helperId,
          actorUserId: authorId,
          reason: 'too noisy',
        ),
      ).thenAnswer(
        (_) async => (status: BeaconStatus.open, statusChangedAt: now),
      );

      await case_.removeFromRoom(
        beaconId: beaconId,
        offerUserId: helperId,
        actorUserId: authorId,
        reason: '  too noisy  ',
      );

      expect(commitmentRepo.recordCalls, [
        (
          beaconId: beaconId,
          userId: helperId,
          actorUserId: authorId,
          kind: CommitmentEventKind.removedFromChat,
          reason: 'too noisy',
        ),
      ]);
    });
  });

  group('setCoordinationResponse', () {
    void stubAuthorSetResponse() {
      when(
        beaconRepo.getBeaconById(beaconId: beaconId),
      ).thenAnswer((_) async => beacon());
      when(
        helpOfferRepo.fetchByBeaconId(beaconId),
      ).thenAnswer((_) async => [activeOffer()]);
      when(
        coordinationRepo.beaconStatusSnapshot(beaconId),
      ).thenAnswer(
        (_) async => (status: BeaconStatus.open, statusChangedAt: now),
      );
      when(
        coordinationRepo.upsertResponse(
          beaconId: beaconId,
          offerUserId: helperId,
          authorUserId: authorId,
          responseType: anyNamed('responseType'),
        ),
      ).thenAnswer((_) async {});
    }

    test('useful response records acknowledged', () async {
      stubAuthorSetResponse();

      await case_.setCoordinationResponse(
        beaconId: beaconId,
        offerUserId: helperId,
        authorUserId: authorId,
        responseType: CoordinationResponseType.useful.smallintValue,
        inviteToRoom: false,
        removeFromRoom: false,
      );

      expect(commitmentRepo.recordCalls, [
        (
          beaconId: beaconId,
          userId: helperId,
          actorUserId: authorId,
          kind: CommitmentEventKind.acknowledged,
          reason: null,
        ),
      ]);
    });

    test('notSuitable after acknowledgement throws commitmentAlreadyAcknowledged',
        () async {
      commitmentRepo = RecordingCommitmentRepository(
        eventsByPair: {
          commitmentPairKey(beaconId, helperId): [
            event(seq: 1, kind: CommitmentEventKind.offered),
            event(seq: 2, kind: CommitmentEventKind.acknowledged),
          ],
        },
      );
      buildCase();
      stubAuthorSetResponse();

      await expectLater(
        case_.setCoordinationResponse(
          beaconId: beaconId,
          offerUserId: helperId,
          authorUserId: authorId,
          responseType: CoordinationResponseType.notSuitable.smallintValue,
          inviteToRoom: false,
          removeFromRoom: false,
        ),
        throwsA(
          isA<HelpOfferCoordinationException>().having(
            (e) =>
                (e.code as HelpOfferCoordinationExceptionCodes).exceptionCode,
            'code',
            HelpOfferCoordinationExceptionCode.commitmentAlreadyAcknowledged,
          ),
        ),
      );
      verifyNever(
        coordinationRepo.upsertResponse(
          beaconId: anyNamed('beaconId'),
          offerUserId: anyNamed('offerUserId'),
          authorUserId: anyNamed('authorUserId'),
          responseType: anyNamed('responseType'),
        ),
      );
    });

    test('notSuitable with inviteToRoom throws admissionRequiresAcknowledgement',
        () async {
      stubAuthorSetResponse();

      await expectLater(
        case_.setCoordinationResponse(
          beaconId: beaconId,
          offerUserId: helperId,
          authorUserId: authorId,
          responseType: CoordinationResponseType.notSuitable.smallintValue,
          inviteToRoom: true,
          removeFromRoom: false,
        ),
        throwsA(
          isA<HelpOfferCoordinationException>().having(
            (e) =>
                (e.code as HelpOfferCoordinationExceptionCodes).exceptionCode,
            'code',
            HelpOfferCoordinationExceptionCode.admissionRequiresAcknowledgement,
          ),
        ),
      );
      verifyNever(
        coordinationRepo.upsertResponse(
          beaconId: anyNamed('beaconId'),
          offerUserId: anyNamed('offerUserId'),
          authorUserId: anyNamed('authorUserId'),
          responseType: anyNamed('responseType'),
        ),
      );
    });

    test('useful with inviteToRoom admits and records acknowledged', () async {
      stubAuthorSetResponse();
      when(
        roomRepo.inviteOfferUserToBeaconRoom(
          beaconId: beaconId,
          offerUserId: helperId,
          authorUserId: authorId,
        ),
      ).thenAnswer((_) async {});

      await case_.setCoordinationResponse(
        beaconId: beaconId,
        offerUserId: helperId,
        authorUserId: authorId,
        responseType: CoordinationResponseType.useful.smallintValue,
        inviteToRoom: true,
        removeFromRoom: false,
      );

      verify(
        roomRepo.inviteOfferUserToBeaconRoom(
          beaconId: beaconId,
          offerUserId: helperId,
          authorUserId: authorId,
        ),
      ).called(1);
      expect(
        commitmentRepo.recordCalls.map((call) => call.kind),
        [CommitmentEventKind.acknowledged],
      );
    });

    test(
      'inviteToRoom with non-acknowledging response prefers admissionRequiresAcknowledgement over downgrade guard',
      () async {
        commitmentRepo = RecordingCommitmentRepository(
          eventsByPair: {
            commitmentPairKey(beaconId, helperId): [
              event(seq: 1, kind: CommitmentEventKind.offered),
              event(seq: 2, kind: CommitmentEventKind.acknowledged),
            ],
          },
        );
        buildCase();
        stubAuthorSetResponse();

        await expectLater(
          case_.setCoordinationResponse(
            beaconId: beaconId,
            offerUserId: helperId,
            authorUserId: authorId,
            responseType: CoordinationResponseType.notSuitable.smallintValue,
            inviteToRoom: true,
            removeFromRoom: false,
          ),
          throwsA(
            isA<HelpOfferCoordinationException>().having(
              (e) =>
                  (e.code as HelpOfferCoordinationExceptionCodes).exceptionCode,
              'code',
              HelpOfferCoordinationExceptionCode
                  .admissionRequiresAcknowledgement,
            ),
          ),
        );
      },
    );

    test('notSuitable without acknowledgement still succeeds', () async {
      stubAuthorSetResponse();

      await case_.setCoordinationResponse(
        beaconId: beaconId,
        offerUserId: helperId,
        authorUserId: authorId,
        responseType: CoordinationResponseType.notSuitable.smallintValue,
        inviteToRoom: false,
        removeFromRoom: false,
      );

      verify(
        coordinationRepo.upsertResponse(
          beaconId: beaconId,
          offerUserId: helperId,
          authorUserId: authorId,
          responseType: CoordinationResponseType.notSuitable.smallintValue,
        ),
      ).called(1);
      expect(commitmentRepo.recordCalls, isEmpty);
    });

    test('removeFromRoom also records removedFromChat', () async {
      stubAuthorSetResponse();
      when(
        roomRepo.revokeOfferUserBeaconRoomAccess(
          beaconId: beaconId,
          offerUserId: helperId,
          authorUserId: authorId,
        ),
      ).thenAnswer((_) async {});

      await case_.setCoordinationResponse(
        beaconId: beaconId,
        offerUserId: helperId,
        authorUserId: authorId,
        responseType: CoordinationResponseType.useful.smallintValue,
        inviteToRoom: false,
        removeFromRoom: true,
      );

      expect(
        commitmentRepo.recordCalls.map((call) => call.kind),
        [
          CommitmentEventKind.acknowledged,
          CommitmentEventKind.removedFromChat,
        ],
      );
      expect(
        commitmentRepo.recordCalls.last.reason,
        isNull,
      );
    });

    test('inviteToRoom after prior remove records readmittedToChat', () async {
      commitmentRepo = RecordingCommitmentRepository(
        eventsByPair: {
          commitmentPairKey(beaconId, helperId): [
            event(seq: 1, kind: CommitmentEventKind.offered),
            event(seq: 2, kind: CommitmentEventKind.acknowledged),
            event(seq: 3, kind: CommitmentEventKind.removedFromChat),
          ],
        },
      );
      buildCase();
      stubAuthorSetResponse();
      when(
        roomRepo.inviteOfferUserToBeaconRoom(
          beaconId: beaconId,
          offerUserId: helperId,
          authorUserId: authorId,
        ),
      ).thenAnswer((_) async {});

      await case_.setCoordinationResponse(
        beaconId: beaconId,
        offerUserId: helperId,
        authorUserId: authorId,
        responseType: CoordinationResponseType.useful.smallintValue,
        inviteToRoom: true,
        removeFromRoom: false,
      );

      expect(
        commitmentRepo.recordCalls.map((call) => call.kind),
        [
          CommitmentEventKind.readmittedToChat,
        ],
      );
    });

    test('repeated useful response does not duplicate acknowledged', () async {
      commitmentRepo = RecordingCommitmentRepository(
        eventsByPair: {
          commitmentPairKey(beaconId, helperId): [
            event(seq: 1, kind: CommitmentEventKind.offered),
            event(seq: 2, kind: CommitmentEventKind.acknowledged),
          ],
        },
      );
      buildCase();
      stubAuthorSetResponse();

      await case_.setCoordinationResponse(
        beaconId: beaconId,
        offerUserId: helperId,
        authorUserId: authorId,
        responseType: CoordinationResponseType.useful.smallintValue,
        inviteToRoom: false,
        removeFromRoom: false,
      );

      expect(commitmentRepo.recordCalls, isEmpty);
    });
  });
}
