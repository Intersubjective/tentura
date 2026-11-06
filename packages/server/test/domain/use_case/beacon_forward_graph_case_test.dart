import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/entity/forward_tree_edge.dart';
import 'package:tentura_server/domain/entity/help_path_node.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_forward_graph_case.dart';

import '../../support/fake_beacon_access_guard.dart';
import 'forward_case_mocks.mocks.dart';

/// Room participants of the beacon, by user id and room access.
class _FakeRoom extends Fake implements BeaconRoomRepositoryPort {
  Map<String, int> accessByUserId = const {};
  Set<String> stewardIds = const {};
  int listCalls = 0;

  @override
  Future<bool> isBeaconSteward({
    required String beaconId,
    required String userId,
  }) async => stewardIds.contains(userId);

  @override
  Future<List<BeaconParticipantRecord>> listParticipants(
    String beaconId,
  ) async {
    listCalls++;
    final at = DateTime.utc(2025);
    return [
      for (final e in accessByUserId.entries)
        BeaconParticipantRecord(
          id: 'P-${e.key}',
          beaconId: beaconId,
          userId: e.key,
          role: 0,
          status: 0,
          roomAccess: e.value,
          createdAt: at,
          updatedAt: at,
        ),
    ];
  }
}

/// The repository's tree read for [edges]: everyone named, no states.
List<ForwardTreeEdge> _tree(List<ForwardEdgeEntity> edges) => [
  for (final edge in edges)
    ForwardTreeEdge(
      edge: edge,
      sender: HelpPathNode.named(userId: edge.senderId, displayName: ''),
      recipient: HelpPathNode.named(userId: edge.recipientId, displayName: ''),
      recipientDeclined: false,
      recipientOffer: ForwardRecipientOfferStatus.none,
    ),
];

