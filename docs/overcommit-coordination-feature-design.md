# Overcommit coordination — design reference (Phase 1)

Companion to [beacon-evaluation-feature-design.md](./beacon-evaluation-feature-design.md) and [beacon-evaluation-principles.md](./beacon-evaluation-principles.md). Coordination during an **active** beacon is **not** post-close evaluation; it is operational metadata about **coverage of the beacon’s need**, not approval of people.

## Codebase touchpoints (implementation)

| Area | Location |
|------|----------|
| Commit V2 mutations | [`packages/server/lib/api/controllers/graphql/mutation/mutation_commitment.dart`](../packages/server/lib/api/controllers/graphql/mutation/mutation_commitment.dart) — `beaconCommit`, `beaconWithdraw` |
| Commit use case | [`packages/server/lib/domain/use_case/commitment_case.dart`](../packages/server/lib/domain/use_case/commitment_case.dart) |
| Commit persistence | [`packages/server/lib/data/repository/commitment_repository.dart`](../packages/server/lib/data/repository/commitment_repository.dart), table [`beacon_commitments.dart`](../packages/server/lib/data/database/table/beacon_commitments.dart) → Postgres `beacon_commitment` |
| Client commit / fetch | [`packages/client/lib/features/forward/data/repository/forward_repository.dart`](../packages/client/lib/features/forward/data/repository/forward_repository.dart), GQL [`beacon_commit.graphql`](../packages/client/lib/features/forward/data/gql/beacon_commit.graphql), [`commitments_fetch.graphql`](../packages/client/lib/features/forward/data/gql/commitments_fetch.graphql) |
| Beacon detail UI | [`packages/client/lib/features/beacon_view/ui/screen/beacon_view_screen.dart`](../packages/client/lib/features/beacon_view/ui/screen/beacon_view_screen.dart), [`beacon_view_cubit.dart`](../packages/client/lib/features/beacon_view/ui/bloc/beacon_view_cubit.dart) |
| My Work / Inbox | [`my_work_fetch.graphql`](../packages/client/lib/features/my_work/data/gql/my_work_fetch.graphql), [`inbox_fetch.graphql`](../packages/client/lib/features/inbox/data/gql/inbox_fetch.graphql), [`beacon_model.graphql`](../packages/client/lib/data/gql/beacon_model.graphql) |
| V2 routing | [`packages/client/lib/data/service/remote_api_client/build_client.dart`](../packages/client/lib/data/service/remote_api_client/build_client.dart) — `_tenturaDirectOperationNames` |
| Hasura | [`hasura/metadata.json`](../hasura/metadata.json) — track `beacon_commitment_coordination`, new columns on `beacon` / `beacon_commitment` |

---

# Tentura overcommit handling feature spec (Phase 1)

This document defines the minimal V1 feature for handling overcommit and fit mismatch on beacons. It is written as an implementation handoff for a code-building LLM.

The goal is to solve coordination failure caused by:

* multiple people committing at once
* overlapping help
* wrong kind of help
* missing critical skill despite existing commitments
* social awkwardness around backing out

This feature must **not** turn commit into an approval ritual. It must preserve the core V1 rule:

* commit is open by default
* ordinary commits do not require pre-approval

Instead of permissioning, this feature adds **coordination responses** from the beacon author and a **beacon-level coordination status**.

---

## 1. Product goal

When multiple people commit to a beacon, the system should make it clear:

* whether there are any commitments yet
* whether the author has reviewed the current commitments
* whether the current commitments fit the need
* whether more or different help is still needed
* whether the beacon currently has enough help committed

The feature should reduce duplicated work, silent mismatch, unnecessary social friction, ambiguous responsibility, and hidden rejection.

It should **not** create author sovereignty over who may help, membership-like gatekeeping, white/blackball rituals for ordinary commits, or invisible rejection.

---

## 2. Core design principle

Do **not** model this as approval of people. Model it as the author’s current view of **coverage of the beacon’s need**.

* Correct framing: *Does this beacon currently have the help it needs?*
* Wrong framing: *Is this committer approved?*

This distinction must be visible in both data model and UI copy.

---

## 3. Phase 1 scope

**Included:** open commit, public commit note, optional help-type tag on commit, author-side per-commit coordination responses, author-side beacon-level coordination status, My Work / Inbox presentation updates, explicit uncommit flow.

**Not included:** mandatory pre-approval, numeric capacity as main model, collective acceptance ritual, automatic matching, complex partial reservation, skill verification, steward approval, treasury-linked authorization.

---

## 4. Core interaction model

