import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_user_block.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_user_block.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/user_block_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/capability_evidence_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/inbox_repository_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/port/user_block_repository_port.dart';
import 'package:tentura_server/domain/port/user_contact_repository_port.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/user_block_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/recording_commitment_repository.dart';

final class _PassThroughUoW extends Fake implements MutatingUnitOfWorkPort {
  @override
  Future<T> run<T>({
    required Future<T> Function() action,
    String? actorUserId,
  }) => action();
}

final class _RecordingBlockRepository extends Fake
    implements UserBlockRepositoryPort {
  String? lastBlockerId;
  String? lastBlockedId;
  int? lastCascadeMode;
  String? lastMethod;

  @override
  Future<void> block({
    required String blockerId,
    required String blockedId,
    required int cascadeMode,
  }) async {
    lastMethod = 'block';
    lastBlockerId = blockerId;
    lastBlockedId = blockedId;
    lastCascadeMode = cascadeMode;
  }

  @override
  Future<void> unblock({
    required String blockerId,
    required String blockedId,
  }) async {
    lastMethod = 'unblock';
    lastBlockerId = blockerId;
    lastBlockedId = blockedId;
  }

  @override
  Future<void> promoteToDirect({
    required String blockerId,
    required String blockedId,
  }) async {
    lastMethod = 'promoteToDirect';
    lastBlockerId = blockerId;
    lastBlockedId = blockedId;
  }

  @override
  Future<int> countRecentByBlocker({
    required String blockerId,
    required Duration window,
  }) async => 0;

  @override
  Future<void> applyWithdrawal({
    required String blockerId,
    required String blockedId,
  }) async {}

  @override
  Future<List<UserBlockIntentEntity>> listIntents(String blockerId) async {
    lastMethod = 'listIntents';
    lastBlockerId = blockerId;
    return const [];
  }

  @override
  Future<List<UserBlockEntity>> listInherited({
    required String blockerId,
    required String originId,
  }) async {
    lastMethod = 'listInherited';
    lastBlockerId = blockerId;
    return const [];
  }

  @override
  Future<BlockPreviewEntity> preview({
    required String blockerId,
    required String blockedId,
    required int cascadeMode,
  }) async {
    lastMethod = 'preview';
    lastBlockerId = blockerId;
    lastBlockedId = blockedId;
    lastCascadeMode = cascadeMode;
    return const BlockPreviewEntity();
  }
}

final class _FakeUsers extends Fake implements UserRepositoryPort {
  @override
  Future<UserEntity> getById(String id) async => UserEntity(id: id);
}

UserBlockCase _userBlockCase(_RecordingBlockRepository blocks) => UserBlockCase(
  _PassThroughUoW(),
  blocks,
  _FakeHelpOffers(),
  _FakeForwardEdges(),
  _FakeContacts(),
  _FakeUsers(),
  _FakeBeacons(),
  NoOpCommitmentRepository(),
  _FakeInbox(),
  _NoopCapabilityEvidence(),
  env: Env.test(),
  logger: Logger('user-block-graphql-test'),
);

final class _NoopCapabilityEvidence extends Fake
    implements CapabilityEvidencePort {
  @override
  Future<void> reconcileForwardReasons({
    required String forwardEdgeId,
    required String observerId,
    required String subjectId,
    required List<String> slugs,
  }) async {}
}

final class _FakeHelpOffers extends Fake implements HelpOfferRepositoryPort {
  @override
  Future<List<HelpOfferEntity>> fetchByUserId(String userId) async => [];
}

final class _FakeForwardEdges extends Fake
    implements ForwardEdgeRepositoryPort {
  @override
  Future<List<ForwardEdgeEntity>> fetchByRecipientId(
    String recipientId, {
    String? context,
  }) async => [];
}

final class _FakeContacts extends Fake implements UserContactRepositoryPort {
  @override
  Future<bool> delete({
    required String viewerId,
    required String subjectId,
  }) async => false;
}

final class _FakeBeacons extends Fake implements BeaconRepositoryPort {}

final class _FakeInbox extends Fake implements InboxRepositoryPort {}

class _FakeProfileLookup extends Fake implements UserProfileBatchLookup {
  _FakeProfileLookup(this.profiles);

