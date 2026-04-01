# Beacon evaluation feature — design reference (Phase 1)

Companion to [beacon-evaluation-principles.md](./beacon-evaluation-principles.md). This document records the **implemented architecture**, data model, eligibility rules, privacy behavior, UI surfaces, and test plan.

## Product framing

- **Close the loop** / **Acknowledge contributions** / **How did this contribution affect this beacon?**
- Never: 360 review, rating people, reputation, leaderboards.

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

1. Author invokes **`beaconCloseWithReview`** → server sets state **5**, opens review window, materializes participants + visibility, creates per-user review status, sends **one** FCM per eligible user (dev: no-op mock).
2. Eligible users complete **`evaluationSubmit`** / **`evaluationFinalize`** / **`evaluationSkip`** during the window.
3. On window expiry (`closes_at`), server sets window **closed**, beacon state **6**, expires pending statuses; summaries computed on read with **k-anonymity** (see Privacy).

## Data model (Postgres)

| Table | Purpose |
|-------|---------|
| `beacon_review_window` | One row per beacon: `opened_at`, `closes_at`, `status` (open/complete). |
| `beacon_evaluation_participant` | Frozen eligibility + `contribution_summary` + `causal_hint` per user. |
| `beacon_evaluation_visibility` | Evaluator × evaluatee pairs allowed for Phase 1. |
| `beacon_evaluation` | Private raw row: evaluator, evaluated, value, reason tags, note. |
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
- **Committer `C`** may evaluate: author `A`; the **forwarder who sent to `C`** (sender of chosen edge to `C`), if that user is a participant and ≠ `C`.
- **Forwarder `F`** may evaluate: each **committer `C`** such that `F` is the adjacent forwarder for `C` (edge `F → C`).

No other pairs are inserted into `beacon_evaluation_visibility`.

## Privacy: evaluated-user summary

- Aggregates **only** rows where `value != 0` (NO_BASIS excluded from signal).
- Let **N** = count of **distinct evaluators** with at least one qualifying row.
- If **N < 3**: return **suppressed** summary (tone-only copy, no bucket counts, no reason-tag breakdown).
- If **N ≥ 3**: tone + bucket counts + top reason tags (still **no** per-evaluator or named data).

## V2 GraphQL (client routed via `_tenturaDirectOperationNames`)

**Queries:** `evaluationParticipants`, `evaluationSummary`, `reviewWindowStatus`  
**Mutations:** `evaluationSubmit`, `evaluationFinalize`, `evaluationSkip`, `beaconCloseWithReview`

## Client integration

- **Beacon detail:** banner when state **5** and user has ≥1 visible card; summary card when state **6** and summary not empty.
- **Author close:** `beaconCloseWithReview` instead of Hasura-only close for the happy path.
- **My Work / profile lists:** active states include **5**; closed states include **6** (and **1**, **2** as before).

## Notifications

- At window open: one FCM to each eligible participant (prod).
- Reminder: optional stub — full scheduler TBD; may be wired via `reviewWindowStatus` + client local reminder later.

## Reason tag constants (Phase 1)

Stored as comma-separated keys; validated server-side against role-specific allowlists.

See implementation: `packages/server/lib/domain/evaluation/evaluation_reason_tags.dart` (or equivalent).

## References

- Principles: [beacon-evaluation-principles.md](./beacon-evaluation-principles.md)
- Implementation plan: workspace plan `beacon_evaluation_feature` (do not edit from code)
