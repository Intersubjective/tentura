import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/capability/capability_consts.dart';
import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/capability/fnv1a64.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/use_case/capability_projection_case.dart';
import 'package:tentura_server/domain/use_case/forward_band_case.dart';
import 'package:tentura_server/env.dart';

import 'capability_projection_case_mocks.mocks.dart';
import 'forward_band_case_mocks.mocks.dart';

void main() {
  late MockWitnessWindowPort witnessWindow;
  late MockCapabilityCellPort cellPort;
  late MockCapabilityOwnEvidencePort ownEvidencePort;
  late MockRoutingMutePort routingMute;
  late MockPairBlockQueryPort pairBlockQuery;
  late MockPersonVisibilityRepositoryPort personVisibility;
  late MockUserBlockRepositoryPort userBlock;
  late MockBandCandidatePort bandCandidatePort;
  late MockBeaconRepositoryPort beaconRepositoryPort;
  late MockBeaconAccessGuard guard;
  late CapabilityProjectionCase projectionCase;
  late ForwardBandCase case_;

  List<String>? capturedSubjectIds;

  const egoId = 'alice';
  const beaconId = 'B_band_fixture';
  const witnessId = 'bob';
  const ctx = '';

  final now = DateTime.utc(2026);

  ForwardBandCase buildCase() => ForwardBandCase(
        bandCandidatePort,
        beaconRepositoryPort,
        projectionCase,
        guard,
        env: Env(environment: Environment.test),
        logger: Logger('ForwardBandCaseTest'),
      );

  CapabilityProjectionCase buildProjectionCase() => CapabilityProjectionCase(
        witnessWindow,
        cellPort,
        ownEvidencePort,
        routingMute,
        pairBlockQuery,
        personVisibility,
        userBlock,
        env: Env(environment: Environment.test),
        logger: Logger('ForwardBandCaseProjectionTest'),
      );

  BeaconEntity stubBeacon({
    Set<String> needs = const {'transport', 'tools', 'legal'},
    String? primaryNeedSlug = 'transport',
  }) =>
      BeaconEntity(
        id: beaconId,
        title: 'Fixture beacon',
        author: const UserEntity(id: 'author'),
        createdAt: now,
        updatedAt: now,
        needs: needs,
        primaryNeedSlug: primaryNeedSlug,
      );

  BandCandidate candidate({
    required String userId,
    double forwardMr = 0.5,
    bool canForwardTo = true,
  }) =>
      BandCandidate(
        userId: userId,
        forwardMr: forwardMr,
        canForwardTo: canForwardTo,
        alreadyForwarded: false,
      );

  WitnessCellRow networkCell({
    required String subjectUserId,
    required String tagSlug,
    double eOut = 0,
    double eSeed = 0,
  }) =>
      WitnessCellRow(
        observerUserId: witnessId,
        subjectUserId: subjectUserId,
        tagSlug: tagSlug,
        eOut: eOut,
        eSeed: eSeed,
        m: 1.0,
      );

  OwnEvidenceRow ownEvidence({
    required String subjectUserId,
    required String tagSlug,
    required EvidenceChannel channel,
  }) =>
      OwnEvidenceRow(
        subjectUserId: subjectUserId,
        tagSlug: tagSlug,
        channel: channel,
      );

  void stubBeaconAndCandidates({
    required List<BandCandidate> candidates,
    BeaconEntity? beacon,
    Set<String> recentlyForwarded = const {},
  }) {
    when(
      beaconRepositoryPort.getBeaconById(beaconId: beaconId),
    ).thenAnswer((_) async => beacon ?? stubBeacon());
    when(
      bandCandidatePort.candidatesFor(
        egoId: egoId,
        beaconId: beaconId,
        normalizedContext: ctx,
      ),
    ).thenAnswer((_) async => candidates);
    when(
      bandCandidatePort.recentlyForwardedTo(
        egoId: egoId,
        withinDays: kCapExplorationRecentForwardDays,
      ),
    ).thenAnswer((_) async => recentlyForwarded);
  }

  void stubProjectionInputs({
    List<WitnessCellRow> cells = const [],
    List<OwnEvidenceRow> ownRows = const [],
  }) {
    when(
      witnessWindow.cachedWindow(egoId: egoId, normalizedContext: ctx),
    ).thenAnswer(
      (_) async => [
        const WitnessWeight(witnessUserId: witnessId, m: 1.0, admitted: true),
      ],
    );
    when(
      cellPort.fetchCells(
        subjectIds: anyNamed('subjectIds'),
        tagSlugs: anyNamed('tagSlugs'),
        admittedWitnesses: anyNamed('admittedWitnesses'),
      ),
    ).thenAnswer((invocation) async {
      capturedSubjectIds = List<String>.from(
        invocation.namedArguments[#subjectIds] as List<String>,
      );
      return cells;
    });
    when(
      ownEvidencePort.fetchOwnEvidence(
        egoId: egoId,
        subjectIds: anyNamed('subjectIds'),
        tagSlugs: anyNamed('tagSlugs'),
      ),
    ).thenAnswer((_) async => ownRows);
    when(
      ownEvidencePort.fetchTombstones(
        egoId: egoId,
        subjectIds: anyNamed('subjectIds'),
      ),
    ).thenAnswer((_) async => const []);
    when(
      pairBlockQuery.blockedPairsAmong(userIds: anyNamed('userIds')),
    ).thenAnswer((_) async => const {});
    when(
      routingMute.mutedSlugsFor(subjectIds: anyNamed('subjectIds')),
    ).thenAnswer((_) async => const {});
  }

  setUp(() {
    bandCandidatePort = MockBandCandidatePort();
    beaconRepositoryPort = MockBeaconRepositoryPort();
    witnessWindow = MockWitnessWindowPort();
    cellPort = MockCapabilityCellPort();
    ownEvidencePort = MockCapabilityOwnEvidencePort();
    routingMute = MockRoutingMutePort();
    pairBlockQuery = MockPairBlockQueryPort();
    personVisibility = MockPersonVisibilityRepositoryPort();
    userBlock = MockUserBlockRepositoryPort();
    guard = MockBeaconAccessGuard();
    capturedSubjectIds = null;
    when(
      userBlock.isBlockedPair(a: anyNamed('a'), b: anyNamed('b')),
    ).thenAnswer((_) async => false);
    when(
      personVisibility.mutuallyVisiblePeerIds(
        viewerId: anyNamed('viewerId'),
        peerIds: anyNamed('peerIds'),
        context: anyNamed('context'),
      ),
    ).thenAnswer((invocation) async {
      final peers = invocation.namedArguments[#peerIds] as Iterable<String>;
      return peers.toSet();
    });
    when(
      guard.canReadContent(
        beaconId: anyNamed('beaconId'),
        viewerId: anyNamed('viewerId'),
      ),
    ).thenAnswer((_) async => true);
    projectionCase = buildProjectionCase();
    case_ = buildCase();
  });

  group('deterministic band composition', () {
    test('orders evidence rows and exploration on a fixed fixture', () async {
      stubBeaconAndCandidates(
        candidates: [
          candidate(userId: 'carol', forwardMr: 0.91),
          candidate(userId: 'alex', forwardMr: 0.82),
          candidate(userId: 'dave', forwardMr: 0.71),
          candidate(userId: 'julia', forwardMr: 0.65),
          candidate(userId: 'eve', forwardMr: 0.55),
          candidate(userId: 'frank', forwardMr: 0.44),
          candidate(userId: 'grace', forwardMr: 0.33),
        ],
      );
      stubProjectionInputs(
        ownRows: [
          ownEvidence(
            subjectUserId: 'carol',
            tagSlug: 'transport',
            channel: EvidenceChannel.outcome,
          ),
          ownEvidence(
            subjectUserId: 'dave',
            tagSlug: 'tools',
            channel: EvidenceChannel.seed,
          ),
        ],
        cells: [
          networkCell(
            subjectUserId: 'carol',
            tagSlug: 'tools',
            eSeed: 0.9,
          ),
          networkCell(
            subjectUserId: 'alex',
            tagSlug: 'transport',
            eOut: 0.50,
          ),
          networkCell(
            subjectUserId: 'alex',
            tagSlug: 'tools',
            eOut: 0.40,
          ),
          networkCell(
            subjectUserId: 'julia',
            tagSlug: 'transport',
            eSeed: 0.30,
          ),
        ],
      );

      final band = await case_.composeBand(
        egoId: egoId,
        beaconId: beaconId,
        normalizedContext: ctx,
      );

      final pool = ['eve', 'frank', 'grace'];
      final offset = fnv1a64Mod(beaconId, pool.length);
      final expectedExploration = [
        pool[offset],
        pool[(offset + 1) % pool.length],
      ];

      expect(band, hasLength(5));
      expect(
        band.map((row) => row.userId).toList(),
        ['carol', 'alex', 'dave', ...expectedExploration],
      );
      expect(band.map((row) => row.rank).toList(), [0, 1, 2, 3, 4]);
      expect(band[0].rowTier, ProjectionTier.ownOutcome);
      expect(band[0].labels.map((label) => label.tagSlug).toList(), ['transport']);
      expect(band[1].rowTier, ProjectionTier.networkOutcome);
      expect(
        band[1].labels.map((label) => label.tagSlug).toList(),
        ['transport', 'tools'],
      );
      expect(band[2].rowTier, ProjectionTier.ownRouting);
      expect(band[3].isExploration, isTrue);
      expect(band[4].isExploration, isTrue);
    });
  });

  test('empty exploration pool leaves evidence rows only', () async {
    stubBeaconAndCandidates(
      candidates: [
        candidate(userId: 'carol', forwardMr: 0.9),
        candidate(userId: 'alex', forwardMr: 0.8, canForwardTo: false),
        candidate(userId: 'blocked_explore', forwardMr: 0.7),
      ],
      recentlyForwarded: {'blocked_explore'},
    );
    stubProjectionInputs(
      cells: [
        networkCell(
          subjectUserId: 'carol',
          tagSlug: 'transport',
          eOut: 0.4,
        ),
        networkCell(
          subjectUserId: 'alex',
          tagSlug: 'transport',
          eOut: 0.9,
        ),
      ],
    );

    final band = await case_.composeBand(
      egoId: egoId,
      beaconId: beaconId,
      normalizedContext: ctx,
    );

    expect(band, hasLength(1));
    expect(band.single.userId, 'carol');
    expect(band.where((row) => row.isExploration), isEmpty);
  });

  test('singleton exploration pool yields one exploration row', () async {
    stubBeaconAndCandidates(
      candidates: [
        candidate(userId: 'carol', forwardMr: 0.9),
        candidate(userId: 'solo', forwardMr: 0.5),
      ],
    );
    stubProjectionInputs(
      cells: [
        networkCell(
          subjectUserId: 'carol',
          tagSlug: 'transport',
          eOut: 0.4,
        ),
      ],
    );

    final band = await case_.composeBand(
      egoId: egoId,
      beaconId: beaconId,
      normalizedContext: ctx,
    );

    expect(band, hasLength(2));
    expect(band[1].userId, 'solo');
    expect(band[1].isExploration, isTrue);
    expect(band.where((row) => row.isExploration), hasLength(1));
  });

  test('ownOutcome row labels only same-tier tags, not weaker networkSeed', () async {
    stubBeaconAndCandidates(
      candidates: [candidate(userId: 'carol', forwardMr: 0.9)],
    );
    stubProjectionInputs(
      ownRows: [
        ownEvidence(
          subjectUserId: 'carol',
          tagSlug: 'transport',
          channel: EvidenceChannel.outcome,
        ),
      ],
      cells: [
        networkCell(
          subjectUserId: 'carol',
          tagSlug: 'tools',
          eSeed: 0.99,
        ),
      ],
    );

    final band = await case_.composeBand(
      egoId: egoId,
      beaconId: beaconId,
      normalizedContext: ctx,
    );

    expect(band, hasLength(1));
    expect(band.single.rowTier, ProjectionTier.ownOutcome);
    expect(band.single.labels, hasLength(1));
    expect(band.single.labels.single.tagSlug, 'transport');
  });

  test('no band when no candidate has evidence', () async {
    stubBeaconAndCandidates(
      candidates: [
        candidate(userId: 'carol', forwardMr: 0.9),
        candidate(userId: 'alex', forwardMr: 0.8),
      ],
    );
    stubProjectionInputs();

    final band = await case_.composeBand(
      egoId: egoId,
      beaconId: beaconId,
      normalizedContext: ctx,
    );

    expect(band, isEmpty);
    verifyNever(
      bandCandidatePort.recentlyForwardedTo(
        egoId: anyNamed('egoId'),
        withinDays: anyNamed('withinDays'),
      ),
    );
  });

  test('row tier reduction picks strongest matched tier', () async {
    stubBeaconAndCandidates(
      candidates: [candidate(userId: 'carol', forwardMr: 0.9)],
    );
    stubProjectionInputs(
      ownRows: [
        ownEvidence(
          subjectUserId: 'carol',
          tagSlug: 'tools',
          channel: EvidenceChannel.seed,
        ),
      ],
      cells: [
        networkCell(
          subjectUserId: 'carol',
          tagSlug: 'transport',
          eSeed: 0.9,
        ),
        networkCell(
          subjectUserId: 'carol',
          tagSlug: 'legal',
          eOut: 0.35,
        ),
      ],
    );

    final band = await case_.composeBand(
      egoId: egoId,
      beaconId: beaconId,
      normalizedContext: ctx,
    );

    expect(band.single.rowTier, ProjectionTier.networkOutcome);
    expect(
      band.single.labels.map((label) => label.tagSlug).toList(),
      ['legal'],
    );
  });

  test('canForwardTo=false candidates are excluded from evidence and exploration', () async {
    stubBeaconAndCandidates(
      candidates: [
        candidate(userId: 'carol', forwardMr: 0.9),
        candidate(
          userId: 'blocked',
          forwardMr: 0.99,
          canForwardTo: false,
        ),
        candidate(userId: 'explore', forwardMr: 0.5),
      ],
    );
    stubProjectionInputs(
      ownRows: [
        ownEvidence(
          subjectUserId: 'blocked',
          tagSlug: 'transport',
          channel: EvidenceChannel.outcome,
        ),
      ],
      cells: [
        networkCell(
          subjectUserId: 'carol',
          tagSlug: 'transport',
          eOut: 0.4,
        ),
      ],
    );

    final band = await case_.composeBand(
      egoId: egoId,
      beaconId: beaconId,
      normalizedContext: ctx,
    );

    expect(capturedSubjectIds, ['carol', 'explore']);
    expect(band.map((row) => row.userId), ['carol', 'explore']);
    expect(band.any((row) => row.userId == 'blocked'), isFalse);
  });

  test('exploration picks are deterministic for the same beacon id', () async {
    final explorationCandidates = [
      candidate(userId: 'p0', forwardMr: 0.9),
      candidate(userId: 'p1', forwardMr: 0.8),
      candidate(userId: 'p2', forwardMr: 0.7),
      candidate(userId: 'p3', forwardMr: 0.6),
    ];
    stubBeaconAndCandidates(
      candidates: [
        candidate(userId: 'carol', forwardMr: 0.95),
        ...explorationCandidates,
      ],
    );
    stubProjectionInputs(
      cells: [
        networkCell(
          subjectUserId: 'carol',
          tagSlug: 'transport',
          eOut: 0.4,
        ),
      ],
    );

    final first = await case_.composeBand(
      egoId: egoId,
      beaconId: beaconId,
      normalizedContext: ctx,
    );
    final second = await case_.composeBand(
      egoId: egoId,
      beaconId: beaconId,
      normalizedContext: ctx,
    );

    final pool = ['p0', 'p1', 'p2', 'p3'];
    final offset = fnv1a64Mod(beaconId, pool.length);
    final expectedExploration = [
      pool[offset],
      pool[(offset + 1) % pool.length],
    ];

    expect(
      first.where((row) => row.isExploration).map((row) => row.userId).toList(),
      expectedExploration,
    );
    expect(
      second.where((row) => row.isExploration).map((row) => row.userId).toList(),
      expectedExploration,
    );
  });
}