void main() {
  late MockForwardEdgeRepositoryPort forwardEdgeRepo;
  late MockHelpOfferRepositoryPort helpOfferRepo;
  late MockBeaconRepositoryPort beaconRepo;
  late FakeBeaconAccessGuard guard;
  late _FakeRoom room;
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
    room = _FakeRoom();

    case_ = BeaconForwardGraphCase(
      beaconRepo,
      forwardEdgeRepo,
      helpOfferRepo,
      guard,
      room,
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
    when(
      forwardEdgeRepo.fetchForwardTree(
        beaconId: beaconId,
        viewerId: anyNamed('viewerId'),
      ),
    ).thenAnswer(
      (_) async => _tree(allEdges),
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
            'Viewer cannot read request involvement',
          ),
        ),
      );

      verifyNever(beaconRepo.getBeaconById(beaconId: anyNamed('beaconId')));
      verifyNever(
        forwardEdgeRepo.fetchForwardTree(
          beaconId: anyNamed('beaconId'),
          viewerId: anyNamed('viewerId'),
        ),
      );
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

    test('an involved forwarder is given every forward edge of the beacon',
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
          edgeAuthorToBranch.id,
          edgeAuthorDirectToHelpOfferer.id,
        },
      );
    });

    test('a help offerer is given every forward edge of the beacon', () async {
      final res = await case_.asMap(
        beaconId: beaconId,
        currentUserId: helpOffererId,
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
    });

    test('a recipient is given every forward edge when there are no help offers',
        () async {
      when(helpOfferRepo.fetchAllByBeaconId(beaconId)).thenAnswer(
        (_) async => [],
      );

      final res = await case_.asMap(
        beaconId: beaconId,
        currentUserId: branchRecipientId,
      );

      expect(res.edges.map((e) => e.id), allEdges.map((e) => e.id));
      expect(res.helpOffererIds, isEmpty);
    });
  });

  group('help offerer seeding', () {
    test('the author is given every forward edge after an offer is withdrawn',
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
          edgeHopToHelpOfferer.id,
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

  group('Post: how each room member got in (#718)', () {
    const bobId = hopId;
    const eveId = helpOffererId;
    const daveId = viewerStrangerId;
    // Author -> Bob (a forward), Bob -> Eve (Bob's post invite, accepted),
    // Author -> Carol, Bob -> Dave (Dave left the chat).
    final edgeAuthorToCarol = edgeAuthorToBranch;
    final edgeBobToDave = ForwardEdgeEntity(
      id: 'F0000000000000000000000005',
      beaconId: beaconId,
      senderId: bobId,
      recipientId: daveId,
      parentEdgeId: edgeAuthorToHop.id,
      createdAt: now.add(const Duration(seconds: 4)),
    );

    void post() {
      when(
        beaconRepo.getBeaconById(beaconId: anyNamed('beaconId')),
      ).thenAnswer(
        (_) async => BeaconEntity(
          id: beaconId,
          title: 'Test post',
          author: const UserEntity(id: authorId),
          kind: BeaconKind.post,
          createdAt: now,
          updatedAt: now,
        ),
      );
      when(helpOfferRepo.fetchAllByBeaconId(beaconId)).thenAnswer(
        (_) async => [],
      );
      when(
        forwardEdgeRepo.fetchForwardTree(
          beaconId: beaconId,
          viewerId: anyNamed('viewerId'),
        ),
      ).thenAnswer(
        (_) async => _tree([
          edgeAuthorToHop,
          edgeHopToHelpOfferer,
          edgeAuthorToCarol,
          edgeBobToDave,
        ]),
      );
      room.accessByUserId = {
        bobId: RoomAccessBits.admitted,
        eveId: RoomAccessBits.admitted,
        branchRecipientId: RoomAccessBits.admitted,
        daveId: RoomAccessBits.left,
      };
    }

    test(
      'the author sees the edge to a member invited by another member',
      () async {
        post();
        final res = await case_.asMap(
          beaconId: beaconId,
          currentUserId: authorId,
        );
        expect(
          res.edges.map((e) => (e.senderId, e.recipientId)),
          containsAll([
            (authorId, bobId),
            (bobId, eveId),
            (authorId, branchRecipientId),
          ]),
        );
      },
    );

    test('an admitted member is given every forward edge of a Post', () async {
      post();
      final res = await case_.asMap(
        beaconId: beaconId,
        currentUserId: branchRecipientId,
      );
      expect(
        res.edges.map((e) => e.id).toSet(),
        {
          edgeAuthorToHop.id,
          edgeHopToHelpOfferer.id,
          edgeAuthorToCarol.id,
          edgeBobToDave.id,
        },
      );
    });

    test('the edge set keeps edges to people who left the chat', () async {
      post();
      final res = await case_.asMap(
        beaconId: beaconId,
        currentUserId: eveId,
      );
      expect(res.edges.map((e) => e.id).toSet(), {
        edgeAuthorToHop.id,
        edgeHopToHelpOfferer.id,
        edgeAuthorToCarol.id,
        edgeBobToDave.id,
      });
    });

    test(
      'a recipient who left the chat is still given every forward edge',
      () async {
        post();
        final res = await case_.asMap(
          beaconId: beaconId,
          currentUserId: daveId,
        );
        expect(
          res.edges.map((e) => e.id).toSet(),
          {
            edgeAuthorToHop.id,
            edgeHopToHelpOfferer.id,
            edgeAuthorToCarol.id,
            edgeBobToDave.id,
          },
        );
      },
    );

    test(
      'a recipient who never joined the chat is given every forward edge',
      () async {
        post();
        const frankId = 'U0000000000000000000000006';
        final edgeAuthorToFrank = ForwardEdgeEntity(
          id: 'F0000000000000000000000006',
          beaconId: beaconId,
          senderId: authorId,
          recipientId: frankId,
          createdAt: now.add(const Duration(seconds: 5)),
        );
        when(
          forwardEdgeRepo.fetchForwardTree(
            beaconId: beaconId,
            viewerId: anyNamed('viewerId'),
          ),
        ).thenAnswer(
          (_) async => _tree([
            edgeAuthorToHop,
            edgeHopToHelpOfferer,
            edgeAuthorToCarol,
            edgeBobToDave,
            edgeAuthorToFrank,
          ]),
        );
        final res = await case_.asMap(
          beaconId: beaconId,
          currentUserId: frankId,
        );
        expect(res.edges.map((e) => e.id).toSet(), {
          edgeAuthorToHop.id,
          edgeHopToHelpOfferer.id,
          edgeAuthorToCarol.id,
          edgeBobToDave.id,
          edgeAuthorToFrank.id,
        });
      },
    );

    test('a steward outside the chat sees how every member got in', () async {
      post();
      room.stewardIds = {daveId};
      final res = await case_.asMap(
        beaconId: beaconId,
        currentUserId: daveId,
      );
      expect(
        res.edges.map((e) => e.id).toSet(),
        {
          edgeAuthorToHop.id,
          edgeHopToHelpOfferer.id,
          edgeAuthorToCarol.id,
          edgeBobToDave.id,
        },
      );
    });

    test('a Request participant is given every forward edge without reading '
        'room members', () async {
      when(helpOfferRepo.fetchAllByBeaconId(beaconId)).thenAnswer(
        (_) async => [],
      );
      room.accessByUserId = {branchRecipientId: RoomAccessBits.admitted};
      final res = await case_.asMap(
        beaconId: beaconId,
        currentUserId: hopId,
      );
      expect(
        res.edges.map((e) => e.id).toSet(),
        allEdges.map((e) => e.id).toSet(),
      );
      expect(room.listCalls, 0);
    });
  });
}
