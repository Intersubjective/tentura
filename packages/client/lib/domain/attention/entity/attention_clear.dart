import 'package:freezed_annotation/freezed_annotation.dart';

import 'attention_summary.dart';

part 'attention_clear.freezed.dart';

/// Why a receipt carries `clearedAt` (§0.1, frozen vocabulary).
///
/// Read-only on the client: the server writes it, nobody sends it.
/// [unknown] exists so a vocabulary the server grows later cannot crash a
/// client that has not shipped yet.
enum AttentionClearReason {
  explicit('explicit'),
  requestOpen('request_open'),
  sweep('sweep'),
  legacySeen('legacy_seen'),
  unknown('unknown');

  const AttentionClearReason(this.wireName);

  final String wireName;

  static AttentionClearReason? fromWire(String? value) {
    if (value == null) return null;
    for (final reason in values) {
      if (reason.wireName == value) return reason;
    }
    return unknown;
  }
}

/// What a clear capture covers — the `kind` argument of
/// `attentionClearSnapshot`. Client-authored, so it has no unknown member:
/// there is no value here the client did not choose itself.
enum AttentionClearCaptureKind {
  /// One event, or the optional set of one card, dismissed by hand.
  explicit('explicit'),

  /// The Request was opened and its optional updates were absorbed.
  requestOpen('request_open');

  const AttentionClearCaptureKind(this.wireName);

  final String wireName;

  static AttentionClearCaptureKind? fromWire(String? value) {
    if (value == null) return null;
    for (final kind in values) {
      if (kind.wireName == value) return kind;
    }
    return null;
  }
}

/// The four-word vocabulary every attention command answers in.
///
/// [unknown] is deliberately not complete: a status this client has never seen
/// must not be reported to a person as a finished operation.
enum AttentionOperationStatus {
  complete('complete'),
  partial('partial'),
  stale('stale'),
  denied('denied'),
  unknown('unknown');

  const AttentionOperationStatus(this.wireName);

  final String wireName;

  bool get isComplete => this == complete;

  static AttentionOperationStatus? fromWire(String? value) {
    if (value == null) return null;
    for (final status in values) {
      if (status.wireName == value) return status;
    }
    return unknown;
  }
}

/// Which axis a sweep/undo member lives on: a receipt's `cleared_at`, or an
/// outcome's `tombstone_dismissed_at`.
enum AttentionSweepMemberKind {
  receipt('receipt'),
  outcome('outcome'),
  unknown('unknown');

  const AttentionSweepMemberKind(this.wireName);

  final String wireName;

  static AttentionSweepMemberKind? fromWire(String? value) {
    if (value == null) return null;
    for (final kind in values) {
      if (kind.wireName == value) return kind;
    }
    return unknown;
  }
}

/// Why a captured member was not swept. A skip without a reason is not a
/// report, so the client keeps the reason rather than a boolean.
enum AttentionSweepSkipReason {
  awaitingDecision('awaiting_decision'),
  responsibilityGained('responsibility_gained'),
  decisionChanged('decision_changed'),
  alreadyCleared('already_cleared'),
  obligation('obligation'),
  notAuthorized('not_authorized'),
  undone('undone'),
  refused('refused'),
  unknown('unknown');

  const AttentionSweepSkipReason(this.wireName);

  final String wireName;

  static AttentionSweepSkipReason? fromWire(String? value) {
    if (value == null) return null;
    for (final reason in values) {
      if (reason.wireName == value) return reason;
    }
    return unknown;
  }
}

/// Why one member was not restored. A sweep refuses to clear and an undo
/// refuses to put back; the two vocabularies are not interchangeable.
enum AttentionUndoSkipReason {
  notApplied('not_applied'),
  alreadyRestored('already_restored'),
  clearedByAnotherOperation('cleared_by_another_operation'),
  decisionChanged('decision_changed'),
  obligation('obligation'),
  notAuthorized('not_authorized'),
  refused('refused'),
  unknown('unknown');

  const AttentionUndoSkipReason(this.wireName);

  final String wireName;

  static AttentionUndoSkipReason? fromWire(String? value) {
    if (value == null) return null;
    for (final reason in values) {
      if (reason.wireName == value) return reason;
    }
    return unknown;
  }
}

/// A refusal of the *whole* undo, as opposed to of one member. `expired` in
/// particular is a thing a person is told, not a thing that fails.
enum AttentionUndoRefusal {
  expired('expired'),
  notFound('not_found'),
  neverApplied('never_applied'),
  unknown('unknown');

  const AttentionUndoRefusal(this.wireName);

  final String wireName;

  static AttentionUndoRefusal? fromWire(String? value) {
    if (value == null) return null;
    for (final refusal in values) {
      if (refusal.wireName == value) return refusal;
    }
    return unknown;
  }
}

