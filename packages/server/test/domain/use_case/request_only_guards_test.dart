import 'dart:typed_data';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/domain/closure/closure_entities.dart';
import 'package:tentura_server/domain/closure/closure_outcome.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_fact_room_access.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/attention_system_settlement_port.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_command_port.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_notification_context_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/closure_finalizer_port.dart';
import 'package:tentura_server/domain/port/closure_receipts_port.dart';
import 'package:tentura_server/domain/port/closure_repository_port.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/domain/use_case/beacon_child_create_case.dart';
import 'package:tentura_server/domain/use_case/beacon_display_case.dart';
import 'package:tentura_server/domain/use_case/beacon_fact_card_case.dart';
import 'package:tentura_server/domain/use_case/capability_case.dart';
import 'package:tentura_server/domain/use_case/closure_case.dart';
import 'package:tentura_server/domain/use_case/coordination_case.dart';
import 'package:tentura_server/domain/use_case/help_offer_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/beacon_lifecycle_effects_test_support.dart';
import '../../support/beacon_not_request_matcher.dart';
import '../../support/beacon_repository_ctor_arg.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_beacon_child_create_port.dart';
import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/noop_commitment_query_case.dart';
import '../../support/recording_commitment_repository.dart';
import '../../support/test_attention_harness.dart';
import 'help_offer_case_mocks.mocks.dart';

const _beaconId = 'Bpostguard001';
const _requestId = 'Brequestgrd01';
const _authorId = 'Uauthorguard1';
const _helperId = 'Uhelperguard1';

final _now = DateTime.utc(2026);

BeaconEntity _beacon({
  required BeaconKind kind,
  String id = _beaconId,
  BeaconStatus status = BeaconStatus.open,
}) => BeaconEntity(
  id: id,
  title: kind == BeaconKind.post ? '' : 'Title',
  author: const UserEntity(id: _authorId),
  createdAt: _now,
  updatedAt: _now,
  status: status,
  kind: kind,
);

/// Beacon port that serves one fixed beacon and records any other call
/// (every write goes through `noSuchMethod`, which then throws).
class _FixedBeaconRepo extends Fake implements BeaconRepositoryPort {
  _FixedBeaconRepo(this.beacon);

  final BeaconEntity beacon;
  final unexpectedCalls = <String>[];

  @override
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) async => beacon;

  @override
  Future<T> runInBeaconStateTransaction<T>({
    required String beaconId,
    required String userId,
    required Future<T> Function(BeaconEntity locked) fn,
  }) => fn(beacon);

  @override
  Future<int> countRecentByAuthor({
    required String userId,
    required Duration window,
  }) async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpectedCalls.add(invocation.memberName.toString());
    return super.noSuchMethod(invocation);
  }
}

class _EvaluatingClosureRepo extends Fake implements ClosureRepositoryPort {
  final unexpectedCalls = <String>[];

  final _epoch = ClosureEpoch(
    beaconId: _beaconId,
    epoch: 1,
    status: ClosureEpochStatus.evaluating,
    openedAt: _now,
    closesAt: _now.add(const Duration(days: 7)),
    extensionsUsed: 0,
  );

  @override
  Future<void> lockRequest(String beaconId) async {}

  @override
  Future<ClosureEpoch?> liveEpoch(String beaconId) async => _epoch;

  @override
  Future<ClosureEpoch?> latestEpoch(String beaconId) async => _epoch;

  @override
  Future<int> cancelledEpochCount(String beaconId) async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpectedCalls.add(invocation.memberName.toString());
    return super.noSuchMethod(invocation);
  }
}

class _NoSettlement extends Fake implements AttentionSystemSettlementPort {}

class _NoReceipts extends Fake implements ClosureReceiptsPort {}

class _NoFinalizer extends Fake implements ClosureFinalizerPort {}

class _FakeImageRepo extends Fake implements ImageRepositoryPort {}

/// Counts attachment I/O: a rejected Post must not store or schedule anything.
class _RecordingImageRepo extends Fake implements ImageRepositoryPort {
  final putCalls = <String>[];

