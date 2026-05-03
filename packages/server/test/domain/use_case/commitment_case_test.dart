import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/consts/beacon_participant_status_bits.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart' show BeaconParticipant;
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/use_case/capability_case.dart';
import 'package:tentura_server/domain/use_case/commitment_case.dart';

import 'commitment_case_mocks.mocks.dart';

void main() {
  late MockBeaconRepositoryPort beaconRepo;
  late MockCommitmentRepositoryPort commitmentRepo;
  late MockCoordinationRepositoryPort coordinationRepo;
  late MockInboxRepositoryPort inboxRepo;
  late MockPersonCapabilityEventRepositoryPort capabilityRepo;
  late MockBeaconRoomRepository roomRepo;
  late MockVoteUserFriendshipLookup friendshipLookup;
  late MockBeaconRoomPushService roomPush;
  late CapabilityCase capabilityCase;
  late CommitmentCase case_;

  final now = DateTime.utc(2025);
  BeaconEntity beacon({
    required String id,
    required int state,
    String authorId = 'Uauth',
  }) =>
      BeaconEntity(
        id: id,
        title: 't',
        author: UserEntity(id: authorId),
        createdAt: now,
        updatedAt: now,
        state: state,
      );

  void stubBeacon(BeaconEntity b) {
    when(
      beaconRepo.getBeaconById(beaconId: b.id),
    ).thenAnswer((_) async => b);
  }

  setUp(() {
    beaconRepo = MockBeaconRepositoryPort();
    commitmentRepo = MockCommitmentRepositoryPort();
    coordinationRepo = MockCoordinationRepositoryPort();
    inboxRepo = MockInboxRepositoryPort();
    capabilityRepo = MockPersonCapabilityEventRepositoryPort();
    roomRepo = MockBeaconRoomRepository();
    friendshipLookup = MockVoteUserFriendshipLookup();
    roomPush = MockBeaconRoomPushService();
    capabilityCase = CapabilityCase(
      capabilityRepo,
      env: Env(environment: Environment.test),
      logger: Logger('CapabilityCaseTest'),
    );
    case_ = CommitmentCase(
      commitmentRepo,
      beaconRepo,
      coordinationRepo,
      inboxRepo,
      capabilityCase,
      roomRepo,
      friendshipLookup,
      roomPush,
      env: Env(environment: Environment.test),
      logger: Logger('CommitmentCaseTest'),
    );
    // Default: no friendship, so auto-admit never fires unless overridden.
    when(
      friendshipLookup.isSubscribedTo(
        viewerId: anyNamed('viewerId'),
        peerId: anyNamed('peerId'),
      ),
    ).thenAnswer((_) async => false);
  });

  group('withdraw lifecycle', () {
    test('rejects CLOSED (1)', () async {
      stubBeacon(beacon(id: 'B1', state: 1));

      await expectLater(
        case_.withdraw(
          beaconId: 'B1',
          userId: 'U1',
          uncommitReason: 'other',
        ),
        throwsA(
          isA<CommitmentCoordinationException>().having(
            (e) =>
                (e.code as CommitmentCoordinationExceptionCodes).exceptionCode,
            'code',
            CommitmentCoordinationExceptionCode.beaconWithdrawForbidden,
          ),
        ),
      );
      verifyZeroInteractions(commitmentRepo);
      verifyZeroInteractions(inboxRepo);
    });

    test('rejects DELETED (2)', () async {
      stubBeacon(beacon(id: 'B1', state: 2));

      await expectLater(
        case_.withdraw(
          beaconId: 'B1',
          userId: 'U1',
          uncommitReason: 'other',
        ),
        throwsA(isA<CommitmentCoordinationException>()),
      );
    });

    test('rejects DRAFT (3)', () async {
      stubBeacon(beacon(id: 'B1', state: 3));

      await expectLater(
        case_.withdraw(
          beaconId: 'B1',
          userId: 'U1',
          uncommitReason: 'other',
        ),
        throwsA(isA<CommitmentCoordinationException>()),
      );
    });

    test('rejects CLOSED_REVIEW_COMPLETE (6)', () async {
      stubBeacon(beacon(id: 'B1', state: 6));

      await expectLater(
        case_.withdraw(
          beaconId: 'B1',
          userId: 'U1',
          uncommitReason: 'other',
        ),
        throwsA(isA<CommitmentCoordinationException>()),
      );
    });

    test('allows OPEN (0)', () async {
      stubBeacon(beacon(id: 'B1', state: 0));
      when(
        coordinationRepo.deleteForCommit(beaconId: 'B1', userId: 'U1'),
      ).thenAnswer((_) => Future.value());
      when(
        commitmentRepo.withdraw(
          beaconId: 'B1',
          userId: 'U1',
          uncommitReason: 'other',
        ),
      ).thenAnswer((_) => Future.value());
      when(
        coordinationRepo.recomputeAndPersistBeaconCoordinationStatus('B1'),
      ).thenAnswer((_) => Future.value());
      when(
        inboxRepo.upsertWatchingForSender(
          senderId: 'U1',
          beaconId: 'B1',
          touchForwardOrdering: false,
        ),
      ).thenAnswer((_) => Future.value());

      await case_.withdraw(
        beaconId: 'B1',
        userId: 'U1',
        uncommitReason: 'other',
      );

      verify(
        commitmentRepo.withdraw(
          beaconId: 'B1',
          userId: 'U1',
          uncommitReason: 'other',
        ),
      ).called(1);
      verify(
        inboxRepo.upsertWatchingForSender(
          senderId: 'U1',
          beaconId: 'B1',
          touchForwardOrdering: false,
        ),
      ).called(1);
    });

    test('allows PENDING_REVIEW (4) and CLOSED_REVIEW_OPEN (5)', () async {
      for (final state in [4, 5]) {
        reset(beaconRepo);
        reset(commitmentRepo);
        reset(coordinationRepo);
        reset(inboxRepo);
        stubBeacon(beacon(id: 'B1', state: state));
        when(
          coordinationRepo.deleteForCommit(beaconId: 'B1', userId: 'U1'),
        ).thenAnswer((_) => Future.value());
        when(
          commitmentRepo.withdraw(
            beaconId: 'B1',
            userId: 'U1',
            uncommitReason: 'timing',
          ),
        ).thenAnswer((_) => Future.value());
        when(
          coordinationRepo.recomputeAndPersistBeaconCoordinationStatus('B1'),
        ).thenAnswer((_) => Future.value());
        when(
          inboxRepo.applyTombstoneAfterWithdraw(
            userId: 'U1',
            beaconId: 'B1',
          ),
        ).thenAnswer((_) => Future.value());

        await case_.withdraw(
          beaconId: 'B1',
          userId: 'U1',
          uncommitReason: 'timing',
        );
        verify(
          commitmentRepo.withdraw(
            beaconId: 'B1',
            userId: 'U1',
            uncommitReason: 'timing',
          ),
        ).called(1);
        verify(
          inboxRepo.applyTombstoneAfterWithdraw(
            userId: 'U1',
            beaconId: 'B1',
          ),
        ).called(1);
      }
    });
  });

  group('commit', () {
    test('rejects when beacon not OPEN', () async {
      stubBeacon(beacon(id: 'B1', state: 1));

      await expectLater(
        case_.commit(beaconId: 'B1', userId: 'U1'),
        throwsA(
          isA<CommitmentCoordinationException>().having(
            (e) =>
                (e.code as CommitmentCoordinationExceptionCodes).exceptionCode,
            'code',
            CommitmentCoordinationExceptionCode.beaconNotOpen,
          ),
        ),
      );
    });

    test('rejects author on initial commit', () async {
      stubBeacon(beacon(id: 'B1', state: 0));
      when(
        commitmentRepo.hasActiveCommitment(
          beaconId: 'B1',
          userId: 'Uauth',
        ),
      ).thenAnswer((_) async => false);

      await expectLater(
        case_.commit(beaconId: 'B1', userId: 'Uauth'),
        throwsA(
          isA<CommitmentCoordinationException>().having(
            (e) =>
                (e.code as CommitmentCoordinationExceptionCodes).exceptionCode,
            'code',
            CommitmentCoordinationExceptionCode.authorCannotCommit,
          ),
        ),
      );
      verifyNever(
        commitmentRepo.upsert(
          beaconId: 'B1',
          userId: 'Uauth',
        ),
      );
    });

    test('allows upsert when already committed (update note)', () async {
      stubBeacon(beacon(id: 'B1', state: 0));
      when(
        commitmentRepo.hasActiveCommitment(
          beaconId: 'B1',
          userId: 'U1',
        ),
      ).thenAnswer((_) async => true);
      when(
        commitmentRepo.upsert(
          beaconId: 'B1',
          userId: 'U1',
          message: 'updated',
        ),
      ).thenAnswer((_) => Future.value());
      when(
        coordinationRepo.recomputeAndPersistBeaconCoordinationStatus('B1'),
      ).thenAnswer((_) => Future.value());

      await case_.commit(beaconId: 'B1', userId: 'U1', message: 'updated');

      verify(
        commitmentRepo.upsert(
          beaconId: 'B1',
          userId: 'U1',
          message: 'updated',
        ),
      ).called(1);
      // Auto-admit must NOT run on the update path.
      verifyNever(
        friendshipLookup.isSubscribedTo(
          viewerId: anyNamed('viewerId'),
          peerId: anyNamed('peerId'),
        ),
      );
    });
  });

  group('auto-admit on new commit', () {
    final epoch = PgDateTime(DateTime.utc(2025));

    BeaconParticipant participant({required int roomAccess}) =>
        BeaconParticipant(
          createdAt: epoch,
          updatedAt: epoch,
          id: 'P1',
          beaconId: 'B1',
          userId: 'U1',
          role: BeaconParticipantRoleBits.helper,
          status: BeaconParticipantStatusBits.offeredHelp,
          roomAccess: roomAccess,
        );

    void stubNewCommit() {
      stubBeacon(beacon(id: 'B1', state: 0));
      when(
        commitmentRepo.hasActiveCommitment(beaconId: 'B1', userId: 'U1'),
      ).thenAnswer((_) async => false);
      when(
        commitmentRepo.upsert(beaconId: 'B1', userId: 'U1'),
      ).thenAnswer((_) => Future.value());
      when(
        coordinationRepo.recomputeAndPersistBeaconCoordinationStatus('B1'),
      ).thenAnswer((_) => Future.value());
    }

    test('admits when author subscribed to committant (no existing participant)',
        () async {
      stubNewCommit();
      when(
        friendshipLookup.isSubscribedTo(
          viewerId: 'Uauth',
          peerId: 'U1',
        ),
      ).thenAnswer((_) async => true);
      when(
        roomRepo.findParticipant(beaconId: 'B1', userId: 'U1'),
      ).thenAnswer((_) async => null);
      when(
        roomRepo.inviteCommitUserToBeaconRoom(
          beaconId: 'B1',
          commitUserId: 'U1',
          authorUserId: 'Uauth',
        ),
      ).thenAnswer((_) => Future.value());
      when(
        roomPush.notifyRoomAdmitted(receiverId: 'U1', beaconId: 'B1'),
      ).thenAnswer((_) => Future.value());

      await case_.commit(beaconId: 'B1', userId: 'U1');

      verify(
        roomRepo.inviteCommitUserToBeaconRoom(
          beaconId: 'B1',
          commitUserId: 'U1',
          authorUserId: 'Uauth',
        ),
      ).called(1);
      verify(
        roomPush.notifyRoomAdmitted(receiverId: 'U1', beaconId: 'B1'),
      ).called(1);
    });

    test('skips admit when not a direct friend', () async {
      stubNewCommit();
      // friendshipLookup returns false by default (set in setUp).

      await case_.commit(beaconId: 'B1', userId: 'U1');

      verifyNever(
        roomRepo.inviteCommitUserToBeaconRoom(
          beaconId: anyNamed('beaconId'),
          commitUserId: anyNamed('commitUserId'),
          authorUserId: anyNamed('authorUserId'),
        ),
      );
    });

    test('skips admit when author explicitly revoked access (roomAccess=none)',
        () async {
      stubNewCommit();
      when(
        friendshipLookup.isSubscribedTo(
          viewerId: 'Uauth',
          peerId: 'U1',
        ),
      ).thenAnswer((_) async => true);
      when(
        roomRepo.findParticipant(beaconId: 'B1', userId: 'U1'),
      ).thenAnswer((_) async => participant(roomAccess: RoomAccessBits.none));

      await case_.commit(beaconId: 'B1', userId: 'U1');

      verifyNever(
        roomRepo.inviteCommitUserToBeaconRoom(
          beaconId: anyNamed('beaconId'),
          commitUserId: anyNamed('commitUserId'),
          authorUserId: anyNamed('authorUserId'),
        ),
      );
    });

    test('re-admits when friend and participant exists with non-none access',
        () async {
      stubNewCommit();
      when(
        friendshipLookup.isSubscribedTo(
          viewerId: 'Uauth',
          peerId: 'U1',
        ),
      ).thenAnswer((_) async => true);
      when(
        roomRepo.findParticipant(beaconId: 'B1', userId: 'U1'),
      ).thenAnswer(
        (_) async => participant(roomAccess: RoomAccessBits.requested),
      );
      when(
        roomRepo.inviteCommitUserToBeaconRoom(
          beaconId: 'B1',
          commitUserId: 'U1',
          authorUserId: 'Uauth',
        ),
      ).thenAnswer((_) => Future.value());
      when(
        roomPush.notifyRoomAdmitted(receiverId: 'U1', beaconId: 'B1'),
      ).thenAnswer((_) => Future.value());

      await case_.commit(beaconId: 'B1', userId: 'U1');

      verify(
        roomRepo.inviteCommitUserToBeaconRoom(
          beaconId: 'B1',
          commitUserId: 'U1',
          authorUserId: 'Uauth',
        ),
      ).called(1);
    });
  });
}