/// An issued capture: the opaque token plus what it covers.
@freezed
abstract class AttentionClearSnapshot with _$AttentionClearSnapshot {
  const factory AttentionClearSnapshot({
    required String snapshotToken,
    @Default(<String>[]) List<String> receiptIds,
    @Default(0) int outcomeGeneration,
    @Default(0) int decisionRevision,
  }) = _AttentionClearSnapshot;

  const AttentionClearSnapshot._();

  bool get isEmpty => receiptIds.isEmpty;
}

/// Result of `attentionClear` — exactly the captured membership, never more.
@freezed
abstract class AttentionClearResult with _$AttentionClearResult {
  const factory AttentionClearResult({
    required String operationId,
    required AttentionOperationStatus status,
    @Default(<String>[]) List<String> appliedReceiptIds,
    @Default(<String>[]) List<String> skippedReceiptIds,
    @Default(<String>[]) List<String> deniedReceiptIds,
  }) = _AttentionClearResult;

  const AttentionClearResult._();

  bool get isComplete => status.isComplete;

  /// Anything the server refused. Optimism over these members must be rolled
  /// back rather than committed.
  bool get hasRefusals =>
      skippedReceiptIds.isNotEmpty || deniedReceiptIds.isNotEmpty;
}

/// One member a sweep refused, and why.
@freezed
abstract class AttentionSweepMember with _$AttentionSweepMember {
  const factory AttentionSweepMember({
    required String id,
    required AttentionSweepMemberKind kind,
    AttentionSweepSkipReason? reason,
  }) = _AttentionSweepMember;
}

/// Result of `attentionDismissAll`. One sweep spans both axes, so
/// [appliedCount] counts receipts and outcomes together.
@freezed
abstract class AttentionDismissAllResult with _$AttentionDismissAllResult {
  const factory AttentionDismissAllResult({
    required String operationId,
    required AttentionOperationStatus status,
    @Default(<String>[]) List<String> appliedReceiptIds,
    @Default(<String>[]) List<String> appliedOutcomeBeaconIds,
    @Default(0) int appliedCount,
    @Default(<AttentionSweepMember>[]) List<AttentionSweepMember> skipped,
    @Default(<AttentionSweepMember>[]) List<AttentionSweepMember> failed,
    @Default(0) int pendingCount,
    String? undoToken,
    DateTime? undoDeadline,
  }) = _AttentionDismissAllResult;

  const AttentionDismissAllResult._();

  bool get isComplete => status.isComplete && pendingCount == 0;

  /// The call was bounded and did not finish: resume with the same
  /// `operationId` rather than starting a second sweep.
  bool get needsResume => pendingCount > 0;

  bool get hasRefusals => skipped.isNotEmpty || failed.isNotEmpty;

  /// No token means no undo affordance to offer — the two undo fields are
  /// null together.
  bool get canUndo => undoToken != null && undoDeadline != null;
}

/// One member an undo did not restore, and why.
@freezed
abstract class AttentionUndoMember with _$AttentionUndoMember {
  const factory AttentionUndoMember({
    required String id,
    required AttentionSweepMemberKind kind,
    AttentionUndoSkipReason? reason,
  }) = _AttentionUndoMember;
}

/// Result of `attentionUndo`.
@freezed
abstract class AttentionUndoResult with _$AttentionUndoResult {
  const factory AttentionUndoResult({
    required String operationId,
    required AttentionOperationStatus status,
    @Default(<String>[]) List<String> restoredReceiptIds,
    @Default(<String>[]) List<String> restoredOutcomeBeaconIds,
    @Default(<AttentionUndoMember>[]) List<AttentionUndoMember> skipped,
    @Default(<AttentionUndoMember>[]) List<AttentionUndoMember> failed,
    AttentionUndoRefusal? refusal,
  }) = _AttentionUndoResult;

  const AttentionUndoResult._();

  /// The whole operation was refused; no member was examined.
  bool get isRefused => refusal != null;

  bool get isComplete => status.isComplete && !isRefused;

  int get restoredCount =>
      restoredReceiptIds.length + restoredOutcomeBeaconIds.length;
}

/// Result of `attentionReconcile` — invalidation and repair, never erasure.
/// [summary] may legitimately be non-zero: it is what the account owes.
@freezed
abstract class AttentionReconcileResult with _$AttentionReconcileResult {
  const factory AttentionReconcileResult({
    required AttentionSurfaceSummary summary,
    @Default(0) int createdObligationCount,
    @Default(0) int settledObligationCount,
    @Default(0) int unrepairableObligationCount,
  }) = _AttentionReconcileResult;

  const AttentionReconcileResult._();

  /// "Reset counters" may not claim success while something is unrepairable.
  bool get isFullyRepaired => unrepairableObligationCount == 0;
}
