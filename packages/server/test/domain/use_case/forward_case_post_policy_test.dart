import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/forward_batch_create_result.dart';
import 'package:tentura_server/domain/entity/forward_delivery_result.dart';
import 'package:tentura_server/domain/entity/forward_edge_created.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/post_lock_port.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/test_attention_harness.dart';
import 'forward_case_mocks.mocks.dart';

const _authorId = 'Uauthor';
const _forwarderId = 'Uforwarder';
const _recipientId = 'Urecipient';
const _beaconId = 'B1';

/// Records each lock and runs [onLocked], which stands for another
/// transaction committing a change while this one waited for the lock.
final class _RecordingPostLock implements PostLockPort {
  final lockedBeaconIds = <String>[];
  void Function()? onLocked;

  @override
  Future<void> lockForPostMutation(String beaconId) async {
    lockedBeaconIds.add(beaconId);
    onLocked?.call();
  }
}

Matcher _unauthorizedWith(String description) => throwsA(
  isA<UnauthorizedException>().having(
    (e) => e.description,
    'description',
    description,
  ),
);

void main() {
  late MockForwardEdgeRepositoryPort forwardEdgeRepo;
  late MockForwardAttributionRepositoryPort forwardAttributionRepo;
  late MockHelpOfferRepositoryPort helpOfferRepo;
  late MockInboxRepositoryPort inboxRepo;
  late MockCapabilityEvidencePort capabilityEvidence;
  late MockBeaconRepositoryPort beaconRepo;
  late MockPersonVisibilityRepositoryPort personVisibilityRepo;
  late _RecordingPostLock postLock;
  late TestAttentionHarness attention;
  late ForwardCase case_;

  final now = DateTime.utc(2026);

  BeaconEntity beacon({
    required BeaconKind kind,
    required BeaconForwardPolicyValue policy,
    BeaconStatus status = BeaconStatus.open,
  }) => BeaconEntity(
    id: _beaconId,
    title: kind == BeaconKind.post ? '' : 'Request title',
    author: const UserEntity(id: _authorId),
    createdAt: now,
    updatedAt: now,
    status: status,
    kind: kind,
    forwardPolicy: policy,
  );

  late BeaconEntity current;

  void stubBeacon(BeaconEntity value) => current = value;

  Future<ForwardDeliveryResult> forwardAs(String senderId) => case_.forward(
    senderId: senderId,
    beaconId: _beaconId,
    recipientIds: const [_recipientId],
  );

  void verifyNoEdgeCreated() {
    verifyNever(
      forwardEdgeRepo.createBatch(
        beaconId: anyNamed('beaconId'),
        senderId: anyNamed('senderId'),
        recipientIds: anyNamed('recipientIds'),
        batchId: anyNamed('batchId'),
        noteForRecipient: anyNamed('noteForRecipient'),
        context: anyNamed('context'),
        parentEdgeId: anyNamed('parentEdgeId'),
        onAfterEdgesInserted: anyNamed('onAfterEdgesInserted'),
      ),
    );
  }

  void verifyEdgeCreatedFor(String senderId) {
    verify(
      forwardEdgeRepo.createBatch(
        beaconId: _beaconId,
        senderId: senderId,
        recipientIds: const [_recipientId],
        batchId: anyNamed('batchId'),
        noteForRecipient: anyNamed('noteForRecipient'),
        context: anyNamed('context'),
        parentEdgeId: anyNamed('parentEdgeId'),
        onAfterEdgesInserted: anyNamed('onAfterEdgesInserted'),
      ),
    ).called(1);
  }

  setUp(() {
    forwardEdgeRepo = MockForwardEdgeRepositoryPort();
    forwardAttributionRepo = MockForwardAttributionRepositoryPort();
    helpOfferRepo = MockHelpOfferRepositoryPort();
    inboxRepo = MockInboxRepositoryPort();
    capabilityEvidence = MockCapabilityEvidencePort();
    beaconRepo = MockBeaconRepositoryPort();
    personVisibilityRepo = MockPersonVisibilityRepositoryPort();
    postLock = _RecordingPostLock();
    attention = TestAttentionHarness();
    current = beacon(
      kind: BeaconKind.request,
      policy: BeaconForwardPolicyValue.open,
    );
    when(
      beaconRepo.getBeaconById(beaconId: anyNamed('beaconId')),
    ).thenAnswer((_) async => current);

    case_ = ForwardCase(
      forwardEdgeRepo,
      forwardAttributionRepo,
      helpOfferRepo,
      inboxRepo,
      capabilityEvidence,
      beaconRepo,
      FakeUserBlockRepository(),
      personVisibilityRepo,
      FakeBeaconAccessGuard(),
      postLock: postLock,
      attentionIntents: attention.intents,
      attention: attention.transactional,
      env: Env(environment: Environment.test),
      logger: Logger('ForwardCasePostPolicyTest'),
    );

    when(
      forwardEdgeRepo.fetchActiveInboundEdges(
        beaconId: anyNamed('beaconId'),
        recipientId: anyNamed('recipientId'),
      ),
    ).thenAnswer((_) async => []);
    when(
      forwardEdgeRepo.lockActiveInboundEdges(
        beaconId: anyNamed('beaconId'),
        recipientId: anyNamed('recipientId'),
      ),
    ).thenAnswer((_) async => []);
    when(
      forwardEdgeRepo.countPriorOutgoingBatches(
        beaconId: anyNamed('beaconId'),
        senderId: anyNamed('senderId'),
        batchId: anyNamed('batchId'),
      ),
    ).thenAnswer((_) async => 0);
    when(
      helpOfferRepo.hasActiveHelpOffer(
        beaconId: anyNamed('beaconId'),
        userId: anyNamed('userId'),
      ),
    ).thenAnswer((_) async => false);
    when(
      inboxRepo.upsertWatchingForSender(
        senderId: anyNamed('senderId'),
        beaconId: anyNamed('beaconId'),
        context: anyNamed('context'),
      ),
    ).thenAnswer((_) async {});
    when(
      forwardEdgeRepo.createBatch(
        beaconId: anyNamed('beaconId'),
        senderId: anyNamed('senderId'),
        recipientIds: anyNamed('recipientIds'),
        batchId: anyNamed('batchId'),
        noteForRecipient: anyNamed('noteForRecipient'),
        context: anyNamed('context'),
        parentEdgeId: anyNamed('parentEdgeId'),
        onAfterEdgesInserted: anyNamed('onAfterEdgesInserted'),
      ),
    ).thenAnswer(
      (_) async => const ForwardBatchCreateResult(
        createdEdges: [
          ForwardEdgeCreated(edgeId: 'E1', recipientId: _recipientId),
        ],
        availabilitySkippedRecipientIds: [],
      ),
    );
    when(
      personVisibilityRepo.personVisiblePeerIds(
        viewerId: anyNamed('viewerId'),
        peerIds: anyNamed('peerIds'),
        context: anyNamed('context'),
      ),
    ).thenAnswer((_) async => {_recipientId});
  });

  group('ForwardCase on a Post with closed forwarding', () {
    setUp(() {
      stubBeacon(
        beacon(
          kind: BeaconKind.post,
          policy: BeaconForwardPolicyValue.closed,
        ),
      );
    });

    test('refuses a non-author with the forwarding-is-off message', () async {
      await expectLater(
        forwardAs(_forwarderId),
        _unauthorizedWith('Forwarding is off for this post'),
      );
      verifyNoEdgeCreated();
      expect(postLock.lockedBeaconIds, [_beaconId]);
    });

    test('lets the author forward under the Post lock', () async {
      final result = await forwardAs(_authorId);

      expect(result.deliveredRecipientIds, [_recipientId]);
      verifyEdgeCreatedFor(_authorId);
      expect(postLock.lockedBeaconIds, [_beaconId]);
    });

    test('keeps the not-open message for a non-author when the Post is '
        'also not open', () async {
      stubBeacon(
        beacon(
          kind: BeaconKind.post,
          policy: BeaconForwardPolicyValue.closed,
          status: BeaconStatus.deleted,
        ),
      );

      await expectLater(
        forwardAs(_forwarderId),
        _unauthorizedWith('Request does not allow forwarding'),
      );
      verifyNoEdgeCreated();
    });

    test('keeps the not-open message for the author when the Post is '
        'also not open', () async {
      stubBeacon(
        beacon(
          kind: BeaconKind.post,
          policy: BeaconForwardPolicyValue.closed,
          status: BeaconStatus.deleted,
        ),
      );

      await expectLater(
        forwardAs(_authorId),
        _unauthorizedWith('Request does not allow forwarding'),
      );
      verifyNoEdgeCreated();
    });

    test('judges the policy as it stands after the Post lock is taken, '
        'when the author opened forwarding meanwhile', () async {
      postLock.onLocked = () => stubBeacon(
        beacon(kind: BeaconKind.post, policy: BeaconForwardPolicyValue.open),
      );

      final result = await forwardAs(_forwarderId);

      expect(postLock.lockedBeaconIds, [_beaconId]);
      expect(result.deliveredRecipientIds, [_recipientId]);
      verifyEdgeCreatedFor(_forwarderId);
    });
  });

  group('ForwardCase on a Post with open forwarding', () {
    test('lets a non-author forward under the Post lock', () async {
      stubBeacon(
        beacon(kind: BeaconKind.post, policy: BeaconForwardPolicyValue.open),
      );

      final result = await forwardAs(_forwarderId);

      expect(result.deliveredRecipientIds, [_recipientId]);
      verifyEdgeCreatedFor(_forwarderId);
      expect(postLock.lockedBeaconIds, [_beaconId]);
    });

    test('judges the status as it stands after the Post lock is taken, '
        'when the Post was deleted meanwhile', () async {
      stubBeacon(
        beacon(kind: BeaconKind.post, policy: BeaconForwardPolicyValue.open),
      );
      postLock.onLocked = () => stubBeacon(
        beacon(
          kind: BeaconKind.post,
          policy: BeaconForwardPolicyValue.open,
          status: BeaconStatus.deleted,
        ),
      );

      await expectLater(
        forwardAs(_forwarderId),
        _unauthorizedWith('Request does not allow forwarding'),
      );
      expect(postLock.lockedBeaconIds, [_beaconId]);
      verifyNoEdgeCreated();
    });

    test('keeps the not-open message when the Post is closed out', () async {
      stubBeacon(
        beacon(
          kind: BeaconKind.post,
          policy: BeaconForwardPolicyValue.open,
          status: BeaconStatus.closed,
        ),
      );

      await expectLater(
        forwardAs(_forwarderId),
        _unauthorizedWith('Request does not allow forwarding'),
      );
      verifyNoEdgeCreated();
    });
  });

  group('ForwardCase on a Request', () {
    test('lets a non-author forward an open Request', () async {
      stubBeacon(
        beacon(
          kind: BeaconKind.request,
          policy: BeaconForwardPolicyValue.open,
        ),
      );

      final result = await forwardAs(_forwarderId);

      expect(result.deliveredRecipientIds, [_recipientId]);
      expect(postLock.lockedBeaconIds, isEmpty);
    });

    test('keeps the not-open message when the Request is closed', () async {
      stubBeacon(
        beacon(
          kind: BeaconKind.request,
          policy: BeaconForwardPolicyValue.open,
          status: BeaconStatus.closed,
        ),
      );

      await expectLater(
        forwardAs(_forwarderId),
        _unauthorizedWith('Request does not allow forwarding'),
      );
      verifyNoEdgeCreated();
    });
  });
}
