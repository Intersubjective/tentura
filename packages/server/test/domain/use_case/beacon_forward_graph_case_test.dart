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
import 'package:tentura_server/domain/use_case/beacon_forward_graph_case.dart';

import '../../support/fake_beacon_access_guard.dart';
import 'forward_case_mocks.mocks.dart';

void main() {
  late MockForwardEdgeRepositoryPort forwardEdgeRepo;
  late MockHelpOfferRepositoryPort helpOfferRepo;
  late MockBeaconRepositoryPort beaconRepo;
  late FakeBeaconAccessGuard guard;
  late BeaconForwardGraphCase case_;

  const beaconId = 'B0000000000000000000000001';
  const authorId = 'U0000000000000000000000001';
  const helpOffererId = 'U0000000000000000000000002';
  const hopId = 'U0000000000000000000000003';
  const branchRecipientId = 'U0000000000000000000000004';
  const viewerStrangerId = 'U0000000000000000000000005';

  final now = DateTime.utc(2025);

  // Author -> hop -> help offerer (chain).
  final edgeAuthorToHop = ForwardEdgeEntity(
    id: 'F0000000000000000000000001',
    beaconId: beaconId,
    senderId: authorId,
    recipientId: hopId,
    createdAt: now,
  );
  final edgeHopToHelpOfferer = ForwardEdgeEntity(
    id: 'F0000000000000000000000002',
    beaconId: beaconId,
    senderId: hopId,
    recipientId: helpOffererId,
    parentEdgeId: edgeAuthorToHop.id,
    createdAt: now.add(const Duration(seconds: 1)),
  );
  // Unrelated branch from author.
  final edgeAuthorToBranch = ForwardEdgeEntity(
    id: 'F0000000000000000000000003',
    beaconId: beaconId,
    senderId: authorId,
    recipientId: branchRecipientId,
    createdAt: now.add(const Duration(seconds: 2)),
  );
  // Direct author -> help offerer.
  final edgeAuthorDirectToHelpOfferer = ForwardEdgeEntity(
    id: 'F0000000000000000000000004',
    beaconId: beaconId,
    senderId: authorId,
    recipientId: helpOffererId,
    createdAt: now.add(const Duration(seconds: 3)),
  );

  final allEdges = <ForwardEdgeEntity>[
    edgeAuthorToHop,
    edgeHopToHelpOfferer,
    edgeAuthorToBranch,
    edgeAuthorDirectToHelpOfferer,
  ];

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

    case_ = BeaconForwardGraphCase(
      beaconRepo,
      forwardEdgeRepo,
      helpOfferRepo,
      guard,
      env: Env(environment: Environment.test),
      logger: Logger('BeaconForwardGraphCaseTest'),
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
  });

  group('authorization', () {
    test('unauthorized viewer throws UnauthorizedException', () async {
      guard.involvementAllowed = false;

      await expectLater(
        case_.asMap(
          beaconId: beaconId,
          currentUserId: viewerStrangerId,
        ),
        throwsA(
          isA<UnauthorizedException>().having(
            (e) => e.description,
            'description',
            'Viewer cannot read beacon involvement',
          ),
        ),
      );

      verifyNever(beaconRepo.getBeaconById(beaconId: anyNamed('beaconId')));
      verifyNever(forwardEdgeRepo.fetchByBeaconId(any));
      verifyNever(helpOfferRepo.fetchAllByBeaconId(any));
    });
  });

  group('edge filtering by viewer role', () {
    test('author sees all edges including help-offerer seeds and parent chains',
        () async {
      final res = await case_.asMap(
        beaconId: beaconId,
        currentUserId: authorId,
      );

      expect(
        res.edges.map((e) => e.id).toSet(),
        {
          edgeAuthorToHop.id,
          edgeHopToHelpOfferer.id,
          edgeAuthorToBranch.id,
          edgeAuthorDirectToHelpOfferer.id,
        },
      );
      expect(res.authorId, authorId);
      expect(res.beaconId, beaconId);
      expect(res.helpOffererIds, [helpOffererId]);
    });

    test('involved hop viewer sees their edges, help-offerer seeds, and ancestors',
        () async {
      final res = await case_.asMap(
        beaconId: beaconId,
        currentUserId: hopId,
      );

      expect(
        res.edges.map((e) => e.id).toSet(),
        {
          edgeAuthorToHop.id,
          edgeHopToHelpOfferer.id,
          edgeAuthorDirectToHelpOfferer.id,
        },
      );
    });

    test('help offerer sees their inbound edges and ancestor chain', () async {
      final res = await case_.asMap(
        beaconId: beaconId,
        currentUserId: helpOffererId,
      );

      expect(
        res.edges.map((e) => e.id).toSet(),
        {
          edgeAuthorToHop.id,
          edgeHopToHelpOfferer.id,
          edgeAuthorDirectToHelpOfferer.id,
        },
      );
    });

    test('viewer on unrelated branch sees only their edge when no help offerers',
        () async {
      when(helpOfferRepo.fetchAllByBeaconId(beaconId)).thenAnswer(
        (_) async => [],
      );

      final res = await case_.asMap(
        beaconId: beaconId,
        currentUserId: branchRecipientId,
      );

      expect(res.edges.map((e) => e.id).toList(), [edgeAuthorToBranch.id]);
      expect(res.helpOffererIds, isEmpty);
    });
  });

  group('help offerer seeding', () {
    test('withdrawn help offerer edges are not auto-seeded for author',
        () async {
      when(helpOfferRepo.fetchAllByBeaconId(beaconId)).thenAnswer(
        (_) async => [activeHelpOffer.copyWith(status: 1)],
      );

      final res = await case_.asMap(
        beaconId: beaconId,
        currentUserId: authorId,
      );

      expect(
        res.edges.map((e) => e.id).toSet(),
        {
          edgeAuthorToHop.id,
          edgeAuthorToBranch.id,
          edgeAuthorDirectToHelpOfferer.id,
        },
      );
      expect(res.helpOffererIds, isEmpty);
    });
  });

  group('edge mapping and ordering', () {
    test('edges are sorted by createdAt ascending', () async {
      final res = await case_.asMap(
        beaconId: beaconId,
        currentUserId: authorId,
      );

      final ids = res.edges.map((e) => e.id).toList();
      expect(ids, [
        edgeAuthorToHop.id,
        edgeHopToHelpOfferer.id,
        edgeAuthorToBranch.id,
        edgeAuthorDirectToHelpOfferer.id,
      ]);
    });

    test('parentEdgeId is preserved in mapped results', () async {
      final res = await case_.asMap(
        beaconId: beaconId,
        currentUserId: hopId,
      );

      final byId = {for (final e in res.edges) e.id: e};
      expect(byId[edgeHopToHelpOfferer.id]!.parentEdgeId, edgeAuthorToHop.id);
      expect(byId[edgeAuthorToHop.id]!.parentEdgeId, isNull);
    });
  });
}
