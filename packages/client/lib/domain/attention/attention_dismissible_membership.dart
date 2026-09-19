import 'entity/attention_feed.dart';
import 'entity/attention_receipt.dart';

/// The client's mirror of the server's sweep membership (owner decision A).
///
/// The server owns the truth — `AttentionDismissibleSql.dismissibleReceipts`
/// (Set R) and `dismissibleOutcomes` (Set O), transcribed for both layers in
/// `docs/contracts/attention-active-attention-axis.json`. This exists only so
/// the **optimistic frame** says the same thing the server will: before U15R-c
/// the sweep optimistically removed every cached uncleared receipt, so the
/// user watched an obligation and an unanswered forward vanish and only the
/// server's refusal put them back. Owner decision A is a product guarantee; a
/// frame that breaks it is a broken frame, not a fast one.
///
/// The rule is deliberately conservative in one direction only: **where
/// membership is unknown, there is no optimism.** A synthetic grouped row
/// (`requestActivity`, `forward`, `watchingDigest`) is one card standing for
/// children whose identities the client does not hold, so it is never an
/// optimistic member — the server's answer moves it instead.
bool isOptimisticallySweepable(AttentionReceipt receipt) {
  // Unknown membership: a grouped row is not a receipt identity the sweep
  // can report back, so nothing is assumed about it.
  if (receipt.itemKind != AttentionItemKind.receipt) return false;
  // Set R, clause by clause.
  if (receipt.surface != AttentionSurface.activity) return false;
  if (receipt.requiresAction) return false;
  if (receipt.isCleared) return false;
  if (receipt.presentationKey == 'relay_received') return false;
  return true;
}

/// The server's `unread` view membership — `$2 = 'unread' AND
/// is_active_attention`, which is a **different expression per branch** of the
/// stream union in `attention_repository.dart`. One rule for all four kinds is
/// what U15R-c shipped and what this replaces: a `requestActivity` card whose
/// last optional child was cleared stayed on the list the server had already
/// dropped it from, showing `0`.
///
/// | item kind         | server expression                                |
/// | ----------------- | ------------------------------------------------ |
/// | `receipt`         | `activeAttention(v) AND primaryPlacement(v)`      |
/// | `requestActivity` | `stats.event_unseen_count > 0`                    |
/// | `forward`         | `false` — an outcome row never carries the dot    |
/// | `watchingDigest`  | `true`                                            |
///
/// `primaryPlacement` is deliberately absent: the client is never served a
/// non-primary row, so mirroring it here would be a predicate with no input.
bool isInUnreadView(AttentionReceipt receipt) => switch (receipt.itemKind) {
  AttentionItemKind.receipt =>
    isActiveOptional(receipt) || receipt.isLiveObligation,
  AttentionItemKind.requestActivity => (receipt.eventUnseenCount ?? 0) > 0,
  AttentionItemKind.forward => false,
  AttentionItemKind.watchingDigest => true,
};

/// Active **optional** attention — `activeOptional` in the server's SQL. The
/// clear axis, independent of `seenAt` (D02): what a clear delta is made of.
bool isActiveOptional(AttentionReceipt receipt) =>
    !receipt.requiresAction && !receipt.isCleared;

/// The subset of [receipts] a sweep may optimistically remove.
Set<String> optimisticSweepMembers(Iterable<AttentionReceipt> receipts) => {
  for (final receipt in receipts)
    if (isOptimisticallySweepable(receipt)) receipt.id,
};