1. **User commits** — optional public note, optional help-type tag; beacon moves to My Work; visible in detail and timeline.
2. **Author reviews** — lightweight coordination responses per commit (coverage / fit, not person-judgment).
3. **System updates beacon-level coordination status** — shown on Inbox row, My Work row, beacon detail.
4. **Committers react** — stay committed, edit note, coordinate via updates, or **uncommit** where lifecycle allows (see §9), with public reason.

---

## 5. Commit model

Commit means explicit responsibility to help, visible commitment, beacon in My Work. It is not a legal contract, not author-approved membership, not guaranteed success.

**Lifecycle (server `beacon.state` / client `BeaconLifecycle`):**

* **Commit (`beaconCommit`)** is allowed only when the beacon is **OPEN** (`state = 0`). Draft, closed, deleted, pending review, and post-close review lifecycles cannot receive new commitments.
* **Beacon-level coordination status does not block commit** — including “enough help committed” (`coordination_status = 3`). Authors signal coverage; the system does not treat that as a lock. A new commit can move derivation back to “commitments waiting for review” (§8 rule 2) when that commit has no author coordination row yet.
* **Author cannot commit** to their own beacon (`authorCannotCommit` on server).
* **Editing an existing active commitment** (note / help type) uses the same `beaconCommit` upsert path when the user already has an active row (still requires OPEN lifecycle).

**Fields (Postgres / app):** `beacon_id`, `user_id`, `created_at`, `status` (active `0` / withdrawn `1` — existing), `message` (public note), `help_type` (optional text key), `uncommit_reason` (set on withdraw).

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
| 0 | No commitments yet |
| 1 | Commitments waiting for review |
| 2 | More or different help needed |
| 3 | Enough help committed |

Framing: author’s current coordination view, not objective truth.

---

## 8. Status derivation (server)

Deterministic rules implemented in `CoordinationCase` / `CoordinationRepository`:

1. **No active commits** → status `0`.
2. **Any active commit without an author coordination row** → status `1`.
3. **Staleness:** if a new active commit appears after the last `coordination_status_updated_at` and still has no response, remain or return to `1` (handled by rule 2).
4. **All commits have responses:** if any response is `overlapping`, `need_different_skill`, `need_coordination`, or `not_suitable` → status `2`.
5. **All responses `useful` only** → status `3` (sufficient coverage signal for Phase 1; author may still call `setBeaconCoordinationStatus` to force `2` or `3` where product requires).

On **uncommit**, delete coordination row for that commit (if any) and re-derive.

---

## 9. Uncommit flow

**Withdraw (`beaconWithdraw`)** sets commitment `status = 1` (withdrawn), requires **uncommit reason** (tag + optional note in message field). Timeline remains legible; beacon-level status recomputes.

**Lifecycle gate:** uncommit is **not** allowed when the beacon is **CLOSED** (`state = 1`), **DRAFT** (`3`), **DELETED** (`2`), or **CLOSED_REVIEW_COMPLETE** (`6`). It **is** allowed for **OPEN** (`0`), **PENDING_REVIEW** (`4`), and **CLOSED_REVIEW_OPEN** (`5`). Server throws `beaconWithdrawForbidden` when blocked; client disables the withdraw control in the same cases.

---

## 10. V2 GraphQL (client must route to `/api/v2/graphql`)

**Extended mutations:** `beaconCommit(id, message, helpType)`, `beaconWithdraw(id, message, uncommitReason)`.

**New:** `setCoordinationResponse(beaconId, commitUserId, responseType)`, `setBeaconCoordinationStatus(beaconId, status)`, `commitmentsWithCoordination(beaconId)`.

---

## 11. Social safeguards & copy

Avoid: Approved, Rejected, Invalid, Commit denied.

Prefer: coverage, fit, overlap, coordination language from the product spec.

When coordination status is **enough help committed**, still allow commit in UI but **soften** the primary action copy (e.g. “Offer help anyway”) so openness is preserved without implying the beacon obviously needs more people.

---

## 12. Relation to evaluation

Author coordination responses are **not** reviews. Evaluation (post-close) is documented in [beacon-evaluation-feature-design.md](./beacon-evaluation-feature-design.md). Coordination rows must not feed public reputation surfaces.

---

## 13. Acceptance criteria (Phase 1)

* Users can commit without pre-approval; optional public note and help-type.
* Authors can set per-commit coordination responses.
* One beacon-level coordination status is exposed and updated deterministically.
* New unreviewed commits push status toward waiting for review.
* Committed beacons appear in My Work; uncommit is explicit.
* UX reads as practical coordination, not gatekeeping.
