/// U09c — `attentionUndo`, the bounded reversal of one sweep.
///
/// Undo is the least trusted command in this family, and the vocabulary here
/// is shaped by three facts that the design plan (D13) states and this unit
/// enforces:
///
/// * **It is bounded.** A sweep that applied anything gets an
///   [AttentionUndoLimits.window]-long, server-enforced window; after it
///   passes, undo refuses. The window is not a client-held token's lifetime —
///   it is a column, `attention_clear_operation.undo_deadline`, and the server
///   compares it against its own clock.
/// * **It is conservative, and the conservatism has a direction: later intent
///   wins.** If anything moved the object after the sweep — a Restore, a
///   re-pin, an answer, another device's clear — undo refuses *that member*
///   rather than resurrecting the old state on top of the new one. That is
///   what `outcome_generation` and `decision_revision` (U09a) exist for.
/// * **It reports partial results explicitly.** "Ok" is not an answer. Every
///   member either comes back or carries a reason why it did not.
///
/// It deliberately does **not** reuse `markUnseen`. That method refuses when
/// an unseen sibling shares the dedup key, a rule that existed because
/// receipts used to be rewritten in place; U05a made them immutable, so the
/// rule protects nothing here — and it reverses `seen_at`, the read axis,
/// which is not the axis a sweep touched.
library;

import 'dart:convert';

/// How long an undo stays available, and why it is this long.
///
/// 30 seconds, matching D13. The number is not arbitrary: the undo window is
/// the lifetime of the affordance that offers it — a snackbar — and a window
/// longer than the affordance would be a promise the interface never makes,
/// while a shorter one would expire while the snackbar is still on screen.
/// It is also short enough that "nothing else has happened yet" is usually
/// true, which is what makes a conservative undo mostly *succeed* rather than
/// mostly refuse.
abstract final class AttentionUndoLimits {
  static const window = Duration(seconds: 30);
}

/// A refusal of the whole operation, as opposed to of one member.
///
/// Typed on purpose. An undo that failed because the window closed and an
/// undo that failed because the operation id is not the caller's are different
/// facts, and "expired" in particular must never reach a caller as an untyped
/// error — it is the one refusal a person will actually see.
enum AttentionUndoRefusal {
  /// The server's clock is past `undo_deadline`.
  expired('expired'),

  /// No such operation, or it belongs to somebody else. Deliberately one
  /// answer: the server does not disclose which.
  notFound('not_found'),

  /// The operation exists and is the caller's, but nothing was ever applied
  /// under it, so no window was ever opened. A sweep or an explicit clear
  /// that cleared nothing has nothing to undo. Since U15R-a an explicit
  /// clear that *did* clear something opens the same bounded window as a
  /// sweep, so it no longer lands here by construction.
  neverApplied('never_applied');

  const AttentionUndoRefusal(this.wireName);

  final String wireName;
}

/// Why one member was not restored.
///
/// Each of these exists because something specific could otherwise be undone
/// that must not be. They are not interchangeable and they are not a single
/// "conflict".
enum AttentionUndoSkipReason {
  /// The member was captured but never cleared — it is still `pending` from a
  /// bounded sweep, or it was skipped or refused at apply time. Undo restores
  /// only what this operation actually did; it never completes a sweep and
  /// never "restores" a row that was never touched.
  notApplied('not_applied'),

  /// The row is already back: another undo got there first, or a person
  /// restored it by hand. Idempotent, not an error.
  alreadyRestored('already_restored'),

  /// The receipt's `cleared_by_operation_id` is somebody else's operation now
  /// — another device swept it, or an explicit × re-cleared it after this
  /// operation was undone once. Reversing that would reverse another actor's
  /// act.
  clearedByAnotherOperation('cleared_by_another_operation'),

  /// The live `decision_revision` / `outcome_generation` no longer match the
  /// snapshot this operation captured: the viewer restored the forward,
  /// re-pinned it, answered it, or the Request reached a terminal state.
  /// Later intent wins — the old state is not put back on top of the new one.
  decisionChanged('decision_changed'),

  /// The receipt became an obligation after the sweep. An obligation may not
  /// carry clear state at all (`notification_outbox__clear_optional_only_chk`),
  /// so restoring it is both wrong and impossible.
  obligation('obligation'),

  /// Authorization was lost, or the row is gone. One reason for both, because
  /// the answer must not disclose which.
  notAuthorized('not_authorized'),

