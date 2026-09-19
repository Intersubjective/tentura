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
  static const dismissibleReceipts = '''
activity_optional_dismissible AS (
  SELECT v.id AS receipt_id, v.beacon_id
  FROM visible v
  WHERE v.surface = 'activity'
    AND NOT v.requires_action
    AND v.cleared_at IS NULL
    AND v.presentation_key IS DISTINCT FROM 'relay_received'
)''';

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
  static const cte = '$prelude,\n$dismissibleReceipts,\n$dismissibleOutcomes';
}
