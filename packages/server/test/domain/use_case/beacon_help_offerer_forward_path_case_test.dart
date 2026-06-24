import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/beacon_help_offerer_forward_path_case.dart';

import '../../support/fake_beacon_access_guard.dart';
import 'forward_case_mocks.mocks.dart';

void main() {
  late MockForwardEdgeRepositoryPort forwardEdgeRepo;
  late MockHelpOfferRepositoryPort helpOfferRepo;
  late MockBeaconRepositoryPort beaconRepo;
  late FakeBeaconAccessGuard guard;
  late BeaconHelpOffererForwardPathCase case_;

  const beaconId = 'B0000000000000000000000001';
  const authorId = 'U0000000000000000000000001';
  const helpOffererId = 'U0000000000000000000000002';
  const viewerInvolvedId = 'U0000000000000000000000003';
  const viewerStrangerId = 'U0000000000000000000000004';

  final now = DateTime.utc(2025);

  // Two ancestor edges feeding helpOffererId (multi-route shape).
  final edgeAuthorToHop = ForwardEdgeEntity(
    id: 'F0000000000000000000000001',
    beaconId: beaconId,
    senderId: authorId,
    recipientId: viewerInvolvedId,
    createdAt: now,
  );
  final edgeHopToHelpOfferer = ForwardEdgeEntity(
    id: 'F0000000000000000000000002',
    beaconId: beaconId,
    senderId: viewerInvolvedId,
    recipientId: helpOffererId,
    parentEdgeId: edgeAuthorToHop.id,
    createdAt: now.add(const Duration(seconds: 1)),
  );
  final edgeAuthorDirectToHelpOfferer = ForwardEdgeEntity(
    id: 'F0000000000000000000000003',
    beaconId: beaconId,
    senderId: authorId,
    recipientId: helpOffererId,
    createdAt: now.add(const Duration(seconds: 2)),
  );

  // Full beacon edge set used by the auth gate.
  final allEdges = <ForwardEdgeEntity>[
    edgeAuthorToHop,
    edgeHopToHelpOfferer,
    edgeAuthorDirectToHelpOfferer,
  ];

  // Active help offer for the focused help offerer.
  final activeHelpOffer = HelpOfferEntity(
    beaconId: beaconId,
    userId: helpOffererId,
    createdAt: now,
    updatedAt: now,
  );

  setUp(() {
    forwardEdgeRepo = MockForwardEdgeRepositoryPort();
    helpOfferRepo = MockHelpOfferRepositoryPort();
    beaconRepo = MockBeaconRepositoryPort();
    guard = FakeBeaconAccessGuard();

    case_ = BeaconHelpOffererForwardPathCase(
      beaconRepo,
      forwardEdgeRepo,
      helpOfferRepo,
      guard,
      env: Env(environment: Environment.test),
      logger: Logger('BeaconHelpOffererForwardPathCaseTest'),
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
    when(helpOfferRepo.fetchAllByBeaconId(beaconId)).thenAnswer(
      (_) async => [activeHelpOffer],
    );
    when(forwardEdgeRepo.fetchByBeaconId(beaconId)).thenAnswer(
      (_) async => allEdges,
    );
    when(
      forwardEdgeRepo.fetchHelpOffererPathChain(
        beaconId: anyNamed('beaconId'),
        helpOffererId: anyNamed('helpOffererId'),
        viewerId: anyNamed('viewerId'),
      ),
    ).thenAnswer(
      (_) async => [
        edgeAuthorToHop,
        edgeHopToHelpOfferer,
        edgeAuthorDirectToHelpOfferer,
      ],
    );
  });

  group('viewer roles', () {
    test('case 1 (viewer = author): viewerId == authorId in result', () async {
      final res = await case_.asMap(
        beaconId: beaconId,
        helpOffererId: helpOffererId,
        currentUserId: authorId,
      );
      expect(res.viewerId, authorId);
      expect(res.authorId, authorId);
      expect(res.beaconId, beaconId);
      expect(res.helpOffererIds, [helpOffererId]);
      verify(
        forwardEdgeRepo.fetchHelpOffererPathChain(
          beaconId: beaconId,
          helpOffererId: helpOffererId,
          viewerId: authorId,
        ),
      ).called(1);
    });

    test(
      'case 2 (viewer = involved-other): viewerId is the involved user',
      () async {
        final res = await case_.asMap(
          beaconId: beaconId,
          helpOffererId: helpOffererId,
          currentUserId: viewerInvolvedId,
        );
        expect(res.viewerId, viewerInvolvedId);
        expect(res.helpOffererIds, [helpOffererId]);
        verify(
          forwardEdgeRepo.fetchHelpOffererPathChain(
            beaconId: beaconId,
            helpOffererId: helpOffererId,
            viewerId: viewerInvolvedId,
          ),
        ).called(1);
      },
    );

    test(
      'case 3 (viewer = help offerer): viewerId == helpOffererId',
      () async {
        final res = await case_.asMap(
          beaconId: beaconId,
          helpOffererId: helpOffererId,
          currentUserId: helpOffererId,
        );
        expect(res.viewerId, helpOffererId);
        expect(res.helpOffererIds, [helpOffererId]);
        verify(
          forwardEdgeRepo.fetchHelpOffererPathChain(
            beaconId: beaconId,
            helpOffererId: helpOffererId,
            viewerId: helpOffererId,
          ),
        ).called(1);
      },
    );
  });

  group('edge mapping', () {
    test('every chain edge is forwarded to the result map', () async {
      final res = await case_.asMap(
        beaconId: beaconId,
        helpOffererId: helpOffererId,
        currentUserId: authorId,
      );
      final edges = res.edges;
      expect(edges.length, 3);
      expect(
        edges.map((e) => e.id).toSet(),
        {
          edgeAuthorToHop.id,
          edgeHopToHelpOfferer.id,
          edgeAuthorDirectToHelpOfferer.id,
        },
      );
      // Ancestor relationship preserved (multi-route: F2 -> F1, F3 root).
      final byId = {
        for (final e in edges) e.id: e,
      };
      expect(byId[edgeHopToHelpOfferer.id]!.parentEdgeId, edgeAuthorToHop.id);
      expect(byId[edgeAuthorDirectToHelpOfferer.id]!.parentEdgeId, isNull);
    });
  });

  group('authorization', () {
    test('non-involved viewer with no edges throws Unauthorized', () async {
      guard.involvementAllowed = false;
      await expectLater(
        case_.asMap(
          beaconId: beaconId,
          helpOffererId: helpOffererId,
          currentUserId: viewerStrangerId,
        ),
        throwsA(isA<UnauthorizedException>()),
      );
      verifyNever(
        forwardEdgeRepo.fetchHelpOffererPathChain(
          beaconId: anyNamed('beaconId'),
          helpOffererId: anyNamed('helpOffererId'),
          viewerId: anyNamed('viewerId'),
        ),
      );
    });

    test(
      'viewer with active help offer on the beacon (not the focused '
      'help offerer) is allowed',
      () async {
        const otherHelpOffererId = 'U0000000000000000000000005';
        when(helpOfferRepo.fetchAllByBeaconId(beaconId)).thenAnswer(
          (_) async => [
            activeHelpOffer,
            HelpOfferEntity(
              beaconId: beaconId,
              userId: otherHelpOffererId,
              createdAt: now,
              updatedAt: now,
            ),
          ],
        );
        final res = await case_.asMap(
          beaconId: beaconId,
          helpOffererId: helpOffererId,
          currentUserId: otherHelpOffererId,
        );
        expect(res.viewerId, otherHelpOffererId);
      },
    );
  });

  group('help offerer validation', () {
    test('non-active help offerer throws IdNotFoundException', () async {
      const inactiveHelpOfferer = 'U0000000000000000000000009';
      await expectLater(
        case_.asMap(
          beaconId: beaconId,
          helpOffererId: inactiveHelpOfferer,
          currentUserId: authorId,
        ),
        throwsA(isA<IdNotFoundException>()),
      );
      verifyNever(
        forwardEdgeRepo.fetchHelpOffererPathChain(
          beaconId: anyNamed('beaconId'),
          helpOffererId: anyNamed('helpOffererId'),
          viewerId: anyNamed('viewerId'),
        ),
      );
    });

    test('withdrawn help offerer is not active → IdNotFoundException', () async {
      when(helpOfferRepo.fetchAllByBeaconId(beaconId)).thenAnswer(
        (_) async => [
          activeHelpOffer.copyWith(status: 1),
        ],
      );
      await expectLater(
        case_.asMap(
          beaconId: beaconId,
          helpOffererId: helpOffererId,
          currentUserId: authorId,
        ),
        throwsA(isA<IdNotFoundException>()),
      );
    });
  });
}
