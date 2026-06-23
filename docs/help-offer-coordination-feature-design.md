# Over-offer coordination — design reference (Phase 1)

Companion to [beacon-evaluation-feature-design.md](./beacon-evaluation-feature-design.md) and [beacon-evaluation-principles.md](./beacon-evaluation-principles.md). Coordination during an **active** beacon is **not** post-close evaluation; it is operational metadata about **coverage of the beacon’s need**, not approval of people.

## Codebase touchpoints (implementation)

| Area | Location |
|------|----------|
| Commit V2 mutations | [`packages/server/lib/api/controllers/graphql/mutation/mutation_help_offer.dart`](../packages/server/lib/api/controllers/graphql/mutation/mutation_help_offer.dart) — `beaconOfferHelp`, `beaconWithdraw` |
| Commit use case | [`packages/server/lib/domain/use_case/help_offer_case.dart`](../packages/server/lib/domain/use_case/help_offer_case.dart) |
| Commit persistence | [`packages/server/lib/data/repository/help_offer_repository.dart`](../packages/server/lib/data/repository/help_offer_repository.dart), table [`beacon_help_offers.dart`](../packages/server/lib/data/database/table/beacon_help_offers.dart) → Postgres `beacon_help_offer` |
| Client commit / fetch | [`packages/client/lib/features/forward/data/repository/forward_repository.dart`](../packages/client/lib/features/forward/data/repository/forward_repository.dart), GQL [`beacon_offer_help.graphql`](../packages/client/lib/features/forward/data/gql/beacon_offer_help.graphql), [`beacon_withdraw.graphql`](../packages/client/lib/features/forward/data/gql/beacon_withdraw.graphql), [`help_offers_fetch.graphql`](../packages/client/lib/features/forward/data/gql/help_offers_fetch.graphql), [`help_offers_with_coordination.graphql`](../packages/client/lib/features/beacon_view/data/gql/help_offers_with_coordination.graphql) |
| Beacon detail UI | [`packages/client/lib/features/beacon_view/ui/screen/beacon_view_screen.dart`](../packages/client/lib/features/beacon_view/ui/screen/beacon_view_screen.dart), [`beacon_view_cubit.dart`](../packages/client/lib/features/beacon_view/ui/bloc/beacon_view_cubit.dart), closure readiness helper [`beacon_closure_readiness.dart`](../packages/client/lib/features/beacon_view/ui/util/beacon_closure_readiness.dart) |
| My Work / Inbox | [`my_work_fetch.graphql`](../packages/client/lib/features/my_work/data/gql/my_work_fetch.graphql), [`inbox_fetch.graphql`](../packages/client/lib/features/inbox/data/gql/inbox_fetch.graphql), [`beacon_model.graphql`](../packages/client/lib/data/gql/beacon_model.graphql) |
| V2 routing | [`packages/client/lib/data/service/remote_api_client/build_client.dart`](../packages/client/lib/data/service/remote_api_client/build_client.dart) — `_tenturaDirectOperationNames` |
| Hasura | [`hasura/metadata.json`](../hasura/metadata.json) — track `beacon_help_offer_coordination`, new columns on `beacon` / `beacon_help_offer` |

---

# Tentura over-offer handling feature spec (Phase 1)

This document defines the minimal V1 feature for handling over-offer and fit mismatch on beacons. It is written as an implementation handoff for a code-building LLM.

The goal is to solve coordination failure caused by:

* multiple people committing at once
* overlapping help
* wrong kind of help
* missing critical skill despite existing help offers
* social awkwardness around backing out

This feature must **not** turn commit into an approval ritual. It must preserve the core V1 rule:

* commit is open by default
* ordinary commits do not require pre-approval

Instead of permissioning, this feature adds **coordination responses** from the beacon author and a **beacon-level coordination status**.

---

## 1. Product goal

When multiple people commit to a beacon, the system should make it clear:

* whether there are any help offers yet
* whether the author has reviewed the current help offers
* whether the current help offers fit the need
* whether more or different help is still needed
* whether the beacon currently has enough help offered help

The feature should reduce duplicated work, silent mismatch, unnecessary social friction, ambiguous responsibility, and hidden rejection.

It should **not** create author sovereignty over who may help, membership-like gatekeeping, white/blackball rituals for ordinary commits, or invisible rejection.

