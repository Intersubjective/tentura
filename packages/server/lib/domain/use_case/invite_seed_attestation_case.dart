import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/capability/capability_slug_validation.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/capability_evidence_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/invite_seed_prompt_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/port/user_block_repository_port.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class InviteSeedAttestationCase extends UseCaseBase {
  InviteSeedAttestationCase(
    this._inviteSeedPrompt,
    this._inviteGenealogy,
    this._capabilityEvidence,
    this._userBlockRepository,
    this._unitOfWork, {
    required super.env,
    required super.logger,
  });

  final InviteSeedPromptPort _inviteSeedPrompt;
  final InviteGenealogyRepositoryPort _inviteGenealogy;
  final CapabilityEvidencePort _capabilityEvidence;
  final UserBlockRepositoryPort _userBlockRepository;
  final MutatingUnitOfWorkPort _unitOfWork;

  Future<PromptState?> promptStateFor({
    required String actorId,
    required String subjectId,
  }) async {
    await _authorizeInviter(actorId: actorId, subjectId: subjectId);
    return _inviteSeedPrompt.stateFor(
      inviterId: actorId,
      inviteeId: subjectId,
    );
  }

  Future<void> answer({
    required String actorId,
    required String subjectId,
    required List<String> slugs,
  }) async {
    await _authorizeInviter(actorId: actorId, subjectId: subjectId);
    final validated = validateCapabilitySlugPayload(slugs);
    await _unitOfWork.run(
      actorUserId: actorId,
      action: () async {
        await _inviteSeedPrompt.markAnswered(
          inviterId: actorId,
          inviteeId: subjectId,
        );
        await _capabilityEvidence.upsertSeedAttestation(
          observerId: actorId,
          subjectId: subjectId,
          slugs: validated,
        );
      },
    );
  }

  Future<void> skip({
    required String actorId,
    required String subjectId,
  }) async {
    await _authorizeInviter(actorId: actorId, subjectId: subjectId);
    await _inviteSeedPrompt.markSkipped(
      inviterId: actorId,
      inviteeId: subjectId,
    );
  }

  /// Clears any prior seed attestation from this inviter; prompt state is left
  /// unchanged (the inviter already engaged with the prompt).
  Future<void> withdraw({
    required String actorId,
    required String subjectId,
  }) async {
    await _authorizeInviter(actorId: actorId, subjectId: subjectId);
    await _capabilityEvidence.upsertSeedAttestation(
      observerId: actorId,
      subjectId: subjectId,
      slugs: const [],
    );
  }

  Future<void> _authorizeInviter({
    required String actorId,
    required String subjectId,
  }) async {
    if (actorId == subjectId) {
      throw const UnauthorizedException(
        description: 'Cannot seed yourself',
      );
    }
    if (await _userBlockRepository.isBlockedPair(a: actorId, b: subjectId)) {
      throw const UnauthorizedException(
        description: 'Blocked user pair',
      );
    }
    final directInviter = await _inviteGenealogy.inviterOf(subjectId);
    if (directInviter != actorId) {
      throw const UnauthorizedException(
        description: 'Only the direct inviter may seed this user',
      );
    }
    final prompt = await _inviteSeedPrompt.stateFor(
      inviterId: actorId,
      inviteeId: subjectId,
    );
    if (prompt == null) {
      throw const UnauthorizedException(
        description: 'No invite-seed prompt for this pair',
      );
    }
  }
}
