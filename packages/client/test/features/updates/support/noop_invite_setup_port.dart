import 'package:tentura/domain/capability/invite_seed_prompt_state.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';

/// Minimal setup port for feed cubit tests that do not exercise prompts.
final class NoopInviteAcceptedSetupPort implements InviteAcceptedSetupPort {
  @override
  Future<Map<String, InviteSeedPromptState>> fetchPrompts(
    Set<String> subjectIds,
  ) async =>
      {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
