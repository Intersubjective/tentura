/// U09a step 2 — the one definition of "rows that carry their own ×".
///
/// Owner decision A is a safety property, not a convenience: *Dismiss all*
/// clears exactly the rows that expose an individual `×`, and never anything
/// awaiting a decision from the viewer. Sweeping an unanswered forward would
/// answer a person by not answering them, and no undo window repairs a signal
/// that has already been sent.
///
/// That property survives only if capture, apply re-check and (later) the
/// "is Dismiss all enabled?" eligibility question all ask the *same* question.
/// So the predicate lives here, once, as SQL text, and U09b composes it rather
/// than re-deriving it. It is deliberately **not** in `attention_repository.dart`:
/// that file is the read projection and U10 rewrites it.
///
/// Every fragment takes the viewer's account id as `$1`.
abstract final class AttentionDismissibleSql {
  /// Visibility, responsibility scope and surface — the one definition.
  ///
  /// U09a kept a deliberate copy of this in `AttentionRepository`, on the
  /// grounds that U10 owned and would rewrite that file. U10a is that
  /// settlement: the copy is gone and the read projection composes this
  /// constant, so U10b's move from `seen_at` to active attention changes one
  /// definition rather than two that drift apart. It lives *here* because
  /// this is the authorization-critical side — a sweep that silently changed
  /// meaning because a projection was refactored answers somebody by not
  /// answering them.
  ///
  /// `authorized.tombstone_copy` is projected for the read path; the sweep
  /// never reads it. It is a column, not a row filter, so both consumers see
  /// the same membership.
  static const visibleWithSurface = r'''
visible_raw AS (
  SELECT outbox.*, authorized.tombstone_copy
  FROM public.visible_attention_receipts($1) authorized
  JOIN public.notification_outbox outbox
    ON outbox.id = authorized.receipt_id
),
scope AS (
  SELECT beacon_id FROM public.responsibility_scope_base_beacons($1)
  UNION
  SELECT DISTINCT visible_raw.beacon_id
  FROM visible_raw
  WHERE visible_raw.requires_action
    AND visible_raw.settlement_kind IS NULL
    AND visible_raw.beacon_id IS NOT NULL
),
visible AS (
  SELECT
    visible_raw.*,
    CASE
      WHEN visible_raw.beacon_id IS NOT NULL
       AND visible_raw.beacon_id IN (SELECT scope.beacon_id FROM scope)
      THEN 'myWork'
      ELSE 'activity'
    END AS surface
  FROM visible_raw
)''';

  /// The pinned decision zone — readable, unanswered forwards outside scope.
  ///
  /// Also the one definition, and for the same reason: the read path groups
  /// its For-you pins by exactly the rows the sweep must refuse to touch.
  /// Requires [visibleWithSurface] (it reads `scope`) to precede it.
  static const eligiblePinned = r'''
eligible_pinned AS (
  SELECT ii.beacon_id
  FROM public.inbox_item ii
  WHERE ii.user_id = $1
    AND ii.tombstone_dismissed_at IS NULL
    AND ii.status = 0
    AND public.beacon_can_read_content(ii.beacon_id, $1)
    AND ii.beacon_id NOT IN (SELECT scope.beacon_id FROM scope)
)''';

  /// What the sweep needs before either dismissible set: visibility, scope,
  /// surface, and the pinned zone it must never sweep.
  static const prelude = '$visibleWithSurface,\n$eligiblePinned';

  /// U10b — the active-attention axis, as one function (D02, D09, §6 M1).
  ///
  /// Three axes, not one (D02): reading is `seen_at`, the optional axis is
  /// `cleared_at`, the obligation axis is `settlement_kind`. Until U10b every
  /// dot, count and summary asked the *reading* question, so U08's clear and
  /// U09's sweep wrote state nothing displayed.
  ///
  /// These are functions rather than constants for one reason: M1. The rule
  /// deciding what a list shows by default and the rule behind its indicator
  /// must be the same rule, so both call this with their own alias instead of
  /// spelling it out. `attention_active_attention_axis_pg_test.dart` asserts
  /// structurally that no caller writes `cleared_at IS NULL` by hand, and
  /// behaviourally that loosening this moves the number and the list together.
  static String activeOptional(String alias) =>
      'NOT $alias.requires_action AND $alias.cleared_at IS NULL';

  /// An obligation still owed: `requires_action` and not yet settled (D02).
  static String liveObligation(String alias) =>
      '$alias.requires_action AND $alias.settlement_kind IS NULL';

