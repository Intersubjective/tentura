import 'dart:async';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/fake_beacon_child_create_port.dart';
import '../../support/beacon_lifecycle_effects_test_support.dart';

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
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/coordination_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/recording_commitment_repository.dart';
import '../../support/test_attention_harness.dart';
import 'help_offer_case_mocks.mocks.dart';

class _TransactionStubBeaconRepo implements BeaconRepositoryPort {
  _TransactionStubBeaconRepo(this._beacon);

  final BeaconEntity _beacon;

  @override
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) async => _beacon;

  @override
  Future<T> runInBeaconStateTransaction<T>({
    required String beaconId,
    required String userId,
    required Future<T> Function(BeaconEntity locked) fn,
  }) => fn(_beacon);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeImageRepo extends Fake implements ImageRepositoryPort {}

class _FakeImageObjectGc extends Fake implements ImageObjectGcPort {}

class _FakeTaskRepo extends Fake implements TaskRepositoryPort {}

/// Models the hierarchy advisory lock for two racing releases: the first
/// caller holds the lock until the second has also passed its pre-checks and
/// is waiting on it, and the second gets the lock only once [releaseFirst]
/// runs (the first transaction has committed). So the second caller's reads
/// before the lock are stale, and only reads after it see the first's writes.
class _RacingLockHierarchy extends FakeBeaconHierarchyRepository {
  final Completer<void> _secondArrived = Completer<void>();
  final Completer<void> _firstDone = Completer<void>();
  int _arrivals = 0;

  void releaseFirst() => _firstDone.complete();

  @override
  Future<void> lockMutationScope() async {
    // Take the arrival ticket before any await, so both callers get distinct
    // ones even though the counter in super is bumped asynchronously.
    final ticket = ++_arrivals;
    await super.lockMutationScope();
    if (ticket == 1) {
      await _secondArrived.future;
    } else if (ticket == 2) {
      _secondArrived.complete();
      await _firstDone.future;
    }
  }
}

/// Runs [onLock] once the hierarchy lock is taken, to model a write that
/// committed between the pre-checks and the locked reads (#634).
class _OnLockHierarchy extends FakeBeaconHierarchyRepository {
  _OnLockHierarchy(this.onLock);

  final void Function() onLock;

  @override
  Future<void> lockMutationScope() async {
    await super.lockMutationScope();
    onLock();
  }
}

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

  void buildCoordinationCase({FakeBeaconHierarchyRepository? hierarchy}) {
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
      FakeUserBlockRepository(),
      commitmentRepo,
      commitmentQueryCase,
      hierarchy ?? FakeBeaconHierarchyRepository(),
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
      FakeBeaconHierarchyRepository(),
      FakeBeaconChildCreatePort(),
      buildLifecycleEffectsCase(),
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
    // #489: an admitted helper's removal posts a room line; strict mocks
    // need it stubbed.
    when(
      roomRepo.recordParticipantRemoved(
        beaconId: anyNamed('beaconId'),
        userId: anyNamed('userId'),
      ),
    ).thenAnswer((_) async {});
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

  test(
    'release without acknowledgement throws commitmentNotAcknowledged',
    () async {
      await expectLater(
        coordinationCase.releaseCommitment(
          beaconId: beaconId,
          offerUserId: helperId,
          authorUserId: authorId,
          reason: 'done',
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
      expect(commitmentRepo.recordCalls, isEmpty);
    },
  );

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
    expect(
      commitmentRepo.recordCalls.last.kind,
      CommitmentEventKind.releasedByAuthor,
    );

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

  test(
    'two racing releases record one releasedByAuthor and one notice',
    () async {
      // PR #633 review: the stake is read before the transaction; a second
      // release that passed that check must re-read it after the lock.
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
      final hierarchy = _RacingLockHierarchy();
      buildCoordinationCase(hierarchy: hierarchy);

      final first = coordinationCase.releaseCommitment(
        beaconId: beaconId,
        offerUserId: helperId,
        authorUserId: authorId,
        reason: 'done',
      );
      final second = coordinationCase.releaseCommitment(
        beaconId: beaconId,
        offerUserId: helperId,
        authorUserId: authorId,
        reason: 'done too',
      );
      await first;
      hierarchy.releaseFirst();
      final secondResult = await second;

      expect(hierarchy.lockMutationScopeCalls, 2);
      expect(
        commitmentRepo.recordCalls.where(
          (c) => c.kind == CommitmentEventKind.releasedByAuthor,
        ),
        hasLength(1),
      );
      expect(
        attention.recorded.where(
          (intent) => intent.eventType == AttentionEventType.commitmentReleased,
        ),
        hasLength(1),
      );
      // The loser deactivates nothing again; it returns the snapshot.
      verify(
        helpOfferRepo.deactivate(beaconId: beaconId, userId: helperId),
      ).called(1);
      expect(secondResult.beaconId, beaconId);
    },
  );

  group('status re-read under the lock (#634)', () {
    Future<void> seedAcknowledged() async {
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
    }

    test('a Close committed before the lock ends in beaconNotOpen', () async {
      await seedAcknowledged();
      final hierarchy = _OnLockHierarchy(() {
        // The author closed the request while this release waited.
        when(
          beaconRepo.getBeaconById(beaconId: beaconId),
        ).thenAnswer((_) async => beacon(status: BeaconStatus.closed));
        when(
          coordinationRepo.beaconStatusSnapshot(beaconId),
        ).thenAnswer(
          (_) async => (status: BeaconStatus.closed, statusChangedAt: now),
        );
      });
      buildCoordinationCase(hierarchy: hierarchy);
      final recordsBefore = commitmentRepo.recordCalls.length;

      await expectLater(
        coordinationCase.releaseCommitment(
          beaconId: beaconId,
          offerUserId: helperId,
          authorUserId: authorId,
          reason: 'done',
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

      expect(hierarchy.lockMutationScopeCalls, 1);
      expect(commitmentRepo.recordCalls, hasLength(recordsBefore));
      expect(attention.recorded, isEmpty);
      verifyNever(
        helpOfferRepo.deactivate(
          beaconId: anyNamed('beaconId'),
          userId: anyNamed('userId'),
        ),
      );
    });

    test('an unchanged status under the lock still releases', () async {
      await seedAcknowledged();
      final hierarchy = _OnLockHierarchy(() {});
      buildCoordinationCase(hierarchy: hierarchy);

      await coordinationCase.releaseCommitment(
        beaconId: beaconId,
        offerUserId: helperId,
        authorUserId: authorId,
        reason: 'done',
      );

      expect(hierarchy.lockMutationScopeCalls, 1);
      expect(
        commitmentRepo.recordCalls.last.kind,
        CommitmentEventKind.releasedByAuthor,
      );
    });
  });
}
