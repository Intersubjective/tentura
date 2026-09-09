/// Shell-level snapshot of "has this account done anything real yet".
///
/// Pure value type: no I/O, no Flutter import. Fed by the reporters that
/// already sit in [HomeScreen]'s account scope.
class HomeActivationSignals {
  const HomeActivationSignals({
    this.myWorkCardCount = 0,
    this.draftCount = 0,
    this.archivedCountHint = 0,
    this.inboxItemCount = 0,
    this.myWorkLoaded = false,
    this.inboxLoaded = false,
    this.inboxFailed = false,
  });

  /// Non-archived cards: authored + help-offered. **Drafts already live inside
  /// this collection** — `MyWorkState.draftCount` is
  /// `countDraftMyWorkCards(nonArchivedCards)` (`my_work_state.dart:41`), so
  /// [draftCount] must never be added on top of it.
  final int myWorkCardCount;
  final int draftCount; // reported for the debug readout only
  final int archivedCountHint;
  final int inboxItemCount; // every inbox item, not just needs-me
  final bool myWorkLoaded;
  final bool inboxLoaded;

  /// The Inbox projection failed rather than resolved. Settles the decision
  /// (no infinite spinner) and forbids orientation (fail closed).
  final bool inboxFailed;

  int get myWorkActivityCount => myWorkCardCount + archivedCountHint;

  /// Disjoint by construction; drafts are deliberately absent.
  int get activityCount => myWorkActivityCount + inboxItemCount;

  bool get hasActivity => activityCount > 0;

  /// Enough is known to decide. A failed Inbox counts as settled.
  bool get isSettled => myWorkLoaded && (inboxLoaded || inboxFailed);

  /// Activity seen on a projection that *individually* succeeded — the trigger
  /// for the activation latch. Deliberately does not require both projections:
  /// a My Work card observed during an Inbox outage is still real activity.
  bool get hasProvenActivity =>
      (myWorkLoaded && myWorkActivityCount > 0) ||
      (inboxLoaded && inboxItemCount > 0);
}

/// Debug-only forcing of the orientation panel (§7). `auto` is production.
enum OrientationDebugOverride { auto, show, hide }

/// The empty branch needs three outcomes, not two: "orientation", "ordinary
/// empty body", and "we do not know yet — keep the spinner".
enum OrientationDecision { show, ordinaryEmpty, undecided }
