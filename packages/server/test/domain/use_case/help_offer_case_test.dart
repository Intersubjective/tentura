import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/consts/beacon_participant_status_bits.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/use_case/capability_case.dart';
import 'package:tentura_server/domain/use_case/help_offer_case.dart';

import 'help_offer_case_mocks.mocks.dart';
import '../../support/block_aware_beacon_access_guard.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/recording_commitment_repository.dart';
import '../../support/test_attention_harness.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

void main() {
  late MockBeaconRepositoryPort beaconRepo;
  late MockHelpOfferRepositoryPort helpOfferRepo;
  late MockInboxRepositoryPort inboxRepo;
  late MockPersonCapabilityEventRepositoryPort capabilityRepo;
  late MockBeaconRoomRepositoryPort roomRepo;
  late MockCoordinationRepositoryPort coordinationRepo;
  late RecordingCommitmentRepository commitmentRepo;
  late CapabilityCase capabilityCase;
  late TestAttentionHarness attention;
  late HelpOfferCase case_;

  final now = DateTime.utc(2025);
  BeaconEntity beacon({
    required String id,
    required BeaconStatus status,
    String authorId = 'Uauth',
  }) => BeaconEntity(
    id: id,
    title: 't',
    author: UserEntity(id: authorId),
    createdAt: now,
    updatedAt: now,
    status: status,
  );

  void stubBeacon(BeaconEntity b) {
    when(
      beaconRepo.getBeaconById(beaconId: b.id),
    ).thenAnswer((_) async => b);
  }

  setUp(() {
    beaconRepo = MockBeaconRepositoryPort();
    helpOfferRepo = MockHelpOfferRepositoryPort();
    inboxRepo = MockInboxRepositoryPort();
    capabilityRepo = MockPersonCapabilityEventRepositoryPort();
    roomRepo = MockBeaconRoomRepositoryPort();
    coordinationRepo = MockCoordinationRepositoryPort();
    commitmentRepo = RecordingCommitmentRepository();
    attention = TestAttentionHarness();
    capabilityCase = CapabilityCase(
      capabilityRepo,
      env: Env(environment: Environment.test),
      logger: Logger('CapabilityCaseTest'),
    );
    case_ = HelpOfferCase(
      helpOfferRepo,
      beaconRepo,
      commitmentRepo,
      inboxRepo,
      capabilityCase,
      FakeBeaconAccessGuard(),
      attentionIntents: attention.intents,
      attention: attention.transactional,
      env: Env(environment: Environment.test),
      logger: Logger('HelpOfferCaseTest'),
    );
  });

  group('withdraw lifecycle', () {
    test('rejects CLOSED (1)', () async {
      stubBeacon(beacon(id: 'B1', status: BeaconStatus.cancelled));

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
      stubBeacon(beacon(id: 'B1', status: BeaconStatus.deleted));

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
      stubBeacon(beacon(id: 'B1', status: BeaconStatus.draft));

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
      stubBeacon(beacon(id: 'B1', status: BeaconStatus.closed));

      await expectLater(
        case_.withdraw(
          beaconId: 'B1',
          userId: 'U1',
          withdrawReason: 'other',
        ),
        throwsA(isA<HelpOfferCoordinationException>()),
      );
    });

    test('rejects WRAPPING UP (reviewOpen)', () async {
      stubBeacon(beacon(id: 'B1', status: BeaconStatus.reviewOpen));

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

    test('allows OPEN (0)', () async {
      stubBeacon(beacon(id: 'B1', status: BeaconStatus.open));
      when(
        helpOfferRepo.withdraw(
          beaconId: 'B1',
          userId: 'U1',
          withdrawReason: 'other',
        ),
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

      expect(commitmentRepo.recordCalls, [
        (
          beaconId: 'B1',
          userId: 'U1',
          actorUserId: 'U1',
          kind: CommitmentEventKind.withdrawnByHelper,
          reason: 'other',
        ),
      ]);
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
      // Open-beacon withdrawal notifies the author/stewards.
      expect(attention.recorded.single.eventType.name, 'promiseWithdrawn');
    });
  });

  group('offerHelp', () {
    test('rejects when beacon not OPEN', () async {
      stubBeacon(beacon(id: 'B1', status: BeaconStatus.closed));

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
      stubBeacon(beacon(id: 'B1', status: BeaconStatus.open));
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
      stubBeacon(beacon(id: 'B1', status: BeaconStatus.open));
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

      await case_.offerHelp(beaconId: 'B1', userId: 'U1', message: 'updated');

      verify(
        helpOfferRepo.upsert(
          beaconId: 'B1',
          userId: 'U1',
          message: 'updated',
        ),
      ).called(1);
    });
  });

  group('direct author forward recipient offer (P5 — no auto-admit)', () {
    void stubNewHelpOffer() {
      stubBeacon(beacon(id: 'B1', status: BeaconStatus.open));
      when(
        helpOfferRepo.hasActiveHelpOffer(beaconId: 'B1', userId: 'U1'),
      ).thenAnswer((_) async => false);
      when(
        helpOfferRepo.upsert(beaconId: 'B1', userId: 'U1'),
      ).thenAnswer((_) async {});
    }

    test(
      'does not write coordination response or acknowledged commitment event',
      () async {
        stubNewHelpOffer();

        await case_.offerHelp(beaconId: 'B1', userId: 'U1');

        verifyNever(
          coordinationRepo.upsertResponse(
            beaconId: anyNamed('beaconId'),
            offerUserId: anyNamed('offerUserId'),
            authorUserId: anyNamed('authorUserId'),
            responseType: anyNamed('responseType'),
          ),
        );
        verifyNever(
          roomRepo.inviteOfferUserToBeaconRoom(
            beaconId: anyNamed('beaconId'),
            offerUserId: anyNamed('offerUserId'),
            authorUserId: anyNamed('authorUserId'),
            admissionReason: anyNamed('admissionReason'),
          ),
        );
        expect(
          commitmentRepo.recordCalls.map((c) => c.kind),
          [CommitmentEventKind.offered],
        );
        expect(
          attention.recorded.map((intent) => intent.eventType.name),
          ['helpOfferSubmitted'],
        );
      },
    );
  });

  group('offerHelp — author notification', () {
    void stubNewHelpOffer() {
      stubBeacon(beacon(id: 'B1', status: BeaconStatus.open));
      when(
        helpOfferRepo.hasActiveHelpOffer(beaconId: 'B1', userId: 'U1'),
      ).thenAnswer((_) async => false);
      when(
        helpOfferRepo.upsert(beaconId: 'B1', userId: 'U1'),
      ).thenAnswer((_) => Future.value());
    }

    test('notifies author on initial help offer', () async {
      stubNewHelpOffer();

      await case_.offerHelp(beaconId: 'B1', userId: 'U1');

      expect(attention.recorded.single.eventType.name, 'helpOfferSubmitted');
    });

    test(
      'does NOT notify author on help offer update (hasActive=true)',
      () async {
        stubBeacon(beacon(id: 'B1', status: BeaconStatus.open));
        when(
          helpOfferRepo.hasActiveHelpOffer(beaconId: 'B1', userId: 'U1'),
        ).thenAnswer((_) async => true);
        when(
          helpOfferRepo.upsert(beaconId: 'B1', userId: 'U1'),
        ).thenAnswer((_) => Future.value());

        await case_.offerHelp(beaconId: 'B1', userId: 'U1');

        expect(attention.recorded, isEmpty);
      },
    );
  });

  group('offerHelp — blocked author/offerer pair (E4, covered by S6 canReadContent)',
      () {
    late FakeUserBlockRepository blocks;

    setUp(() {
      blocks = FakeUserBlockRepository();
      case_ = HelpOfferCase(
        helpOfferRepo,
        beaconRepo,
        RecordingCommitmentRepository(),
        inboxRepo,
        capabilityCase,
        BlockAwareBeaconAccessGuard(
          blocks: blocks,
          beaconRepo: beaconRepo,
        ),
        attentionIntents: attention.intents,
        attention: attention.transactional,
        env: Env(environment: Environment.test),
        logger: Logger('HelpOfferCaseBlockTest'),
      );
    });

    test('rejects when author blocked offerer', () async {
      stubBeacon(
        beacon(id: 'B1', status: BeaconStatus.open, authorId: 'Uauth'),
      );
      blocks.blockPair('Uauth', 'Uofferer');

      await expectLater(
        case_.offerHelp(beaconId: 'B1', userId: 'Uofferer'),
        throwsA(isA<UnauthorizedException>()),
      );
      verifyNever(
        helpOfferRepo.upsert(
          beaconId: anyNamed('beaconId'),
          userId: anyNamed('userId'),
          message: anyNamed('message'),
          helpTypes: anyNamed('helpTypes'),
        ),
      );
    });

    test('rejects when offerer blocked author', () async {
      stubBeacon(
        beacon(id: 'B1', status: BeaconStatus.open, authorId: 'Uauth'),
      );
      blocks.blockPair('Uofferer', 'Uauth');

      await expectLater(
        case_.offerHelp(beaconId: 'B1', userId: 'Uofferer'),
        throwsA(isA<UnauthorizedException>()),
      );
    });
  });
}
