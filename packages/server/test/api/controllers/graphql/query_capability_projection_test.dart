import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_capability_projection.dart';
import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/capability_projection_case.dart';
import 'package:tentura_server/domain/use_case/capability_routing_case.dart';
import 'package:tentura_server/domain/use_case/forward_band_case.dart';
import 'package:tentura_server/env.dart';

import '../../../domain/use_case/capability_projection_case_mocks.mocks.dart';
import '../../../domain/use_case/capability_routing_case_mocks.mocks.dart'
    hide MockRoutingMutePort;
import '../../../domain/use_case/forward_band_case_mocks.mocks.dart';

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
  late MockCapabilityEvidencePort capabilityEvidence;
  late CapabilityProjectionCase projectionCase;
  late ForwardBandCase forwardBandCase;
  late CapabilityRoutingCase routingCase;
  late QueryCapabilityProjection query;

  const actor = 'alice';
  const target = 'carol';
  const beaconId = 'B_fixture';

  CapabilityProjectionCase buildProjectionCase() => CapabilityProjectionCase(
        witnessWindow,
        cellPort,
        ownEvidencePort,
        routingMute,
        pairBlockQuery,
        personVisibility,
        userBlock,
        env: Env(environment: Environment.test),
        logger: Logger('QueryCapabilityProjectionProjectionTest'),
      );

  setUp(() {
    witnessWindow = MockWitnessWindowPort();
    cellPort = MockCapabilityCellPort();
    ownEvidencePort = MockCapabilityOwnEvidencePort();
    routingMute = MockRoutingMutePort();
    pairBlockQuery = MockPairBlockQueryPort();
    personVisibility = MockPersonVisibilityRepositoryPort();
    userBlock = MockUserBlockRepositoryPort();
    bandCandidatePort = MockBandCandidatePort();
    beaconRepositoryPort = MockBeaconRepositoryPort();
    guard = MockBeaconAccessGuard();
    capabilityEvidence = MockCapabilityEvidencePort();
    projectionCase = buildProjectionCase();
    forwardBandCase = ForwardBandCase(
      bandCandidatePort,
      beaconRepositoryPort,
      projectionCase,
      guard,
      env: Env(environment: Environment.test),
      logger: Logger('QueryCapabilityProjectionBandTest'),
    );
    routingCase = CapabilityRoutingCase(
      capabilityEvidence,
      routingMute,
      env: Env(environment: Environment.test),
      logger: Logger('QueryCapabilityProjectionRoutingTest'),
    );
    query = QueryCapabilityProjection(
      capabilityProjectionCase: projectionCase,
      forwardBandCase: forwardBandCase,
      capabilityRoutingCase: routingCase,
    );

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
    when(
      pairBlockQuery.blockedPairsAmong(userIds: anyNamed('userIds')),
    ).thenAnswer((_) async => const {});
    when(
      routingMute.mutedSlugsFor(subjectIds: anyNamed('subjectIds')),
    ).thenAnswer((_) async => const {});
    when(
      witnessWindow.cachedWindow(
        egoId: anyNamed('egoId'),
        normalizedContext: anyNamed('normalizedContext'),
      ),
    ).thenAnswer((_) async => const []);
    when(
      cellPort.fetchCells(
        subjectIds: anyNamed('subjectIds'),
        tagSlugs: anyNamed('tagSlugs'),
        admittedWitnesses: anyNamed('admittedWitnesses'),
      ),
    ).thenAnswer((_) async => const []);
  });

  Future<Object?> resolveSubjectiveTags() async {
    final field = query.all.singleWhere((f) => f.name == 'subjectiveTags');
    return field.resolve!(null, {
      kGlobalInputQueryJwt: const JwtEntity(sub: actor),
      'targetId': target,
    });
  }

  Future<Object?> resolveTagExplanation() async {
    final field = query.all.singleWhere((f) => f.name == 'tagExplanation');
    return field.resolve!(null, {
      kGlobalInputQueryJwt: const JwtEntity(sub: actor),
      'targetId': target,
      'slug': 'transport',
    });
  }

  Future<Object?> resolveForwardContext() async {
    final field = query.all.singleWhere((f) => f.name == 'forwardContext');
    return field.resolve!(null, {
      kGlobalInputQueryJwt: const JwtEntity(sub: actor),
      'beaconId': beaconId,
      'context': '',
    });
  }

  group('subjectiveTags', () {
    test('blocked viewer gets empty list', () async {
      when(
        userBlock.isBlockedPair(a: actor, b: target),
      ).thenAnswer((_) async => true);

      final result = await resolveSubjectiveTags();

      expect(result, isEmpty);
      verifyNever(
        witnessWindow.cachedWindow(
          egoId: anyNamed('egoId'),
          normalizedContext: anyNamed('normalizedContext'),
        ),
      );
    });

    test('visible viewer receives mapped projections without score', () async {
      when(
        userBlock.isBlockedPair(a: anyNamed('a'), b: anyNamed('b')),
      ).thenAnswer((_) async => false);
      when(
        personVisibility.mutuallyVisiblePeerIds(
          viewerId: actor,
          peerIds: [target],
          context: '',
        ),
      ).thenAnswer((_) async => {target});
      when(
        witnessWindow.cachedWindow(egoId: actor, normalizedContext: ''),
      ).thenAnswer((_) async => const []);
      when(
        ownEvidencePort.fetchOwnEvidence(
          egoId: actor,
          subjectIds: [target],
          tagSlugs: anyNamed('tagSlugs'),
        ),
      ).thenAnswer(
        (_) async => const [
          OwnEvidenceRow(
            subjectUserId: target,
            tagSlug: 'transport',
            channel: EvidenceChannel.outcome,
          ),
        ],
      );

      final result = await resolveSubjectiveTags() as List<dynamic>;

      expect(result, hasLength(1));
      expect(result.single, {
        'subjectUserId': target,
        'tagSlug': 'transport',
        'tier': ProjectionTier.ownOutcome.name,
      });
      expect(result.single.keys, containsAll(['subjectUserId', 'tagSlug', 'tier']));
      expect(result.single.keys, isNot(contains('score')));
      expect(result.single.keys, isNot(contains('count')));
      expect(result.single.keys, isNot(contains('witnessUserId')));
    });
  });

  group('tagExplanation', () {
    test('blocked viewer gets null', () async {
      when(
        userBlock.isBlockedPair(a: actor, b: target),
      ).thenAnswer((_) async => true);

      final result = await resolveTagExplanation();

      expect(result, isNull);
    });

    test('returns only the tier string on the happy path', () async {
      when(
        userBlock.isBlockedPair(a: anyNamed('a'), b: anyNamed('b')),
      ).thenAnswer((_) async => false);
      when(
        personVisibility.mutuallyVisiblePeerIds(
          viewerId: actor,
          peerIds: [target],
          context: '',
        ),
      ).thenAnswer((_) async => {target});
      when(
        ownEvidencePort.fetchOwnEvidence(
          egoId: actor,
          subjectIds: [target],
          tagSlugs: ['transport'],
        ),
      ).thenAnswer(
        (_) async => const [
          OwnEvidenceRow(
            subjectUserId: target,
            tagSlug: 'transport',
            channel: EvidenceChannel.seed,
          ),
        ],
      );

      final result = await resolveTagExplanation();

      expect(result, ProjectionTier.ownRouting.name);
    });
  });

  group('forwardContext', () {
    test('rejects viewer who cannot read beacon content', () async {
      when(
        guard.canReadContent(beaconId: beaconId, viewerId: actor),
      ).thenAnswer((_) async => false);

      await expectLater(
        resolveForwardContext(),
        throwsA(
          isA<UnauthorizedException>().having(
            (e) => e.description,
            'description',
            'Viewer cannot read request content',
          ),
        ),
      );
    });
  });
}