  final Map<String, UserPublicRecord> profiles;
  Iterable<String>? lastIds;

  @override
  Future<Map<String, UserPublicRecord>> userPublicRecordsByIds({
    required Iterable<String> ids,
    required Set<String> reciprocalPeerIds,
    Set<String> trustsViewerPeerIds = const {},
  }) async {
    lastIds = ids;
    return {
      for (final id in ids)
        if (profiles.containsKey(id)) id: profiles[id]!,
    };
  }
}

const _profileU2 = UserPublicRecord(
  id: 'U2',
  displayName: 'Blocked User',
  description: '',
  userAvailability: null,
);

void main() {
  const auth = {kGlobalInputQueryJwt: JwtEntity(sub: 'U1')};

  group('schema registration', () {
    test('mutations and queries expose user-block operations', () {
      final mutationNames = MutationUserBlock(
        userBlockCase: _userBlockCase(_RecordingBlockRepository()),
      ).all.map((field) => field.name).toSet();
      final queryNames = QueryUserBlock(
        blockRepository: _RecordingBlockRepository(),
        profileLookup: _FakeProfileLookup({}),
      ).all.map((field) => field.name).toSet();

      expect(
        mutationNames,
        containsAll(['userBlock', 'userUnblock', 'userBlockPromote']),
      );
      expect(
        queryNames,
        containsAll(['myBlocks', 'blockInherited', 'blockPreview']),
      );
    });
  });

  group('mutations scope actor from JWT only', () {
    late _RecordingBlockRepository blocks;
    late MutationUserBlock mutation;

    setUp(() {
      blocks = _RecordingBlockRepository();
      mutation = MutationUserBlock(userBlockCase: _userBlockCase(blocks));
    });

    test(
      'userBlock uses jwt.sub as blocker and defaults cascadeMode to 0',
      () async {
        final field = mutation.all.singleWhere((f) => f.name == 'userBlock');
        expect(
          await field.resolve!(null, {
            ...auth,
            'objectId': 'U2',
            'blockerId': 'U-ATTACKER',
          }),
          isTrue,
        );
        expect(blocks.lastBlockerId, 'U1');
        expect(blocks.lastBlockedId, 'U2');
        expect(blocks.lastCascadeMode, 0);
      },
    );

    test('userBlock forwards cascadeMode when provided', () async {
      final field = mutation.all.singleWhere((f) => f.name == 'userBlock');
      await field.resolve!(null, {
        ...auth,
        'objectId': 'U2',
        'cascadeMode': 1,
      });
      expect(blocks.lastCascadeMode, 1);
    });

    test('userUnblock uses jwt.sub as blocker', () async {
      final field = mutation.all.singleWhere((f) => f.name == 'userUnblock');
      expect(
        await field.resolve!(null, {
          ...auth,
          'objectId': 'U2',
          'blockerId': 'U-ATTACKER',
        }),
        isTrue,
      );
      expect(blocks.lastBlockerId, 'U1');
      expect(blocks.lastBlockedId, 'U2');
    });

    test('userBlockPromote uses jwt.sub as blocker', () async {
      final field = mutation.all.singleWhere(
        (f) => f.name == 'userBlockPromote',
      );
      expect(
        await field.resolve!(null, {
          ...auth,
          'objectId': 'U2',
          'blockerId': 'U-ATTACKER',
        }),
        isTrue,
      );
      expect(blocks.lastBlockerId, 'U1');
      expect(blocks.lastBlockedId, 'U2');
      expect(blocks.lastMethod, 'promoteToDirect');
    });

    test('mutations require authentication', () {
      final field = mutation.all.first;
      expect(
        () => field.resolve!(null, {'objectId': 'U2'}),
        throwsA(isA<UnauthorizedException>()),
      );
    });
  });

  group('queries scope viewer from JWT only', () {
    test('myBlocks enriches intents with blocked profiles', () async {
      final dataRepo = _MyBlocksRepo();
      final profiles = _FakeProfileLookup({'U2': _profileU2});
      final query = QueryUserBlock(
        blockRepository: dataRepo,
        profileLookup: profiles,
      );

      final field = query.all.singleWhere((f) => f.name == 'myBlocks');
      final result = await field.resolve!(null, {
        ...auth,
        'blockerId': 'U-ATTACKER',
      });

      expect(dataRepo.lastBlockerId, 'U1');
      expect(profiles.lastIds, ['U2']);
      expect(result, [
        {
          'blocked': {
            'id': 'U2',
            'displayName': 'Blocked User',
            'handle': null,
            'description': '',
            'my_vote': null,
            'is_mutual_friend': false,
            'trusts_viewer': false,
            'image': null,
            'scores': <Map<String, dynamic>>[],
            'user_presence': null,
          },
          'cascadeMode': 1,
          'inheritedCount': 3,
          'cascadeCapped': false,
          'cascadePending': true,
        },
      ]);
    });

    test(
      'blockInherited returns UserPublic rows for inherited blocks',
      () async {
        final repo = _InheritedRepo();
        final profiles = _FakeProfileLookup({
          'U3': const UserPublicRecord(
            id: 'U3',
            displayName: 'Inherited',
            description: '',
            userAvailability: null,
          ),
        });
        final query = QueryUserBlock(
          blockRepository: repo,
          profileLookup: profiles,
        );

        final field = query.all.singleWhere((f) => f.name == 'blockInherited');
        final result = await field.resolve!(null, {
          ...auth,
          'originId': 'U2',
          'blockerId': 'U-ATTACKER',
        });

        expect(repo.lastBlockerId, 'U1');
        expect(repo.lastOriginId, 'U2');
        expect((result as List).single['id'], 'U3');
      },
    );

    test('blockPreview maps preview entity and defaults cascadeMode', () async {
      final repo = _PreviewRepo();
      final query = QueryUserBlock(
        blockRepository: repo,
        profileLookup: _FakeProfileLookup({}),
      );

      final field = query.all.singleWhere((f) => f.name == 'blockPreview');
      expect(
        await field.resolve!(null, {
          ...auth,
          'objectId': 'U2',
          'blockerId': 'U-ATTACKER',
        }),
        {
          'cascadeCandidateCount': 5,
          'cascadeCapped': true,
          'openCommitmentCount': 2,
          'willWithdrawEdge': true,
        },
      );
      expect(repo.lastBlockerId, 'U1');
      expect(repo.lastBlockedId, 'U2');
      expect(repo.lastCascadeMode, 0);
    });

    test('queries require authentication', () {
      final query = QueryUserBlock(
        blockRepository: _RecordingBlockRepository(),
        profileLookup: _FakeProfileLookup({}),
      );
      expect(
        () => query.all.first.resolve!(null, {}),
        throwsA(isA<UnauthorizedException>()),
      );
    });
  });
}