  @override
  Future<String> put({
    required String authorId,
    required Stream<Uint8List> bytes,
  }) async {
    putCalls.add(authorId);
    return 'Iimage000001';
  }
}

class _RecordingTaskRepo extends Fake implements TaskRepositoryPort {
  final scheduled = <TaskEntity>[];

  @override
  Future<String> schedule(TaskEntity task) async {
    scheduled.add(task);
    return 'Ttask0000001';
  }
}

/// Room access that would let the author write: only the beacon's kind can
/// stop a fact-card write.
class _WritableFactsRepo extends Fake implements BeaconFactCardRepositoryPort {
  final unexpectedCalls = <String>[];

  @override
  Future<BeaconFactRoomAccess> loadRoomAccess({
    required String beaconId,
    required String userId,
  }) async => BeaconFactRoomAccess(
    beaconStatus: BeaconStatus.open.smallintValue,
    canUseRoom: true,
    canReadContent: true,
    exists: true,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpectedCalls.add(invocation.memberName.toString());
    return super.noSuchMethod(invocation);
  }
}

class _UnusedRoom extends Fake implements BeaconRoomRepositoryPort {}

class _FakeImageObjectGc extends Fake implements ImageObjectGcPort {}

class _FakeTaskRepo extends Fake implements TaskRepositoryPort {}

class _FakeNotificationContext extends Fake
    implements BeaconRoomNotificationContextPort {}

class _OpenParentCommands extends Fake implements BeaconHierarchyCommandPort {
  final unexpectedCalls = <String>[];

  @override
  Future<BeaconChildCommandRecord?> findCommand({
    required String actorUserId,
    required String clientCommandId,
  }) async => null;

  @override
  Future<void> lockBeaconRows(List<String> beaconIds) async {}

  @override
  Future<void> lockChildCommandRow({
    required String actorUserId,
    required String clientCommandId,
  }) async {}

  @override
  Future<void> lockPromotionRows({
    String? childBeaconId,
    String? sourceMessageId,
  }) async {}

  @override
  Future<bool> effectiveAdmission({
    required String beaconId,
    required String viewerId,
  }) async => true;

  @override
  Future<BeaconParentValidationRow?> loadParentValidationRow(
    String parentBeaconId,
  ) async => BeaconParentValidationRow(
    id: parentBeaconId,
    ownerId: _authorId,
    status: BeaconStatus.open,
    isPublished: true,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpectedCalls.add(invocation.memberName.toString());
    return super.noSuchMethod(invocation);
  }
}

