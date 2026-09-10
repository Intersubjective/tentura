import 'package:tentura_server/domain/capability/capability_evidence_models.dart';

abstract interface class InviteSeedPromptPort {
  Future<PromptState?> stateFor({
    required String inviterId,
    required String inviteeId,
  });

  /// Rows for [inviteeIds] where [inviterId] is the stored inviter; omits ids
  /// with no row or a different inviter.
  Future<List<PromptState>> statesForInvitees({
    required String inviterId,
    required List<String> inviteeIds,
  });

  /// Inserts state `pending` for a new signup; idempotent on conflict.
  Future<void> insertPending({
    required String inviterId,
    required String inviteeId,
  });

  Future<void> markAnswered({
    required String inviterId,
    required String inviteeId,
  });

  Future<void> markSkipped({
    required String inviterId,
    required String inviteeId,
  });
}