  /// Active attention — what the **default list** on a surface shows.
  ///
  /// The union is deliberate: a default list that dropped live obligations
  /// would take rows off it that the viewer still owes an answer to — the
  /// "silently disappears" failure.
  ///
  /// It is **not** a §6 indicator, and since U15R-d nothing claims it is.
  /// §6 gives each indicator its own rule — `my desk.dot` is optional events
  /// and outcomes only, `my desk.count` is obligations only, `for you.dot`
  /// is Set R ∪ Set O ∪ the pinned zone — and `surfaceSummary` composes those
  /// as `my_desk_dot` / `for_you_dot`. Until U18c the summary also returned
  /// three legacy totals built from this union (`activity_unread_total`,
  /// `my_work_unread_total`, `needs_you_total`); they are retired, and this
  /// predicate now reaches the surface summary only through those §6 rules.
  /// It still spells the `unread` view of the History feed, which §3 keeps.
  static String activeAttention(String alias) =>
      '((${activeOptional(alias)}) OR (${liveObligation(alias)}))';

  /// U11 / D16 — the *placement* filter: does this receipt speak on a primary
  /// surface at all?
  ///
  /// Orthogonal to the three axes above, and deliberately a separate predicate
  /// rather than a clause folded into [activeOptional]. `activeOptional` is
  /// also what the sweep composes, and placement is not a sweep question: a
  /// `timeline_only` receipt is an ordinary optional receipt that happens to
  /// have nothing to show, so nothing changes about whether it can be cleared.
  /// What changes is only what a dot, a count and a position may count.
  ///
  /// Every indicator in the read projection is wrapped in this. A grouped
  /// row's `MIN`/`MAX(created_at)` are wrapped too — those are its position
  /// and its freshness, and R7 says child activity moves neither.
  ///
  /// The column is written by the producer (`AttentionPolicy.placement`,
  /// m0189) and defaults to `'primary'`, so this narrows nothing for any
  /// receipt written before U11.
  static String primaryPlacement(String alias) =>
      "$alias.placement = 'primary'";

  /// Set R — dismissible optional receipts, the `notification_outbox` axis.
  ///
  /// The exclusions are the point:
  ///
  /// * `NOT requires_action` keeps every obligation out — live or settled.
  ///   An obligation has no `×` and is never swept (D06, D07).
  /// * `cleared_at IS NULL` keeps an already-cleared receipt out, so a sweep
  ///   never re-stamps and undo has one operation to unwind.
  /// * `surface = 'activity'` keeps My Desk work out: a Request the viewer is
  ///   responsible for is not dismissible from For You.
  /// * `relay_received` rows are the synthetic forward shell, not real
  ///   receipts; the forward itself is decided, never dismissed.
  static String get dismissibleReceipts => '''
activity_optional_dismissible AS (
  SELECT v.id AS receipt_id, v.beacon_id
  FROM visible v
  WHERE v.surface = 'activity'
    AND ${activeOptional('v')}
    AND v.presentation_key IS DISTINCT FROM 'relay_received'
)''';

  /// §6 `my desk.dot` — "any owned Request has a dot", where
  /// `request.dot = has at least one uncleared optional event or uncleared
  /// outcome". Obligations are absent on purpose: they are the *number*, and
  /// D09 keeps dot and number independent.
  ///
  /// A boolean expression over [cte]. It lives here, not inline in the
  /// repository, because U15R-d's verify pass caught the M1 test composing
  /// its own slightly looser copy — the Set R leg without the placement
  /// filter — which is a guard that cannot catch the drift it exists for.
  /// One definition, both callers.
  static String get myDeskDotExpression => '''
EXISTS (
  SELECT 1
  FROM visible v
  WHERE v.surface = 'myWork'
    AND ${activeOptional('v')}
    AND ${primaryPlacement('v')}
)
OR EXISTS (
  SELECT 1
  FROM activity_outcome_dismissible o
  WHERE o.beacon_id IN (SELECT scope.beacon_id FROM scope)
)''';

  /// §6 `my desk.count` — "sum of request.count", where
  /// `request.count = number of live obligations on it`.
  ///
  /// An integer expression over [cte], beside [myDeskDotExpression] for the
  /// same reason: one definition, every caller. Uncleared optional events are
  /// absent on purpose — they are the *dot*, and D09 keeps the two
  /// independent, so neither may be derived from the other.
  ///
  /// The `surface = 'myWork'` leg is what U15R-d could not write. It was
  /// blocked because a Request-less live obligation was storable and
  /// [visibleWithSurface] labels every beacon-less row `activity`, so scoping
  /// would have made such a row invisible on every §6 indicator. m0191
  /// (`notification_outbox__obligation_beacon_chk`) makes that shape
  /// unstorable, stating the rule `AttentionPolicy.logicalTaskKey` already
  /// enforces. With it in place the leg drops nothing — a live obligation
  /// always names a Request, and the `scope` UNION absorbs any Request a live
  /// obligation names — so it is written because §6 states the rule that way,
  /// not to change the population.
  ///
  /// U18c retired the three legacy totals this was deliberately not a
  /// re-scoping of; §6's rule is now the only one the summary states.
  static String get myDeskCountExpression => '''
SELECT COUNT(*) FILTER (
  WHERE v.surface = 'myWork'
    AND ${liveObligation('v')}
    AND ${primaryPlacement('v')}
)::int AS value
FROM visible v''';