void main() {
  final env = Env(environment: Environment.test);

  late _FixedBeaconRepo beaconRepo;
  late MockHelpOfferRepositoryPort helpOfferRepo;
  late MockInboxRepositoryPort inboxRepo;
  late MockPersonCapabilityEventRepositoryPort capabilityRepo;
  late MockBeaconRoomRepositoryPort roomRepo;
  late MockCoordinationRepositoryPort coordinationRepo;
  late RecordingCommitmentRepository commitmentRepo;
  late TestAttentionHarness attention;

  setUp(() {
    beaconRepo = _FixedBeaconRepo(_beacon(kind: BeaconKind.post));
    helpOfferRepo = MockHelpOfferRepositoryPort();
    inboxRepo = MockInboxRepositoryPort();
    capabilityRepo = MockPersonCapabilityEventRepositoryPort();
    roomRepo = MockBeaconRoomRepositoryPort();
    coordinationRepo = MockCoordinationRepositoryPort();
    commitmentRepo = RecordingCommitmentRepository();
    attention = TestAttentionHarness();
  });

  group('HelpOfferCase rejects a Post', () {
    late HelpOfferCase helpOfferCase;

    setUp(() {
      helpOfferCase = HelpOfferCase(
        helpOfferRepo,
        beaconRepo,
        commitmentRepo,
        inboxRepo,
        CapabilityCase(
          capabilityRepo,
          env: env,
          logger: Logger('RequestOnlyGuardsTest'),
        ),
        FakeBeaconAccessGuard(),
        roomRepository: roomRepo,
        attentionIntents: attention.intents,
        attention: attention.transactional,
        env: env,
        logger: Logger('RequestOnlyGuardsTest'),
      );
    });

    test('offerHelp', () async {
      await expectLater(
        helpOfferCase.offerHelp(beaconId: _beaconId, userId: _helperId),
        throwsBeaconNotRequest,
      );

      verifyZeroInteractions(helpOfferRepo);
      verifyZeroInteractions(inboxRepo);
      expect(commitmentRepo.recordCalls, isEmpty);
      expect(attention.recorded, isEmpty);
    });

    test('setRoleLabel', () async {
      when(
        helpOfferRepo.hasActiveHelpOffer(
          beaconId: anyNamed('beaconId'),
          userId: anyNamed('userId'),
        ),
      ).thenAnswer((_) async => true);

      await expectLater(
        helpOfferCase.setRoleLabel(
          beaconId: _beaconId,
          actorUserId: _authorId,
          offerUserId: _helperId,
          roleLabel: 'Driver',
        ),
        throwsBeaconNotRequest,
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

    test('withdraw', () async {
      await expectLater(
        helpOfferCase.withdraw(
          beaconId: _beaconId,
          userId: _helperId,
          withdrawReason: 'other',
        ),
        throwsBeaconNotRequest,
      );

      verifyZeroInteractions(helpOfferRepo);
      expect(commitmentRepo.recordCalls, isEmpty);
      expect(attention.recorded, isEmpty);
    });
  });

  group('CoordinationCase rejects a Post', () {
    late CoordinationCase coordinationCase;

    setUp(() {
      coordinationCase = CoordinationCase(
        beaconRepo,
        helpOfferRepo,
        coordinationRepo,
        roomRepo,
        FakeUserBlockRepository(),
        commitmentRepo,
        noopCommitmentQueryCase(logger: Logger('RequestOnlyGuardsTest')),
        FakeBeaconHierarchyRepository(),
        attentionIntents: attention.intents,
        attention: attention.transactional,
        guard: FakeBeaconAccessGuard(),
        env: env,
        logger: Logger('RequestOnlyGuardsTest'),
      );
    });

    void expectNoCoordinationWrites() {
      verifyZeroInteractions(coordinationRepo);
      verifyNever(
        roomRepo.inviteOfferUserToBeaconRoom(
          beaconId: anyNamed('beaconId'),
          offerUserId: anyNamed('offerUserId'),
          authorUserId: anyNamed('authorUserId'),
        ),
      );
      verifyNever(
        roomRepo.revokeOfferUserBeaconRoomAccess(
          beaconId: anyNamed('beaconId'),
          offerUserId: anyNamed('offerUserId'),
          authorUserId: anyNamed('authorUserId'),
        ),
      );
      expect(commitmentRepo.recordCalls, isEmpty);
      expect(beaconRepo.unexpectedCalls, isEmpty);
      expect(attention.recorded, isEmpty);
    }

    test('helpOffersWithCoordination', () async {
      await expectLater(
        coordinationCase.helpOffersWithCoordination(
          beaconId: _beaconId,
          viewerId: _authorId,
        ),
        throwsBeaconNotRequest,
      );

      verifyZeroInteractions(coordinationRepo);
    });

    test('acceptHelpOffer (admission preparation)', () async {
      await expectLater(
        coordinationCase.acceptHelpOffer(
          beaconId: _beaconId,
          offerUserId: _helperId,
          actorUserId: _authorId,
        ),
        throwsBeaconNotRequest,
      );

      expectNoCoordinationWrites();
    });

    test('declineHelpOffer (admission preparation)', () async {
      await expectLater(
        coordinationCase.declineHelpOffer(
          beaconId: _beaconId,
          offerUserId: _helperId,
          actorUserId: _authorId,
          reason: 'not a fit',
        ),
        throwsBeaconNotRequest,
      );

      expectNoCoordinationWrites();
    });

    test('removeFromRoom (admission preparation)', () async {
      await expectLater(
        coordinationCase.removeFromRoom(
          beaconId: _beaconId,
          offerUserId: _helperId,
          actorUserId: _authorId,
          reason: 'not a fit',
        ),
        throwsBeaconNotRequest,
      );

      expectNoCoordinationWrites();
    });

    test('releaseCommitment', () async {
      await expectLater(
        coordinationCase.releaseCommitment(
          beaconId: _beaconId,
          offerUserId: _helperId,
          authorUserId: _authorId,
          reason: 'done',
        ),
        throwsBeaconNotRequest,
      );

      expectNoCoordinationWrites();
    });

    test('setCoordinationResponse', () async {
      await expectLater(
        coordinationCase.setCoordinationResponse(
          beaconId: _beaconId,
          offerUserId: _helperId,
          authorUserId: _authorId,
          responseType: 0,
          inviteToRoom: false,
          removeFromRoom: false,
        ),
        throwsBeaconNotRequest,
      );

      expectNoCoordinationWrites();
    });

    test('setBeaconStatus', () async {
      await expectLater(
        coordinationCase.setBeaconStatus(
          beaconId: _beaconId,
          authorUserId: _authorId,
          status: BeaconStatus.enoughHelp.smallintValue,
        ),
        throwsBeaconNotRequest,
      );

      expectNoCoordinationWrites();
    });
  });

  // Contract: every public ClosureCase method that loads the beacon rejects a
  // Post — the author-checking paths (extend, closeNow, saveOutcome,
  // saveAuthorSplit, saveStory) and the paths that read the beacon on their
  // own (close, reopen, setMark, state). The vote-only methods (toggleSupport,
  // done, skip) never load the beacon, so a Post is stopped upstream of them.
  group('ClosureCase rejects a Post', () {
    late _EvaluatingClosureRepo closureRepo;
    late ClosureCase closureCase;

    setUp(() {
      closureRepo = _EvaluatingClosureRepo();
      closureCase = ClosureCase(
        unitOfWork: PassThroughMutatingUnitOfWork(),
        closureRepository: closureRepo,
        beaconRepository: beaconRepo,
        commitmentRepository: commitmentRepo,
        helpOfferRepository: helpOfferRepo,
        hierarchyRepository: FakeBeaconHierarchyRepository(),
        lifecycleEffects: buildLifecycleEffectsCase(),
        attentionSystemSettlement: _NoSettlement(),
        receipts: _NoReceipts(),
        finalizer: _NoFinalizer(),
        env: env,
        logger: Logger('RequestOnlyGuardsTest'),
      );
    });

    void expectNoClosureWrites() {
      expect(closureRepo.unexpectedCalls, isEmpty);
      expect(beaconRepo.unexpectedCalls, isEmpty);
      expect(commitmentRepo.recordCalls, isEmpty);
      verifyZeroInteractions(helpOfferRepo);
    }

    test('close', () async {
      await expectLater(
        closureCase.close(authorId: _authorId, beaconId: _beaconId),
        throwsBeaconNotRequest,
      );

      expectNoClosureWrites();
    });

    test('extend', () async {
      await expectLater(
        closureCase.extend(authorId: _authorId, beaconId: _beaconId),
        throwsBeaconNotRequest,
      );

      expectNoClosureWrites();
    });

    test('reopen', () async {
      await expectLater(
        closureCase.reopen(authorId: _authorId, beaconId: _beaconId),
        throwsBeaconNotRequest,
      );

      expectNoClosureWrites();
    });

    test('closeNow', () async {
      await expectLater(
        closureCase.closeNow(authorId: _authorId, beaconId: _beaconId),
        throwsBeaconNotRequest,
      );

      expectNoClosureWrites();
    });

    test('saveOutcome', () async {
      await expectLater(
        closureCase.saveOutcome(
          authorId: _authorId,
          beaconId: _beaconId,
          expectedEpoch: 1,
          helperId: _helperId,
          outcome: ClosureOutcome.done,
        ),
        throwsBeaconNotRequest,
      );

      expectNoClosureWrites();
    });

    test('saveAuthorSplit', () async {
      await expectLater(
        closureCase.saveAuthorSplit(
          authorId: _authorId,
          beaconId: _beaconId,
          expectedEpoch: 1,
          split: null,
        ),
        throwsBeaconNotRequest,
      );

      expectNoClosureWrites();
    });

    test('saveStory', () async {
      await expectLater(
        closureCase.saveStory(
          authorId: _authorId,
          beaconId: _beaconId,
          expectedEpoch: 1,
          body: 'How it went',
        ),
        throwsBeaconNotRequest,
      );

      expectNoClosureWrites();
    });

    test('setMark', () async {
      await expectLater(
        closureCase.setMark(
          userId: _authorId,
          beaconId: _beaconId,
          expectedEpoch: 1,
          targetId: _helperId,
          on: true,
        ),
        throwsBeaconNotRequest,
      );

      expectNoClosureWrites();
    });

    test('state', () async {
      await expectLater(
        closureCase.state(viewerId: _authorId, beaconId: _beaconId),
        throwsBeaconNotRequest,
      );

      expectNoClosureWrites();
    });
  });

  group('BeaconCase rejects a Post', () {
    late BeaconCase beaconCase;

    setUp(() {
      beaconCase = BeaconCase(
        beaconRepo,
        _FakeImageRepo(),
        _FakeImageObjectGc(),
        _FakeTaskRepo(),
        noopCommitmentQueryCase(logger: Logger('RequestOnlyGuardsTest')),
        FakeBeaconAccessGuard(),
        FakeBeaconHierarchyRepository(),
        FakeBeaconChildCreatePort(),
        buildLifecycleEffectsCase(),
        attentionIntents: attention.intents,
        attention: attention.transactional,
        env: env,
        logger: Logger('RequestOnlyGuardsTest'),
      );
    });

    test('beaconCancel', () async {
      await expectLater(
        beaconCase.beaconCancel(beaconId: _beaconId, userId: _authorId),
        throwsBeaconNotRequest,
      );

      expect(beaconRepo.unexpectedCalls, isEmpty);
      expect(attention.recorded, isEmpty);
    });

    test('fork', () async {
      await expectLater(
        beaconCase.fork(sourceId: _beaconId, userId: _authorId),
        throwsBeaconNotRequest,
      );

      expect(beaconRepo.unexpectedCalls, isEmpty);
    });
  });

  // The parent's validation row says published/open/admitted; only the beacon
  // port knows the parent is a Post.
  group('BeaconChildCreateCase rejects a Post parent', () {
    test('createChild', () async {
      final commands = _OpenParentCommands();
      final childCreateCase = BeaconChildCreateCase(
        beaconRepo,
        FakeBeaconHierarchyRepository(),
        commands,
        FakeBeaconAccessGuard(),
        _FakeNotificationContext(),
        attentionIntents: attention.intents,
        attention: attention.transactional,
        env: env,
        logger: Logger('RequestOnlyGuardsTest'),
      );

      await expectLater(
        childCreateCase.createChild(
          actorUserId: _authorId,
          parentBeaconId: _beaconId,
          clientCommandId: 'cmd-1',
          title: 'Child',
          description: 'Child description',
          draft: true,
        ),
        throwsBeaconNotRequest,
      );

      expect(commands.unexpectedCalls, isEmpty);
      expect(beaconRepo.unexpectedCalls, isEmpty);
    });
  });

  group('BeaconFactCardCase rejects a Post room', () {
    late _WritableFactsRepo facts;
    late _RecordingImageRepo images;
    late _RecordingTaskRepo tasks;
    late BeaconFactCardCase factCardCase;

    setUp(() {
      facts = _WritableFactsRepo();
      images = _RecordingImageRepo();
      tasks = _RecordingTaskRepo();
      factCardCase = buildWithBeaconRepository<BeaconFactCardCase>(
        BeaconFactCardCase.new,
        positional: [
          facts,
          _UnusedRoom(),
          images,
          tasks,
          FakeBeaconHierarchyRepository(),
          FakeBeaconAccessGuard(),
        ],
        named: {
          #env: env,
          #logger: Logger('RequestOnlyGuardsTest'),
        },
        beaconRepository: beaconRepo,
      );
    });

    void expectNothingWritten() {
      expect(facts.unexpectedCalls, isEmpty);
      expect(images.putCalls, isEmpty);
      expect(tasks.scheduled, isEmpty);
    }

    test('pin', () async {
      await expectLater(
        factCardCase.pin(
          beaconId: _beaconId,
          factText: 'Fact',
          visibility: 0,
          userId: _authorId,
        ),
        throwsBeaconNotRequest,
      );

      expectNothingWritten();
    });

    test('correct', () async {
      await expectLater(
        factCardCase.correct(
          factCardId: 'Ffact0000001',
          beaconId: _beaconId,
          actorUserId: _authorId,
          newText: 'Fact',
          baseRevisionSeq: 1,
        ),
        throwsBeaconNotRequest,
      );

      expectNothingWritten();
    });

    test('uploadAttachment (before the file is stored or hashed)', () async {
      await expectLater(
        factCardCase.uploadAttachment(
          beaconId: _beaconId,
          actorUserId: _authorId,
          attachmentBytes: Stream.value(Uint8List.fromList([1, 2, 3])),
          attachmentMimeType: 'image/png',
        ),
        throwsBeaconNotRequest,
      );

      expectNothingWritten();
    });

    test('restore', () async {
      await expectLater(
        factCardCase.restore(
          factCardId: 'Ffact0000001',
          beaconId: _beaconId,
          actorUserId: _authorId,
          fromSeq: 1,
          baseRevisionSeq: 2,
        ),
        throwsBeaconNotRequest,
      );

      expectNothingWritten();
    });

    test('remove', () async {
      await expectLater(
        factCardCase.remove(
          factCardId: 'Ffact0000001',
          beaconId: _beaconId,
          actorUserId: _authorId,
        ),
        throwsBeaconNotRequest,
      );

      expectNothingWritten();
    });

    test('setVisibility', () async {
      await expectLater(
        factCardCase.setVisibility(
          factCardId: 'Ffact0000001',
          beaconId: _beaconId,
          actorUserId: _authorId,
          visibility: 0,
        ),
        throwsBeaconNotRequest,
      );

      expectNothingWritten();
    });
  });

  group('BeaconDisplayCase.displayStatuses', () {
    late MockBeaconRepositoryPort mockBeaconRepo;
    late BeaconDisplayCase displayCase;

    setUp(() {
      mockBeaconRepo = MockBeaconRepositoryPort();
      displayCase = BeaconDisplayCase(
        mockBeaconRepo,
        helpOfferRepo,
        coordinationRepo,
        _EvaluatingClosureRepo(),
        roomRepo,
        FakeBeaconAccessGuard(),
        noopCommitmentQueryCase(logger: Logger('RequestOnlyGuardsTest')),
        env: env,
        logger: Logger('RequestOnlyGuardsTest'),
      );
      when(mockBeaconRepo.getBeaconById(beaconId: _beaconId)).thenAnswer(
        (_) async => _beacon(kind: BeaconKind.post),
      );
      when(mockBeaconRepo.getBeaconById(beaconId: _requestId)).thenAnswer(
        (_) async => _beacon(kind: BeaconKind.request, id: _requestId),
      );
      when(helpOfferRepo.fetchByBeaconId(any)).thenAnswer((_) async => []);
      when(
        coordinationRepo.coordinationResponseTypeByOfferUserId(any),
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

    test('returns no entry for a Post', () async {
      final result = await displayCase.displayStatuses(
        beaconIds: const [_beaconId],
        viewerId: _authorId,
      );

      expect(result, isEmpty);
      verifyNever(helpOfferRepo.fetchByBeaconId(any));
    });

    test('keeps the entry of a Request listed next to a Post', () async {
      final result = await displayCase.displayStatuses(
        beaconIds: const [_beaconId, _requestId],
        viewerId: _authorId,
      );

      expect(result.map((s) => s.beaconId), [_requestId]);
    });
  });
}
