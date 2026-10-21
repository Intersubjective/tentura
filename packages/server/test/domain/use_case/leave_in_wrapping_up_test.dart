import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/repository/mock/closure_repository_mock.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/closure/closure_entities.dart';
import 'package:tentura_server/domain/closure/membership_reducer.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/attention_system_settlement_port.dart';
import 'package:tentura_server/domain/port/closure_finalizer_port.dart';
import 'package:tentura_server/domain/port/closure_receipts_port.dart';
import 'package:tentura_server/domain/use_case/capability_case.dart';
import 'package:tentura_server/domain/use_case/closure_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/coordination_case.dart';
import 'package:tentura_server/domain/use_case/help_offer_case.dart';
import 'package:tentura_server/env.dart';
import 'package:test/test.dart';

import '../../support/beacon_lifecycle_effects_test_support.dart';
import '../../support/commitment_gates_harness.dart'
    show
        InMemoryHelpOfferRepository,
        MutableBeaconRepository,
        NoOpInboxRepository;
import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/recording_commitment_repository.dart';
import '../../support/test_attention_harness.dart';
import 'help_offer_case_mocks.mocks.dart';

// #489: once a Request is Wrapping up (reviewOpen, a live closure epoch), the
// author must still be able to end a helper's participation and a helper must
// still be able to leave, each with a reason that is logged as a commitment
// event, and the departure must reach the live review epoch (the member row's
// `departure`, which is what drops a removed member's vote, U49).

const _beaconId = 'B-wrap-489';
const _authorId = 'U-author-489';
const _helperId = 'U-helper-489';
const _otherId = 'U-other-489';

/// A closure repository with one live (evaluating) epoch whose member rows
/// follow [setDeparture], so a test can read the review set after the call.
class _LiveEpochClosureRepo extends ClosureRepositoryMock {
  _LiveEpochClosureRepo(DateTime openedAt)
    : _epoch = ClosureEpoch(
        beaconId: _beaconId,
        epoch: 1,
        status: ClosureEpochStatus.evaluating,
        openedAt: openedAt,
        closesAt: openedAt.add(const Duration(days: 7)),
        extensionsUsed: 0,
      );

  final ClosureEpoch _epoch;

  final rows = <String, ClosureMemberRow>{
    _helperId: const ClosureMemberRow(userId: _helperId, activeAtOpen: true),
    _otherId: const ClosureMemberRow(userId: _otherId, activeAtOpen: true),
  };

  final departures = <({String userId, Departure? departure})>[];

  @override
  Future<ClosureEpoch?> liveEpoch(String beaconId) async => _epoch;

  @override
  Future<ClosureEpoch?> latestEpoch(String beaconId) async => _epoch;

  @override
  Future<List<ClosureMemberRow>> members({
    required String beaconId,
    required int epoch,
  }) async => rows.values.toList();

  @override
  Future<void> setDeparture({
    required String beaconId,
    required int epoch,
    required String userId,
    Departure? departure,
  }) async {
    departures.add((userId: userId, departure: departure));
    final row = rows[userId]!;
    rows[userId] = ClosureMemberRow(
      userId: userId,
      activeAtOpen: row.activeAtOpen,
      arrivalEdgeId: row.arrivalEdgeId,
      departure: departure,
    );
  }
}

class _NoSettlement extends Fake implements AttentionSystemSettlementPort {}

class _NoReceipts extends Fake implements ClosureReceiptsPort {}

class _NoFinalizer extends Fake implements ClosureFinalizerPort {}

