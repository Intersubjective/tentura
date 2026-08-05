import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/domain/commitment/commitment_event.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/coordination/derive_beacon_display_status.dart';
import 'package:tentura_server/domain/entity/beacon_display_status.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/evaluation/beacon_evaluation_record.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/evaluation_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_display_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/coordination_item_record_fixtures.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/noop_commitment_query_case.dart';
import '../../support/recording_commitment_repository.dart';
import 'help_offer_case_mocks.mocks.dart';

class _FakeEvaluationRepository extends Fake implements EvaluationRepositoryPort {
  BeaconReviewWindowRecord? reviewWindow;

  @override
  Future<BeaconReviewWindowRecord?> getReviewWindow(String beaconId) async =>
      reviewWindow;
}

void main() {
  late MockBeaconRepositoryPort beaconRepo;
  late MockHelpOfferRepositoryPort helpOfferRepo;
  late MockCoordinationRepositoryPort coordinationRepo;
  late _FakeEvaluationRepository evaluationRepo;
  late MockBeaconRoomRepositoryPort roomRepo;
  late FakeBeaconAccessGuard guard;
  late BeaconDisplayCase case_;
  late CommitmentQueryCase commitmentQueryCase;

  const beaconId = 'B0000000000000000000000001';
  const authorId = 'U0000000000000000000000001';
  const stewardId = 'U0000000000000000000000002';
  const participantId = 'U0000000000000000000000003';
  const strangerId = 'U0000000000000000000000004';
  const offererId = 'U0000000000000000000000005';

  final now = DateTime.utc(2025, 6, 1);
  final reviewClosesAt = now.add(const Duration(days: 7));

  BeaconEntity openBeacon({BeaconStatus status = BeaconStatus.open}) =>
      BeaconEntity(
        id: beaconId,
        title: 'Test beacon',
        author: const UserEntity(id: authorId),
        status: status,
        createdAt: now,
        updatedAt: now,
      );

  CommitmentQueryCase commitmentQueryCaseFromEvents(
    List<CommitmentEvent> events,
  ) =>
      CommitmentQueryCase(
        RecordingCommitmentRepository(
          eventsByPair: {
            commitmentPairKey(beaconId, offererId): events,
          },
        ),
        helpOfferRepo,
        env: Env(environment: Environment.test),
        logger: Logger('BeaconDisplayCaseTest'),
      );

  setUp(() {
    beaconRepo = MockBeaconRepositoryPort();
    helpOfferRepo = MockHelpOfferRepositoryPort();
    coordinationRepo = MockCoordinationRepositoryPort();
    evaluationRepo = _FakeEvaluationRepository();
    roomRepo = MockBeaconRoomRepositoryPort();
    guard = FakeBeaconAccessGuard();
    commitmentQueryCase = noopCommitmentQueryCase(
      logger: Logger('BeaconDisplayCaseTest'),
    );

    case_ = BeaconDisplayCase(
      beaconRepo,
      helpOfferRepo,
      coordinationRepo,
      evaluationRepo,
      roomRepo,
      guard,
      commitmentQueryCase,
      env: Env(environment: Environment.test),
      logger: Logger('BeaconDisplayCaseTest'),
    );

    when(beaconRepo.getBeaconById(beaconId: anyNamed('beaconId'))).thenAnswer(
      (_) async => openBeacon(),
    );
    when(helpOfferRepo.fetchByBeaconId(beaconId)).thenAnswer(
      (_) async => const <HelpOfferEntity>[],
    );
    when(
      coordinationRepo.coordinationResponseTypeByOfferUserId(beaconId),
    ).thenAnswer((_) async => <String, int>{});
    when(
      roomRepo.isBeaconSteward(
        beaconId: anyNamed('beaconId'),
        userId: anyNamed('userId'),
      ),
    ).thenAnswer((_) async => false);
    when(
      roomRepo.findParticipant(
        beaconId: anyNamed('beaconId'),
        userId: anyNamed('userId'),
      ),
    ).thenAnswer((_) async => null);
  });

  group('BeaconDisplayCase', () {
    test('empty beaconIds returns empty list', () async {
      final result = await case_.displayStatuses(
        beaconIds: const [],
        viewerId: authorId,
      );

      expect(result, isEmpty);
      verifyNever(beaconRepo.getBeaconById(beaconId: anyNamed('beaconId')));
    });

    test('skips beacon when guard denies read', () async {
      guard.contentAllowed = false;

      final result = await case_.displayStatuses(
        beaconIds: [beaconId],
        viewerId: authorId,
      );

      expect(result, isEmpty);
      verifyNever(beaconRepo.getBeaconById(beaconId: anyNamed('beaconId')));
    });

    test('author uses coordination tier (forward vs offerHelp)', () async {
      final result = await case_.displayStatuses(
        beaconIds: [beaconId],
        viewerId: authorId,
      );

      expect(result, hasLength(1));
      expect(result.single.tier, BeaconDisplayTier.coordination);
      expect(result.single.phase, BeaconDisplayPhase.lookingForHelpers);
      expect(
        result.single.suggestedAction,
        BeaconDisplayPrimaryAction.forward,
      );
      verifyNever(
        roomRepo.isBeaconSteward(
          beaconId: anyNamed('beaconId'),
          userId: anyNamed('userId'),
        ),
      );
    });

    test('stranger uses public tier', () async {
      final result = await case_.displayStatuses(
        beaconIds: [beaconId],
        viewerId: strangerId,
      );

      expect(result.single.tier, BeaconDisplayTier.public);
      expect(result.single.phase, BeaconDisplayPhase.lookingForHelpers);
      expect(
        result.single.suggestedAction,
        BeaconDisplayPrimaryAction.offerHelp,
      );
    });

    test('steward resolves coordination tier without participant lookup', () async {
      when(
        roomRepo.isBeaconSteward(
          beaconId: beaconId,
          userId: stewardId,
        ),
      ).thenAnswer((_) async => true);

      final result = await case_.displayStatuses(
        beaconIds: [beaconId],
        viewerId: stewardId,
      );

      expect(result.single.tier, BeaconDisplayTier.coordination);
      verifyNever(
        roomRepo.findParticipant(
          beaconId: anyNamed('beaconId'),
          userId: anyNamed('userId'),
        ),
      );
    });

    test('participant resolves coordination tier', () async {
      when(
        roomRepo.findParticipant(
          beaconId: beaconId,
          userId: participantId,
        ),
      ).thenAnswer(
        (_) async => testBeaconParticipant(
          id: 'P1',
          beaconId: beaconId,
          userId: participantId,
        ),
      );

      final result = await case_.displayStatuses(
        beaconIds: [beaconId],
        viewerId: participantId,
      );

      expect(result.single.tier, BeaconDisplayTier.coordination);
    });

    test('wires hasUnreviewedOffers into offersAwaitingAuthor', () async {
      when(helpOfferRepo.fetchByBeaconId(beaconId)).thenAnswer(
        (_) async => [
          HelpOfferEntity(
            beaconId: beaconId,
            userId: offererId,
            createdAt: now,
            updatedAt: now,
          ),
        ],
      );

      final result = await case_.displayStatuses(
        beaconIds: [beaconId],
        viewerId: authorId,
      );

      expect(result.single.phase, BeaconDisplayPhase.offersAwaitingAuthor);
      expect(
        result.single.suggestedAction,
        BeaconDisplayPrimaryAction.reviewOffers,
      );
    });

    test('enoughHelp public tier suggests forward', () async {
      when(beaconRepo.getBeaconById(beaconId: beaconId)).thenAnswer(
        (_) async => openBeacon(status: BeaconStatus.enoughHelp),
      );

      final result = await case_.displayStatuses(
        beaconIds: [beaconId],
        viewerId: strangerId,
      );

      expect(result.single.tier, BeaconDisplayTier.public);
      expect(result.single.phase, BeaconDisplayPhase.enoughHelpInMotion);
      expect(
        result.single.suggestedAction,
        BeaconDisplayPrimaryAction.forward,
      );
    });

    test('backup offer without response does not trigger offersAwaitingAuthor',
        () async {
      when(beaconRepo.getBeaconById(beaconId: beaconId)).thenAnswer(
        (_) async => openBeacon(status: BeaconStatus.enoughHelp),
      );
      when(helpOfferRepo.fetchByBeaconId(beaconId)).thenAnswer(
        (_) async => [
          HelpOfferEntity(
            beaconId: beaconId,
            userId: offererId,
            createdAt: now,
            updatedAt: now,
            offerKind: 1,
          ),
        ],
      );

      final result = await case_.displayStatuses(
        beaconIds: [beaconId],
        viewerId: authorId,
      );

      expect(result.single.phase, BeaconDisplayPhase.enoughHelpInMotion);
      expect(result.single.phase, isNot(BeaconDisplayPhase.offersAwaitingAuthor));
    });

    test('reviewOpen fetches review window closesAt', () async {
      when(beaconRepo.getBeaconById(beaconId: beaconId)).thenAnswer(
        (_) async => openBeacon(status: BeaconStatus.reviewOpen),
      );
      evaluationRepo.reviewWindow = BeaconReviewWindowRecord(
        beaconId: beaconId,
        openedAt: now,
        closesAt: reviewClosesAt,
        status: 0,
        extensionsUsed: 0,
        createdAt: now,
        updatedAt: now,
      );

      final result = await case_.displayStatuses(
        beaconIds: [beaconId],
        viewerId: authorId,
      );

      expect(result.single.phase, BeaconDisplayPhase.wrappingUp);
      expect(result.single.reviewClosesAt, reviewClosesAt);
      expect(result.single.slot2Kind, BeaconDisplaySlot2Kind.reviewCountdown);
    });

    test('output matches deriveBeaconDisplayStatus for assembled inputs', () async {
      when(helpOfferRepo.fetchByBeaconId(beaconId)).thenAnswer(
        (_) async => [
          HelpOfferEntity(
            beaconId: beaconId,
            userId: offererId,
            createdAt: now,
            updatedAt: now,
            status: 1,
          ),
        ],
      );
      when(
        coordinationRepo.coordinationResponseTypeByOfferUserId(beaconId),
      ).thenAnswer((_) async => {offererId: 1});

      final result = await case_.displayStatuses(
        beaconIds: [beaconId],
        viewerId: authorId,
      );

      final expected = deriveBeaconDisplayStatus(
        BeaconDisplayStatusInput(
          status: BeaconStatus.open,
          tier: BeaconDisplayTier.coordination,
          helpOfferCount: 0,
          hasUnreviewedOffers: false,
          updatedAt: now,
        ),
      );

      expect(result.single.phase, expected.phase);
      expect(result.single.suggestedAction, expected.suggestedAction);
      expect(result.single.slot2Kind, expected.slot2Kind);
      expect(result.single.lastActivityAt, expected.lastActivityAt);
      expect(result.single.lifecycleEndedAt, expected.lifecycleEndedAt);
    });

    group('P8.1 commitment gate fields', () {
      Future<BeaconDisplayStatus> authorStatus({
        BeaconStatus status = BeaconStatus.open,
        CommitmentQueryCase? queryCase,
      }) async {
        when(beaconRepo.getBeaconById(beaconId: beaconId)).thenAnswer(
          (_) async => openBeacon(status: status),
        );
        final displayCase = queryCase == null
            ? case_
            : BeaconDisplayCase(
                beaconRepo,
                helpOfferRepo,
                coordinationRepo,
                evaluationRepo,
                roomRepo,
                guard,
                queryCase,
                env: Env(environment: Environment.test),
                logger: Logger('BeaconDisplayCaseTest'),
              );
        final result = await displayCase.displayStatuses(
          beaconIds: [beaconId],
          viewerId: authorId,
        );
        return result.single;
      }

      test('author with no acknowledged committers can cancel and delete', () async {
        final status = await authorStatus();

        expect(status.canCancel, isTrue);
        expect(status.canDelete, isTrue);
        expect(status.everAcknowledgedCommitterCount, 0);
      });

      test('draft author can delete with no commitment history', () async {
        final status = await authorStatus(status: BeaconStatus.draft);

        expect(status.canDelete, isTrue);
        expect(status.canCancel, isFalse);
        expect(status.everAcknowledgedCommitterCount, 0);
      });

      test(
        'author with ever-acknowledged committer cannot cancel or delete',
        () async {
          final status = await authorStatus(
            queryCase: commitmentQueryCaseFromEvents([
              CommitmentEvent(
                id: 'CE-1',
                seq: 1,
                beaconId: beaconId,
                userId: offererId,
                actorUserId: authorId,
                kind: CommitmentEventKind.acknowledged,
                reason: null,
                createdAt: now,
              ),
            ]),
          );

          expect(status.canCancel, isFalse);
          expect(status.canDelete, isFalse);
          expect(status.everAcknowledgedCommitterCount, 1);
        },
      );

      test('non-author viewer gets false gates and zero count', () async {
        when(beaconRepo.getBeaconById(beaconId: beaconId)).thenAnswer(
          (_) async => openBeacon(),
        );
        when(
          roomRepo.isBeaconSteward(
            beaconId: beaconId,
            userId: stewardId,
          ),
        ).thenAnswer((_) async => true);
        final displayCase = BeaconDisplayCase(
          beaconRepo,
          helpOfferRepo,
          coordinationRepo,
          evaluationRepo,
          roomRepo,
          guard,
          commitmentQueryCaseFromEvents([
            CommitmentEvent(
              id: 'CE-1',
              seq: 1,
              beaconId: beaconId,
              userId: offererId,
              actorUserId: authorId,
              kind: CommitmentEventKind.acknowledged,
              reason: null,
              createdAt: now,
            ),
          ]),
          env: Env(environment: Environment.test),
          logger: Logger('BeaconDisplayCaseTest'),
        );

        final stewardResult = await displayCase.displayStatuses(
          beaconIds: [beaconId],
          viewerId: stewardId,
        );

        expect(stewardResult.single.canCancel, isFalse);
        expect(stewardResult.single.canDelete, isFalse);
        expect(stewardResult.single.everAcknowledgedCommitterCount, 0);
      });
    });
  });
}
