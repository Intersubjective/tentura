import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/forward_batch_create_result.dart';
import 'package:tentura_server/domain/entity/forward_edge_created.dart';
import 'package:tentura_server/domain/entity/invitation_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/evaluation_repository_port.dart';
import 'package:tentura_server/domain/use_case/capability_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/coordination_case.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/help_offer_case.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/env.dart';

import '../../domain/use_case/forward_case_mocks.mocks.dart' as forward_mocks;
import '../../domain/use_case/help_offer_case_mocks.mocks.dart' as help_mocks;
import '../../domain/use_case/invitation_case_mocks.mocks.dart'
    as invitation_mocks;
import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/beacon_hierarchy_fixture.dart';
import '../../support/recording_commitment_repository.dart';
import '../../support/test_attention_harness.dart';

/// Wires production use cases with a real [BeaconAccessGuard] so hierarchy
/// context viewers hit the same `canReadContent` gates as production.
///
/// Downstream ports are stubbed for the success path, so a call that passes
/// the guard completes without touching the database.
final class HierarchyOnlyViewerHarness {
  HierarchyOnlyViewerHarness({
    required BeaconAccessGuard access,
    required this.childBeaconId,
    required this.hierarchyOnlyViewerId,
  }) : _access = access;

  final BeaconAccessGuard _access;
  final String childBeaconId;
  final String hierarchyOnlyViewerId;

  static final _env = Env(environment: Environment.test);
  static final _logger = Logger('HierarchyOnlyViewerHarness');

  BeaconEntity _childBeacon({String authorId = BeaconHierarchyTopology.bobId}) {
    final now = DateTime.utc(2026, 1, 1);
    return BeaconEntity(
      id: childBeaconId,
      title: 'Child request',
      author: UserEntity(id: authorId),
      createdAt: now,
      updatedAt: now,
      status: BeaconStatus.open,
    );
  }

  HelpOfferCase buildHelpOfferCase({
    help_mocks.MockHelpOfferRepositoryPort? helpOfferRepo,
    RecordingCommitmentRepository? commitmentRepo,
    TestAttentionHarness? attention,
    String lockedBeaconAuthorId = BeaconHierarchyTopology.bobId,
  }) {
    final child = _childBeacon(authorId: lockedBeaconAuthorId);
    final beaconRepo = _HarnessChildBeaconRepo(child);
    final help = helpOfferRepo ?? help_mocks.MockHelpOfferRepositoryPort();
    if (helpOfferRepo == null) {
      when(
        help.hasActiveHelpOffer(
          beaconId: childBeaconId,
          userId: anyNamed('userId'),
        ),
      ).thenAnswer((_) async => false);
      when(
        help.upsert(
          beaconId: anyNamed('beaconId'),
          userId: anyNamed('userId'),
          message: anyNamed('message'),
          helpTypes: anyNamed('helpTypes'),
          offerKind: anyNamed('offerKind'),
        ),
      ).thenAnswer((_) async {});
      when(
        help.withdraw(
          beaconId: anyNamed('beaconId'),
          userId: anyNamed('userId'),
          message: anyNamed('message'),
          withdrawReason: anyNamed('withdrawReason'),
        ),
      ).thenAnswer((_) async {});
    }
    final inbox = help_mocks.MockInboxRepositoryPort();
    when(
      inbox.upsertWatchingForSender(
        senderId: anyNamed('senderId'),
        beaconId: anyNamed('beaconId'),
        touchForwardOrdering: anyNamed('touchForwardOrdering'),
      ),
    ).thenAnswer((_) async {});
    final room = help_mocks.MockBeaconRoomRepositoryPort();
    when(
      room.revokeOfferUserBeaconRoomAccess(
        beaconId: anyNamed('beaconId'),
        offerUserId: anyNamed('offerUserId'),
        authorUserId: anyNamed('authorUserId'),
      ),
    ).thenAnswer((_) async {});
    final commitment = commitmentRepo ?? RecordingCommitmentRepository();
    final att = attention ?? TestAttentionHarness();
    return HelpOfferCase(
      help,
      beaconRepo,
      commitment,
      inbox,
      CapabilityCase(
        help_mocks.MockPersonCapabilityEventRepositoryPort(),
        env: _env,
        logger: _logger,
      ),
      _access,
      roomRepository: room,
      attentionIntents: att.intents,
      attention: att.transactional,
      env: _env,
      logger: _logger,
    );
  }

