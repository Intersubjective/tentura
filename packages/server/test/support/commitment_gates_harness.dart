import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/data/repository/mock/trust_ledger_repository_mock.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/commitment/commitment_state.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/capability_evidence_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/inbox_repository_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/port/person_capability_event_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/user_block_repository_port.dart';
import 'package:tentura_server/domain/port/user_contact_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/domain/use_case/capability_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/coordination_case.dart';
import 'package:tentura_server/domain/use_case/help_offer_case.dart';
import 'package:tentura_server/domain/use_case/user_block_case.dart';
import 'package:tentura_server/env.dart';

import '../domain/use_case/help_offer_case_mocks.mocks.dart';
import 'coordination_item_record_fixtures.dart';
import 'fake_beacon_access_guard.dart';
import 'fake_beacon_hierarchy_repository.dart';
import 'fake_beacon_child_create_port.dart';
import 'beacon_lifecycle_effects_test_support.dart';
import 'fake_user_block_repository.dart';
import 'recording_commitment_repository.dart';
import 'test_attention_harness.dart';

/// In-memory help-offer store shared across gate-scenario use cases.
final class InMemoryHelpOfferRepository implements HelpOfferRepositoryPort {
  InMemoryHelpOfferRepository(this._clock);

  final DateTime Function() _clock;
  final Map<String, HelpOfferEntity> _offers = {};

  static String _key(String beaconId, String userId) => '$beaconId:$userId';

  @override
  Future<void> upsert({
    required String beaconId,
    required String userId,
    String message = '',
    List<String>? helpTypes,
    int status = 0,
    int offerKind = 0,
  }) async {
    final now = _clock();
    final existing = _offers[_key(beaconId, userId)];
    _offers[_key(beaconId, userId)] = HelpOfferEntity(
      beaconId: beaconId,
      userId: userId,
      message: message,
      helpType: helpTypes?.isNotEmpty == true ? helpTypes!.first : null,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      status: status,
      offerKind: offerKind,
    );
  }

  @override
  Future<void> withdraw({
    required String beaconId,
    required String userId,
    required String withdrawReason,
    String message = '',
  }) async {
    final existing = _offers[_key(beaconId, userId)];
    if (existing == null) return;
    _offers[_key(beaconId, userId)] = existing.copyWith(
      status: 1,
      updatedAt: _clock(),
    );
  }

  @override
  Future<void> deactivate({
    required String beaconId,
    required String userId,
  }) async {
    final key = _key(beaconId, userId);
    final existing = _offers[key];
    if (existing != null) {
      _offers[key] = existing.copyWith(status: 1, updatedAt: _clock());
    }
  }

  @override
  Future<List<HelpOfferEntity>> fetchByBeaconId(String beaconId) async =>
      _offers.values
          .where((o) => o.beaconId == beaconId && o.isActive)
          .toList();

  @override
  Future<List<HelpOfferEntity>> fetchAllByBeaconId(String beaconId) async =>
      _offers.values.where((o) => o.beaconId == beaconId).toList();

  @override
  Future<List<HelpOfferEntity>> fetchByUserId(String userId) async =>
      _offers.values.where((o) => o.userId == userId).toList();

  @override
  Future<bool> hasActiveHelpOffer({
    required String beaconId,
    required String userId,
  }) async => _offers[_key(beaconId, userId)]?.isActive ?? false;

  @override
  Future<List<String>> fetchActiveHelpTypes({
    required String beaconId,
    required String userId,
  }) async {
    final offer = _offers[_key(beaconId, userId)];
    if (offer == null || !offer.isActive) {
      return const [];
    }
    final raw = offer.helpType;
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    return [raw];
  }

  @override
  Future<void> setRoleLabel({
    required String beaconId,
    required String offerUserId,
    required String actorUserId,
    required String? roleLabel,
  }) async {
    final existing = _offers[_key(beaconId, offerUserId)];
    if (existing == null || !existing.isActive) return;
    _offers[_key(beaconId, offerUserId)] = existing.copyWith(
      roleLabel: roleLabel,
      updatedAt: _clock(),
    );
  }
}

/// Beacon repo that mutates status on lifecycle transitions.
final class MutableBeaconRepository implements BeaconRepositoryPort {
  MutableBeaconRepository(this.beacon, {int reviewReopenCount = 0})
    : _reviewReopenCount = reviewReopenCount;

