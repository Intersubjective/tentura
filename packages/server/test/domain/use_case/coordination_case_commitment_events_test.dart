import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../../support/fake_beacon_hierarchy_repository.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/commitment/commitment_event.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/coordination/coordination_response_type.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/attention_system_settlement_port.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/coordination_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/coordination_item_record_fixtures.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/recording_commitment_repository.dart';
import '../../support/test_attention_harness.dart';
import 'help_offer_case_mocks.mocks.dart';


class _RecordingAttentionSystemSettlement extends Fake
    implements AttentionSystemSettlementPort {
  final settleAuthorHelpOfferSubmittedCalls =
      <({String beaconId, String authorAccountId, String helpOffererUserId})>[];

  @override
  Future<int> settleAuthorHelpOfferSubmitted({
    required String beaconId,
    required String authorAccountId,
    required String helpOffererUserId,
  }) async {
    settleAuthorHelpOfferSubmittedCalls.add((
      beaconId: beaconId,
      authorAccountId: authorAccountId,
      helpOffererUserId: helpOffererUserId,
    ));
    return 1;
  }

  final supersedeAuthorHelpOfferSubmittedCalls =
      <({String beaconId, String authorAccountId, String helpOffererUserId})>[];

  @override
  Future<int> supersedeAuthorHelpOfferSubmitted({
    required String beaconId,
    required String authorAccountId,
    required String helpOffererUserId,
  }) async {
    supersedeAuthorHelpOfferSubmittedCalls.add((
      beaconId: beaconId,
      authorAccountId: authorAccountId,
      helpOffererUserId: helpOffererUserId,
    ));
    return 1;
  }

  @override
  Future<int> supersedeAuthorHelpOfferObligationsOnBeaconClose(
    String beaconId,
  ) async => 0;
}