---

## 2. Core design principle

Do **not** model this as approval of people. Model it as the author’s current view of **coverage of the beacon’s need**.

* Correct framing: *Does this beacon currently have the help it needs?*
* Wrong framing: *Is this helper approved?*

This distinction must be visible in both data model and UI copy.

---

## 3. Phase 1 scope

**Included:** open commit, public commit note, optional help-type tag on commit, author-side per-commit coordination responses, author-side beacon-level coordination status, My Work / Inbox presentation updates, explicit withdraw flow.

**Not included:** mandatory pre-approval, numeric capacity as main model, collective acceptance ritual, automatic matching, complex partial reservation, skill verification, steward approval, treasury-linked authorization.

---

## 4. Core interaction model

1. **User commits** — optional public note, optional help-type tag; beacon moves to My Work; visible in detail and timeline.
2. **Author reviews** — lightweight coordination responses per commit (coverage / fit, not person-judgment).
3. **System updates beacon-level coordination status** — shown on Inbox row, My Work row, beacon detail.
4. **Helpers react** — stay offered help, edit note, coordinate via updates, or **withdraw** where lifecycle allows (see §9), with public reason.

---

## 5. Commit model

Commit means explicit responsibility to help, visible help offer, beacon in My Work. It is not a legal contract, not author-approved membership, not guaranteed success.

**Lifecycle (server `beacon.state` / client `BeaconLifecycle`):**

* **Commit (`beaconOfferHelp`)** is allowed only when the beacon is **OPEN** (`state = 0`). Draft, closed, deleted, pending review, and post-close review lifecycles cannot receive new help offers.
* **Beacon-level coordination status does not block commit** — including “enough help offered help” (`coordination_status = 3`). Authors signal coverage; the system does not treat that as a lock. A new commit can move derivation back to “help offers waiting for review” (§8 rule 2) when that commit has no author coordination row yet.
* **Author cannot commit** to their own beacon (`authorCannotCommit` on server).
* **Editing an existing active help offer** (note / help type) uses the same `beaconOfferHelp` upsert path when the user already has an active row (still requires OPEN lifecycle).

**Fields (Postgres / app):** `beacon_id`, `user_id`, `created_at`, `status` (active `0` / withdrawn `1` — existing), `message` (public note), `help_type` (optional text key), `withdraw_reason` (set on withdraw).

**Help-type tags (suggested):** Money, Time, Skill, Verification, Contact / intro, Transport, Other — stored as stable string keys (e.g. `money`, `time`, …).

---

## 6. Author-side coordination responses

Per active commit, author may set one of: **Useful**, **Overlapping**, **Need different skill**, **Need coordination**, **Not suitable**, or **unset** (no row).

These are beacon-local coordination signals; avoid punitive red/green styling.

---

## 7. Beacon-level coordination status

**Values (stored as `smallint` on `beacon`):**

| Int | Meaning |
|-----|--------|
| 0 | No help offers yet |
| 1 | Help offers waiting for review |
| 2 | More or different help needed |
| 3 | Enough help offered help |

Framing: author’s current coordination view, not objective truth.

---

## 8. Status derivation (server)

Deterministic rules implemented in `CoordinationCase` / `CoordinationRepository`:

1. **No active commits** → status `0`.
2. **Any active commit without an author coordination row** → status `1`.
3. **Staleness:** if a new active commit appears after the last `coordination_status_updated_at` and still has no response, remain or return to `1` (handled by rule 2).
4. **All commits have responses:** if any response is `overlapping`, `need_different_skill`, `need_coordination`, or `not_suitable` → status `2`.
5. **All responses `useful` only** → status `3` (sufficient coverage signal for Phase 1; author may still call `setBeaconCoordinationStatus` to force `2` or `3` where product requires).

On **withdraw**, delete coordination row for that commit (if any) and re-derive.

---

## 9. Withdraw flow

**Withdraw (`beaconWithdraw`)** sets help offer `status = 1` (withdrawn), requires **withdraw reason** (tag + optional note in message field). Timeline remains legible; beacon-level status recomputes.

