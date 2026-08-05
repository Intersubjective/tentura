import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/inbox_repository_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/port/user_block_repository_port.dart';
import 'package:tentura_server/domain/port/user_contact_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/user_block_case.dart';
import 'package:tentura_server/domain/user_block/user_block_withdraw_reason.dart';
import 'package:tentura_server/env.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import '../../support/recording_commitment_repository.dart';

final class _PassThroughUoW extends Fake implements MutatingUnitOfWorkPort {
  @override
  Future<T> run<T>({
    required Future<T> Function() action,
    String? actorUserId,
  }) =>
      action();
}

final class _RecordingUoW extends Fake implements MutatingUnitOfWorkPort {
  Object? caughtError;

  @override
  Future<T> run<T>({
    required Future<T> Function() action,
    String? actorUserId,
  }) async {
    try {
      return await action();
    } catch (e) {
      caughtError = e;
      rethrow;
    }
  }
}

final class _FakeBlocks extends Fake implements UserBlockRepositoryPort {
  int recentCount = 0;
  var blockCalls = 0;
  var applyWithdrawalCalls = 0;

  @override
  Future<int> countRecentByBlocker({
    required String blockerId,
    required Duration window,
  }) async =>
      recentCount;

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
  }) async {
    applyWithdrawalCalls++;
  }

  @override
  Future<void> unblock({
    required String blockerId,
    required String blockedId,
  }) async {}
}

final class _FakeUsers extends Fake implements UserRepositoryPort {
  final Set<String> existingIds;

  _FakeUsers(this.existingIds);

  @override
  Future<UserEntity> getById(String id) async {
    if (!existingIds.contains(id)) {
      throw StateError('Expected exactly one element, but got 0');
    }
    return UserEntity(id: id);
  }
}

final class _FakeHelpOffers extends Fake implements HelpOfferRepositoryPort {
  final Map<String, List<HelpOfferEntity>> offersByUserId;

  _FakeHelpOffers([this.offersByUserId = const {}]);

  final withdrawCalls = <({String beaconId, String userId, String reason})>[];

  @override
  Future<List<HelpOfferEntity>> fetchByUserId(String userId) async =>
      offersByUserId[userId] ?? [];

  @override
  Future<void> withdraw({
    required String beaconId,
    required String userId,
    String message = '',
    required String withdrawReason,
  }) async {
    withdrawCalls.add(
      (beaconId: beaconId, userId: userId, reason: withdrawReason),
    );
  }
}

final class _FakeForwardEdges extends Fake implements ForwardEdgeRepositoryPort {
  final Map<String, List<ForwardEdgeEntity>> edgesByRecipientId;

  _FakeForwardEdges([this.edgesByRecipientId = const {}]);

  final cancelCalls = <({String edgeId, String senderId})>[];

  @override
  Future<List<ForwardEdgeEntity>> fetchByRecipientId(
    String recipientId, {
    String? context,
  }) async =>
      edgesByRecipientId[recipientId] ?? [];

  @override
  Future<void> cancel(String edgeId, String senderId) async {
    cancelCalls.add((edgeId: edgeId, senderId: senderId));
  }
}

final class _RecordingInbox extends Fake implements InboxRepositoryPort {
  final upsertWatchingCalls =
      <({String senderId, String beaconId, bool touchForwardOrdering})>[];
  final tombstoneCalls = <({String userId, String beaconId})>[];
  final markForwardCancelledCalls =
      <({String beaconId, String recipientId})>[];

  @override
  Future<void> upsertWatchingForSender({
    required String senderId,
    required String beaconId,
    String? context,
    bool touchForwardOrdering = true,
  }) async {
    upsertWatchingCalls.add(
      (
        senderId: senderId,
        beaconId: beaconId,
        touchForwardOrdering: touchForwardOrdering,
      ),
    );
  }

  @override
  Future<void> applyTombstoneAfterWithdraw({
    required String userId,
    required String beaconId,
  }) async {
    tombstoneCalls.add((userId: userId, beaconId: beaconId));
  }

  @override
  Future<void> markForwardCancelledForRecipient({
    required String beaconId,
    required String recipientId,
  }) async {
    markForwardCancelledCalls.add(
      (beaconId: beaconId, recipientId: recipientId),
    );
  }
}

final class _FailingContacts extends Fake implements UserContactRepositoryPort {
  @override
  Future<bool> delete({
    required String viewerId,
    required String subjectId,
  }) async {
    throw StateError('contact delete failed');
  }
}

