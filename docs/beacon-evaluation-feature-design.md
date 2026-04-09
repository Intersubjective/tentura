# Beacon evaluation feature — design reference (Phase 1)

Companion to [beacon-evaluation-principles.md](./beacon-evaluation-principles.md). This document records the **implemented architecture**, data model, eligibility rules, privacy behavior, UI surfaces, and test plan.

## Product framing

- **Close the loop** / **Acknowledge contributions** / **How did this contribution affect this beacon?**
- Never: 360 review, rating people, reputation, leaderboards.

**Not the same as overcommit coordination:** During an **open** beacon, authors may set per-commit **coordination responses** and a beacon-level **coordination status** (coverage / fit of the need — not “approval” of committers). That feature is documented in [`overcommit-coordination-feature-design.md`](./overcommit-coordination-feature-design.md). Evaluation here applies **after** successful closure and the review window; coordination metadata during active work may provide context later but is **not** an evaluation submission.

**Not the same as Watching:** The inbox **Watching** stance ([`docs/v1/watching-mechanism.md`](./v1/watching-mechanism.md)) does **not** by itself confer evaluation eligibility; eligibility follows the participant and visibility rules in this document only.

## Phase 1 scope

- Successful closure **by beacon author** only (`beaconCloseWithReview` V2 mutation).
- Roles: **author**, **committers** (active `beacon_commitment` at closure), **adjacent forwarders** only (see below).
- Excluded: dead-branch forwarders, failed/disputed closures, reopened beacons (Phase 2), stewards, cross-beacon summaries.

## Beacon lifecycle values (`beacon.state` smallint)

| Value | Enum | Meaning |
|------|------|--------|
| 0–4 | (existing) | open, closed, deleted, draft, pending_review |
| **5** | `closedReviewOpen` | Review window open |
| **6** | `closedReviewComplete` | Review window ended |

- `isActiveSection` (client): open, draft, pendingReview, **closedReviewOpen** (needs user action in My Work).
- `isClosedSection`: closed, deleted, **closedReviewComplete** (and legacy closed/deleted as before).

## Core flow

### Phase A — active beacon (draft pre-flow)

While `beacon.state = 0` (open), eligible users may save **private draft** evaluations via **`evaluationDraftSave`** (memory aids only). Drafts:

- are private to the drafter
- do not count toward summaries until explicitly submitted after closure
- are validated at closure: rows whose (evaluator, evaluated) pair is **not** in the frozen visibility set are **deleted**

**Queries:** `evaluationDrafts(beaconId)` — current user’s drafts for that beacon.  
**Mutations:** `evaluationDraftSave`, `evaluationDraftDelete`.

### Phase B — author closes successfully

1. Author invokes **`beaconCloseWithReview`** → server sets state **5**, opens review window, materializes participants + visibility, creates per-user review status, preserves valid drafts / drops invalid ones, sends **one** FCM per eligible user (dev: no-op mock).
2. Eligible users complete **`evaluationSubmit`** / **`evaluationFinalize`** / **`evaluationSkip`** during the window. Submitted rows use **`beacon_evaluation.status = submitted`** (1).
3. On window expiry (`closes_at`), server sets window **closed**, beacon state **6**, expires pending user statuses; **submitted** evaluation rows become **final** (2); remaining **draft** rows (never submitted) are removed without effect.

### Phase C — after freeze

Summaries computed on read with **k-anonymity** (see Privacy). Only **submitted** and **final** rows participate in aggregates (not draft).

## Per-evaluation item states (`beacon_evaluation.status`)

| Int | Meaning |
|-----|---------|
| 0 | `draft` — pre-closure memory aid or unsubmitted during window |
| 1 | `submitted` — saved during open review window |
| 2 | `final` — window closed; submission frozen |
| 3 | `responded` — reserved (Phase 2 response window) |

## Data model (Postgres)

| Table | Purpose |
|-------|---------|
| `beacon_review_window` | One row per beacon: `opened_at`, `closes_at`, `status` (open/complete). |
| `beacon_evaluation_participant` | Frozen eligibility + `contribution_summary` + `causal_hint` per user. |
| `beacon_evaluation_visibility` | Evaluator × evaluatee pairs allowed for Phase 1. |
| `beacon_evaluation` | Private raw row: evaluator, evaluated, `value`, `reason_tags`, `note`, **`status`**. |
| `beacon_review_status` | Per user: not_started / in_progress / submitted / skipped / expired. |

