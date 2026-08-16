import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_capability_projection.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_invite_seed_prompt.dart';
import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/use_case/capability_projection_case.dart';
import 'package:tentura_server/domain/use_case/capability_routing_case.dart';
import 'package:tentura_server/domain/use_case/forward_band_case.dart';
import 'package:tentura_server/domain/use_case/invite_seed_attestation_case.dart';
import 'package:tentura_server/env.dart';

import '../../../domain/use_case/capability_projection_case_mocks.mocks.dart';
import '../../../domain/use_case/capability_routing_case_mocks.mocks.dart'
    hide MockRoutingMutePort;
import '../../../domain/use_case/forward_band_case_mocks.mocks.dart';
import 'invite_seed_resolver_mocks.mocks.dart';
import 'invite_seed_resolver_test_helper.dart';

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
  late QueryCapabilityProjection projectionQuery;
  late MockInviteSeedPromptPort promptPort;
  late MockInviteGenealogyRepositoryPort genealogyPort;
  late MockUserBlockRepositoryPort blockPort;
  late MockMutatingUnitOfWorkPort unitOfWork;
  late InviteSeedAttestationCase inviteSeedCase;
  late QueryInviteSeedPrompt inviteSeedQuery;

  const actor = 'alice';
  const subject = 'carol';

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
    projectionCase = CapabilityProjectionCase(
      witnessWindow,
      cellPort,
      ownEvidencePort,
      routingMute,
      pairBlockQuery,
      personVisibility,
      userBlock,
      env: Env(environment: Environment.test),
      logger: Logger('E1bQueryProjectionTest'),
    );
    forwardBandCase = ForwardBandCase(
      bandCandidatePort,
      beaconRepositoryPort,
      projectionCase,
      guard,
      env: Env(environment: Environment.test),
      logger: Logger('E1bQueryBandTest'),
    );
    routingCase = CapabilityRoutingCase(
      capabilityEvidence,
      routingMute,
      env: Env(environment: Environment.test),
      logger: Logger('E1bQueryRoutingTest'),
    );
    projectionQuery = QueryCapabilityProjection(
      capabilityProjectionCase: projectionCase,
      forwardBandCase: forwardBandCase,
      capabilityRoutingCase: routingCase,
    );
    promptPort = MockInviteSeedPromptPort();
    genealogyPort = MockInviteGenealogyRepositoryPort();
    blockPort = MockUserBlockRepositoryPort();
    unitOfWork = MockMutatingUnitOfWorkPort();
    inviteSeedCase = buildInviteSeedCase(
      promptPort: promptPort,
      genealogyPort: genealogyPort,
      evidencePort: capabilityEvidence,
      blockPort: blockPort,
      unitOfWork: unitOfWork,
    );
    inviteSeedQuery = QueryInviteSeedPrompt(
      inviteSeedAttestationCase: inviteSeedCase,
    );
    stubAuthorizedInviter(
      genealogyPort: genealogyPort,
      promptPort: promptPort,
      blockPort: blockPort,
      actor: actor,
      subject: subject,
      evidencePort: capabilityEvidence,
    );
  });

  group('myRoutingTags', () {
    test('passes jwt.sub as actorId to the use case', () async {
      when(routingMute.mutedSlugsForUser(actor)).thenAnswer(
        (_) async => {'transport', 'pets'},
      );
      final field =
          projectionQuery.all.singleWhere((f) => f.name == 'myRoutingTags');

      final result = await field.resolve!(null, {
        kGlobalInputQueryJwt: const JwtEntity(sub: actor),
      });

      expect(result, unorderedEquals(['transport', 'pets']));
      verify(routingMute.mutedSlugsForUser(actor)).called(1);
      verifyNever(routingMute.mutedSlugsForUser(subject));
    });
  });

  group('inviteSeedPromptState', () {
    test('passes jwt.sub as actorId to promptStateFor', () async {
      final field =
          inviteSeedQuery.all.singleWhere((f) => f.name == 'inviteSeedPromptState');

      final result = await field.resolve!(null, {
        kGlobalInputQueryJwt: const JwtEntity(sub: actor),
        'subjectId': subject,
      });

      verify(
        promptPort.stateFor(inviterId: actor, inviteeId: subject),
      ).called(1);
      verify(
        capabilityEvidence.activeSeedSlugs(
          observerId: actor,
          subjectId: subject,
        ),
      ).called(1);
      expect(result, {
        'inviterUserId': actor,
        'inviteeUserId': subject,
        'state': PromptStateValue.pending.name,
        'slugs': <String>[],
      });
    });

    test('includes sorted taxonomy slugs from the ledger', () async {
      stubAuthorizedInviter(
        genealogyPort: genealogyPort,
        promptPort: promptPort,
        blockPort: blockPort,
        actor: actor,
        subject: subject,
        evidencePort: capabilityEvidence,
        seedSlugs: {'pets', 'transport'},
      );
      final field =
          inviteSeedQuery.all.singleWhere((f) => f.name == 'inviteSeedPromptState');

      final result = await field.resolve!(null, {
        kGlobalInputQueryJwt: const JwtEntity(sub: actor),
        'subjectId': subject,
      });

      expect(result, {
        'inviterUserId': actor,
        'inviteeUserId': subject,
        'state': PromptStateValue.pending.name,
        'slugs': ['transport', 'pets'],
      });
    });
  });
}
