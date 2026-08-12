import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/port/invite_seed_prompt_port.dart';

@Injectable(
  as: InviteSeedPromptPort,
  env: [Environment.test],
  order: 1,
)
class InviteSeedPromptRepositoryMock implements InviteSeedPromptPort {
  final pendingInserts =
      <({String inviterId, String inviteeId})>[];

  PromptState? state;

  @override
  Future<PromptState?> stateFor({
    required String inviterId,
    required String inviteeId,
  }) async {
    final current = state;
    if (current == null ||
        current.inviterUserId != inviterId ||
        current.inviteeUserId != inviteeId) {
      return null;
    }
    return current;
  }

  @override
  Future<void> insertPending({
    required String inviterId,
    required String inviteeId,
  }) async {
    pendingInserts.add((inviterId: inviterId, inviteeId: inviteeId));
    state ??= PromptState(
      inviterUserId: inviterId,
      inviteeUserId: inviteeId,
      state: PromptStateValue.pending,
    );
  }

  @override
  Future<void> markAnswered({
    required String inviterId,
    required String inviteeId,
  }) async {
    state = PromptState(
      inviterUserId: inviterId,
      inviteeUserId: inviteeId,
      state: PromptStateValue.answered,
    );
  }

  @override
  Future<void> markSkipped({
    required String inviterId,
    required String inviteeId,
  }) async {
    state = PromptState(
      inviterUserId: inviterId,
      inviteeUserId: inviteeId,
      state: PromptStateValue.skipped,
    );
  }
}
