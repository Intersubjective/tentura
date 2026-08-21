import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/commitment/commitment_state.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/evaluation_repository_port.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/coordination_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/recording_commitment_repository.dart';
import '../../support/test_attention_harness.dart';
import 'help_offer_case_mocks.mocks.dart';

class _MinimalEvaluationRepo extends Fake implements EvaluationRepositoryPort {}

class _TransactionStubBeaconRepo implements BeaconRepositoryPort {
  _TransactionStubBeaconRepo(this._beacon);

  final BeaconEntity _beacon;

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

class _FakeImageRepo extends Fake implements ImageRepositoryPort {}

class _FakeImageObjectGc extends Fake implements ImageObjectGcPort {}

class _FakeTaskRepo extends Fake implements TaskRepositoryPort {}

void main() {
  const beaconId = 'B-release';
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

  late MockBeaconRepositoryPort beaconRepo;
  late MockHelpOfferRepositoryPort helpOfferRepo;
  late MockCoordinationRepositoryPort coordinationRepo;
  late MockBeaconRoomRepositoryPort roomRepo;
  late RecordingCommitmentRepository commitmentRepo;
  late CommitmentQueryCase commitmentQueryCase;
  late TestAttentionHarness attention;
  late CoordinationCase coordinationCase;

  void buildCoordinationCase() {
    attention = TestAttentionHarness();
    commitmentQueryCase = CommitmentQueryCase(
      commitmentRepo,
      helpOfferRepo,
      env: Env(environment: Environment.test),
      logger: Logger('CoordinationCaseReleaseTest'),
    );
    coordinationCase = CoordinationCase(
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
      logger: Logger('CoordinationCaseReleaseTest'),
    );
  }

  BeaconCase buildBeaconCase() {
    final attention = TestAttentionHarness();
    return BeaconCase(
      _TransactionStubBeaconRepo(beacon()),
      _FakeImageRepo(),
      _FakeImageObjectGc(),
      _FakeTaskRepo(),
      commitmentQueryCase,
      FakeBeaconAccessGuard(),
      attentionIntents: attention.intents,
      attention: attention.transactional,
      env: Env(environment: Environment.test),
      logger: Logger('CoordinationCaseReleaseTest'),
    );
  }

  setUp(() {
    beaconRepo = MockBeaconRepositoryPort();
    helpOfferRepo = MockHelpOfferRepositoryPort();
    coordinationRepo = MockCoordinationRepositoryPort();
    roomRepo = MockBeaconRoomRepositoryPort();
    commitmentRepo = RecordingCommitmentRepository();
    when(
      beaconRepo.getBeaconById(beaconId: beaconId),
    ).thenAnswer((_) async => beacon());
    when(
      coordinationRepo.beaconStatusSnapshot(beaconId),
    ).thenAnswer(
      (_) async => (status: BeaconStatus.open, statusChangedAt: now),
    );
    when(
      roomRepo.findParticipant(beaconId: beaconId, userId: helperId),
    ).thenAnswer((_) async => null);
    when(
      helpOfferRepo.fetchAllByBeaconId(beaconId),
    ).thenAnswer(
      (_) async => [
        HelpOfferEntity(
          beaconId: beaconId,
          userId: helperId,
          createdAt: now,
          updatedAt: now,
          status: 0,
        ),
      ],
    );
    buildCoordinationCase();
  });

  test('release without acknowledgement throws commitmentNotAcknowledged', () async {
    await expectLater(
      coordinationCase.releaseCommitment(
        beaconId: beaconId,
        offerUserId: helperId,
        authorUserId: authorId,
        reason: 'done',
      ),
      throwsA(
        isA<HelpOfferCoordinationException>().having(
          (e) => (e.code as HelpOfferCoordinationExceptionCodes).exceptionCode,
          'code',
          HelpOfferCoordinationExceptionCode.commitmentNotAcknowledged,
        ),
      ),
    );
    expect(commitmentRepo.recordCalls, isEmpty);
  });

  test('release removes current stake but keeps everAcknowledged', () async {
    commitmentRepo = RecordingCommitmentRepository();
    await commitmentRepo.record(
      beaconId: beaconId,
      userId: helperId,
      actorUserId: authorId,
      kind: CommitmentEventKind.offered,
    );
    await commitmentRepo.record(
      beaconId: beaconId,
      userId: helperId,
      actorUserId: authorId,
      kind: CommitmentEventKind.acknowledged,
    );
    buildCoordinationCase();

    await coordinationCase.releaseCommitment(
      beaconId: beaconId,
      offerUserId: helperId,
      authorUserId: authorId,
      reason: 'scope changed',
    );

    expect(commitmentRepo.recordCalls, hasLength(3));
    expect(commitmentRepo.recordCalls.last.kind, CommitmentEventKind.releasedByAuthor);

    final events = await commitmentRepo.eventsForPair(
      beaconId: beaconId,
      userId: helperId,
    );
    expect(currentStakeState(events), CommitmentStakeState.released);
    expect(currentStakeState(events).index, 5);
    expect(everAcknowledged(events), isTrue);

    final current = await commitmentQueryCase.currentCommitterUserIds(beaconId);
    expect(current, isEmpty);

    final everAck = await commitmentQueryCase.everAcknowledgedUserIds(beaconId);
    expect(everAck, {helperId});

    await expectLater(
      buildBeaconCase().beaconCancel(beaconId: beaconId, userId: authorId),
      throwsA(
        isA<EvaluationException>().having(
          (e) => (e.code as EvaluationExceptionCodes).exceptionCode,
          'code',
          EvaluationExceptionCode.beaconNotClosable,
        ),
      ),
    );
  });

  test('release also removes an admitted helper from the discussion', () async {
    commitmentRepo = RecordingCommitmentRepository();
    await commitmentRepo.record(
      beaconId: beaconId,
      userId: helperId,
      actorUserId: authorId,
      kind: CommitmentEventKind.offered,
    );
    await commitmentRepo.record(
      beaconId: beaconId,
      userId: helperId,
      actorUserId: authorId,
      kind: CommitmentEventKind.acknowledged,
    );
    when(
      roomRepo.findParticipant(beaconId: beaconId, userId: helperId),
    ).thenAnswer(
      (_) async => BeaconParticipantRecord(
        id: 'participant-1',
        beaconId: beaconId,
        userId: helperId,
        role: 2,
        status: 0,
        roomAccess: RoomAccessBits.admitted,
        createdAt: now,
        updatedAt: now,
      ),
    );
    when(
      coordinationRepo.removeFromRoom(
        beaconId: beaconId,
        offerUserId: helperId,
        actorUserId: authorId,
        reason: 'done',
      ),
    ).thenAnswer(
      (_) async => (status: BeaconStatus.open, statusChangedAt: now),
    );
    buildCoordinationCase();

    await coordinationCase.releaseCommitment(
      beaconId: beaconId,
      offerUserId: helperId,
      authorUserId: authorId,
      reason: 'done',
    );

    verify(
      coordinationRepo.removeFromRoom(
        beaconId: beaconId,
        offerUserId: helperId,
        actorUserId: authorId,
        reason: 'done',
      ),
    ).called(1);
    expect(
      attention.recorded.where(
        (intent) => intent.eventType == AttentionEventType.offerRemoved,
      ),
      hasLength(1),
    );
  });

  test('second release is idempotent and records no new event', () async {
    commitmentRepo = RecordingCommitmentRepository();
    await commitmentRepo.record(
      beaconId: beaconId,
      userId: helperId,
      actorUserId: authorId,
      kind: CommitmentEventKind.offered,
    );
    await commitmentRepo.record(
      beaconId: beaconId,
      userId: helperId,
      actorUserId: authorId,
      kind: CommitmentEventKind.acknowledged,
    );
    buildCoordinationCase();

    await coordinationCase.releaseCommitment(
      beaconId: beaconId,
      offerUserId: helperId,
      authorUserId: authorId,
      reason: 'done',
    );
    final countAfterFirst = commitmentRepo.recordCalls.length;

    await coordinationCase.releaseCommitment(
      beaconId: beaconId,
      offerUserId: helperId,
      authorUserId: authorId,
      reason: 'done again',
    );

    expect(commitmentRepo.recordCalls.length, countAfterFirst);
    expect(
      attention.recorded.where(
        (intent) => intent.eventType == AttentionEventType.commitmentReleased,
      ),
      hasLength(1),
    );
  });
}