  /// §6 `for you.dot` — "any dismissible attention, pending forward or pending
  /// prompt". Each of the three is a term of its own, composed from the sets
  /// the For-You lists and the sweep already compose (M1).
  ///
  /// The Set R leg carries [primaryPlacement] deliberately: a non-primary
  /// dismissible row is sweepable but is not on the list, and a tab that
  /// lights with nothing to act on is the failure §6's "One predicate"
  /// paragraph exists to prevent.
  static String get forYouDotExpression => '''
EXISTS (
  SELECT 1
  FROM activity_optional_dismissible r
  JOIN visible v ON v.id = r.receipt_id
  WHERE ${primaryPlacement('v')}
)
OR EXISTS (SELECT 1 FROM activity_outcome_dismissible)
OR EXISTS (SELECT 1 FROM eligible_pinned)
-- Pending prompts: a written FALSE, not a missing term. No classified prompt
-- event has a row in any of the sets above yet (U09a, restated in
-- [dismissibleOutcomes]). When one gains a live row this becomes its
-- predicate; until then silence here would be indistinguishable from a
-- predicate somebody deleted.
OR FALSE''';

  /// U16c-1 — "would *Dismiss all* actually clear anything?"
  ///
  /// The enablement rule for the For You header control, and deliberately the
  /// **capture set itself** rather than a third spelling of the membership:
  /// [AttentionSweepRepository.captureSql] selects from exactly these two
  /// CTEs, so the flag is true precisely when that statement returns a row.
  /// `attention_sweep_eligibility_pg_test.dart` asserts that iff against the
  /// live capture SQL — U15R-d's verify pass caught a guard that carried its
  /// own slightly looser copy of the predicate it existed to protect.
  ///
  /// It is **not** [forYouDotExpression]: that carries `eligible_pinned`, so
  /// gating the button on it would light a control when only an unanswered
  /// forward remains, and tapping it would do nothing. Owner decision A keeps
  /// the pin out of the sweep; this keeps it out of the sweep's *affordance*
  /// too, which is the same promise stated once more where the user can see
  /// it.
  ///
  /// It is also **not** the Set R leg of [forYouDotExpression]: that leg
  /// carries [primaryPlacement] because a dot must not light for a row no
  /// list shows, whereas the sweep clears non-primary dismissible rows as
  /// well. Enablement follows the *action*, so it must not narrow what the
  /// action does — a disabled button beside rows the sweep would still clear
  /// is a surface that cannot reach zero (§7).
  static String get forYouSweepEligibleExpression => '''
EXISTS (SELECT 1 FROM activity_optional_dismissible)
OR EXISTS (SELECT 1 FROM activity_outcome_dismissible)''';

  /// Set O — dismissible outcome rows, the `inbox_item` axis.
  ///
  /// `NOT IN eligible_pinned` is the load-bearing exclusion and the entire
  /// margin of owner decision A: an unanswered forward — `status = 0`,
  /// readable, outside the responsibility scope — is awaiting a decision and
  /// must never be a member. Do not "simplify" it away. (For rows that pass
  /// the readability clause below it is equivalent to the projection's
  /// `status <> 0 OR beacon_id IN scope`; stating it as the pinned-zone
  /// exclusion is what makes the intent, and its test, legible.)
  ///
  /// Pending prompts have **no row here at all** yet — see the class-level
  /// note in the U09a journal entry. Until classified prompt events exist,
  /// "awaits a decision" is expressed entirely as these two exclusions:
  /// unanswered forwards (here) and obligations (Set R). A prompt that later
  /// gains a live feed row must be excluded explicitly; it will not fall out
  /// of these predicates by itself.
  static const dismissibleOutcomes = r'''
activity_outcome_dismissible AS (
  SELECT
    ii.beacon_id,
    COALESCE(ars.outcome_generation, 0) AS outcome_generation,
    COALESCE(ars.decision_revision, 0) AS decision_revision
  FROM public.inbox_item ii
  JOIN public.beacon b ON b.id = ii.beacon_id
  LEFT JOIN public.attention_request_state ars
    ON ars.account_id = ii.user_id AND ars.beacon_id = ii.beacon_id
  WHERE ii.user_id = $1
    AND ii.tombstone_dismissed_at IS NULL
    AND ii.beacon_id NOT IN (SELECT beacon_id FROM eligible_pinned)
    AND (
      public.beacon_can_read_content(ii.beacon_id, $1)
      OR (
        ii.status IN (3, 4)
        AND public.beacon_can_read_tombstone(ii.beacon_id, $1)
      )
    )
)''';

  /// Everything above, ready to follow a `WITH`.
  static String get cte =>
      '$prelude,\n$dismissibleReceipts,\n$dismissibleOutcomes';
}