final class _MyBlocksRepo extends _RecordingBlockRepository {
  @override
  Future<List<UserBlockIntentEntity>> listIntents(String blockerId) async {
    lastMethod = 'listIntents';
    lastBlockerId = blockerId;
    return [
      UserBlockIntentEntity(
        blockerId: blockerId,
        blockedId: 'U2',
        cascadeMode: 1,
        cascadeStatus: 1,
        materializedCount: 3,
        createdAt: DateTime.utc(2026, 8, 2),
      ),
    ];
  }
}

final class _InheritedRepo extends _RecordingBlockRepository {
  String? lastOriginId;

  @override
  Future<List<UserBlockEntity>> listInherited({
    required String blockerId,
    required String originId,
  }) async {
    lastMethod = 'listInherited';
    lastBlockerId = blockerId;
    lastOriginId = originId;
    return [
      UserBlockEntity(
        blockerId: blockerId,
        blockedId: 'U3',
        originId: originId,
        createdAt: DateTime.utc(2026, 8, 2),
      ),
    ];
  }
}

final class _PreviewRepo extends _RecordingBlockRepository {
  @override
  Future<BlockPreviewEntity> preview({
    required String blockerId,
    required String blockedId,
    required int cascadeMode,
  }) async {
    lastMethod = 'preview';
    lastBlockerId = blockerId;
    lastBlockedId = blockedId;
    lastCascadeMode = cascadeMode;
    return const BlockPreviewEntity(
      cascadeCandidateCount: 5,
      cascadeCapped: true,
      openCommitmentCount: 2,
      willWithdrawEdge: true,
    );
  }
}