  /// The database refused the write. The guards above are the first line of
  /// defence and this should never be the reason; it is separated so that it
  /// is visible when it is.
  refused('refused');

  const AttentionUndoSkipReason(this.wireName);

  final String wireName;

  static AttentionUndoSkipReason fromWireName(String value) =>
      AttentionUndoSkipReason.values.firstWhere(
        (reason) => reason.wireName == value,
        orElse: () => AttentionUndoSkipReason.refused,
      );
}

/// One member of an undo and what became of it.
class AttentionUndoMember {
  const AttentionUndoMember({
    required this.kind,
    required this.id,
    this.reason,
  });

  /// `receipt` or `outcome`, the same two axes the sweep spans.
  final String kind;

  /// A receipt id, or — for an outcome member — the Request's id.
  final String id;

  final AttentionUndoSkipReason? reason;
}

/// What an undo did, member by member.
///
/// There is no silent success here: [restoredReceiptIds] and
/// [restoredOutcomeBeaconIds] are what actually came back, read back from the
/// rows themselves, and everything else is in [skipped] or [failed] with a
/// reason attached.
class AttentionUndoResult {
  const AttentionUndoResult({
    required this.operationId,
    required this.restoredReceiptIds,
    required this.restoredOutcomeBeaconIds,
    required this.skipped,
    required this.failed,
    required this.status,
    this.refusal,
  });

  /// The whole operation was refused; no member was examined.
  const AttentionUndoResult.refused({
    required this.operationId,
    required AttentionUndoRefusal this.refusal,
  }) : restoredReceiptIds = const [],
       restoredOutcomeBeaconIds = const [],
       skipped = const [],
       failed = const [],
       status = AttentionUndoStatus.denied;

  final String operationId;
  final List<String> restoredReceiptIds;
  final List<String> restoredOutcomeBeaconIds;
  final List<AttentionUndoMember> skipped;
  final List<AttentionUndoMember> failed;
  final AttentionUndoStatus status;

  /// Set only when the whole operation was refused.
  final AttentionUndoRefusal? refusal;

  int get restoredCount =>
      restoredReceiptIds.length + restoredOutcomeBeaconIds.length;
}

/// U08's four-word vocabulary, reused so the three attention commands answer
/// in the same shape.
enum AttentionUndoStatus {
  /// Every member this operation applied came back.
  complete,

  /// Some came back; the rest carry a reason.
  partial,

  /// Nothing came back and at least one member was refused.
  stale,

  /// The operation itself was refused — see [AttentionUndoResult.refusal].
  denied,
}

/// The undo token: opaque, and bound rather than trusted.
///
/// It carries no capability. Authorization is the caller's JWT compared with
/// `attention_clear_operation.account_id`, and the window is a server column —
/// the token cannot widen either. What it does carry is *offer*: a client may
/// only undo an operation the server handed it a token for, so an operation
/// that never opened a window (any clear or sweep that cleared nothing) has
/// no token and no undo affordance, and a guessed operation id is refused the
/// same way whether it exists or not.
class AttentionUndoToken {
  const AttentionUndoToken({
    required this.accountId,
    required this.operationId,
  });

  factory AttentionUndoToken.decode(String value) {
    try {
      final padding = '=' * ((4 - value.length % 4) % 4);
      final decoded = jsonDecode(
        utf8.decode(base64Url.decode('$value$padding')),
      );
      if (decoded is! Map) throw const FormatException();
      if (decoded['v'] != schemaVersion) throw const FormatException();
      final accountId = decoded['a'];
      final operationId = decoded['o'];
      if (accountId is! String ||
          accountId.isEmpty ||
          operationId is! String ||
          operationId.isEmpty ||
          operationId.length > 64) {
        throw const FormatException();
      }
      return AttentionUndoToken(
        accountId: accountId,
        operationId: operationId,
      );
    } on Object {
      throw ArgumentError.value(
        value,
        'undoToken',
        'invalid attention undo token',
      );
    }
  }

  /// Its own version, so an undo token and a clear snapshot token can never be
  /// mistaken for one another even though they share a transport.
  static const int schemaVersion = 1;

  final String accountId;
  final String operationId;

  String encode() => base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'v': schemaVersion,
            'a': accountId,
            'o': operationId,
          }),
        ),
      )
      .replaceAll('=', '');
}
