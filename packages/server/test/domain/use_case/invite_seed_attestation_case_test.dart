import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/invite_seed_attestation_case.dart';

import '../../api/controllers/graphql/invite_seed_resolver_mocks.mocks.dart';
import '../../api/controllers/graphql/invite_seed_resolver_test_helper.dart';
import 'capability_projection_case_mocks.mocks.dart' show MockUserBlockRepositoryPort;
import 'capability_routing_case_mocks.mocks.dart';

void main() {
  late MockInviteSeedPromptPort promptPort;
  late MockInviteGenealogyRepositoryPort genealogyPort;
  late MockCapabilityEvidencePort evidencePort;
  late MockUserBlockRepositoryPort blockPort;
  late MockMutatingUnitOfWorkPort unitOfWork;
  late InviteSeedAttestationCase case_;

  const actor = 'alice';
  const subject = 'carol';

  setUp(() {
    promptPort = MockInviteSeedPromptPort();
    genealogyPort = MockInviteGenealogyRepositoryPort();
    evidencePort = MockCapabilityEvidencePort();
    blockPort = MockUserBlockRepositoryPort();
    unitOfWork = MockMutatingUnitOfWorkPort();
    case_ = buildInviteSeedCase(
      promptPort: promptPort,
      genealogyPort: genealogyPort,
      evidencePort: evidencePort,
      blockPort: blockPort,
      unitOfWork: unitOfWork,
    );
  });

  test('promptStateFor returns taxonomy-ordered ledger slugs', () async {
    stubAuthorizedInviter(
      genealogyPort: genealogyPort,
      promptPort: promptPort,
      blockPort: blockPort,
      actor: actor,
      subject: subject,
      evidencePort: evidencePort,
      promptState: PromptStateValue.answered,
      seedSlugs: {'pets', 'transport'},
    );

    final view = await case_.promptStateFor(
      actorId: actor,
      subjectId: subject,
    );

    expect(view.state, PromptStateValue.answered);
    expect(view.slugs, ['transport', 'pets']);
  });

  test('promptStateFor drops unknown ledger slugs', () async {
    stubAuthorizedInviter(
      genealogyPort: genealogyPort,
      promptPort: promptPort,
      blockPort: blockPort,
      actor: actor,
      subject: subject,
      evidencePort: evidencePort,
      promptState: PromptStateValue.answered,
      seedSlugs: {'transport', 'not_a_tag'},
    );

    final view = await case_.promptStateFor(
      actorId: actor,
      subjectId: subject,
    );

    expect(view.slugs, ['transport']);
  });

  test('unauthorized inviter never reads the seed ledger', () async {
    when(blockPort.isBlockedPair(a: actor, b: subject)).thenAnswer((_) async => false);
    when(genealogyPort.inviterOf(subject)).thenAnswer((_) async => 'bob');

    await expectLater(
      case_.promptStateFor(actorId: actor, subjectId: subject),
      throwsA(isA<UnauthorizedException>()),
    );
    verifyNever(
      evidencePort.activeSeedSlugs(
        observerId: anyNamed('observerId'),
        subjectId: anyNamed('subjectId'),
      ),
    );
  });

  test('ledger read failure returns empty slugs', () async {
    stubAuthorizedInviter(
      genealogyPort: genealogyPort,
      promptPort: promptPort,
      blockPort: blockPort,
      actor: actor,
      subject: subject,
      promptState: PromptStateValue.answered,
    );
    when(
      evidencePort.activeSeedSlugs(observerId: actor, subjectId: subject),
    ).thenThrow(StateError('ledger down'));

    final view = await case_.promptStateFor(
      actorId: actor,
      subjectId: subject,
    );

    expect(view.state, PromptStateValue.answered);
    expect(view.slugs, isEmpty);
  });
}
