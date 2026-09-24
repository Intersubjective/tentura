import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/gql_nodel_base.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_help_offer.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
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

class _LockingBeaconRepo extends Fake implements BeaconRepositoryPort {
  BeaconEntity _beacon = BeaconEntity(
    id: 'Bplaceholder1',
    title: 't',
    author: const UserEntity(id: 'Uauth'),
    createdAt: DateTime.utc(2025),
    updatedAt: DateTime.utc(2025),
    status: BeaconStatus.open,
  );

  void setBeacon(BeaconEntity beacon) => _beacon = beacon;

  @override
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) async =>
      _beacon;

  @override
  Future<T> runInBeaconStateTransaction<T>({
    required String beaconId,
    required String userId,
    required Future<T> Function(BeaconEntity locked) fn,
  }) =>
      fn(_beacon);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _LockingBeaconRepo beaconRepo;
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
    beaconRepo.setBeacon(b);
  }

  setUp(() {
    beaconRepo = _LockingBeaconRepo();
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
      roomRepository: roomRepo,
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
      verifyNever(
        helpOfferRepo.upsert(
          beaconId: anyNamed('beaconId'),
          userId: anyNamed('userId'),
        ),
      );
      expect(commitmentRepo.recordCalls, isEmpty);
      expect(attention.recorded, isEmpty);
    });

    test('rejects more than four help types', () async {
      stubBeacon(beacon(id: 'B1', status: BeaconStatus.open));
      when(
        helpOfferRepo.hasActiveHelpOffer(
          beaconId: 'B1',
          userId: 'U1',
        ),
      ).thenAnswer((_) async => false);

      await expectLater(
        case_.offerHelp(
          beaconId: 'B1',
          userId: 'U1',
          helpTypes: const [
            'money',
            'time',
            'transport',
            'storage',
            'tools',
          ],
        ),
        throwsA(
          isA<HelpOfferCoordinationException>().having(
            (e) =>
                (e.code as HelpOfferCoordinationExceptionCodes).exceptionCode,
            'code',
            HelpOfferCoordinationExceptionCode.invalidHelpType,
          ),
        ),
      );
      verifyNever(
        helpOfferRepo.upsert(
          beaconId: anyNamed('beaconId'),
          userId: anyNamed('userId'),
        ),
      );
      expect(commitmentRepo.recordCalls, isEmpty);
      expect(attention.recorded, isEmpty);
    });

    test('accepts four help types', () async {
      stubBeacon(beacon(id: 'B1', status: BeaconStatus.open));
      when(
        helpOfferRepo.hasActiveHelpOffer(
          beaconId: 'B1',
          userId: 'U1',
        ),
      ).thenAnswer((_) async => false);
      when(
        helpOfferRepo.upsert(
          beaconId: 'B1',
          userId: 'U1',
          helpTypes: anyNamed('helpTypes'),
          offerKind: anyNamed('offerKind'),
        ),
      ).thenAnswer((_) async {});

      await case_.offerHelp(
        beaconId: 'B1',
        userId: 'U1',
        helpTypes: const ['money', 'time', 'transport', 'storage'],
      );

      verify(
        helpOfferRepo.upsert(
          beaconId: 'B1',
          userId: 'U1',
          helpTypes: ['money', 'time', 'transport', 'storage'],
          offerKind: 0,
        ),
      ).called(1);
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
      expect(commitmentRepo.recordCalls, isEmpty);
      expect(attention.recorded, isEmpty);
    });

    test('allows upsert when already offered help (update note)', () async {
      stubBeacon(beacon(id: 'B1', status: BeaconStatus.open));
      when(
        helpOfferRepo.hasActiveHelpOffer(
          beaconId: 'B1',
          userId: 'U1',
        ),
      ).thenAnswer((_) async => true);
      when(helpOfferRepo.fetchByBeaconId('B1')).thenAnswer(
        (_) async => [
          HelpOfferEntity(
            beaconId: 'B1',
            userId: 'U1',
            createdAt: now,
            updatedAt: now,
            offerKind: 0,
          ),
        ],
      );
      when(
        helpOfferRepo.upsert(
          beaconId: 'B1',
          userId: 'U1',
          message: 'updated',
          offerKind: 0,
        ),
      ).thenAnswer((_) => Future.value());

      await case_.offerHelp(beaconId: 'B1', userId: 'U1', message: 'updated');

      verify(
        helpOfferRepo.upsert(
          beaconId: 'B1',
          userId: 'U1',
          message: 'updated',
          offerKind: 0,
        ),
      ).called(1);
      expect(commitmentRepo.recordCalls, isEmpty);
      expect(attention.recorded, isEmpty);
    });
  });

  group('offerHelp — expectedOfferKind', () {
    test(
      'rejects normal kind after locked status becomes enoughHelp with no writes',
      () async {
        stubBeacon(beacon(id: 'B1', status: BeaconStatus.enoughHelp));
        when(
          helpOfferRepo.hasActiveHelpOffer(beaconId: 'B1', userId: 'U1'),
        ).thenAnswer((_) async => false);

        await expectLater(
          case_.offerHelp(
            beaconId: 'B1',
            userId: 'U1',
            expectedOfferKind: 0,
          ),
          throwsA(
            isA<HelpOfferCoordinationException>().having(
              (e) =>
                  (e.code as HelpOfferCoordinationExceptionCodes).exceptionCode,
              'code',
              HelpOfferCoordinationExceptionCode.offerKindChanged,
            ),
          ),
        );

        verifyNever(
          helpOfferRepo.upsert(
            beaconId: anyNamed('beaconId'),
            userId: anyNamed('userId'),
          ),
        );
        expect(commitmentRepo.recordCalls, isEmpty);
        expect(attention.recorded, isEmpty);
      },
    );

    test(
      'rejects backup kind after locked status is open with no writes',
      () async {
        stubBeacon(beacon(id: 'B1', status: BeaconStatus.open));
        when(
          helpOfferRepo.hasActiveHelpOffer(beaconId: 'B1', userId: 'U1'),
        ).thenAnswer((_) async => false);

        await expectLater(
          case_.offerHelp(
            beaconId: 'B1',
            userId: 'U1',
            expectedOfferKind: 1,
          ),
          throwsA(
            isA<HelpOfferCoordinationException>().having(
              (e) =>
                  (e.code as HelpOfferCoordinationExceptionCodes).exceptionCode,
              'code',
              HelpOfferCoordinationExceptionCode.offerKindChanged,
            ),
          ),
        );

        verifyNever(
          helpOfferRepo.upsert(
            beaconId: anyNamed('beaconId'),
            userId: anyNamed('userId'),
          ),
        );
        expect(commitmentRepo.recordCalls, isEmpty);
        expect(attention.recorded, isEmpty);
      },
    );

    test('omitted kind keeps enoughHelp backup creation', () async {
      stubBeacon(beacon(id: 'B1', status: BeaconStatus.enoughHelp));
      when(
        helpOfferRepo.hasActiveHelpOffer(beaconId: 'B1', userId: 'U1'),
      ).thenAnswer((_) async => false);
      when(
        helpOfferRepo.upsert(
          beaconId: 'B1',
          userId: 'U1',
          offerKind: 1,
        ),
      ).thenAnswer((_) async {});

      await case_.offerHelp(beaconId: 'B1', userId: 'U1');

      verify(
        helpOfferRepo.upsert(
          beaconId: 'B1',
          userId: 'U1',
          offerKind: 1,
        ),
      ).called(1);
    });

    test(
      'active backup offer rejects normal expected kind without changing row',
      () async {
        stubBeacon(beacon(id: 'B1', status: BeaconStatus.enoughHelp));
        when(
          helpOfferRepo.hasActiveHelpOffer(beaconId: 'B1', userId: 'U1'),
        ).thenAnswer((_) async => true);
        when(helpOfferRepo.fetchByBeaconId('B1')).thenAnswer(
          (_) async => [
            HelpOfferEntity(
              beaconId: 'B1',
              userId: 'U1',
              createdAt: now,
              updatedAt: now,
              message: 'keep me',
              offerKind: 1,
            ),
          ],
        );

        await expectLater(
          case_.offerHelp(
            beaconId: 'B1',
            userId: 'U1',
            message: 'new text',
            expectedOfferKind: 0,
          ),
          throwsA(
            isA<HelpOfferCoordinationException>().having(
              (e) =>
                  (e.code as HelpOfferCoordinationExceptionCodes).exceptionCode,
              'code',
              HelpOfferCoordinationExceptionCode.offerKindChanged,
            ),
          ),
        );

        verifyNever(
          helpOfferRepo.upsert(
            beaconId: anyNamed('beaconId'),
            userId: anyNamed('userId'),
            message: anyNamed('message'),
          ),
        );
        expect(commitmentRepo.recordCalls, isEmpty);
        expect(attention.recorded, isEmpty);
      },
    );

    test(
      'matching active-offer update preserves kind and creates no receipt',
      () async {
        stubBeacon(beacon(id: 'B1', status: BeaconStatus.enoughHelp));
        when(
          helpOfferRepo.hasActiveHelpOffer(beaconId: 'B1', userId: 'U1'),
        ).thenAnswer((_) async => true);
        when(helpOfferRepo.fetchByBeaconId('B1')).thenAnswer(
          (_) async => [
            HelpOfferEntity(
              beaconId: 'B1',
              userId: 'U1',
              createdAt: now,
              updatedAt: now,
              offerKind: 1,
            ),
          ],
        );
        when(
          helpOfferRepo.upsert(
            beaconId: 'B1',
            userId: 'U1',
            message: 'updated',
            offerKind: 1,
          ),
        ).thenAnswer((_) async {});

        await case_.offerHelp(
          beaconId: 'B1',
          userId: 'U1',
          message: 'updated',
          expectedOfferKind: 1,
        );

        verify(
          helpOfferRepo.upsert(
            beaconId: 'B1',
            userId: 'U1',
            message: 'updated',
            offerKind: 1,
          ),
        ).called(1);
        expect(commitmentRepo.recordCalls, isEmpty);
        expect(attention.recorded, isEmpty);
      },
    );
  });

  group('offerHelp — offerKind assignment (P6)', () {
    void stubNewOffer(BeaconStatus status) {
      stubBeacon(beacon(id: 'B1', status: status));
      when(
        helpOfferRepo.hasActiveHelpOffer(beaconId: 'B1', userId: 'U1'),
      ).thenAnswer((_) async => false);
      when(
        helpOfferRepo.upsert(
          beaconId: 'B1',
          userId: 'U1',
          offerKind: anyNamed('offerKind'),
        ),
      ).thenAnswer((_) async {});
    }

    test('enoughHelp beacon persists offerKind 1', () async {
      stubNewOffer(BeaconStatus.enoughHelp);

      await case_.offerHelp(beaconId: 'B1', userId: 'U1');

      verify(
        helpOfferRepo.upsert(
          beaconId: 'B1',
          userId: 'U1',
          offerKind: 1,
        ),
      ).called(1);
    });

    test('open beacon persists offerKind 0', () async {
      stubNewOffer(BeaconStatus.open);

      await case_.offerHelp(beaconId: 'B1', userId: 'U1');

      verify(
        helpOfferRepo.upsert(
          beaconId: 'B1',
          userId: 'U1',
          offerKind: 0,
        ),
      ).called(1);
    });

    test('needsMoreHelp beacon persists offerKind 0', () async {
      stubNewOffer(BeaconStatus.needsMoreHelp);

      await case_.offerHelp(beaconId: 'B1', userId: 'U1');

      verify(
        helpOfferRepo.upsert(
          beaconId: 'B1',
          userId: 'U1',
          offerKind: 0,
        ),
      ).called(1);
    });

    test('enoughHelp notification uses backup-offer copy', () async {
      stubNewOffer(BeaconStatus.enoughHelp);

      await case_.offerHelp(beaconId: 'B1', userId: 'U1');

      expect(attention.recorded.single.eventType.name, 'helpOfferSubmitted');
      expect(attention.recorded.single.body, 'Actor offered to help as backup');
      expect(
        attention.recorded.single.priority,
        NotificationPriority.normal,
      );
    });

    test('open notification uses standard help-offer copy', () async {
      stubNewOffer(BeaconStatus.open);

      await case_.offerHelp(beaconId: 'B1', userId: 'U1');

      expect(attention.recorded.single.eventType.name, 'helpOfferSubmitted');
      expect(attention.recorded.single.body, 'Actor offered help');
    });

    test('open notification uses offer message as body excerpt', () async {
      stubNewOffer(BeaconStatus.open);

      await case_.offerHelp(
        beaconId: 'B1',
        userId: 'U1',
        message: 'I can sew the costume',
      );

      expect(attention.recorded.single.eventType.name, 'helpOfferSubmitted');
      expect(attention.recorded.single.body, 'I can sew the costume');
    });

    test('re-upsert preserves original offerKind when beacon status changed',
        () async {
      stubBeacon(beacon(id: 'B1', status: BeaconStatus.enoughHelp));
      when(
        helpOfferRepo.hasActiveHelpOffer(beaconId: 'B1', userId: 'U1'),
      ).thenAnswer((_) async => true);
      when(helpOfferRepo.fetchByBeaconId('B1')).thenAnswer(
        (_) async => [
          HelpOfferEntity(
            beaconId: 'B1',
            userId: 'U1',
            createdAt: now,
            updatedAt: now,
            offerKind: 0,
          ),
        ],
      );
      when(
        helpOfferRepo.upsert(
          beaconId: 'B1',
          userId: 'U1',
          message: 'updated',
          offerKind: 0,
        ),
      ).thenAnswer((_) async {});

      await case_.offerHelp(beaconId: 'B1', userId: 'U1', message: 'updated');

      verify(
        helpOfferRepo.upsert(
          beaconId: 'B1',
          userId: 'U1',
          message: 'updated',
          offerKind: 0,
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
        when(helpOfferRepo.fetchByBeaconId('B1')).thenAnswer(
          (_) async => [
            HelpOfferEntity(
              beaconId: 'B1',
              userId: 'U1',
              createdAt: now,
              updatedAt: now,
            ),
          ],
        );
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
        roomRepository: roomRepo,
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

  group('beaconOfferHelp schema compatibility', () {
    test('legacy operation validates and executes without expectedOfferKind', () async {
      const beaconId = 'Bhelpoffer001';
      stubBeacon(beacon(id: beaconId, status: BeaconStatus.open));
      when(
        helpOfferRepo.hasActiveHelpOffer(beaconId: beaconId, userId: 'U1'),
      ).thenAnswer((_) async => false);
      when(
        helpOfferRepo.upsert(beaconId: beaconId, userId: 'U1', offerKind: 0),
      ).thenAnswer((_) async {});

      final mutation = MutationHelpOffer(helpOfferCase: case_);
      final graphQL = GraphQL(
        GraphQLSchema(
          queryType: GraphQLObjectType('Query', 'Query root')
            ..fields.add(
              GraphQLObjectField(
                '_health',
                graphQLBoolean.nonNullable(),
                resolve: (_, __) => true,
              ),
            ),
          mutationType: GraphQLObjectType('Mutation', 'Mutation root')
            ..fields.addAll(mutation.all),
        ),
      );

      const document = r'''
mutation BeaconOfferHelp($beaconId: String!, $message: String) {
  beaconOfferHelp(id: $beaconId, message: $message)
}
''';

      final result =
          await graphQL.parseAndExecute(
                document,
                operationName: 'BeaconOfferHelp',
                variableValues: {
                  'beaconId': beaconId,
                  'message': 'hello',
                },
                globalVariables: {
                  kGlobalInputQueryJwt: const JwtEntity(sub: 'U1'),
                },
              )
              as Map<String, dynamic>;
      expect(result['errors'], isNull);
      expect(result['beaconOfferHelp'], isTrue);
    });
  });

  group('setRoleLabel', () {
    void stubActiveOffer({required String offerUserId}) {
      when(
        helpOfferRepo.hasActiveHelpOffer(
          beaconId: 'B1',
          userId: offerUserId,
        ),
      ).thenAnswer((_) async => true);
      when(
        helpOfferRepo.setRoleLabel(
          beaconId: anyNamed('beaconId'),
          offerUserId: anyNamed('offerUserId'),
          actorUserId: anyNamed('actorUserId'),
          roleLabel: anyNamed('roleLabel'),
        ),
      ).thenAnswer((_) async {});
    }

    test('self can set role label', () async {
      stubBeacon(beacon(id: 'B1', status: BeaconStatus.open));
      stubActiveOffer(offerUserId: 'U1');
      when(
        roomRepo.isBeaconSteward(beaconId: 'B1', userId: 'U1'),
      ).thenAnswer((_) async => false);

      await case_.setRoleLabel(
        beaconId: 'B1',
        actorUserId: 'U1',
        offerUserId: 'U1',
        roleLabel: 'driver',
      );

      verify(
        helpOfferRepo.setRoleLabel(
          beaconId: 'B1',
          offerUserId: 'U1',
          actorUserId: 'U1',
          roleLabel: 'driver',
        ),
      ).called(1);
    });

    test('author can set helper role label', () async {
      stubBeacon(beacon(id: 'B1', status: BeaconStatus.open));
      stubActiveOffer(offerUserId: 'U1');
      when(
        roomRepo.isBeaconSteward(beaconId: 'B1', userId: 'Uauth'),
      ).thenAnswer((_) async => false);

      await case_.setRoleLabel(
        beaconId: 'B1',
        actorUserId: 'Uauth',
        offerUserId: 'U1',
        roleLabel: 'nav',
      );

      verify(
        helpOfferRepo.setRoleLabel(
          beaconId: 'B1',
          offerUserId: 'U1',
          actorUserId: 'Uauth',
          roleLabel: 'nav',
        ),
      ).called(1);
    });

    test('steward can set helper role label', () async {
      stubBeacon(beacon(id: 'B1', status: BeaconStatus.open));
      stubActiveOffer(offerUserId: 'U1');
      when(
        roomRepo.isBeaconSteward(beaconId: 'B1', userId: 'Usteward'),
      ).thenAnswer((_) async => true);

      await case_.setRoleLabel(
        beaconId: 'B1',
        actorUserId: 'Usteward',
        offerUserId: 'U1',
        roleLabel: 'lead',
      );

      verify(
        helpOfferRepo.setRoleLabel(
          beaconId: 'B1',
          offerUserId: 'U1',
          actorUserId: 'Usteward',
          roleLabel: 'lead',
        ),
      ).called(1);
    });

    test('other helper cannot set role label', () async {
      stubBeacon(beacon(id: 'B1', status: BeaconStatus.open));
      stubActiveOffer(offerUserId: 'U1');
      when(
        roomRepo.isBeaconSteward(beaconId: 'B1', userId: 'U2'),
      ).thenAnswer((_) async => false);

      await expectLater(
        case_.setRoleLabel(
          beaconId: 'B1',
          actorUserId: 'U2',
          offerUserId: 'U1',
          roleLabel: 'x',
        ),
        throwsA(isA<UnauthorizedException>()),
      );
      verifyNever(
        helpOfferRepo.setRoleLabel(
          beaconId: anyNamed('beaconId'),
          offerUserId: anyNamed('offerUserId'),
          actorUserId: anyNamed('actorUserId'),
          roleLabel: anyNamed('roleLabel'),
        ),
      );
    });

    test('author as target without active offer fails', () async {
      stubBeacon(beacon(id: 'B1', status: BeaconStatus.open));
      when(
        helpOfferRepo.hasActiveHelpOffer(
          beaconId: 'B1',
          userId: 'Uauth',
        ),
      ).thenAnswer((_) async => false);

      await expectLater(
        case_.setRoleLabel(
          beaconId: 'B1',
          actorUserId: 'Uauth',
          offerUserId: 'Uauth',
          roleLabel: 'owner',
        ),
        throwsA(
          isA<HelpOfferCoordinationException>().having(
            (e) =>
                (e.code as HelpOfferCoordinationExceptionCodes).exceptionCode,
            'code',
            HelpOfferCoordinationExceptionCode.helpOfferNotActive,
          ),
        ),
      );
    });

    test('withdrawn / inactive offer fails', () async {
      stubBeacon(beacon(id: 'B1', status: BeaconStatus.open));
      when(
        helpOfferRepo.hasActiveHelpOffer(
          beaconId: 'B1',
          userId: 'U1',
        ),
      ).thenAnswer((_) async => false);

      await expectLater(
        case_.setRoleLabel(
          beaconId: 'B1',
          actorUserId: 'U1',
          offerUserId: 'U1',
          roleLabel: 'gone',
        ),
        throwsA(
          isA<HelpOfferCoordinationException>().having(
            (e) =>
                (e.code as HelpOfferCoordinationExceptionCodes).exceptionCode,
            'code',
            HelpOfferCoordinationExceptionCode.helpOfferNotActive,
          ),
        ),
      );
    });

    test('rejects too long label', () async {
      stubBeacon(beacon(id: 'B1', status: BeaconStatus.open));
      stubActiveOffer(offerUserId: 'U1');

      await expectLater(
        case_.setRoleLabel(
          beaconId: 'B1',
          actorUserId: 'U1',
          offerUserId: 'U1',
          roleLabel: 'x' * 33,
        ),
        throwsA(
          isA<HelpOfferCoordinationException>().having(
            (e) =>
                (e.code as HelpOfferCoordinationExceptionCodes).exceptionCode,
            'code',
            HelpOfferCoordinationExceptionCode.invalidRoleLabel,
          ),
        ),
      );
      verifyNever(
        helpOfferRepo.setRoleLabel(
          beaconId: anyNamed('beaconId'),
          offerUserId: anyNamed('offerUserId'),
          actorUserId: anyNamed('actorUserId'),
          roleLabel: anyNamed('roleLabel'),
        ),
      );
    });

    test('rejects newline in label', () async {
      stubBeacon(beacon(id: 'B1', status: BeaconStatus.open));
      stubActiveOffer(offerUserId: 'U1');

      await expectLater(
        case_.setRoleLabel(
          beaconId: 'B1',
          actorUserId: 'U1',
          offerUserId: 'U1',
          roleLabel: 'line\nbreak',
        ),
        throwsA(
          isA<HelpOfferCoordinationException>().having(
            (e) =>
                (e.code as HelpOfferCoordinationExceptionCodes).exceptionCode,
            'code',
            HelpOfferCoordinationExceptionCode.invalidRoleLabel,
          ),
        ),
      );
    });

    test('empty string clears to null', () async {
      stubBeacon(beacon(id: 'B1', status: BeaconStatus.open));
      stubActiveOffer(offerUserId: 'U1');
      when(
        roomRepo.isBeaconSteward(beaconId: 'B1', userId: 'U1'),
      ).thenAnswer((_) async => false);

      await case_.setRoleLabel(
        beaconId: 'B1',
        actorUserId: 'U1',
        offerUserId: 'U1',
        roleLabel: '   ',
      );

      verify(
        helpOfferRepo.setRoleLabel(
          beaconId: 'B1',
          offerUserId: 'U1',
          actorUserId: 'U1',
          roleLabel: null,
        ),
      ).called(1);
    });
  });
}