## Evaluation value encoding (DB `beacon_evaluation.value`)

| Int | Meaning |
|-----|---------|
| 0 | NO_BASIS |
| 1 | NEG_2 |
| 2 | NEG_1 |
| 3 | ZERO |
| 4 | POS_1 |
| 5 | POS_2 |

**Reason tags:** required for **NEG_2, NEG_1, POS_2**; optional for **ZERO, POS_1**; not used for **NO_BASIS** (reject if tags sent).

## Eligibility — participants

1. **Author** `A` = `beacon.user_id`.
2. **Committers** = users with active commitment (`status = 0`) at closure.
3. **Adjacent forwarder** for committer `C`: among edges with `recipient_id = C`, take the **latest** by `created_at` (direct forward into committer). `sender_id` is the adjacent forwarder `F`. Add `F` to the set (dedupe).

`participants = {A} ∪ committers ∪ adjacent_forwarders`.

## Eligibility — visibility (who may evaluate whom)

For participants `E` (evaluator) and `P` (evaluated), `E ≠ P`:

- **Author** may evaluate: every committer; every **forwarder** participant (adjacent only; they are already filtered).
- **Committer `C`** may evaluate: author `A`; **every other committer**; the **forwarder who sent to `C`** (sender of chosen edge to `C`), if that user is a participant and ≠ `C`.
- **Forwarder `F`** may evaluate: **author `A`**; each **committer `C`** such that `F` is the adjacent forwarder for `C` (edge `F → C`).

No other pairs are inserted into `beacon_evaluation_visibility`.

### Restricted prompt: forwarder → committer

When `F` evaluates downstream committer `C`, the UI uses **handoff** prompt variant (not full committer rubric). Server exposes `promptVariant: "handoff" | "full"` on each card in **`evaluationParticipants`**.

## Privacy: evaluated-user summary

- Aggregates **only** rows where `value != 0` (NO_BASIS excluded) and **`status` ≥ 1** (submitted/final; never draft).
- Let **N** = count of **distinct evaluators** with at least one qualifying row.
- If **N < 3**: return **suppressed** summary (tone-only copy, no bucket counts, no reason-tag breakdown).
- If **N ≥ 3**: tone + bucket counts + top reason tags (still **no** per-evaluator or named data).

## V2 GraphQL (client routed via `_tenturaDirectOperationNames`)

**Queries:** `evaluationParticipants`, `evaluationSummary`, `reviewWindowStatus`, `evaluationDrafts`  
**Mutations:** `evaluationSubmit`, `evaluationFinalize`, `evaluationSkip`, `beaconCloseWithReview`, `evaluationDraftSave`, `evaluationDraftDelete`

## Client integration

- **Beacon detail (open):** banner for draft-eligible users; primary CTA **Draft review** → draft flow (same route as review, draft mode).
- **Beacon detail (state 5):** banner; primary CTA **Review**; no secondary “Later” (deferral = review window + drafts).
- **Beacon detail (state 6):** summary card when summary available.
- **Author close:** `beaconCloseWithReview` instead of Hasura-only close for the happy path.
- **My Work / profile lists:** active states include **5**; closed states include **6** (and **1**, **2** as before).

### Required microcopy (l10n)

- Extended privacy block on **Acknowledge contributions** screen (private, not public, personal trust calibration, judge only what you saw, use “No basis” if unsure).
- Evaluation detail: helper lines for private beacon-local feedback.
- Empty / clean submission: confirmation per product spec where applicable.

## Notifications

- At window open: one FCM to each eligible participant (prod).
- Reminder: optional stub — full scheduler TBD; may be wired via `reviewWindowStatus` + client local reminder later.

## Reason tag constants (Phase 1)

Stored as comma-separated keys; validated server-side against role-specific allowlists.

See implementation: `packages/server/lib/domain/evaluation/evaluation_reason_tags.dart`.

## UX corner cases (Phase 1 handling)

- **No basis vs zero:** distinct values and copy; server rejects tags on NO_BASIS.
- **Tiny N:** summary suppression when distinct evaluators &lt; 3.
- **Forwarder → committer:** handoff-only prompt variant; same tag sets as full committer evaluation for validation.
- **Drafts never submitted:** dropped or non-counting at window end.

## References

- Principles: [beacon-evaluation-principles.md](./beacon-evaluation-principles.md)
