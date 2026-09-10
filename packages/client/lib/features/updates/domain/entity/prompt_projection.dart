import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/capability/invite_seed_prompt_state.dart';
import 'package:tentura/domain/capability/prompt_state_value.dart';
import 'package:tentura/features/updates/updates_receipt_display_copy.dart';

part 'prompt_projection.freezed.dart';

/// Tri-state prompt projection shared by feed placement and invite cards.
@freezed
sealed class PromptProjection with _$PromptProjection {
  const factory PromptProjection.unknown() = PromptProjectionUnknown;

  const factory PromptProjection.known(InviteSeedPromptState state) =
      PromptProjectionKnown;

  const factory PromptProjection.failed() = PromptProjectionFailed;

  const PromptProjection._();

  bool get isUnknown => this is PromptProjectionUnknown;

  bool get isFailed => this is PromptProjectionFailed;

  bool get isKnownPending => switch (this) {
    PromptProjectionKnown(:final state) =>
      state.state == PromptStateValue.pending,
    _ => false,
  };

  bool get isKnownSettled => switch (this) {
    PromptProjectionKnown(:final state) =>
      state.state != PromptStateValue.pending,
    _ => false,
  };
}

String? inviteAcceptedPromptSubjectId(AttentionReceipt receipt) {
  final subjectId = receipt.actorUserId ?? receipt.targetEntityId;
  if (subjectId == null || subjectId.isEmpty) return null;
  return subjectId;
}

bool receiptNeedsInvitePromptProjection(AttentionReceipt receipt) {
  if (!isInviteAcceptedPresentationKey(receipt.presentationKey)) return false;
  if (inviteOriginFromPresentationPayload(receipt.presentationPayloadJson) !=
      'new_account') {
    return false;
  }
  return inviteAcceptedPromptSubjectId(receipt) != null;
}

bool isInvitePromptPinCandidate({
  required AttentionReceipt receipt,
  required PromptProjection projection,
}) {
  if (!receiptNeedsInvitePromptProjection(receipt)) return false;
  return projection.isKnownPending;
}
