import 'package:freezed_annotation/freezed_annotation.dart';

import 'prompt_state_value.dart';

part 'invite_seed_prompt_state.freezed.dart';

@freezed
abstract class InviteSeedPromptState with _$InviteSeedPromptState {
  const factory InviteSeedPromptState({
    required String inviterUserId,
    required String inviteeUserId,
    required PromptStateValue state,
  }) = _InviteSeedPromptState;

  const InviteSeedPromptState._();
}
