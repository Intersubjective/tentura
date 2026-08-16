import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/port/capability_evidence_port.dart';
import 'package:tentura_server/domain/port/user_block_repository_port.dart';
import 'package:tentura_server/domain/use_case/invite_seed_attestation_case.dart';
import 'package:tentura_server/env.dart';

import '../../../domain/use_case/capability_routing_case_mocks.mocks.dart';
import 'invite_seed_resolver_mocks.mocks.dart';

InviteSeedAttestationCase buildInviteSeedCase({
  required MockInviteSeedPromptPort promptPort,
  required MockInviteGenealogyRepositoryPort genealogyPort,
  required CapabilityEvidencePort evidencePort,
  required UserBlockRepositoryPort blockPort,
  required MockMutatingUnitOfWorkPort unitOfWork,
}) {
  when(
    unitOfWork.run(
      action: anyNamed('action'),
      actorUserId: anyNamed('actorUserId'),
    ),
  ).thenAnswer((invocation) async {
    final action =
        invocation.namedArguments[#action] as Future<void> Function();
    await action();
  });
  return InviteSeedAttestationCase(
    promptPort,
    genealogyPort,
    evidencePort,
    blockPort,
    unitOfWork,
    env: Env(environment: Environment.test),
    logger: Logger('InviteSeedResolverTestHelper'),
  );
}

void stubAuthorizedInviter({
  required MockInviteGenealogyRepositoryPort genealogyPort,
  required MockInviteSeedPromptPort promptPort,
  required UserBlockRepositoryPort blockPort,
  required String actor,
  required String subject,
  MockCapabilityEvidencePort? evidencePort,
  Set<String> seedSlugs = const {},
  PromptStateValue promptState = PromptStateValue.pending,
}) {
  when(blockPort.isBlockedPair(a: actor, b: subject)).thenAnswer((_) async => false);
  when(genealogyPort.inviterOf(subject)).thenAnswer((_) async => actor);
  when(
    promptPort.stateFor(inviterId: actor, inviteeId: subject),
  ).thenAnswer(
    (_) async => PromptState(
      inviterUserId: actor,
      inviteeUserId: subject,
      state: promptState,
    ),
  );
  if (evidencePort != null) {
    when(
      evidencePort.activeSeedSlugs(observerId: actor, subjectId: subject),
    ).thenAnswer((_) async => seedSlugs);
  }
}
