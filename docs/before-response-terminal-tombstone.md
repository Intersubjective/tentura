# Before-response terminal state and tombstone inbox cards

Canonical product and implementation reference for when a beacon becomes **terminal** before the recipient takes an **explicit** triage stance (Watching, Not for me, commit, etc.).

## Purpose

Preserve two truths at once:

1. The beacon is **no longer actionable** for triage.
2. The user **never chose a stance** — opening the beacon, reading forwards, or seeing a draft does **not** count.

When those truths conflict with convenience, **preserve truth**. The system must not infer Watching, Not for me, My Work ownership, or forwarded involvement from silence.

## Data model (Phase 1)

- **`inbox_item.status`** extends [`InboxItemStatus`](../packages/client/lib/features/inbox/domain/enum.dart):
  - `3` — **closed_before_response** (beacon left the open triage window without the user acting).
  - `4` — **deleted_before_response** (lifecycle deleted, or upgraded from `3` when the beacon is later deleted).
- **`before_response_terminal_at`** — set when the row first enters `3` or `4` (used for “last 24h” grouping and sorting).
- **`tombstone_dismissed_at`** — when set, the passive card is **hidden** in the inbox UI. Dismiss does **not** change `status` or stance history.

**Hard SQL delete of `beacon` rows:** `inbox_item` references `beacon` with `ON DELETE CASCADE`. Phase 1 tombstones assume **lifecycle** `deleted` (`beacon.state = 2`) with the **beacon row still present** so titles and detail links remain joinable. Hard deletes that remove the beacon row are out of scope for tombstone UX until snapshotting or FK strategy changes.

## When rows become terminal (server)

On `beacon.state` transition, for each `inbox_item` with `beacon_id = beacon.id`:

- Eligible only if **`status = 0` (needs_me)** and the user has **no active** `beacon_commitment` (`status = 0` on commitment).
- **Do not** change rows that are already **watching** (`1`) or **rejected** (`2`).

Mappings:

- New state **`1` (closed)**, **`5` (closed review open)**, or **`6` (closed review complete)** from **`0` (open)`** → set `status = 3`, set `before_response_terminal_at` if null.
- New state **`2` (deleted)** → set `status = 4` (from `0`, or upgrade from `3` to `4`).
- **`5` → `6` (review window ends)** — if `inbox_item.status = 1` (**Watching**) and the user has a **withdrawn** `beacon_commitment` (`status = 1`) and **no active** commitment (`status = 0`), set `status = 3`. This matches users who **committed then withdrew**: `beaconWithdraw` calls `upsertWatchingForSender`, which is **not** the same as explicitly choosing Watching before closure (see watching doc); once the beacon reaches **review complete**, they should see a **passive tombstone**, not a triage-style Watching row. Users who chose **Watching** without ever having a commitment row keep **Watching** (Case 6).

**Withdraw (`beaconWithdraw`)** when the beacon is **not OPEN** (`state <> 0`): the server calls `inbox_item_apply_tombstone_after_withdraw` so the inbox row becomes **`closed_before_response` / `deleted_before_response`** instead of **`upsertWatchingForSender`** (which would leave a triage-style **Watching** row on a terminal beacon). Open beacons (`state = 0`) still use Watching after withdraw.

Logic lives in Postgres (see migrations `m0024`–`m0026`) and [`CommitmentCase.withdraw`](../packages/server/lib/domain/use_case/commitment_case.dart) so all writers behave consistently.

## UI (Flutter)

- **Needs me** tab: above actionable cards, a **Resolved beacons** section (chip **Last 24h**) lists non-dismissed tombstones with `before_response_terminal_at` in the last 24 hours.
- **Card** (mockup-aligned): muted surface, context/org line, title (or generic copy for sensitive deletion), status pill, icon + primary/secondary message, **Dismiss** and **Open** (read-only detail / beacon view as allowed).
- **Tone:** informational, low drama — not error styling.
- **Deletion / privacy:** prefer generic **“No longer available”** when the product must conceal title or summary.

## Dismiss mutation

Clients call a dedicated GraphQL mutation that sets **`tombstone_dismissed_at`** only (Hasura `update_inbox_item`). Row-level permissions restrict this to `status IN (3, 4)`.

## Corner cases (headlines)

| Area | Rule |
|------|------|
| Explicit stance | Watching, rejected, commitment, forward-committed paths **override** before-response derivation. |
| Offline / sync | On sync, derive from stored stance + latest beacon lifecycle; explicit stance wins. |
| Dismiss | Hides continuity artifact only; does not rewrite history. |
| Recipient lists | Silent recipients must not appear as if they chose Watching / Not for me. |
| Volume | Do not flood inbox; filter by time window; future: grouped Updates/Activity. |

## Appendix: full corner-case matrix

1. **Inbox, never opened, author closes** — remove from actionable queue; optional tombstone; `closed_before_response`; no Watching.
2. **Opened detail, no action, author closes** — same as (1).
3. **Saw forwards, no action, author closes** — same as (1).
4. **Local draft review without stance** — Phase 1: treat as no stance unless another explicit action was submitted.
5. **Author deletes (lifecycle) before reaction** — `deleted_before_response`; generic passive copy; unsafe rationale not exposed.
6. **User moved to Watching before closure** — not before-response; keep Watching; update lifecycle only.
7. **User forwarded but did not commit, then closes** — not before-response; keep forward stance.
8. **User committed, then closes** — normal My Work / closure flow.
9. **Not for me, then closes** — keep rejected semantics; do not overwrite with before-response.
10. **Closes while offline** — on sync, deterministic from stance + lifecycle.
11. **Push only, never opens app** — valid before-response; tombstone may appear when app opens.
12. **Lost visibility via MR/context before reacting** — future: `unavailable_before_response`; Phase 1 optional.
13. **Closed then reopened before sync** — reopening out of scope; authoritative lifecycle wins on sync.
14. **Deleted after closure, never reacted** — prefer latest terminal reason; safest user copy “No longer available”.
15. **User dismisses tombstone** — hide only; relation state unchanged.
16–18. **Alice/Bob forward chains** — do not label silent Bob as Watching/NFM; explicit Bob stance may be visible to Alice when Bob actually chose it.
19. **Many dead beacons** — group/dismiss; read-only detail access.
20. **Privacy-sensitive deletion** — generic label; conceal title/summary if required.
21. **Benign closure** — tombstone must not look alarming.

## Non-goals (Phase 1)

Dispute over obligation to act, blame, inferred recommendations from silence, public non-response metrics.

## Acceptance criteria

- No-explicit-stance truth preserved for before-response cases.
- Explicit stance always overrides before-response derivation.
- Recipient lists do not mislabel silent users.
- Tombstone behavior is passive; dismissal does not rewrite history.

## Related documents

- [`docs/v1/product-decisions.md`](v1/product-decisions.md) — inbox locks and document map.
- [`docs/v1/watching-mechanism.md`](v1/watching-mechanism.md) — Watching vs triage.
- [`docs/overcommit-coordination-feature-design.md`](overcommit-coordination-feature-design.md) — commit gates and lifecycle.

## Implementation pointers

- Migration: [`packages/server/lib/data/database/migration/m0024.dart`](../packages/server/lib/data/database/migration/m0024.dart)
- Drift table: [`packages/server/lib/data/database/table/inbox_items.dart`](../packages/server/lib/data/database/table/inbox_items.dart)
- Client inbox: [`packages/client/lib/features/inbox/`](../packages/client/lib/features/inbox/)
