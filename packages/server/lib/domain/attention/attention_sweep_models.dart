/// U09b — *Dismiss all*, the sweep.
///
/// The sweep differs from U08's clear in one way that decides everything else:
/// its membership is captured **server-side across the whole authorized
/// surface**, including pages nobody has loaded. There is no token, because
/// there is no client-held list — a client cannot hand over what it has never
/// seen, and a surface-wide clear that only covered the loaded pages would
/// quietly leave the dot on.
///
/// What it may touch is owner decision A, and only that: the rows that carry
/// their own `×`. It never touches an obligation and never touches anything
/// awaiting a decision — sweeping an unanswered forward would answer a person
/// by not answering them.
library;

import 'attention_clear_models.dart';

/// How much work one call does.
///
/// A surface-wide sweep is the one attention command with no natural ceiling
/// on its membership, so the ceiling is explicit: members are captured and
/// decided in batches, and a caller that wants to bound a single request
/// bounds the number of batches and resumes with the same operation id.
abstract final class AttentionSweepLimits {
  static const batchSize = 200;
  static const maxBatchSize = 500;
}

/// Which axis a member lives on. One operation spans both (U09a): a receipt
/// member is cleared on `notification_outbox.cleared_at`, an outcome member is
/// dismissed on `inbox_item.tombstone_dismissed_at`.
enum AttentionSweepMemberKind {
  receipt('receipt'),
  outcome('outcome');

  const AttentionSweepMemberKind(this.wireName);

  final String wireName;

  static AttentionSweepMemberKind fromWireName(String value) =>
      AttentionSweepMemberKind.values.firstWhere(
        (kind) => kind.wireName == value,
        orElse: () => throw ArgumentError.value(value, 'kind'),
      );
}

/// Why a captured member was not swept.
///
/// "Skipped" without a reason is not a report. These are the answers the sweep
/// is allowed to give, and each one is a different fact about the world: a
/// Request whose forward became unanswered again is not the same event as a
/// Request the viewer may no longer read, and only one of them is a bug if it
/// happens often.
enum AttentionSweepSkipReason {
  /// The row is back in the pinned decision zone — a Restore re-pinned the
  /// forward, or the person was forwarded the Request again. Owner decision A:
  /// never swept, always reported.
  awaitingDecision('awaiting_decision'),

  /// The viewer gained responsibility for the Request after capture, so it is
  /// My Desk work now and no longer dismissible from For You (D07).
  responsibilityGained('responsibility_gained'),

  /// Somebody decided something on this Request between capture and apply:
  /// the live `decision_revision` / `outcome_generation` no longer match the
  /// snapshot, so the row the sweep captured is not the row in front of the
  /// person now.
  decisionChanged('decision_changed'),

  /// Another gesture got there first — an explicit `×`, opening the Request,
  /// or another device's sweep.
  alreadyCleared('already_cleared'),

  /// The member is an obligation. It has no `×` and is never swept; this can
  /// only happen if a receipt gained `requires_action` after capture.
  obligation('obligation'),

  /// Authorization was lost, or the row is gone: the Request was deleted, the
  /// author blocked the viewer, the inbox row disappeared. Deliberately one
  /// reason, because the sweep must not disclose which.
  notAuthorized('not_authorized'),

  /// U09c undid this member after the sweep applied it. Not a refusal by the
  /// sweep — a later reversal of it, reported here so a resumed call cannot
  /// mistake an undone member for one it still has to do.
  undone('undone'),

  /// The write was refused by the database. The sweep's own predicate is the
  /// first line of defence and this should never be the reason; if it is,
  /// something above the database is out of step with it.
  refused('refused');

  const AttentionSweepSkipReason(this.wireName);

  final String wireName;

  static AttentionSweepSkipReason fromWireName(String value) =>
      AttentionSweepSkipReason.values.firstWhere(
        (reason) => reason.wireName == value,
        orElse: () => AttentionSweepSkipReason.refused,
      );
}

/// One member of a sweep and what became of it.
class AttentionSweepMember {
  const AttentionSweepMember({
    required this.kind,
    required this.id,
    this.reason,
  });

  final AttentionSweepMemberKind kind;

  /// A receipt id, or — for an outcome member — the Request's id.
  final String id;

  /// Set on skipped and failed members only.
  final AttentionSweepSkipReason? reason;
}

/// The authoritative answer of a sweep, rebuilt from stored membership.
///
/// It is the same answer for the call that did the work, for a call that
/// resumed it, and for a concurrent twin that did nothing — because none of
/// them reports what *it* did, they all report what the operation's members
/// say. "Applied" means cleared, and nothing else is reported as applied.
class AttentionSweepResult {
  const AttentionSweepResult({
    required this.operationId,
    required this.appliedReceiptIds,
    required this.appliedOutcomeBeaconIds,
    required this.skipped,
    required this.failed,
    required this.pending,
    required this.status,
    this.undoDeadline,
    this.undoToken,
  });

  final String operationId;
  final List<String> appliedReceiptIds;
  final List<String> appliedOutcomeBeaconIds;
  final List<AttentionSweepMember> skipped;
  final List<AttentionSweepMember> failed;

  /// Members captured but not yet decided — a bounded call stopped early and
  /// the same `operationId` resumes exactly where it left off. Never a new
  /// capture: membership is captured once and is never extended.
  final List<AttentionSweepMember> pending;

  /// U08's vocabulary, deliberately reused: `complete` only when every member
  /// was cleared, `partial` the moment anything was refused or is still
  /// pending, `stale` when nothing could be cleared at all, `denied` when the
  /// operation id belongs to somebody else.
  final AttentionClearStatus status;

  /// When the undo window closes, server clock. Set once this operation has
  /// actually cleared something, and moved forward again by a resumed call
  /// that cleared more — a bounded sweep is one gesture, and the window runs
  /// from the last thing it swept. Never moved by a call that cleared
  /// nothing: a replay must not be able to buy more undo time by asking
  /// again. NULL on an operation that cleared nothing, which is also how the
  /// caller knows there is nothing to offer an undo for.
  final DateTime? undoDeadline;

  /// Present exactly when [undoDeadline] is. Opaque and bound to the account
  /// and the operation; it carries no capability — see `AttentionUndoToken`.
  final String? undoToken;

  int get appliedCount =>
      appliedReceiptIds.length + appliedOutcomeBeaconIds.length;
}
