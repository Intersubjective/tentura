import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_capability_routing.dart';
import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/capability_routing_case.dart';
import 'package:tentura_server/domain/use_case/invite_seed_attestation_case.dart';
import 'package:tentura_server/env.dart';

import '../../../domain/use_case/capability_projection_case_mocks.mocks.dart'
    show MockUserBlockRepositoryPort;
import '../../../domain/use_case/capability_routing_case_mocks.mocks.dart';
import 'invite_seed_resolver_mocks.mocks.dart';
import 'invite_seed_resolver_test_helper.dart';

void main() {
  late MockCapabilityEvidencePort capabilityEvidence;
  late MockRoutingMutePort routingMute;
  late CapabilityRoutingCase routingCase;
  late MockInviteSeedPromptPort promptPort;
  late MockInviteGenealogyRepositoryPort genealogyPort;
  late MockUserBlockRepositoryPort blockPort;
  late MockMutatingUnitOfWorkPort unitOfWork;
  late InviteSeedAttestationCase inviteSeedCase;
  late MutationCapabilityRouting mutation;

  const actor = 'alice';
  const subject = 'carol';
  const beaconId = 'B_fixture';
  const slug = 'transport';

  setUp(() {
    capabilityEvidence = MockCapabilityEvidencePort();
    routingMute = MockRoutingMutePort();
    routingCase = CapabilityRoutingCase(
      capabilityEvidence,
      routingMute,
      env: Env(environment: Environment.test),
      logger: Logger('MutationCapabilityRoutingTest'),
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
    mutation = MutationCapabilityRouting(
      capabilityRoutingCase: routingCase,
      inviteSeedAttestationCase: inviteSeedCase,
    );
    stubAuthorizedInviter(
      genealogyPort: genealogyPort,
      promptPort: promptPort,
      blockPort: blockPort,
      actor: actor,
      subject: subject,
    );
  });

  Future<Object?> resolveRevokeAcknowledgement() async {
    final field =
        mutation.all.singleWhere((f) => f.name == 'revokeAcknowledgement');
    return field.resolve!(null, {
      kGlobalInputQueryJwt: const JwtEntity(sub: actor),
      'beaconId': beaconId,
      'subjectId': subject,
      'slug': slug,
    });
  }

  Future<Object?> resolveSetRoutingMute({required bool muted}) async {
    final field = mutation.all.singleWhere((f) => f.name == 'setRoutingMute');
    return field.resolve!(null, {
      kGlobalInputQueryJwt: const JwtEntity(sub: actor),
      'slug': slug,
      'muted': muted,
    });
  }

  Future<Object?> resolveSeedRoutingAttestation({
    required List<String> slugs,
  }) async {
    final field =
        mutation.all.singleWhere((f) => f.name == 'seedRoutingAttestation');
    return field.resolve!(null, {
      kGlobalInputQueryJwt: const JwtEntity(sub: actor),
      'subjectId': subject,
      'slugs': slugs,
    });
  }

  Future<Object?> resolveInviteSeedPromptAnswer({
    required List<String> slugs,
  }) async {
    final field =
        mutation.all.singleWhere((f) => f.name == 'inviteSeedPromptAnswer');
    return field.resolve!(null, {
      kGlobalInputQueryJwt: const JwtEntity(sub: actor),
      'subjectId': subject,
      'slugs': slugs,
    });
  }

  Future<Object?> resolveInviteSeedPromptSkip() async {
    final field =
        mutation.all.singleWhere((f) => f.name == 'inviteSeedPromptSkip');
    return field.resolve!(null, {
      kGlobalInputQueryJwt: const JwtEntity(sub: actor),
      'subjectId': subject,
    });
  }

  group('revokeAcknowledgement', () {
    test('passes jwt.sub as actorId to the use case', () async {
      final result = await resolveRevokeAcknowledgement();

      expect(result, isTrue);
      verify(
        capabilityEvidence.revokeOutcomeEvidence(
          beaconId: beaconId,
          observerId: actor,
          subjectId: subject,
          slug: slug,
        ),
      ).called(1);
    });
  });

  group('setRoutingMute', () {
    test('passes jwt.sub as actorId to the use case', () async {
      final result = await resolveSetRoutingMute(muted: true);

      expect(result, isTrue);
      verify(
        routingMute.setMute(
          userId: actor,
          tagSlug: slug,
          muted: true,
        ),
      ).called(1);
    });
  });

  group('seedRoutingAttestation', () {
    test('non-empty slugs upsert attestation with jwt.sub as observer', () async {
      when(
        capabilityEvidence.upsertSeedAttestation(
          observerId: actor,
          subjectId: subject,
          slugs: const ['transport', 'pets'],
        ),
      ).thenAnswer((_) async {});

      final result = await resolveSeedRoutingAttestation(
        slugs: const ['transport', 'pets'],
      );

      expect(result, isTrue);
      verify(
        capabilityEvidence.upsertSeedAttestation(
          observerId: actor,
          subjectId: subject,
          slugs: const ['transport', 'pets'],
        ),
      ).called(1);
      verifyNever(
        promptPort.markAnswered(
          inviterId: anyNamed('inviterId'),
          inviteeId: anyNamed('inviteeId'),
        ),
      );
    });

    test('empty slugs call withdraw with jwt.sub', () async {
      when(
        capabilityEvidence.upsertSeedAttestation(
          observerId: actor,
          subjectId: subject,
          slugs: const [],
        ),
      ).thenAnswer((_) async {});

      final result = await resolveSeedRoutingAttestation(slugs: const []);

      expect(result, isTrue);
      verify(
        capabilityEvidence.upsertSeedAttestation(
          observerId: actor,
          subjectId: subject,
          slugs: const [],
        ),
      ).called(1);
    });
  });

  group('inviteSeedPromptAnswer', () {
    test('passes jwt.sub as actorId to answer', () async {
      when(
        promptPort.markAnswered(inviterId: actor, inviteeId: subject),
      ).thenAnswer((_) async {});
      when(
        capabilityEvidence.upsertSeedAttestation(
          observerId: actor,
          subjectId: subject,
          slugs: const ['transport'],
        ),
      ).thenAnswer((_) async {});

      final result = await resolveInviteSeedPromptAnswer(
        slugs: const ['transport'],
      );

      expect(result, isTrue);
      verify(
        promptPort.markAnswered(inviterId: actor, inviteeId: subject),
      ).called(1);
      verify(
        capabilityEvidence.upsertSeedAttestation(
          observerId: actor,
          subjectId: subject,
          slugs: const ['transport'],
        ),
      ).called(1);
    });
  });

  group('inviteSeedPromptSkip', () {
    test('passes jwt.sub as actorId to skip', () async {
      when(
        promptPort.markSkipped(inviterId: actor, inviteeId: subject),
      ).thenAnswer((_) async {});

      final result = await resolveInviteSeedPromptSkip();

      expect(result, isTrue);
      verify(
        promptPort.markSkipped(inviterId: actor, inviteeId: subject),
      ).called(1);
    });
  });

  group('non-inviter cannot seed', () {
    test('inviteSeedPromptAnswer propagates UnauthorizedException', () async {
      when(genealogyPort.inviterOf(subject)).thenAnswer((_) async => 'bob');

      await expectLater(
        resolveInviteSeedPromptAnswer(slugs: const ['transport']),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('seedRoutingAttestation propagates UnauthorizedException', () async {
      when(genealogyPort.inviterOf(subject)).thenAnswer((_) async => 'bob');

      await expectLater(
        resolveSeedRoutingAttestation(slugs: const ['transport']),
        throwsA(isA<UnauthorizedException>()),
      );
    });
  });
}
