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
import 'package:tentura_server/domain/entity/gql_public/help_offer_with_coordination_row.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/use_case/capability_case.dart';
import 'package:tentura_server/domain/use_case/help_offer_case.dart';

import 'help_offer_case_mocks.mocks.dart';

void main() {
  late MockBeaconRepositoryPort beaconRepo;
  late MockHelpOfferRepositoryPort helpOfferRepo;
  late MockCoordinationRepositoryPort coordinationRepo;
  late MockInboxRepositoryPort inboxRepo;
  late MockPersonCapabilityEventRepositoryPort capabilityRepo;
  late MockBeaconRoomRepository roomRepo;
  late MockVoteUserFriendshipLookup friendshipLookup;
  late MockForwardEdgeRepositoryPort forwardEdgeRepo;
  late MockBeaconRoomPushService roomPush;
  late CapabilityCase capabilityCase;
  late HelpOfferCase case_;

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
    helpOfferRepo = MockHelpOfferRepositoryPort();
    coordinationRepo = MockCoordinationRepositoryPort();
    inboxRepo = MockInboxRepositoryPort();
    capabilityRepo = MockPersonCapabilityEventRepositoryPort();
    roomRepo = MockBeaconRoomRepository();
    friendshipLookup = MockVoteUserFriendshipLookup();
    forwardEdgeRepo = MockForwardEdgeRepositoryPort();
    roomPush = MockBeaconRoomPushService();
    capabilityCase = CapabilityCase(
      capabilityRepo,
      env: Env(environment: Environment.test),
      logger: Logger('CapabilityCaseTest'),
    );
    case_ = HelpOfferCase(
      helpOfferRepo,
      beaconRepo,
      coordinationRepo,
      inboxRepo,
      capabilityCase,
      roomRepo,
      friendshipLookup,
      forwardEdgeRepo,
      roomPush,
      env: Env(environment: Environment.test),
      logger: Logger('HelpOfferCaseTest'),
    );
    // Default: not trusted — no direct forward, no mutual friendship.
    when(
      forwardEdgeRepo.isDirectAuthorForward(
        beaconId: anyNamed('beaconId'),
        authorId: anyNamed('authorId'),
        userId: anyNamed('userId'),
      ),
    ).thenAnswer((_) async => false);
    when(
      friendshipLookup.isReciprocalSubscribe(
        viewerId: anyNamed('viewerId'),
        peerId: anyNamed('peerId'),
      ),
    ).thenAnswer((_) async => false);
    when(
      roomPush.notifyHelpOfferToAuthor(
        beaconId: anyNamed('beaconId'),
        helpOffererId: anyNamed('helpOffererId'),
        authorId: anyNamed('authorId'),
      ),
    ).thenAnswer((_) async {});
  });

  group('withdraw lifecycle', () {
    test('rejects CLOSED (1)', () async {
      stubBeacon(beacon(id: 'B1', state: 1));

      await expectLater(
        case_.withdraw(
          beaconId: 'B1',
          userId: 'U1',
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
      verifyZeroInteractions(helpOfferRepo);
      verifyZeroInteractions(inboxRepo);
    });

    test('rejects DELETED (2)', () async {
      stubBeacon(beacon(id: 'B1', state: 2));

      await expectLater(
        case_.withdraw(
          beaconId: 'B1',
          userId: 'U1',
          withdrawReason: 'other',
        ),
        throwsA(isA<HelpOfferCoordinationException>()),
      );
    });

    test('rejects DRAFT (3)', () async {
      stubBeacon(beacon(id: 'B1', state: 3));

      await expectLater(
        case_.withdraw(
          beaconId: 'B1',
          userId: 'U1',
          withdrawReason: 'other',
        ),
        throwsA(isA<HelpOfferCoordinationException>()),
      );
    });

    test('rejects CLOSED_REVIEW_COMPLETE (6)', () async {
      stubBeacon(beacon(id: 'B1', state: 6));

      await expectLater(
        case_.withdraw(
          beaconId: 'B1',
          userId: 'U1',
          withdrawReason: 'other',
        ),
        throwsA(isA<HelpOfferCoordinationException>()),
      );
    });

    test('allows OPEN (0)', () async {
      stubBeacon(beacon(id: 'B1', state: 0));
      when(
        coordinationRepo.deleteForCommit(beaconId: 'B1', userId: 'U1'),
      ).thenAnswer((_) => Future.value());
      when(
        helpOfferRepo.withdraw(
          beaconId: 'B1',
          userId: 'U1',
          withdrawReason: 'other',
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
        withdrawReason: 'other',
      );

      verify(
        helpOfferRepo.withdraw(
          beaconId: 'B1',
          userId: 'U1',
          withdrawReason: 'other',
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
        reset(helpOfferRepo);
        reset(coordinationRepo);
        reset(inboxRepo);
        stubBeacon(beacon(id: 'B1', state: state));
        when(
          coordinationRepo.deleteForCommit(beaconId: 'B1', userId: 'U1'),
        ).thenAnswer((_) => Future.value());
        when(
          helpOfferRepo.withdraw(
            beaconId: 'B1',
            userId: 'U1',
            withdrawReason: 'timing',
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
          withdrawReason: 'timing',
        );
        verify(
          helpOfferRepo.withdraw(
            beaconId: 'B1',
            userId: 'U1',
            withdrawReason: 'timing',
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

  group('offerHelp', () {
    test('rejects when beacon not OPEN', () async {
      stubBeacon(beacon(id: 'B1', state: 1));

      await expectLater(
        case_.offerHelp(beaconId: 'B1', userId: 'U1'),
        throwsA(
          isA<HelpOfferCoordinationException>().having(
            (e) =>
                (e.code as HelpOfferCoordinationExceptionCodes).exceptionCode,
            'code',
            HelpOfferCoordinationExceptionCode.beaconNotOpen,
          ),
        ),
      );
    });

    test('rejects author on initial offer', () async {
      stubBeacon(beacon(id: 'B1', state: 0));
      when(
        helpOfferRepo.hasActiveHelpOffer(
          beaconId: 'B1',
          userId: 'Uauth',
        ),
      ).thenAnswer((_) async => false);

      await expectLater(
        case_.offerHelp(beaconId: 'B1', userId: 'Uauth'),
        throwsA(
          isA<HelpOfferCoordinationException>().having(
            (e) =>
                (e.code as HelpOfferCoordinationExceptionCodes).exceptionCode,
            'code',
            HelpOfferCoordinationExceptionCode.authorCannotCommit,
          ),
        ),
      );
      verifyNever(
        helpOfferRepo.upsert(
          beaconId: 'B1',
          userId: 'Uauth',
        ),
      );
    });

    test('allows upsert when already offered help (update note)', () async {
      stubBeacon(beacon(id: 'B1', state: 0));
      when(
        helpOfferRepo.hasActiveHelpOffer(
          beaconId: 'B1',
          userId: 'U1',
        ),
      ).thenAnswer((_) async => true);
      when(
        helpOfferRepo.upsert(
          beaconId: 'B1',
          userId: 'U1',
          message: 'updated',
        ),
      ).thenAnswer((_) => Future.value());
      when(
        coordinationRepo.recomputeAndPersistBeaconCoordinationStatus('B1'),
      ).thenAnswer((_) => Future.value());

      await case_.offerHelp(beaconId: 'B1', userId: 'U1', message: 'updated');

      verify(
        helpOfferRepo.upsert(
          beaconId: 'B1',
          userId: 'U1',
          message: 'updated',
        ),
      ).called(1);
      // Auto-admit must NOT run on the update path.
      verifyNever(
        forwardEdgeRepo.isDirectAuthorForward(
          beaconId: anyNamed('beaconId'),
          authorId: anyNamed('authorId'),
          userId: anyNamed('userId'),
        ),
      );
      verifyNever(
        friendshipLookup.isReciprocalSubscribe(
          viewerId: anyNamed('viewerId'),
          peerId: anyNamed('peerId'),
        ),
      );
    });
  });

  group('auto-admit on new help offer', () {
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

    void stubNewHelpOffer() {
      stubBeacon(beacon(id: 'B1', state: 0));
      when(
        helpOfferRepo.hasActiveHelpOffer(beaconId: 'B1', userId: 'U1'),
      ).thenAnswer((_) async => false);
      when(
        helpOfferRepo.upsert(beaconId: 'B1', userId: 'U1'),
      ).thenAnswer((_) async {});
      when(
        coordinationRepo.recomputeAndPersistBeaconCoordinationStatus('B1'),
      ).thenAnswer((_) => Future.value());
    }

    void stubAdmitCalls() {
      when(
        roomRepo.findParticipant(beaconId: 'B1', userId: 'U1'),
      ).thenAnswer((_) async => null);
      when(
        roomRepo.inviteOfferUserToBeaconRoom(
          beaconId: 'B1',
          offerUserId: 'U1',
          authorUserId: 'Uauth',
        ),
      ).thenAnswer((_) => Future.value());
      when(
        roomPush.notifyRoomAdmitted(
          receiverId: 'U1',
          beaconId: 'B1',
          actorUserId: 'Uauth',
        ),
      ).thenAnswer((_) => Future.value());
    }

    test('admits when author directly forwarded beacon to help offerer', () async {
      stubNewHelpOffer();
      when(
        forwardEdgeRepo.isDirectAuthorForward(
          beaconId: 'B1',
          authorId: 'Uauth',
          userId: 'U1',
        ),
      ).thenAnswer((_) async => true);
      stubAdmitCalls();

      await case_.offerHelp(beaconId: 'B1', userId: 'U1');

      verify(
        roomRepo.inviteOfferUserToBeaconRoom(
          beaconId: 'B1',
          offerUserId: 'U1',
          authorUserId: 'Uauth',
        ),
      ).called(1);
      verify(
        roomPush.notifyRoomAdmitted(
          receiverId: 'U1',
          beaconId: 'B1',
          actorUserId: 'Uauth',
        ),
      ).called(1);
    });

    test('admits when help offerer is a mutual (reciprocal) friend of author',
        () async {
      stubNewHelpOffer();
      // No direct forward — forward check returns false (default from setUp).
      when(
        friendshipLookup.isReciprocalSubscribe(
          viewerId: 'Uauth',
          peerId: 'U1',
        ),
      ).thenAnswer((_) async => true);
      stubAdmitCalls();

      await case_.offerHelp(beaconId: 'B1', userId: 'U1');

      verify(
        roomRepo.inviteOfferUserToBeaconRoom(
          beaconId: 'B1',
          offerUserId: 'U1',
          authorUserId: 'Uauth',
        ),
      ).called(1);
    });

    test('skips admit when only one-way author trust (not mutual, no direct forward)',
        () async {
      stubNewHelpOffer();
      // Both checks return false (defaults from setUp).

      await case_.offerHelp(beaconId: 'B1', userId: 'U1');

      verifyNever(
        roomRepo.inviteOfferUserToBeaconRoom(
          beaconId: anyNamed('beaconId'),
          offerUserId: anyNamed('offerUserId'),
          authorUserId: anyNamed('authorUserId'),
        ),
      );
    });

    test('skips admit when author explicitly revoked access (roomAccess=none)',
        () async {
      stubNewHelpOffer();
      when(
        forwardEdgeRepo.isDirectAuthorForward(
          beaconId: 'B1',
          authorId: 'Uauth',
          userId: 'U1',
        ),
      ).thenAnswer((_) async => true);
      when(
        roomRepo.findParticipant(beaconId: 'B1', userId: 'U1'),
      ).thenAnswer((_) async => participant(roomAccess: RoomAccessBits.none));

      await case_.offerHelp(beaconId: 'B1', userId: 'U1');

      verifyNever(
        roomRepo.inviteOfferUserToBeaconRoom(
          beaconId: anyNamed('beaconId'),
          offerUserId: anyNamed('offerUserId'),
          authorUserId: anyNamed('authorUserId'),
        ),
      );
    });

    test('re-admits trusted user when participant exists with non-none access',
        () async {
      stubNewHelpOffer();
      when(
        forwardEdgeRepo.isDirectAuthorForward(
          beaconId: 'B1',
          authorId: 'Uauth',
          userId: 'U1',
        ),
      ).thenAnswer((_) async => true);
      when(
        roomRepo.findParticipant(beaconId: 'B1', userId: 'U1'),
      ).thenAnswer(
        (_) async => participant(roomAccess: RoomAccessBits.requested),
      );
      when(
        roomRepo.inviteOfferUserToBeaconRoom(
          beaconId: 'B1',
          offerUserId: 'U1',
          authorUserId: 'Uauth',
        ),
      ).thenAnswer((_) => Future.value());
      when(
        roomPush.notifyRoomAdmitted(
          receiverId: 'U1',
          beaconId: 'B1',
          actorUserId: 'Uauth',
        ),
      ).thenAnswer((_) => Future.value());

      await case_.offerHelp(beaconId: 'B1', userId: 'U1');

      verify(
        roomRepo.inviteOfferUserToBeaconRoom(
          beaconId: 'B1',
          offerUserId: 'U1',
          authorUserId: 'Uauth',
        ),
      ).called(1);
    });
  });

  group('helpOffersWithCoordination after auto-admit (contract)', () {
    test('row may have admitted roomAccess before author coordination response', () {
      const user = UserPublicRecord(
        id: 'U1',
        title: 't',
        description: '',
      );
      final row = HelpOfferWithCoordinationRow(
        beaconId: 'B1',
        userId: 'U1',
        message: 'm',
        status: 0,
        createdAt: DateTime.utc(2025),
        updatedAt: DateTime.utc(2025),
        user: user,
        roomAccess: RoomAccessBits.admitted,
      );
      expect(row.responseType, isNull);
      expect(row.roomAccess, RoomAccessBits.admitted);
    });
  });

  group('offerHelp — author notification', () {
    void stubNewHelpOffer() {
      stubBeacon(beacon(id: 'B1', state: 0));
      when(
        helpOfferRepo.hasActiveHelpOffer(beaconId: 'B1', userId: 'U1'),
      ).thenAnswer((_) async => false);
      when(
        helpOfferRepo.upsert(beaconId: 'B1', userId: 'U1'),
      ).thenAnswer((_) => Future.value());
      when(
        coordinationRepo.recomputeAndPersistBeaconCoordinationStatus('B1'),
      ).thenAnswer((_) => Future.value());
    }

    test('notifies author on initial help offer', () async {
      stubNewHelpOffer();

      await case_.offerHelp(beaconId: 'B1', userId: 'U1');

      verify(
        roomPush.notifyHelpOfferToAuthor(
          beaconId: 'B1',
          helpOffererId: 'U1',
          authorId: 'Uauth',
        ),
      ).called(1);
    });

    test('does NOT notify author on help offer update (hasActive=true)', () async {
      stubBeacon(beacon(id: 'B1', state: 0));
      when(
        helpOfferRepo.hasActiveHelpOffer(beaconId: 'B1', userId: 'U1'),
      ).thenAnswer((_) async => true);
      when(
        helpOfferRepo.upsert(beaconId: 'B1', userId: 'U1'),
      ).thenAnswer((_) => Future.value());
      when(
        coordinationRepo.recomputeAndPersistBeaconCoordinationStatus('B1'),
      ).thenAnswer((_) => Future.value());

      await case_.offerHelp(beaconId: 'B1', userId: 'U1');

      verifyNever(
        roomPush.notifyHelpOfferToAuthor(
          beaconId: anyNamed('beaconId'),
          helpOffererId: anyNamed('helpOffererId'),
          authorId: anyNamed('authorId'),
        ),
      );
    });
  });
}
