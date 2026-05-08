import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/commitment_entity.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/beacon_committer_forward_path_case.dart';

import 'forward_case_mocks.mocks.dart';

void main() {
  late MockForwardEdgeRepositoryPort forwardEdgeRepo;
  late MockCommitmentRepositoryPort commitmentRepo;
  late MockBeaconRepositoryPort beaconRepo;
  late BeaconCommitterForwardPathCase case_;

  const beaconId = 'B0000000000000000000000001';
  const authorId = 'U0000000000000000000000001';
  const committerId = 'U0000000000000000000000002';
  const viewerInvolvedId = 'U0000000000000000000000003';
  const viewerStrangerId = 'U0000000000000000000000004';

  final now = DateTime.utc(2025);

  // Two ancestor edges feeding committerId (multi-route shape).
  final edgeAuthorToHop = ForwardEdgeEntity(
    id: 'F0000000000000000000000001',
    beaconId: beaconId,
    senderId: authorId,
    recipientId: viewerInvolvedId,
    createdAt: now,
  );
  final edgeHopToCommitter = ForwardEdgeEntity(
    id: 'F0000000000000000000000002',
    beaconId: beaconId,
    senderId: viewerInvolvedId,
    recipientId: committerId,
    parentEdgeId: edgeAuthorToHop.id,
    createdAt: now.add(const Duration(seconds: 1)),
  );
  final edgeAuthorDirectToCommitter = ForwardEdgeEntity(
    id: 'F0000000000000000000000003',
    beaconId: beaconId,
    senderId: authorId,
    recipientId: committerId,
    createdAt: now.add(const Duration(seconds: 2)),
  );

  // Full beacon edge set used by the auth gate.
  final allEdges = <ForwardEdgeEntity>[
    edgeAuthorToHop,
    edgeHopToCommitter,
    edgeAuthorDirectToCommitter,
  ];

  // Active commitment for the focused committer.
  final activeCommitment = CommitmentEntity(
    beaconId: beaconId,
    userId: committerId,
    createdAt: now,
    updatedAt: now,
  );

  setUp(() {
    forwardEdgeRepo = MockForwardEdgeRepositoryPort();
    commitmentRepo = MockCommitmentRepositoryPort();
    beaconRepo = MockBeaconRepositoryPort();

    case_ = BeaconCommitterForwardPathCase(
      beaconRepo,
      forwardEdgeRepo,
      commitmentRepo,
      env: Env(environment: Environment.test),
      logger: Logger('BeaconCommitterForwardPathCaseTest'),
    );

    when(beaconRepo.getBeaconById(beaconId: anyNamed('beaconId'))).thenAnswer(
      (_) async => BeaconEntity(
        id: beaconId,
        title: 'Test beacon',
        author: const UserEntity(id: authorId),
        createdAt: now,
        updatedAt: now,
      ),
    );
    when(commitmentRepo.fetchAllByBeaconId(beaconId)).thenAnswer(
      (_) async => [activeCommitment],
    );
    when(forwardEdgeRepo.fetchByBeaconId(beaconId)).thenAnswer(
      (_) async => allEdges,
    );
    when(
      forwardEdgeRepo.fetchCommitterPathChain(
        beaconId: anyNamed('beaconId'),
        committerId: anyNamed('committerId'),
        viewerId: anyNamed('viewerId'),
      ),
    ).thenAnswer(
      (_) async => [
        edgeAuthorToHop,
        edgeHopToCommitter,
        edgeAuthorDirectToCommitter,
      ],
    );
  });

  group('viewer roles', () {
    test('case 1 (viewer = author): viewerId == authorId in result', () async {
      final res = await case_.asMap(
        beaconId: beaconId,
        committerId: committerId,
        currentUserId: authorId,
      );
      expect(res['viewerId'], authorId);
      expect(res['authorId'], authorId);
      expect(res['beaconId'], beaconId);
      expect(res['committerIds'], [committerId]);
      verify(
        forwardEdgeRepo.fetchCommitterPathChain(
          beaconId: beaconId,
          committerId: committerId,
          viewerId: authorId,
        ),
      ).called(1);
    });

    test(
      'case 2 (viewer = involved-other): viewerId is the involved user',
      () async {
        final res = await case_.asMap(
          beaconId: beaconId,
          committerId: committerId,
          currentUserId: viewerInvolvedId,
        );
        expect(res['viewerId'], viewerInvolvedId);
        expect(res['committerIds'], [committerId]);
        verify(
          forwardEdgeRepo.fetchCommitterPathChain(
            beaconId: beaconId,
            committerId: committerId,
            viewerId: viewerInvolvedId,
          ),
        ).called(1);
      },
    );

    test(
      'case 3 (viewer = committer): viewerId == committerId',
      () async {
        final res = await case_.asMap(
          beaconId: beaconId,
          committerId: committerId,
          currentUserId: committerId,
        );
        expect(res['viewerId'], committerId);
        expect(res['committerIds'], [committerId]);
        verify(
          forwardEdgeRepo.fetchCommitterPathChain(
            beaconId: beaconId,
            committerId: committerId,
            viewerId: committerId,
          ),
        ).called(1);
      },
    );
  });

  group('edge mapping', () {
    test('every chain edge is forwarded to the result map', () async {
      final res = await case_.asMap(
        beaconId: beaconId,
        committerId: committerId,
        currentUserId: authorId,
      );
      final edges = res['edges']! as List<Map<String, dynamic>>;
      expect(edges.length, 3);
      expect(
        edges.map((e) => e['id']).toSet(),
        {
          edgeAuthorToHop.id,
          edgeHopToCommitter.id,
          edgeAuthorDirectToCommitter.id,
        },
      );
      // Ancestor relationship preserved (multi-route: F2 -> F1, F3 root).
      final byId = {
        for (final e in edges) e['id'] as String: e,
      };
      expect(byId[edgeHopToCommitter.id]!['parentEdgeId'], edgeAuthorToHop.id);
      expect(byId[edgeAuthorDirectToCommitter.id]!['parentEdgeId'], isNull);
    });
  });

  group('authorization', () {
    test('non-involved viewer with no edges throws Unauthorized', () async {
      await expectLater(
        case_.asMap(
          beaconId: beaconId,
          committerId: committerId,
          currentUserId: viewerStrangerId,
        ),
        throwsA(isA<UnauthorizedException>()),
      );
      verifyNever(
        forwardEdgeRepo.fetchCommitterPathChain(
          beaconId: anyNamed('beaconId'),
          committerId: anyNamed('committerId'),
          viewerId: anyNamed('viewerId'),
        ),
      );
    });

    test(
      'viewer with active commitment on the beacon (not the focused '
      'committer) is allowed',
      () async {
        const otherCommitterId = 'U0000000000000000000000005';
        when(commitmentRepo.fetchAllByBeaconId(beaconId)).thenAnswer(
          (_) async => [
            activeCommitment,
            CommitmentEntity(
              beaconId: beaconId,
              userId: otherCommitterId,
              createdAt: now,
              updatedAt: now,
            ),
          ],
        );
        final res = await case_.asMap(
          beaconId: beaconId,
          committerId: committerId,
          currentUserId: otherCommitterId,
        );
        expect(res['viewerId'], otherCommitterId);
      },
    );
  });

  group('committer validation', () {
    test('non-active committer throws IdNotFoundException', () async {
      const inactiveCommitter = 'U0000000000000000000000009';
      await expectLater(
        case_.asMap(
          beaconId: beaconId,
          committerId: inactiveCommitter,
          currentUserId: authorId,
        ),
        throwsA(isA<IdNotFoundException>()),
      );
      verifyNever(
        forwardEdgeRepo.fetchCommitterPathChain(
          beaconId: anyNamed('beaconId'),
          committerId: anyNamed('committerId'),
          viewerId: anyNamed('viewerId'),
        ),
      );
    });

    test('withdrawn committer is not active → IdNotFoundException', () async {
      when(commitmentRepo.fetchAllByBeaconId(beaconId)).thenAnswer(
        (_) async => [
          activeCommitment.copyWith(status: 1),
        ],
      );
      await expectLater(
        case_.asMap(
          beaconId: beaconId,
          committerId: committerId,
          currentUserId: authorId,
        ),
        throwsA(isA<IdNotFoundException>()),
      );
    });
  });
}