final class _FakeContacts extends Fake implements UserContactRepositoryPort {
  @override
  Future<bool> delete({
    required String viewerId,
    required String subjectId,
  }) async =>
      false;
}

final class _FakeBeacons extends Fake implements BeaconRepositoryPort {
  _FakeBeacons({
    this.authorIdByBeaconId = const {},
    this.statusByBeaconId = const {},
  });

  final Map<String, String> authorIdByBeaconId;
  final Map<String, BeaconStatus> statusByBeaconId;

  @override
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) async =>
      BeaconEntity(
        id: beaconId,
        title: 't',
        author: UserEntity(id: authorIdByBeaconId[beaconId] ?? 'unused'),
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        status: statusByBeaconId[beaconId] ?? BeaconStatus.open,
      );
}

UserBlockCase _buildCase({
  required UserBlockRepositoryPort blocks,
  required UserRepositoryPort users,
  MutatingUnitOfWorkPort? unitOfWork,
  HelpOfferRepositoryPort? helpOffers,
  ForwardEdgeRepositoryPort? forwardEdges,
  UserContactRepositoryPort? contacts,
  BeaconRepositoryPort? beacons,
  RecordingCommitmentRepository? commitment,
  InboxRepositoryPort? inbox,
  int blockRateLimitPerDay = 50,
}) =>
    UserBlockCase(
      unitOfWork ?? _PassThroughUoW(),
      blocks,
      helpOffers ?? _FakeHelpOffers(),
      forwardEdges ?? _FakeForwardEdges(),
      contacts ?? _FakeContacts(),
      users,
      beacons ?? _FakeBeacons(),
      commitment ?? RecordingCommitmentRepository(),
      inbox ?? _RecordingInbox(),
      env: Env(
        environment: Environment.test,
        blockRateLimitPerDay: blockRateLimitPerDay,
      ),
      logger: Logger('UserBlockCaseTest'),
    );

