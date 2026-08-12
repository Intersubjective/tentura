import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/capability/capability_consts.dart';
import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/use_case/capability_projection_case.dart';

import 'capability_projection_case_mocks.mocks.dart';

void main() {
  late MockWitnessWindowPort witnessWindow;
  late MockCapabilityCellPort cellPort;
  late MockCapabilityOwnEvidencePort ownEvidencePort;
  late MockRoutingMutePort routingMute;
  late MockPairBlockQueryPort pairBlockQuery;
  late CapabilityProjectionCase case_;

  const ego = 'alice';
  const carol = 'carol';
  const ctx = '';

  CapabilityProjectionCase buildCase() => CapabilityProjectionCase(
        witnessWindow,
        cellPort,
        ownEvidencePort,
        routingMute,
        pairBlockQuery,
        env: Env(environment: Environment.test),
        logger: Logger('CapabilityProjectionCaseTest'),
      );

  void stubEmptyOwnAndTombstones() {
    when(
      ownEvidencePort.fetchOwnEvidence(
        egoId: anyNamed('egoId'),
        subjectIds: anyNamed('subjectIds'),
        tagSlugs: anyNamed('tagSlugs'),
      ),
    ).thenAnswer((_) async => const []);
    when(
      ownEvidencePort.fetchTombstones(
        egoId: anyNamed('egoId'),
        subjectIds: anyNamed('subjectIds'),
      ),
    ).thenAnswer((_) async => const []);
  }

  void stubNoBlocksAndMutes() {
    when(
      pairBlockQuery.blockedPairsAmong(userIds: anyNamed('userIds')),
    ).thenAnswer((_) async => const {});
    when(
      routingMute.mutedSlugsFor(subjectIds: anyNamed('subjectIds')),
    ).thenAnswer((_) async => const {});
  }

  setUp(() {
    witnessWindow = MockWitnessWindowPort();
    cellPort = MockCapabilityCellPort();
    ownEvidencePort = MockCapabilityOwnEvidencePort();
    routingMute = MockRoutingMutePort();
    pairBlockQuery = MockPairBlockQueryPort();
    case_ = buildCase();
    stubEmptyOwnAndTombstones();
    stubNoBlocksAndMutes();
  });

  group('§13.1 worked example', () {
    test('Bob-only S_out = 0.321 yields networkOutcome', () async {
      const bob = 'bob';
      when(
        witnessWindow.cachedWindow(egoId: ego, normalizedContext: ctx),
      ).thenAnswer(
        (_) async => [
          const WitnessWeight(witnessUserId: bob, m: 1.0, admitted: true),
        ],
      );
      when(
        cellPort.fetchCells(
          subjectIds: anyNamed('subjectIds'),
          tagSlugs: anyNamed('tagSlugs'),
          admittedWitnesses: anyNamed('admittedWitnesses'),
        ),
      ).thenAnswer(
        (_) async => [
          const WitnessCellRow(
            observerUserId: bob,
            subjectUserId: carol,
            tagSlug: 'transport',
            eOut: 0.321,
            eSeed: 0,
            m: 1.0,
          ),
        ],
      );

      final rows = await case_.project(
        egoId: ego,
        subjectIds: [carol],
        tagSlugs: ['transport'],
        normalizedContext: ctx,
        surface: ProjectionSurface.forwardBand,
      );

      expect(rows, hasLength(1));
      expect(rows.single.tier, ProjectionTier.networkOutcome);
      expect(rows.single.channel, EvidenceChannel.outcome);
      expect(rows.single.score, closeTo(0.321, 1e-9));
    });

    test('Bob + Dave S_out = 0.448 still networkOutcome', () async {
      const bob = 'bob';
      const dave = 'dave';
      when(
        witnessWindow.cachedWindow(egoId: ego, normalizedContext: ctx),
      ).thenAnswer(
        (_) async => [
          const WitnessWeight(witnessUserId: bob, m: 1.0, admitted: true),
          const WitnessWeight(witnessUserId: dave, m: 0.5, admitted: true),
        ],
      );
      when(
        cellPort.fetchCells(
          subjectIds: anyNamed('subjectIds'),
          tagSlugs: anyNamed('tagSlugs'),
          admittedWitnesses: anyNamed('admittedWitnesses'),
        ),
      ).thenAnswer(
        (_) async => [
          const WitnessCellRow(
            observerUserId: bob,
            subjectUserId: carol,
            tagSlug: 'transport',
            eOut: 0.321,
            eSeed: 0,
            m: 1.0,
          ),
          const WitnessCellRow(
            observerUserId: dave,
            subjectUserId: carol,
            tagSlug: 'transport',
            eOut: 0.255,
            eSeed: 0,
            m: 0.5,
          ),
        ],
      );

      final rows = await case_.project(
        egoId: ego,
        subjectIds: [carol],
        tagSlugs: ['transport'],
        normalizedContext: ctx,
        surface: ProjectionSurface.forwardBand,
      );

      expect(rows, hasLength(1));
      expect(rows.single.tier, ProjectionTier.networkOutcome);
      expect(rows.single.score, closeTo(0.448, 0.001));
    });
  });

  test('§13.2 Sybil farm — no admitted witnesses yields no row', () async {
    when(
      witnessWindow.cachedWindow(egoId: ego, normalizedContext: ctx),
    ).thenAnswer(
      (_) async => [
        const WitnessWeight(witnessUserId: 'sybil1', m: 1.0, admitted: false),
        const WitnessWeight(witnessUserId: 'sybil2', m: 1.0, admitted: false),
      ],
    );
    when(
      cellPort.fetchCells(
        subjectIds: anyNamed('subjectIds'),
        tagSlugs: anyNamed('tagSlugs'),
        admittedWitnesses: anyNamed('admittedWitnesses'),
      ),
    ).thenAnswer((_) async => const []);

    final rows = await case_.project(
      egoId: ego,
      subjectIds: [carol],
      tagSlugs: ['transport'],
      normalizedContext: ctx,
      surface: ProjectionSurface.forwardBand,
    );

    expect(rows, isEmpty);
  });

  test('ineligible coalition summing 0.9 contributes nothing (D15)', () async {
    when(
      witnessWindow.cachedWindow(egoId: ego, normalizedContext: ctx),
    ).thenAnswer(
      (_) async => [
        const WitnessWeight(witnessUserId: 'w1', m: 1.0, admitted: false),
        const WitnessWeight(witnessUserId: 'w2', m: 1.0, admitted: false),
      ],
    );
    when(
      cellPort.fetchCells(
        subjectIds: anyNamed('subjectIds'),
        tagSlugs: anyNamed('tagSlugs'),
        admittedWitnesses: anyNamed('admittedWitnesses'),
      ),
    ).thenAnswer((_) async => const []);

    final rows = await case_.project(
      egoId: ego,
      subjectIds: [carol],
      tagSlugs: ['transport'],
      normalizedContext: ctx,
      surface: ProjectionSurface.forwardBand,
    );

    expect(rows, isEmpty);
    verify(
      cellPort.fetchCells(
        subjectIds: [carol],
        tagSlugs: ['transport'],
        admittedWitnesses: const [],
      ),
    ).called(1);
  });

  test(
    'routing mute suppresses both networkOutcome and networkSeed for the '
    'muted pair, leaving an unmuted tag untouched (architecture D4/§5.5/'
    '§12.2/§14: mute anti-joins the row feeding both S_out and S_seed)',
    () async {
      const bob = 'bob';
      when(
        witnessWindow.cachedWindow(egoId: ego, normalizedContext: ctx),
      ).thenAnswer(
        (_) async => [
          const WitnessWeight(witnessUserId: bob, m: 1.0, admitted: true),
        ],
      );
      when(
        cellPort.fetchCells(
          subjectIds: anyNamed('subjectIds'),
          tagSlugs: anyNamed('tagSlugs'),
          admittedWitnesses: anyNamed('admittedWitnesses'),
        ),
      ).thenAnswer(
        (_) async => [
          const WitnessCellRow(
            observerUserId: bob,
            subjectUserId: carol,
            tagSlug: 'transport',
            eOut: 0.35,
            eSeed: 0,
            m: 1.0,
          ),
          // 'pets' would qualify for BOTH networkOutcome (eOut 0.35 >= 0.30)
          // and networkSeed (eSeed 0.30 >= 0.25) if it were not muted.
          const WitnessCellRow(
            observerUserId: bob,
            subjectUserId: carol,
            tagSlug: 'pets',
            eOut: 0.35,
            eSeed: 0.30,
            m: 1.0,
          ),
        ],
      );
      when(
        routingMute.mutedSlugsFor(subjectIds: anyNamed('subjectIds')),
      ).thenAnswer((_) async => {carol: {'pets'}});

      final rows = await case_.project(
        egoId: ego,
        subjectIds: [carol],
        tagSlugs: ['transport', 'pets'],
        normalizedContext: ctx,
        surface: ProjectionSurface.forwardBand,
      );

      expect(rows.map((r) => (r.tagSlug, r.tier)), [
        ('transport', ProjectionTier.networkOutcome),
      ]);
    },
  );

  test('tombstone suppresses network and own evidence for the pair', () async {
    const bob = 'bob';
    when(
      witnessWindow.cachedWindow(egoId: ego, normalizedContext: ctx),
    ).thenAnswer(
      (_) async => [
        const WitnessWeight(witnessUserId: bob, m: 1.0, admitted: true),
      ],
    );
    when(
      cellPort.fetchCells(
        subjectIds: anyNamed('subjectIds'),
        tagSlugs: anyNamed('tagSlugs'),
        admittedWitnesses: anyNamed('admittedWitnesses'),
      ),
    ).thenAnswer(
      (_) async => [
        const WitnessCellRow(
          observerUserId: bob,
          subjectUserId: carol,
          tagSlug: 'transport',
          eOut: 0.35,
          eSeed: 0,
          m: 1.0,
        ),
      ],
    );
    when(
      ownEvidencePort.fetchTombstones(
        egoId: ego,
        subjectIds: anyNamed('subjectIds'),
      ),
    ).thenAnswer(
      (_) async => [
        const TombstoneRef(subjectUserId: carol, tagSlug: 'transport'),
      ],
    );
    when(
      ownEvidencePort.fetchOwnEvidence(
        egoId: ego,
        subjectIds: anyNamed('subjectIds'),
        tagSlugs: anyNamed('tagSlugs'),
      ),
    ).thenAnswer(
      (_) async => [
        const OwnEvidenceRow(
          subjectUserId: carol,
          tagSlug: 'transport',
          channel: EvidenceChannel.outcome,
        ),
      ],
    );

    final rows = await case_.project(
      egoId: ego,
      subjectIds: [carol],
      tagSlugs: ['transport'],
      normalizedContext: ctx,
      surface: ProjectionSurface.forwardBand,
    );

    expect(rows, isEmpty);
  });

  group('profile surface cap and filter', () {
    test('keeps at most 3 outcome tags in priority order', () async {
      const bob = 'bob';
      when(
        witnessWindow.cachedWindow(egoId: ego, normalizedContext: ctx),
      ).thenAnswer(
        (_) async => [
          const WitnessWeight(witnessUserId: bob, m: 1.0, admitted: true),
        ],
      );
      when(
        cellPort.fetchCells(
          subjectIds: anyNamed('subjectIds'),
          tagSlugs: anyNamed('tagSlugs'),
          admittedWitnesses: anyNamed('admittedWitnesses'),
        ),
      ).thenAnswer(
        (_) async => [
          const WitnessCellRow(
            observerUserId: bob,
            subjectUserId: carol,
            tagSlug: 'alpha',
            eOut: 0.50,
            eSeed: 0,
            m: 1.0,
          ),
          const WitnessCellRow(
            observerUserId: bob,
            subjectUserId: carol,
            tagSlug: 'beta',
            eOut: 0.40,
            eSeed: 0,
            m: 1.0,
          ),
          const WitnessCellRow(
            observerUserId: bob,
            subjectUserId: carol,
            tagSlug: 'gamma',
            eOut: 0.35,
            eSeed: 0,
            m: 1.0,
          ),
          const WitnessCellRow(
            observerUserId: bob,
            subjectUserId: carol,
            tagSlug: 'delta',
            eOut: 0.31,
            eSeed: 0,
            m: 1.0,
          ),
          const WitnessCellRow(
            observerUserId: bob,
            subjectUserId: carol,
            tagSlug: 'seed_only',
            eOut: 0,
            eSeed: 0.30,
            m: 1.0,
          ),
        ],
      );
      when(
        ownEvidencePort.fetchOwnEvidence(
          egoId: ego,
          subjectIds: anyNamed('subjectIds'),
          tagSlugs: anyNamed('tagSlugs'),
        ),
      ).thenAnswer(
        (_) async => [
          const OwnEvidenceRow(
            subjectUserId: carol,
            tagSlug: 'own_tag',
            channel: EvidenceChannel.outcome,
          ),
          const OwnEvidenceRow(
            subjectUserId: carol,
            tagSlug: 'routing_tag',
            channel: EvidenceChannel.seed,
          ),
        ],
      );

      final profileRows = await case_.project(
        egoId: ego,
        subjectIds: [carol],
        tagSlugs: [
          'own_tag',
          'routing_tag',
          'alpha',
          'beta',
          'gamma',
          'delta',
          'seed_only',
        ],
        normalizedContext: ctx,
        surface: ProjectionSurface.profile,
      );

      expect(profileRows, hasLength(kCapMaxTagsPerSubjectBeacon));
      expect(
        profileRows.map((r) => r.tagSlug).toList(),
        ['own_tag', 'alpha', 'beta'],
      );
      expect(profileRows.every((r) => r.tier == ProjectionTier.ownOutcome ||
          r.tier == ProjectionTier.networkOutcome), isTrue);

      final bandRows = await case_.project(
        egoId: ego,
        subjectIds: [carol],
        tagSlugs: [
          'own_tag',
          'routing_tag',
          'alpha',
          'beta',
          'gamma',
          'delta',
          'seed_only',
        ],
        normalizedContext: ctx,
        surface: ProjectionSurface.forwardBand,
      );

      expect(
        bandRows.any((r) => r.tier == ProjectionTier.ownRouting),
        isTrue,
      );
      expect(
        bandRows.any((r) => r.tier == ProjectionTier.networkSeed),
        isTrue,
      );
      expect(bandRows.length, greaterThan(profileRows.length));
    });
  });

  test('own outcome evidence overrides network outcome on same tag', () async {
    const bob = 'bob';
    when(
      witnessWindow.cachedWindow(egoId: ego, normalizedContext: ctx),
    ).thenAnswer(
      (_) async => [
        const WitnessWeight(witnessUserId: bob, m: 1.0, admitted: true),
      ],
    );
    when(
      cellPort.fetchCells(
        subjectIds: anyNamed('subjectIds'),
        tagSlugs: anyNamed('tagSlugs'),
        admittedWitnesses: anyNamed('admittedWitnesses'),
      ),
    ).thenAnswer(
      (_) async => [
        const WitnessCellRow(
          observerUserId: bob,
          subjectUserId: carol,
          tagSlug: 'transport',
          eOut: 0.35,
          eSeed: 0,
          m: 1.0,
        ),
      ],
    );
    when(
      ownEvidencePort.fetchOwnEvidence(
        egoId: ego,
        subjectIds: anyNamed('subjectIds'),
        tagSlugs: anyNamed('tagSlugs'),
      ),
    ).thenAnswer(
      (_) async => [
        const OwnEvidenceRow(
          subjectUserId: carol,
          tagSlug: 'transport',
          channel: EvidenceChannel.outcome,
        ),
      ],
    );

    final rows = await case_.project(
      egoId: ego,
      subjectIds: [carol],
      tagSlugs: ['transport'],
      normalizedContext: ctx,
      surface: ProjectionSurface.forwardBand,
    );

    expect(rows, hasLength(1));
    expect(rows.single.tier, ProjectionTier.ownOutcome);
    expect(rows.single.score, kCapOwnEvidenceScore);
  });

  test('ego↔witness block removes witness contribution', () async {
    const bob = 'bob';
    when(
      witnessWindow.cachedWindow(egoId: ego, normalizedContext: ctx),
    ).thenAnswer(
      (_) async => [
        const WitnessWeight(witnessUserId: bob, m: 1.0, admitted: true),
      ],
    );
    when(
      pairBlockQuery.blockedPairsAmong(userIds: anyNamed('userIds')),
    ).thenAnswer((_) async => {(ego, bob)});
    when(
      cellPort.fetchCells(
        subjectIds: anyNamed('subjectIds'),
        tagSlugs: anyNamed('tagSlugs'),
        admittedWitnesses: anyNamed('admittedWitnesses'),
      ),
    ).thenAnswer((_) async => const []);

    final rows = await case_.project(
      egoId: ego,
      subjectIds: [carol],
      tagSlugs: ['transport'],
      normalizedContext: ctx,
      surface: ProjectionSurface.forwardBand,
    );

    expect(rows, isEmpty);
    verify(
      cellPort.fetchCells(
        subjectIds: [carol],
        tagSlugs: ['transport'],
        admittedWitnesses: const [],
      ),
    ).called(1);
  });

  test('witness↔subject block drops cells for that subject only', () async {
    const bob = 'bob';
    const dave = 'dave';
    const other = 'other_subject';
    when(
      witnessWindow.cachedWindow(egoId: ego, normalizedContext: ctx),
    ).thenAnswer(
      (_) async => [
        const WitnessWeight(witnessUserId: bob, m: 1.0, admitted: true),
        const WitnessWeight(witnessUserId: dave, m: 1.0, admitted: true),
      ],
    );
    when(
      pairBlockQuery.blockedPairsAmong(userIds: anyNamed('userIds')),
    ).thenAnswer((_) async => {(bob, carol)});
    when(
      cellPort.fetchCells(
        subjectIds: anyNamed('subjectIds'),
        tagSlugs: anyNamed('tagSlugs'),
        admittedWitnesses: anyNamed('admittedWitnesses'),
      ),
    ).thenAnswer(
      (_) async => [
        const WitnessCellRow(
          observerUserId: bob,
          subjectUserId: carol,
          tagSlug: 'transport',
          eOut: 0.35,
          eSeed: 0,
          m: 1.0,
        ),
        const WitnessCellRow(
          observerUserId: bob,
          subjectUserId: other,
          tagSlug: 'transport',
          eOut: 0.35,
          eSeed: 0,
          m: 1.0,
        ),
        const WitnessCellRow(
          observerUserId: dave,
          subjectUserId: carol,
          tagSlug: 'transport',
          eOut: 0.35,
          eSeed: 0,
          m: 1.0,
        ),
      ],
    );

    final rows = await case_.project(
      egoId: ego,
      subjectIds: [carol, other],
      tagSlugs: ['transport'],
      normalizedContext: ctx,
      surface: ProjectionSurface.forwardBand,
    );

    expect(rows, hasLength(2));
    expect(
      rows.singleWhere((r) => r.subjectUserId == carol).tier,
      ProjectionTier.networkOutcome,
    );
    expect(
      rows.singleWhere((r) => r.subjectUserId == other).tier,
      ProjectionTier.networkOutcome,
    );
    expect(
      rows.singleWhere((r) => r.subjectUserId == carol).score,
      closeTo(0.35, 1e-9),
    );
  });
}