void main() {
  const beaconId = 'B-commitment';
  const authorId = 'U-author';
  const stewardId = 'U-steward';
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
  late _RecordingAttentionSystemSettlement systemSettlement;
  late CommitmentQueryCase commitmentQueryCase;
  late TestAttentionHarness attention;
  late CoordinationCase case_;
  late FakeBeaconHierarchyRepository hierarchy;

  void buildCase() {
    attention = TestAttentionHarness();
    systemSettlement = _RecordingAttentionSystemSettlement();
    commitmentQueryCase = CommitmentQueryCase(
      commitmentRepo,
      helpOfferRepo,
      env: Env(environment: Environment.test),
      logger: Logger('CoordinationCaseCommitmentEventsTest'),
    );
    hierarchy = FakeBeaconHierarchyRepository();
    case_ = CoordinationCase(
      beaconRepo,
      helpOfferRepo,
      coordinationRepo,
      roomRepo,
      FakeUserBlockRepository(),
      commitmentRepo,
      commitmentQueryCase,
      hierarchy,
      attentionIntents: attention.intents,
      attention: attention.transactional,
      attentionSystemSettlement: systemSettlement,
      guard: FakeBeaconAccessGuard(),
      env: Env(environment: Environment.test),
      logger: Logger('CoordinationCaseCommitmentEventsTest'),
    );
  }

  void stubAdmissionPrereqs({String actorUserId = authorId}) {
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
    if (actorUserId != authorId) {
      when(
        roomRepo.isBeaconSteward(beaconId: beaconId, userId: actorUserId),
      ).thenAnswer((_) async => true);
    }
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
          confirmingAuthorId: authorId,
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

      // Lock order (§0) holds without the optional author-invite port: the
      // hierarchy lock is taken unconditionally before the child lock.
      expect(hierarchy.lockMutationScopeCalls, 1);
      expect(commitmentRepo.recordCalls, [
        (
          beaconId: beaconId,
          userId: helperId,
          actorUserId: authorId,
          kind: CommitmentEventKind.acknowledged,
          reason: null,
        ),
      ]);
      expect(systemSettlement.settleAuthorHelpOfferSubmittedCalls, [
        (
          beaconId: beaconId,
          authorAccountId: authorId,
          helpOffererUserId: helperId,
        ),
      ]);
    });

    test(
        'steward accept settles author help-offer with author account id',
        () async {
      stubAdmissionPrereqs(actorUserId: stewardId);
      when(
        coordinationRepo.acceptHelpOffer(
          beaconId: beaconId,
          offerUserId: helperId,
          confirmingAuthorId: stewardId,
          actorUserId: stewardId,
        ),
      ).thenAnswer(
        (_) async => (status: BeaconStatus.open, statusChangedAt: now),
      );

      await case_.acceptHelpOffer(
        beaconId: beaconId,
        offerUserId: helperId,
        actorUserId: stewardId,
      );

      expect(systemSettlement.settleAuthorHelpOfferSubmittedCalls, [
        (
          beaconId: beaconId,
          authorAccountId: authorId,
          helpOffererUserId: helperId,
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
          confirmingAuthorId: authorId,
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

      expect(hierarchy.lockMutationScopeCalls, 1);
      expect(commitmentRepo.recordCalls, isEmpty);
      expect(systemSettlement.settleAuthorHelpOfferSubmittedCalls, [
        (
          beaconId: beaconId,
          authorAccountId: authorId,
          helpOffererUserId: helperId,
        ),
      ]);
    });

    test(
        'steward decline settles author help-offer with author account id',
        () async {
      stubAdmissionPrereqs(actorUserId: stewardId);
      when(
        coordinationRepo.declineHelpOffer(
          beaconId: beaconId,
          offerUserId: helperId,
          actorUserId: stewardId,
          reason: 'no',
        ),
      ).thenAnswer(
        (_) async => (status: BeaconStatus.open, statusChangedAt: now),
      );

      await case_.declineHelpOffer(
        beaconId: beaconId,
        offerUserId: helperId,
        actorUserId: stewardId,
        reason: 'no',
      );

      expect(systemSettlement.settleAuthorHelpOfferSubmittedCalls, [
        (
          beaconId: beaconId,
          authorAccountId: authorId,
          helpOffererUserId: helperId,
        ),
      ]);
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

  // #596: a backup offer is answered with «Keep as standby»: the author's
  // obligation ends, the offer stays a backup.
  group('keepHelpOfferAsStandby', () {
    HelpOfferEntity backupOffer() =>
        activeOffer().copyWith(offerKind: HelpOfferKind.backup);

    void stubBackupOffer() {
      when(
        helpOfferRepo.fetchByBeaconId(beaconId),
      ).thenAnswer((_) async => [backupOffer()]);
    }

    Matcher throwsCoordinationCode(HelpOfferCoordinationExceptionCode code) =>
        throwsA(
          isA<HelpOfferCoordinationException>().having(
            (e) =>
                (e.code as HelpOfferCoordinationExceptionCodes).exceptionCode,
            'code',
            code,
          ),
        );

    test('author ends the obligation and leaves the offer alone', () async {
      stubAdmissionPrereqs();
      stubBackupOffer();

      await case_.keepHelpOfferAsStandby(
        beaconId: beaconId,
        offerUserId: helperId,
        actorUserId: authorId,
      );

      expect(hierarchy.lockMutationScopeCalls, 1);
      // An answer: resolved, receipt seen (#707 review), not superseded.
      expect(systemSettlement.settleAuthorHelpOfferSubmittedCalls, [
        (
          beaconId: beaconId,
          authorAccountId: authorId,
          helpOffererUserId: helperId,
        ),
      ]);
      expect(systemSettlement.supersedeAuthorHelpOfferSubmittedCalls, isEmpty);
      expect(commitmentRepo.recordCalls, isEmpty);
      verifyNever(
        helpOfferRepo.deactivate(
          beaconId: anyNamed('beaconId'),
          userId: anyNamed('userId'),
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

    test('steward ends the obligation of the author account', () async {
      stubAdmissionPrereqs(actorUserId: stewardId);
      stubBackupOffer();

      await case_.keepHelpOfferAsStandby(
        beaconId: beaconId,
        offerUserId: helperId,
        actorUserId: stewardId,
      );

      expect(systemSettlement.settleAuthorHelpOfferSubmittedCalls, [
        (
          beaconId: beaconId,
          authorAccountId: authorId,
          helpOffererUserId: helperId,
        ),
      ]);
    });

    test('someone who is neither author nor steward is refused', () async {
      const otherId = 'U-other';
      stubAdmissionPrereqs();
      stubBackupOffer();
      when(
        roomRepo.isBeaconSteward(beaconId: beaconId, userId: otherId),
      ).thenAnswer((_) async => false);

      await expectLater(
        case_.keepHelpOfferAsStandby(
          beaconId: beaconId,
          offerUserId: helperId,
          actorUserId: otherId,
        ),
        throwsCoordinationCode(
          HelpOfferCoordinationExceptionCode.notBeaconAuthor,
        ),
      );
      expect(systemSettlement.settleAuthorHelpOfferSubmittedCalls, isEmpty);
    });

    test('an ordinary offer is refused', () async {
      stubAdmissionPrereqs();

      await expectLater(
        case_.keepHelpOfferAsStandby(
          beaconId: beaconId,
          offerUserId: helperId,
          actorUserId: authorId,
        ),
        throwsCoordinationCode(
          HelpOfferCoordinationExceptionCode.offerKindChanged,
        ),
      );
      expect(systemSettlement.settleAuthorHelpOfferSubmittedCalls, isEmpty);
    });

    test('a withdrawn or missing offer is refused', () async {
      stubAdmissionPrereqs();
      when(
        helpOfferRepo.fetchByBeaconId(beaconId),
      ).thenAnswer((_) async => const []);

      await expectLater(
        case_.keepHelpOfferAsStandby(
          beaconId: beaconId,
          offerUserId: helperId,
          actorUserId: authorId,
        ),
        throwsCoordinationCode(
          HelpOfferCoordinationExceptionCode.helpOfferNotActive,
        ),
      );
      expect(systemSettlement.settleAuthorHelpOfferSubmittedCalls, isEmpty);
    });

    // #707 review: a backup already admitted or acknowledged is no longer
    // pending; the server refuses it as decline does.
    test('an acknowledged backup offer is refused', () async {
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
      stubBackupOffer();

      await expectLater(
        case_.keepHelpOfferAsStandby(
          beaconId: beaconId,
          offerUserId: helperId,
          actorUserId: authorId,
        ),
        throwsCoordinationCode(
          HelpOfferCoordinationExceptionCode.commitmentAlreadyAcknowledged,
        ),
      );
      expect(systemSettlement.settleAuthorHelpOfferSubmittedCalls, isEmpty);
      expect(systemSettlement.supersedeAuthorHelpOfferSubmittedCalls, isEmpty);
    });

    // Guard (passes before #596): declining a backup offer was already
    // allowed on the server; only the sheet hid it.
    test('declining a backup offer settles the obligation', () async {
      stubAdmissionPrereqs();
      stubBackupOffer();
      when(
        coordinationRepo.declineHelpOffer(
          beaconId: beaconId,
          offerUserId: helperId,
          actorUserId: authorId,
          reason: 'no',
        ),
      ).thenAnswer(
        (_) async => (status: BeaconStatus.enoughHelp, statusChangedAt: now),
      );

      await case_.declineHelpOffer(
        beaconId: beaconId,
        offerUserId: helperId,
        actorUserId: authorId,
        reason: 'no',
      );

      expect(systemSettlement.settleAuthorHelpOfferSubmittedCalls, [
        (
          beaconId: beaconId,
          authorAccountId: authorId,
          helpOffererUserId: helperId,
        ),
      ]);
    });
  });

  group('declineRemainingHelpOffers', () {
    test('reads status and offers only after taking the hierarchy '
        'lock', () async {
      var lockedWhenStatusRead = -1;
      var lockedWhenOffersRead = -1;
      when(beaconRepo.getBeaconById(beaconId: beaconId)).thenAnswer((_) async {
        lockedWhenStatusRead = hierarchy.lockMutationScopeCalls;
        return beacon(status: BeaconStatus.enoughHelp);
      });
      when(helpOfferRepo.fetchByBeaconId(beaconId)).thenAnswer((_) async {
        lockedWhenOffersRead = hierarchy.lockMutationScopeCalls;
        return [activeOffer()];
      });
      when(
        roomRepo.findParticipant(beaconId: beaconId, userId: helperId),
      ).thenAnswer(
        (_) async => testBeaconParticipant(
          beaconId: beaconId,
          userId: helperId,
          roomAccess: RoomAccessBits.requested,
        ),
      );
      when(
        coordinationRepo.declineHelpOffer(
          beaconId: beaconId,
          offerUserId: helperId,
          actorUserId: authorId,
          reason: 'enough',
        ),
      ).thenAnswer(
        (_) async => (status: BeaconStatus.enoughHelp, statusChangedAt: now),
      );

      final declined = await case_.declineRemainingHelpOffers(
        beaconId: beaconId,
        actorUserId: authorId,
        reason: ' enough ',
      );

      expect(declined, 1);
      expect(hierarchy.lockMutationScopeCalls, 1);
      expect(lockedWhenStatusRead, 1, reason: 'status re-read under lock');
      expect(lockedWhenOffersRead, 1, reason: 'offers re-read under lock');
      expect(systemSettlement.settleAuthorHelpOfferSubmittedCalls, [
        (
          beaconId: beaconId,
          authorAccountId: authorId,
          helpOffererUserId: helperId,
        ),
      ]);
    });

    test('skips a pair acknowledged meanwhile', () async {
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
        beaconRepo.getBeaconById(beaconId: beaconId),
      ).thenAnswer((_) async => beacon(status: BeaconStatus.enoughHelp));

      final declined = await case_.declineRemainingHelpOffers(
        beaconId: beaconId,
        actorUserId: authorId,
        reason: 'enough',
      );

      expect(declined, 0);
      verifyNever(
        coordinationRepo.declineHelpOffer(
          beaconId: anyNamed('beaconId'),
          offerUserId: anyNamed('offerUserId'),
          actorUserId: anyNamed('actorUserId'),
          reason: anyNamed('reason'),
        ),
      );
      expect(systemSettlement.settleAuthorHelpOfferSubmittedCalls, isEmpty);
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