  BeaconEntity beacon;
  int _reviewReopenCount;
  final statusTransitions = <BeaconStatusTransitionCall>[];

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
  Future<void> recordBeaconStatusTransition({
    required String beaconId,
    required BeaconStatus fromStatus,
    required BeaconStatus toStatus,
    required String reason,
    String? actorId,
  }) async {
    statusTransitions.add(
      BeaconStatusTransitionCall(
        beaconId: beaconId,
        fromStatus: fromStatus,
        toStatus: toStatus,
        reason: reason,
        actorId: actorId,
      ),
    );
    beacon = beacon.copyWith(status: toStatus);
  }

  @override
  Future<void> deleteBeaconById(String id, {required String userId}) async {}

  @override
  Future<int> reviewReopenCount(String beaconId) async => _reviewReopenCount;

  @override
  Future<void> incrementReviewReopenCount(String beaconId) async {
    _reviewReopenCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

@immutable
class BeaconStatusTransitionCall {
  const BeaconStatusTransitionCall({
    required this.beaconId,
    required this.fromStatus,
    required this.toStatus,
    required this.reason,
    this.actorId,
  });

  final String beaconId;
  final BeaconStatus fromStatus;
  final BeaconStatus toStatus;
  final String reason;
  final String? actorId;
}

final class NoOpInboxRepository extends Fake implements InboxRepositoryPort {
  @override
  Future<void> upsertWatchingForSender({
    required String senderId,
    required String beaconId,
    String? context,
    bool touchForwardOrdering = true,
  }) async {}

  @override
  Future<void> applyTombstoneAfterWithdraw({
    required String userId,
    required String beaconId,
  }) async {}
}

final class NoOpPersonCapabilityEventRepository extends Fake
    implements PersonCapabilityEventRepositoryPort {
  @override
  Future<void> insertCommitRole({
    required String observerId,
    required String subjectId,
    required String beaconId,
    required String slug,
  }) async {}
}

final class PassThroughMutatingUnitOfWork extends Fake
    implements MutatingUnitOfWorkPort {
  @override
  Future<T> run<T>({
    required Future<T> Function() action,
    String? actorUserId,
  }) => action();
}

final class GateScenarioUserRepository extends Fake
    implements UserRepositoryPort {
  GateScenarioUserRepository(this._ids);

  final Set<String> _ids;

  @override
  Future<UserEntity> getById(String id) async {
    if (!_ids.contains(id)) {
      throw StateError('user not found: $id');
    }
    return UserEntity(id: id);
  }
}

final class NoOpUserContactRepository extends Fake
    implements UserContactRepositoryPort {
  @override
  Future<bool> delete({
    required String viewerId,
    required String subjectId,
  }) async => true;
}

final class NoOpUserBlockRepository extends Fake
    implements UserBlockRepositoryPort {
  int blockCalls = 0;

  @override
  Future<int> countRecentByBlocker({
    required String blockerId,
    required Duration window,
  }) async => 0;

  @override
  Future<void> block({
    required String blockerId,
    required String blockedId,
    required int cascadeMode,
  }) async {
    blockCalls++;
  }

  @override
  Future<void> applyWithdrawal({
    required String blockerId,
    required String blockedId,
  }) async {}

  @override
  Future<void> unblock({
    required String blockerId,
    required String blockedId,
  }) async {}
}

/// Wires real use cases to in-memory fakes for P3.12 gate scenarios.
final class CommitmentGatesHarness {
  CommitmentGatesHarness({
    this.beaconId = 'B-gates',
    this.authorId = 'U-author',
    this.helperId = 'U-helper',
    this.helper2Id = 'U-helper2',
    DateTime? baseTime,
    BeaconStatus initialStatus = BeaconStatus.open,
    int reviewReopenCount = 0,
  }) : baseTime = baseTime ?? DateTime.utc(2026, 6, 1, 12) {
    reset(initialStatus: initialStatus, reviewReopenCount: reviewReopenCount);
  }

  static const _logName = 'CommitmentGatesHarness';

  final String beaconId;
  final String authorId;
  final String helperId;
  final String helper2Id;
  final DateTime baseTime;

  late RecordingCommitmentRepository commitmentRepo;
  late InMemoryHelpOfferRepository helpOfferRepo;
  late MutableBeaconRepository beaconRepo;
  late CommitmentQueryCase commitmentQueryCase;
  late HelpOfferCase helpOfferCase;
  late CoordinationCase coordinationCase;
  late BeaconCase beaconCase;
  late UserBlockCase userBlockCase;
  late TestAttentionHarness attention;

  late MockCoordinationRepositoryPort _coordinationRepo;
  late MockBeaconRoomRepositoryPort _roomRepo;
  late MockHelpOfferAdmissionRepositoryPort _admissionRepo;
  late MockForwardEdgeRepositoryPort _forwardEdgeRepo;
  late MockInboxRepositoryPort _inboxRepo;
  late MockPersonCapabilityEventRepositoryPort _capabilityRepo;

  void reset({
    BeaconStatus initialStatus = BeaconStatus.open,
    int reviewReopenCount = 0,
  }) {
    commitmentRepo = RecordingCommitmentRepository(initialClock: baseTime);
    helpOfferRepo = InMemoryHelpOfferRepository(() => commitmentRepo.clock);
    beaconRepo = MutableBeaconRepository(
      BeaconEntity(
        id: beaconId,
        title: 'Gate scenario beacon',
        author: UserEntity(id: authorId),
        createdAt: baseTime,
        updatedAt: baseTime,
        status: initialStatus,
      ),
      reviewReopenCount: reviewReopenCount,
    );

    commitmentQueryCase = CommitmentQueryCase(
      commitmentRepo,
      helpOfferRepo,
      env: Env(environment: Environment.test),
      logger: Logger(_logName),
    );

    attention = TestAttentionHarness();
    _coordinationRepo = MockCoordinationRepositoryPort();
    _roomRepo = MockBeaconRoomRepositoryPort();
    _admissionRepo = MockHelpOfferAdmissionRepositoryPort();
    _forwardEdgeRepo = MockForwardEdgeRepositoryPort();
    _inboxRepo = MockInboxRepositoryPort();
    _capabilityRepo = MockPersonCapabilityEventRepositoryPort();

    _stubCoordinationDefaults();

    final capabilityCase = CapabilityCase(
      _capabilityRepo,
      env: Env(environment: Environment.test),
      logger: Logger(_logName),
    );

    helpOfferCase = HelpOfferCase(
      helpOfferRepo,
      beaconRepo,
      commitmentRepo,
      _inboxRepo,
      capabilityCase,
      FakeBeaconAccessGuard(),
      roomRepository: _roomRepo,
      attentionIntents: attention.intents,
      attention: attention.transactional,
      env: Env(environment: Environment.test),
      logger: Logger(_logName),
    );

    coordinationCase = CoordinationCase(
      beaconRepo,
      helpOfferRepo,
      _coordinationRepo,
      _roomRepo,
      FakeUserBlockRepository(),
      commitmentRepo,
      commitmentQueryCase,
      FakeBeaconHierarchyRepository(),
      attentionIntents: attention.intents,
      attention: attention.transactional,
      guard: FakeBeaconAccessGuard(),
      env: Env(environment: Environment.test),
      logger: Logger(_logName),
    );

    beaconCase = BeaconCase(
      beaconRepo,
      _FakeImageRepository(),
      _FakeImageObjectGc(),
      _FakeTaskRepository(),
      commitmentQueryCase,
      FakeBeaconAccessGuard(),
      FakeBeaconHierarchyRepository(),
      FakeBeaconChildCreatePort(),
      buildLifecycleEffectsCase(),
      attentionIntents: attention.intents,
      attention: attention.transactional,
      env: Env(environment: Environment.test),
      logger: Logger(_logName),
    );

    userBlockCase = UserBlockCase(
      PassThroughMutatingUnitOfWork(),
      NoOpUserBlockRepository(),
      helpOfferRepo,
      _FakeForwardEdgeRepository(),
      NoOpUserContactRepository(),
      GateScenarioUserRepository({authorId, helperId, helper2Id}),
      beaconRepo,
      commitmentRepo,
      _inboxRepo,
      _NoopCapabilityEvidence(),
      FakeBeaconHierarchyRepository(),
      trustLedger: TrustLedgerRepositoryMock(),
      env: Env(environment: Environment.test),
      logger: Logger(_logName),
    );
  }

  void _stubCoordinationDefaults() {
    when(
      _coordinationRepo.beaconStatusSnapshot(beaconId),
    ).thenAnswer(
      (_) async => (status: beaconRepo.beacon.status, statusChangedAt: null),
    );
    when(
      _coordinationRepo.acceptHelpOffer(
        beaconId: anyNamed('beaconId'),
        offerUserId: anyNamed('offerUserId'),
        actorUserId: anyNamed('actorUserId'),
      ),
    ).thenAnswer(
      (_) async => (
        status: beaconRepo.beacon.status,
        statusChangedAt: commitmentRepo.clock,
      ),
    );
    when(
      _coordinationRepo.declineHelpOffer(
        beaconId: anyNamed('beaconId'),
        offerUserId: anyNamed('offerUserId'),
        actorUserId: anyNamed('actorUserId'),
        reason: anyNamed('reason'),
      ),
    ).thenAnswer(
      (_) async => (
        status: beaconRepo.beacon.status,
        statusChangedAt: commitmentRepo.clock,
      ),
    );
    when(
      _coordinationRepo.upsertResponse(
        beaconId: anyNamed('beaconId'),
        offerUserId: anyNamed('offerUserId'),
        authorUserId: anyNamed('authorUserId'),
        responseType: anyNamed('responseType'),
      ),
    ).thenAnswer((_) async {});
    when(
      _roomRepo.findParticipant(
        beaconId: anyNamed('beaconId'),
        userId: anyNamed('userId'),
      ),
    ).thenAnswer(
      (invocation) async {
        final userId = invocation.namedArguments[#userId] as String;
        final beaconId = invocation.namedArguments[#beaconId] as String;
        return testBeaconParticipant(
          beaconId: beaconId,
          userId: userId,
          roomAccess: RoomAccessBits.requested,
        );
      },
    );
    when(
      _forwardEdgeRepo.isDirectAuthorForward(
        beaconId: anyNamed('beaconId'),
        authorId: anyNamed('authorId'),
        userId: anyNamed('userId'),
      ),
    ).thenAnswer((_) async => false);
    when(
      _admissionRepo.record(
        beaconId: anyNamed('beaconId'),
        offerUserId: anyNamed('offerUserId'),
        actorUserId: anyNamed('actorUserId'),
        action: anyNamed('action'),
      ),
    ).thenAnswer((_) async {});
    when(
      _inboxRepo.upsertWatchingForSender(
        senderId: anyNamed('senderId'),
        beaconId: anyNamed('beaconId'),
        touchForwardOrdering: anyNamed('touchForwardOrdering'),
      ),
    ).thenAnswer((_) async {});
  }

  void advanceClock(Duration duration) => commitmentRepo.advanceClock(duration);

  Future<void> offerHelp({
    String userId = '',
    String message = 'I can help',
  }) => helpOfferCase.offerHelp(
    beaconId: beaconId,
    userId: userId.isEmpty ? helperId : userId,
    message: message,
  );

  Future<void> acceptOffer({String userId = ''}) =>
      coordinationCase.acceptHelpOffer(
        beaconId: beaconId,
        offerUserId: userId.isEmpty ? helperId : userId,
        actorUserId: authorId,
      );

  Future<void> withdrawOffer({
    String userId = '',
    Duration advanceBefore = Duration.zero,
  }) async {
    if (advanceBefore > Duration.zero) {
      advanceClock(advanceBefore);
    }
    await helpOfferCase.withdraw(
      beaconId: beaconId,
      userId: userId.isEmpty ? helperId : userId,
      withdrawReason: 'other',
    );
  }

  Future<void> blockHelper() => userBlockCase.block(
    blockerId: authorId,
    blockedId: helperId,
    cascadeMode: 0,
  );

  Future<void> recordReleasedByAuthor({String userId = ''}) =>
      commitmentRepo.record(
        beaconId: beaconId,
        userId: userId.isEmpty ? helperId : userId,
        actorUserId: authorId,
        kind: CommitmentEventKind.releasedByAuthor,
      );

  Future<bool> currentStakeIsAcknowledged({String userId = ''}) async {
    final events = await commitmentRepo.eventsForPair(
      beaconId: beaconId,
      userId: userId.isEmpty ? helperId : userId,
    );
    return currentStakeState(events) == CommitmentStakeState.acknowledged;
  }

  Future<void> setCoordinationResponse({
    required int responseType,
    bool inviteToRoom = false,
    String userId = '',
  }) => coordinationCase.setCoordinationResponse(
    beaconId: beaconId,
    offerUserId: userId.isEmpty ? helperId : userId,
    authorUserId: authorId,
    responseType: responseType,
    inviteToRoom: inviteToRoom,
    removeFromRoom: false,
  );

  Future<void> declineOffer({String userId = ''}) =>
      coordinationCase.declineHelpOffer(
        beaconId: beaconId,
        offerUserId: userId.isEmpty ? helperId : userId,
        actorUserId: authorId,
        reason: 'not needed',
      );
}

class _FakeImageRepository extends Fake implements ImageRepositoryPort {}

class _FakeImageObjectGc extends Fake implements ImageObjectGcPort {}

class _FakeTaskRepository extends Fake implements TaskRepositoryPort {}

class _NoopCapabilityEvidence extends Fake implements CapabilityEvidencePort {
  @override
  Future<void> reconcileForwardReasons({
    required String forwardEdgeId,
    required String observerId,
    required String subjectId,
    required List<String> slugs,
  }) async {}
}

class _FakeForwardEdgeRepository extends Fake
    implements ForwardEdgeRepositoryPort {
  @override
  Future<List<ForwardEdgeEntity>> fetchByRecipientId(
    String recipientId, {
    String? context,
  }) async => [];
}