**Lifecycle gate:** withdraw is **not** allowed when the beacon is **CLOSED** (`state = 1`), **DRAFT** (`3`), **DELETED** (`2`), or **CLOSED_REVIEW_COMPLETE** (`6`). It **is** allowed for **OPEN** (`0`), **PENDING_REVIEW** (`4`), and **CLOSED_REVIEW_OPEN** (`5`). Server throws `beaconWithdrawForbidden` when blocked; client disables the withdraw control in the same cases.

---

## 10. V2 GraphQL (client must route to `/api/v2/graphql`)

**Extended mutations:** `beaconOfferHelp(id, message, helpTypes)`, `beaconWithdraw(id, message, withdrawReason)`.

**New:** `setCoordinationResponse(beaconId, commitUserId, responseType)`, `setBeaconCoordinationStatus(beaconId, status)`, `helpOffersWithCoordination(beaconId)`.

---

## 11. Social safeguards & copy

Avoid: Approved, Rejected, Invalid, Commit denied.

Prefer: coverage, fit, overlap, coordination language from the product spec.

When coordination status is **enough help offered help**, still allow commit in UI but **soften** the primary action copy (e.g. “Offer help anyway”) so openness is preserved without implying the beacon obviously needs more people.

---

## 12. Relation to evaluation

Author coordination responses are **not** reviews. Evaluation (post-close) is documented in [beacon-evaluation-feature-design.md](./beacon-evaluation-feature-design.md). Coordination rows must not feed public reputation surfaces.

---

## 13. Acceptance criteria (Phase 1)

* Users can commit without pre-approval; optional public note and help-type.
* Authors can set per-commit coordination responses.
* One beacon-level coordination status is exposed and updated deterministically.
* New unreviewed commits push status toward waiting for review.
* Help Offered beacons appear in My Work; withdraw is explicit.
* UX reads as practical coordination, not gatekeeping.

---

## 14. Author closure readiness (HUD — presentation-only)

Closure readiness is **derived presentation** from existing beacon view state (coordination status, help offers + coordination responses, room participant rows, room cue blockers, structured activity events). **Server mutations remain authoritative** for whether close succeeds.

**Implementation:** [`packages/client/lib/features/beacon_view/ui/util/beacon_closure_readiness.dart`](../packages/client/lib/features/beacon_view/ui/util/beacon_closure_readiness.dart) (`BeaconClosureReadiness`, `ClosureActionPriority`, `computeClosureReadiness`).

### Hard gates

Author **Close** is suppressed unless: the viewer owns the beacon; lifecycle is **open**; view state has loaded successfully with a non-empty author id; the cubit is not in a global loading state. (Delegated non-author closers are a future extension.)

### Blocking signals (`blocked`)

* Open blocker title present on room state cue (`beacon_room_state`).
* Beacon coordination status **more or different help needed** (`coordination_status = 2`).
* Author’s room participant row has status **needsInfo** (v1 proxy for “need-info targeted at the author”).
* For each **relevant** help offer (non-withdrawn; coordination response not `not_suitable` / `overlapping`), the matching participant row: status **blocked**, or **needsInfo** when that participant is the beacon author.

### v1 need-info policy

Helper-targeted **needsInfo** (without the author row being in **needsInfo**) **does not** block primary Close. A future `needInfoBlocksClosure` (or equivalent) field should refine this.

### Positive completion signals

* **Whole-beacon done:** `beacon_activity_event` type `doneMarked` with JSON `diff_json` containing `scope: wholeBeacon` or `target: wholeBeacon`. Payloads such as `{kind: message}` (message-level mark-done) **do not** count as whole-beacon completion for this derivation.
* **Ready path without whole-beacon flag:** coordination status **enough help offered help** **and** at least one relevant help offer shows a **useful** coordination response or participant **done** / `next_move_status` done **and** every relevant help offer is in a settled terminal state per the helper (see code).

Ordinary chat / timeline text is never parsed for closure.

### Product flag

[`kBeaconAllowForceCloseWhenBlocked`](../packages/client/lib/consts.dart): when `false`, `blocked` readiness maps Close to **hidden** (HUD rail + app-bar overflow). When `true`, Close may appear only in overflow (“close anyway” semantics remain confirmation-gated in UI).

### Server / schema follow-ups

* Emit structured `diff_json` for true beacon-scope done when that product action exists.
* Optional `needInfoBlocksClosure` (or targeting metadata) to replace the author-row proxy for need-info blocking.
* Steward / delegated closer permission OR-ed into the hard gate when supported.