void main() {
  final t0 = DateTime.utc(2026, 6, 1, 12);
  final env = Env(environment: Environment.test);

  late RecordingCommitmentRepository commitments;
  late InMemoryHelpOfferRepository helpOffers;
  late MutableBeaconRepository beacons;
  late MockBeaconRoomRepositoryPort roomRepo;
  late MockCoordinationRepositoryPort coordinationRepo;
  late _LiveEpochClosureRepo closureRepo;
  late ClosureCase closureCase;
  late TestAttentionHarness attention;
  late HelpOfferCase helpOfferCase;
  late CoordinationCase coordinationCase;

  BeaconParticipantRecord admittedHelper() => BeaconParticipantRecord(
    id: 'P-helper-489',
    beaconId: _beaconId,
    userId: _helperId,
    role: BeaconParticipantRoleBits.helper,
    status: 0,
    roomAccess: RoomAccessBits.admitted,
    createdAt: t0,
    updatedAt: t0,
  );

  /// The helper offered, the author accepted, and a day later the Request
  /// went into Wrapping up with the helper in the review set.
  Future<void> seedAcceptedHelperThenWrappingUp() async {
    await helpOffers.upsert(beaconId: _beaconId, userId: _helperId);
    await commitments.record(
      beaconId: _beaconId,
      userId: _helperId,
      actorUserId: _helperId,
      kind: CommitmentEventKind.offered,
    );
    await commitments.record(
      beaconId: _beaconId,
      userId: _helperId,
      actorUserId: _authorId,
      kind: CommitmentEventKind.acknowledged,
    );
    commitments.advanceClock(const Duration(days: 2));
    beacons.beacon = beacons.beacon.copyWith(status: BeaconStatus.reviewOpen);
    commitments.recordCalls.clear();
  }

  setUp(() {
    commitments = RecordingCommitmentRepository(initialClock: t0);
    helpOffers = InMemoryHelpOfferRepository(() => commitments.clock);
    beacons = MutableBeaconRepository(
      BeaconEntity(
        id: _beaconId,
        title: 'Wrapping up request',
        author: const UserEntity(id: _authorId),
        createdAt: t0,
        updatedAt: t0,
      ),
    );
    roomRepo = MockBeaconRoomRepositoryPort();
    coordinationRepo = MockCoordinationRepositoryPort();
    closureRepo = _LiveEpochClosureRepo(t0.add(const Duration(days: 1)));
    attention = TestAttentionHarness();

    when(
      roomRepo.findParticipant(beaconId: _beaconId, userId: _helperId),
    ).thenAnswer((_) async => admittedHelper());
    // #489: an admitted helper's removal posts a room line; strict mocks
    // need it stubbed.
    when(
      roomRepo.recordParticipantRemoved(
        beaconId: anyNamed('beaconId'),
        userId: anyNamed('userId'),
      ),
    ).thenAnswer((_) async {});
    when(coordinationRepo.beaconStatusSnapshot(_beaconId)).thenAnswer(
      (_) async => (status: beacons.beacon.status, statusChangedAt: t0),
    );
    when(
      coordinationRepo.removeFromRoom(
        beaconId: anyNamed('beaconId'),
        offerUserId: anyNamed('offerUserId'),
        actorUserId: anyNamed('actorUserId'),
        reason: anyNamed('reason'),
      ),
    ).thenAnswer(
      (_) async => (status: beacons.beacon.status, statusChangedAt: t0),
    );

    closureCase = ClosureCase(
      unitOfWork: PassThroughMutatingUnitOfWork(),
      closureRepository: closureRepo,
      beaconRepository: beacons,
      commitmentRepository: commitments,
      helpOfferRepository: helpOffers,
      hierarchyRepository: FakeBeaconHierarchyRepository(),
      lifecycleEffects: buildLifecycleEffectsCase(),
      attentionSystemSettlement: _NoSettlement(),
      receipts: _NoReceipts(),
      finalizer: _NoFinalizer(),
      env: env,
      logger: Logger('LeaveInWrappingUpTest'),
    );

    helpOfferCase = HelpOfferCase(
      helpOffers,
      beacons,
      commitments,
      NoOpInboxRepository(),
      CapabilityCase(
        MockPersonCapabilityEventRepositoryPort(),
        env: env,
        logger: Logger('LeaveInWrappingUpTest'),
      ),
      FakeBeaconAccessGuard(),
      roomRepository: roomRepo,
      attentionIntents: attention.intents,
      attention: attention.transactional,
      closureCase: closureCase,
      env: env,
      logger: Logger('LeaveInWrappingUpTest'),
    );

    coordinationCase = CoordinationCase(
      beacons,
      helpOffers,
      coordinationRepo,
      roomRepo,
      FakeUserBlockRepository(),
      commitments,
      CommitmentQueryCase(
        commitments,
        helpOffers,
        env: env,
        logger: Logger('LeaveInWrappingUpTest'),
      ),
      FakeBeaconHierarchyRepository(),
      attentionIntents: attention.intents,
      attention: attention.transactional,
      guard: FakeBeaconAccessGuard(),
      closureCase: closureCase,
      env: env,
      logger: Logger('LeaveInWrappingUpTest'),
    );
  });

  group('#489 helper leaves while the Request is Wrapping up', () {
    test(
      'withdraw in reviewOpen is logged with its reason and departs the review epoch',
      () async {
        await seedAcceptedHelperThenWrappingUp();

        await helpOfferCase.withdraw(
          beaconId: _beaconId,
          userId: _helperId,
          withdrawReason: 'timing',
          message: 'Could not make it after all',
        );

        expect(commitments.recordCalls, [
          (
            beaconId: _beaconId,
            userId: _helperId,
            actorUserId: _helperId,
            kind: CommitmentEventKind.withdrawnByHelper,
            reason: 'timing',
          ),
        ]);
        expect(
          await helpOffers.hasActiveHelpOffer(
            beaconId: _beaconId,
            userId: _helperId,
          ),
          isFalse,
        );
        // The room is told who left and why.
        verify(
          roomRepo.recordParticipantLeft(
            beaconId: _beaconId,
            userId: _helperId,
            withdrawReason: 'timing',
            note: 'Could not make it after all',
          ),
        ).called(1);
        // The live review epoch learns the departure; the colleague is
        // untouched.
        expect(closureRepo.departures, [
          (userId: _helperId, departure: Departure.voluntary),
        ]);
        expect(closureRepo.rows[_otherId]!.departure, isNull);
        // U49: only an author removal drops a vote; a voluntary leaver
        // still counts in the review set.
        expect(ClosureCase.isVoter(closureRepo.rows[_helperId]!), isTrue);
      },
    );

    test('withdraw after the Request is closed is still forbidden', () async {
      await seedAcceptedHelperThenWrappingUp();
      beacons.beacon = beacons.beacon.copyWith(status: BeaconStatus.closed);

      await expectLater(
        helpOfferCase.withdraw(
          beaconId: _beaconId,
          userId: _helperId,
          withdrawReason: 'timing',
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
      expect(commitments.recordCalls, isEmpty);
      expect(closureRepo.departures, isEmpty);
    });
  });

  group('#489 author ends a helper participation while Wrapping up', () {
    test(
      'releaseCommitment in reviewOpen is logged with its reason and drops the vote',
      () async {
        await seedAcceptedHelperThenWrappingUp();
        expect(ClosureCase.isVoter(closureRepo.rows[_helperId]!), isTrue);

        await coordinationCase.releaseCommitment(
          beaconId: _beaconId,
          offerUserId: _helperId,
          authorUserId: _authorId,
          reason: 'never showed up',
        );

        final released = commitments.recordCalls.where(
          (c) => c.kind == CommitmentEventKind.releasedByAuthor,
        );
        expect(released, hasLength(1));
        expect(released.single.userId, _helperId);
        expect(released.single.actorUserId, _authorId);
        expect(released.single.reason, 'never showed up');
        // An admitted no-show also leaves the discussion.
        verify(
          coordinationRepo.removeFromRoom(
            beaconId: _beaconId,
            offerUserId: _helperId,
            actorUserId: _authorId,
            reason: 'never showed up',
          ),
        ).called(1);
        // The live review epoch marks them removed: no longer a voter, and
        // the colleague keeps their vote.
        expect(closureRepo.departures, isNotEmpty);
        expect(
          closureRepo.departures.map((d) => d.userId).toSet(),
          {_helperId},
        );
        expect(
          closureRepo.rows[_helperId]!.departure,
          Departure.removed,
        );
        expect(ClosureCase.isVoter(closureRepo.rows[_helperId]!), isFalse);
        expect(ClosureCase.isVoter(closureRepo.rows[_otherId]!), isTrue);
      },
    );

    test(
      'releaseCommitment in reviewOpen still requires an accepted helper',
      () async {
        // A pending offer that the author never accepted: there is no
        // participation to end, in Wrapping up as before.
        await helpOffers.upsert(beaconId: _beaconId, userId: _otherId);
        await commitments.record(
          beaconId: _beaconId,
          userId: _otherId,
          actorUserId: _otherId,
          kind: CommitmentEventKind.offered,
        );
        beacons.beacon = beacons.beacon.copyWith(
          status: BeaconStatus.reviewOpen,
        );
        commitments.recordCalls.clear();

        await expectLater(
          coordinationCase.releaseCommitment(
            beaconId: _beaconId,
            offerUserId: _otherId,
            authorUserId: _authorId,
            reason: 'not needed',
          ),
          throwsA(
            isA<HelpOfferCoordinationException>().having(
              (e) =>
                  (e.code as HelpOfferCoordinationExceptionCodes).exceptionCode,
              'code',
              HelpOfferCoordinationExceptionCode.commitmentNotAcknowledged,
            ),
          ),
        );
        expect(commitments.recordCalls, isEmpty);
      },
    );

    test('accepting a pending offer in reviewOpen is still refused', () async {
      // Ending participation is widened to Wrapping up; admitting new
      // helpers is not.
      await helpOffers.upsert(beaconId: _beaconId, userId: _otherId);
      await commitments.record(
        beaconId: _beaconId,
        userId: _otherId,
        actorUserId: _otherId,
        kind: CommitmentEventKind.offered,
      );
      beacons.beacon = beacons.beacon.copyWith(
        status: BeaconStatus.reviewOpen,
      );
      commitments.recordCalls.clear();

      await expectLater(
        coordinationCase.acceptHelpOffer(
          beaconId: _beaconId,
          offerUserId: _otherId,
          actorUserId: _authorId,
        ),
        throwsA(
          isA<HelpOfferCoordinationException>().having(
            (e) =>
                (e.code as HelpOfferCoordinationExceptionCodes).exceptionCode,
            'code',
            HelpOfferCoordinationExceptionCode.beaconNotOpen,
          ),
        ),
      );
      expect(commitments.recordCalls, isEmpty);
      expect(closureRepo.departures, isEmpty);
    });

    for (final status in [
      BeaconStatus.closed,
      BeaconStatus.cancelled,
      BeaconStatus.draft,
    ]) {
      test('releaseCommitment in ${status.name} is still refused', () async {
        await seedAcceptedHelperThenWrappingUp();
        beacons.beacon = beacons.beacon.copyWith(status: status);

        await expectLater(
          coordinationCase.releaseCommitment(
            beaconId: _beaconId,
            offerUserId: _helperId,
            authorUserId: _authorId,
            reason: 'never showed up',
          ),
          throwsA(isA<HelpOfferCoordinationException>()),
        );
        expect(commitments.recordCalls, isEmpty);
        expect(closureRepo.departures, isEmpty);
      });
    }
  });

  // #621: ending the participation of a helper who is not in the room (never
  // admitted, or already out) must end their help offer too, as it does for
  // an admitted helper; it used to stay active and keep counting.
  group('#621 releasing a helper who is not admitted closes their offer', () {
    BeaconParticipantRecord helperWithAccess(int roomAccess) =>
        BeaconParticipantRecord(
          id: 'P-helper-489',
          beaconId: _beaconId,
          userId: _helperId,
          role: BeaconParticipantRoleBits.helper,
          status: 0,
          roomAccess: roomAccess,
          createdAt: t0,
          updatedAt: t0,
        );

    void stubHelperParticipant(BeaconParticipantRecord? participant) => when(
      roomRepo.findParticipant(beaconId: _beaconId, userId: _helperId),
    ).thenAnswer((_) async => participant);

    Future<void> releaseHelper() => coordinationCase.releaseCommitment(
      beaconId: _beaconId,
      offerUserId: _helperId,
      authorUserId: _authorId,
      reason: 'never showed up',
    );

    Future<void> expectOfferClosedWithoutExitReason() async {
      expect(
        await helpOffers.hasActiveHelpOffer(
          beaconId: _beaconId,
          userId: _helperId,
        ),
        isFalse,
        reason: 'a released helper no longer has an active offer',
      );
      final offer = (await helpOffers.fetchAllByBeaconId(_beaconId)).single;
      expect(offer.withdrawReason, isNull, reason: 'not a helper withdrawal');
    }

    final notAdmitted = <String, BeaconParticipantRecord? Function()>{
      'never admitted (access requested)': () =>
          helperWithAccess(RoomAccessBits.requested),
      'removed (no room access)': () => helperWithAccess(RoomAccessBits.none),
      'no participant row': () => null,
    };

    for (final MapEntry(key: label, value: participant)
        in notAdmitted.entries) {
      test('in Wrapping up: $label', () async {
        await seedAcceptedHelperThenWrappingUp();
        stubHelperParticipant(participant());
        expect(
          await helpOffers.hasActiveHelpOffer(
            beaconId: _beaconId,
            userId: _helperId,
          ),
          isTrue,
        );

        await releaseHelper();

        await expectOfferClosedWithoutExitReason();
        expect(
          commitments.recordCalls.where(
            (c) => c.kind == CommitmentEventKind.releasedByAuthor,
          ),
          hasLength(1),
        );
      });
    }

    test('in Coordinating (open): never admitted', () async {
      await seedAcceptedHelperThenWrappingUp();
      beacons.beacon = beacons.beacon.copyWith(status: BeaconStatus.open);
      stubHelperParticipant(helperWithAccess(RoomAccessBits.requested));

      await releaseHelper();

      await expectOfferClosedWithoutExitReason();
    });

    test(
      'an admitted helper released in Wrapping up loses the offer too',
      () async {
        await seedAcceptedHelperThenWrappingUp();

        await releaseHelper();

        await expectOfferClosedWithoutExitReason();
      },
    );

    test(
      'the release notice is built while the helper can still read the '
      'request (offer closed after it)',
      () async {
        // CI pg: closing the offer first made an admitted helper's
        // `commitmentReleased` notice recipient_safe, which the outbox
        // check constraint refuses for `commitment_released`. Access here
        // follows the live offer, as the real guard does once the helper is
        // out of the room.
        final liveAccess = TestAttentionHarness(
          canReadContent: (viewerId) async =>
              viewerId == _authorId ||
              await helpOffers.hasActiveHelpOffer(
                beaconId: _beaconId,
                userId: viewerId,
              ),
        );
        final caseWithLiveAccess = CoordinationCase(
          beacons,
          helpOffers,
          coordinationRepo,
          roomRepo,
          FakeUserBlockRepository(),
          commitments,
          CommitmentQueryCase(
            commitments,
            helpOffers,
            env: env,
            logger: Logger('LeaveInWrappingUpTest'),
          ),
          FakeBeaconHierarchyRepository(),
          attentionIntents: liveAccess.intents,
          attention: liveAccess.transactional,
          guard: FakeBeaconAccessGuard(),
          closureCase: closureCase,
          env: env,
          logger: Logger('LeaveInWrappingUpTest'),
        );
        await seedAcceptedHelperThenWrappingUp();

        await caseWithLiveAccess.releaseCommitment(
          beaconId: _beaconId,
          offerUserId: _helperId,
          authorUserId: _authorId,
          reason: 'scope changed',
        );

        final released = liveAccess.recorded
            .where((i) => i.eventType == AttentionEventType.commitmentReleased)
            .single;
        final helper = released.recipients.singleWhere(
          (r) => r.recipientId == _helperId,
        );
        expect(helper.role.canReadBeaconContent, isTrue);
        await expectOfferClosedWithoutExitReason();
      },
    );

    test(
      'a helper who is not admitted is not removed from the room again',
      () async {
        // Guard: only the offer is closed; no second removal, no room line.
        await seedAcceptedHelperThenWrappingUp();
        stubHelperParticipant(helperWithAccess(RoomAccessBits.none));

        await releaseHelper();

        verifyNever(
          coordinationRepo.removeFromRoom(
            beaconId: anyNamed('beaconId'),
            offerUserId: anyNamed('offerUserId'),
            actorUserId: anyNamed('actorUserId'),
            reason: anyNamed('reason'),
          ),
        );
        verifyNever(
          roomRepo.recordParticipantRemoved(
            beaconId: anyNamed('beaconId'),
            userId: anyNamed('userId'),
          ),
        );
      },
    );
  });
}