  HelpOfferCase buildHelpOfferCaseWithInjectedUpsertFailure({
    required RecordingCommitmentRepository commitmentRepo,
  }) {
    final help = help_mocks.MockHelpOfferRepositoryPort();
    when(
      help.hasActiveHelpOffer(
        beaconId: childBeaconId,
        userId: anyNamed('userId'),
      ),
    ).thenAnswer((_) async => false);
    when(
      help.upsert(
        beaconId: anyNamed('beaconId'),
        userId: anyNamed('userId'),
        message: anyNamed('message'),
        helpTypes: anyNamed('helpTypes'),
        offerKind: anyNamed('offerKind'),
      ),
    ).thenThrow(StateError('injected help offer upsert failure'));
    return buildHelpOfferCase(
      helpOfferRepo: help,
      commitmentRepo: commitmentRepo,
      lockedBeaconAuthorId: BeaconHierarchyTopology.aliceId,
    );
  }

  /// [onEdgesCreated] receives the recipients a successful forward would
  /// insert, so a pg test can persist the same edges.
  ForwardCase buildForwardCase({
    Future<void> Function(List<String> recipientIds)? onEdgesCreated,
    String authorId = BeaconHierarchyTopology.bobId,
  }) {
    final edges = forward_mocks.MockForwardEdgeRepositoryPort();
    when(
      edges.fetchActiveInboundEdges(
        beaconId: anyNamed('beaconId'),
        recipientId: anyNamed('recipientId'),
      ),
    ).thenAnswer((_) async => []);
    when(
      edges.lockActiveInboundEdges(
        beaconId: anyNamed('beaconId'),
        recipientId: anyNamed('recipientId'),
      ),
    ).thenAnswer((_) async => []);
    when(
      edges.countPriorOutgoingBatches(
        beaconId: anyNamed('beaconId'),
        senderId: anyNamed('senderId'),
        batchId: anyNamed('batchId'),
      ),
    ).thenAnswer((_) async => 0);
    when(
      edges.createBatch(
        beaconId: anyNamed('beaconId'),
        senderId: anyNamed('senderId'),
        recipientIds: anyNamed('recipientIds'),
        batchId: anyNamed('batchId'),
        noteForRecipient: anyNamed('noteForRecipient'),
        context: anyNamed('context'),
        parentEdgeId: anyNamed('parentEdgeId'),
        onAfterEdgesInserted: anyNamed('onAfterEdgesInserted'),
      ),
    ).thenAnswer((invocation) async {
      final recipientIds =
          invocation.namedArguments[#recipientIds] as List<String>;
      await onEdgesCreated?.call(recipientIds);
      final onAfter =
          invocation.namedArguments[#onAfterEdgesInserted]
              as Future<void> Function()?;
      await onAfter?.call();
      return ForwardBatchCreateResult(
        createdEdges: [
          for (var i = 0; i < recipientIds.length; i++)
            ForwardEdgeCreated(edgeId: 'E${i + 1}', recipientId: recipientIds[i]),
        ],
        availabilitySkippedRecipientIds: const [],
      );
    });
    final help = forward_mocks.MockHelpOfferRepositoryPort();
    when(
      help.hasActiveHelpOffer(
        beaconId: anyNamed('beaconId'),
        userId: anyNamed('userId'),
      ),
    ).thenAnswer((_) async => false);
    final inbox = forward_mocks.MockInboxRepositoryPort();
    when(
      inbox.upsertWatchingForSender(
        senderId: anyNamed('senderId'),
        beaconId: anyNamed('beaconId'),
        context: anyNamed('context'),
      ),
    ).thenAnswer((_) async {});
    final beacons = forward_mocks.MockBeaconRepositoryPort();
    when(
      beacons.getBeaconById(beaconId: anyNamed('beaconId')),
    ).thenAnswer((_) async => _childBeacon(authorId: authorId));
    final visibility = forward_mocks.MockPersonVisibilityRepositoryPort();
    when(
      visibility.mutuallyVisiblePeerIds(
        viewerId: anyNamed('viewerId'),
        peerIds: anyNamed('peerIds'),
        context: anyNamed('context'),
      ),
    ).thenAnswer(
      (invocation) async =>
          (invocation.namedArguments[#peerIds] as Iterable<String>).toSet(),
    );
    final att = TestAttentionHarness();
    return ForwardCase(
      edges,
      forward_mocks.MockForwardAttributionRepositoryPort(),
      help,
      inbox,
      forward_mocks.MockCapabilityEvidencePort(),
      beacons,
      FakeUserBlockRepository(),
      visibility,
      _access,
      attentionIntents: att.intents,
      attention: att.transactional,
      env: _env,
      logger: _logger,
    );
  }

  InvitationCase buildInvitationCase({
    String authorId = BeaconHierarchyTopology.bobId,
  }) {
    final invitations = invitation_mocks.MockInvitationRepositoryPort();
    when(
      invitations.create(
        issuerId: anyNamed('issuerId'),
        addresseeName: anyNamed('addresseeName'),
        beaconId: anyNamed('beaconId'),
        parentForwardEdgeId: anyNamed('parentForwardEdgeId'),
      ),
    ).thenAnswer((invocation) async {
      final now = DateTime.utc(2026, 1, 1);
      return InvitationEntity(
        id: 'Ihierinvite01',
        issuer: UserEntity(id: invocation.namedArguments[#issuerId] as String),
        beaconId: invocation.namedArguments[#beaconId] as String?,
        createdAt: now,
        updatedAt: now,
      );
    });
    final beacons = invitation_mocks.MockBeaconRepositoryPort();
    when(
      beacons.getBeaconById(beaconId: anyNamed('beaconId')),
    ).thenAnswer((_) async => _childBeacon(authorId: authorId));
    final edges = help_mocks.MockForwardEdgeRepositoryPort();
    when(
      edges.fetchActiveInboundEdges(
        beaconId: anyNamed('beaconId'),
        recipientId: anyNamed('recipientId'),
      ),
    ).thenAnswer((_) async => []);
    return InvitationCase(
      invitations,
      invitation_mocks.MockUserRepositoryPort(),
      beacons,
      invitation_mocks.MockVoteUserFriendshipLookupPort(),
      invitation_mocks.MockUserContactRepositoryPort(),
      _access,
      edges,
      FakeUserBlockRepository(),
      env: _env,
      logger: _logger,
    );
  }

  CoordinationCase buildCoordinationCase() => CoordinationCase(
    help_mocks.MockBeaconRepositoryPort(),
    help_mocks.MockHelpOfferRepositoryPort(),
    help_mocks.MockCoordinationRepositoryPort(),
    help_mocks.MockBeaconRoomRepositoryPort(),
    _FakeEvaluationRepository(),
    FakeUserBlockRepository(),
    RecordingCommitmentRepository(),
    CommitmentQueryCase(
      RecordingCommitmentRepository(),
      help_mocks.MockHelpOfferRepositoryPort(),
      env: _env,
      logger: _logger,
    ),
    FakeBeaconHierarchyRepository(),
    guard: _access,
    env: _env,
    logger: _logger,
  );
}

final class _FakeEvaluationRepository extends Fake
    implements EvaluationRepositoryPort {}

final class _HarnessChildBeaconRepo extends Fake implements BeaconRepositoryPort {
  _HarnessChildBeaconRepo(this._child);

  final BeaconEntity _child;

  @override
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) async =>
      _child;

  @override
  Future<T> runInBeaconStateTransaction<T>({
    required String beaconId,
    required String userId,
    required Future<T> Function(BeaconEntity locked) fn,
  }) =>
      fn(_child);
}