void main() {
  const blockerId = 'U-blocker';
  const blockedId = 'U-blocked';

  test('self-block throws ArgumentError before unit of work', () async {
    final blocks = _FakeBlocks();
    final case_ = _buildCase(
      blocks: blocks,
      users: _FakeUsers({blockerId}),
    );

    expect(
      () => case_.block(
        blockerId: blockerId,
        blockedId: blockerId,
        cascadeMode: 0,
      ),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('cannot block yourself'),
        ),
      ),
    );
    expect(blocks.blockCalls, 0);
  });

  test('unknown blockedId throws IdNotFoundException', () async {
    final blocks = _FakeBlocks();
    final case_ = _buildCase(
      blocks: blocks,
      users: _FakeUsers({blockerId}),
    );

    await expectLater(
      case_.block(
        blockerId: blockerId,
        blockedId: blockedId,
        cascadeMode: 0,
      ),
      throwsA(isA<IdNotFoundException>()),
    );
    expect(blocks.blockCalls, 0);
  });

  test('rate limit rejects when recent blocks reach env.blockRateLimitPerDay', () async {
    final blocks = _FakeBlocks()..recentCount = 50;
    final case_ = _buildCase(
      blocks: blocks,
      users: _FakeUsers({blockerId, blockedId}),
      blockRateLimitPerDay: 50,
    );

    await expectLater(
      case_.block(
        blockerId: blockerId,
        blockedId: blockedId,
        cascadeMode: 0,
      ),
      throwsA(isA<RateLimitedException>()),
    );
    expect(blocks.blockCalls, 0);
  });

  test('failure during cleanup propagates from unit of work', () async {
    final blocks = _FakeBlocks();
    final uow = _RecordingUoW();
    final case_ = _buildCase(
      blocks: blocks,
      users: _FakeUsers({blockerId, blockedId}),
      unitOfWork: uow,
      contacts: _FailingContacts(),
    );

    await expectLater(
      case_.block(
        blockerId: blockerId,
        blockedId: blockedId,
        cascadeMode: 0,
      ),
      throwsA(isA<StateError>()),
    );
    expect(blocks.blockCalls, 1);
    expect(blocks.applyWithdrawalCalls, 0);
    expect(uow.caughtError, isA<StateError>());
  });

  test('successful block runs cleanup and withdrawal', () async {
    final blocks = _FakeBlocks();
    final case_ = _buildCase(
      blocks: blocks,
      users: _FakeUsers({blockerId, blockedId}),
    );

    await case_.block(
      blockerId: blockerId,
      blockedId: blockedId,
      cascadeMode: 1,
    );

    expect(blocks.blockCalls, 1);
    expect(blocks.applyWithdrawalCalls, 1);
  });

  test('withdraw reason constant is the block feature value', () {
    expect(kBlockWithdrawReason, 'blocked');
  });

  test(
    'help-offer cleanup records blockedCleanup, withdraws, and upserts watching on open beacon',
    () async {
      const beaconId = 'B-open';
      final helpOffers = _FakeHelpOffers({
        blockerId: [
          HelpOfferEntity(
            beaconId: beaconId,
            userId: blockerId,
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
            status: 0,
          ),
        ],
      });
      final commitment = RecordingCommitmentRepository();
      final inbox = _RecordingInbox();
      final case_ = _buildCase(
        blocks: _FakeBlocks(),
        users: _FakeUsers({blockerId, blockedId}),
        helpOffers: helpOffers,
        commitment: commitment,
        inbox: inbox,
        beacons: _FakeBeacons(
          authorIdByBeaconId: {beaconId: blockedId},
          statusByBeaconId: {beaconId: BeaconStatus.open},
        ),
      );

      await case_.block(
        blockerId: blockerId,
        blockedId: blockedId,
        cascadeMode: 0,
      );

      expect(commitment.recordCalls, [
        (
          beaconId: beaconId,
          userId: blockerId,
          actorUserId: blockerId,
          kind: CommitmentEventKind.blockedCleanup,
          reason: kBlockWithdrawReason,
        ),
      ]);
      expect(helpOffers.withdrawCalls, [
        (
          beaconId: beaconId,
          userId: blockerId,
          reason: kBlockWithdrawReason,
        ),
      ]);
      expect(inbox.upsertWatchingCalls, [
        (
          senderId: blockerId,
          beaconId: beaconId,
          touchForwardOrdering: false,
        ),
      ]);
      expect(inbox.tombstoneCalls, isEmpty);
    },
  );

  test(
    'help-offer cleanup applies inbox tombstone when beacon is not open-family',
    () async {
      const beaconId = 'B-closed';
      final helpOffers = _FakeHelpOffers({
        blockedId: [
          HelpOfferEntity(
            beaconId: beaconId,
            userId: blockedId,
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
            status: 0,
          ),
        ],
      });
      final commitment = RecordingCommitmentRepository();
      final inbox = _RecordingInbox();
      final case_ = _buildCase(
        blocks: _FakeBlocks(),
        users: _FakeUsers({blockerId, blockedId}),
        helpOffers: helpOffers,
        commitment: commitment,
        inbox: inbox,
        beacons: _FakeBeacons(
          authorIdByBeaconId: {beaconId: blockerId},
          statusByBeaconId: {beaconId: BeaconStatus.closed},
        ),
      );

      await case_.block(
        blockerId: blockerId,
        blockedId: blockedId,
        cascadeMode: 0,
      );

      expect(commitment.recordCalls, [
        (
          beaconId: beaconId,
          userId: blockedId,
          actorUserId: blockedId,
          kind: CommitmentEventKind.blockedCleanup,
          reason: kBlockWithdrawReason,
        ),
      ]);
      expect(helpOffers.withdrawCalls, [
        (
          beaconId: beaconId,
          userId: blockedId,
          reason: kBlockWithdrawReason,
        ),
      ]);
      expect(inbox.tombstoneCalls, [
        (userId: blockedId, beaconId: beaconId),
      ]);
      expect(inbox.upsertWatchingCalls, isEmpty);
    },
  );

  test(
    'forward-edge cleanup cancels edge and marks recipient inbox',
    () async {
      const edgeId = 'F-edge';
      const beaconId = 'B-fwd';
      final forwardEdges = _FakeForwardEdges({
        blockedId: [
          ForwardEdgeEntity(
            id: edgeId,
            beaconId: beaconId,
            senderId: blockerId,
            recipientId: blockedId,
            createdAt: DateTime.utc(2026),
          ),
        ],
      });
      final inbox = _RecordingInbox();
      final case_ = _buildCase(
        blocks: _FakeBlocks(),
        users: _FakeUsers({blockerId, blockedId}),
        forwardEdges: forwardEdges,
        inbox: inbox,
      );

      await case_.block(
        blockerId: blockerId,
        blockedId: blockedId,
        cascadeMode: 0,
      );

      expect(forwardEdges.cancelCalls, [
        (edgeId: edgeId, senderId: blockerId),
      ]);
      expect(inbox.markForwardCancelledCalls, [
        (beaconId: beaconId, recipientId: blockedId),
      ]);
    },
  );
}
