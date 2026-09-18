---
status: draft
kind: architecture
---
# Availability / request-receptiveness — architecture

**Status:** architecture draft, **rev 3**, awaiting approval. **Shape only** — no implementation
steps, no unit breakdown, no migration numbering, no file-by-file task list. Decisions
**D1–D30** are binding on any implementation plan derived from this document. §15 lists what
still needs product sign-off.

**Revision history**

**rev 3** (2026-08-13) — third adversarial pass
([codex, `architecture_reviewer` posture](availability-review-codex.md)) found four blocking
defects, three of them introduced *by rev 2 while fixing rev 1*. All are closed here, and the
product decision below closed the one that cascaded.

**Product decision: the temporal contract is a UTC-date boundary.** Rev 2 tried to have both an
exact subject-local expiry instant and a leak-free bare `date` on the wire; those are mutually
exclusive, because a date without a zone does not identify an instant. Rev 3 stores and exposes
a single `resume_on` **date**, meaning *the first UTC day on which this person is available
again*. Every reader — client and server — derives expiry from that one value, so the shared
`effectiveAt` of D3 is real again and invariant 1 is checkable. The cost is an honest, bounded
skew (§4).

That choice dissolved two further blockers. Splitting the write API into three single-purpose
mutations (D9) removes the "omitted vs null" problem entirely rather than working around a
Ferry/coercer limitation, **and** removes the lost-update race, because no mutation
read-modify-writes a field it does not own. Separately, `createBatch` turned out to already run
inside a transaction and already return the inserted recipient pairs
(`forward_edge_repository.dart:94-147`), so the atomic forward gate (D10) and the typed delivery
result (D23) are far cheaper than the review assumed.

**rev 2** (2026-08-13) — two independent reviews ([grok-4.6](availability-review-grok46.md),
[kimi-k3](availability-review-kimik3.md)) both found rev 1's §11 was written against dead code
(`computeBeaconListSections`, zero call sites, per ADR 0004 Amendment E). Also corrected:
`user_presence` is `UNLOGGED` with a per-user creation trigger, so "exact structural clone" was
wrong and dangerous; the read-path inventory missed three of five payload builders; a new V2
mutation must be registered in `_tenturaDirectOperationNames`; D20 cited a formatter that renders
no weekday. **Model changed** on the product decision that *"be selective with me" is a permanent
state — semantically distinct from "don't bother", which is time-limited*: `limited` and `paused`
became orthogonal fields rather than values of one enum.

**rev 1** — initial design.

**Scope:** a per-user signal answering *"is it appropriate to involve this person in a new
request right now?"* — expressed as **the subject's own control over incoming forwards**.
Not free/busy, not capacity, not presence, not a schedule.

---

## 0. One-page summary

Tentura already asks this question and answers it badly: the Forward recipient row shows
**`Last seen 3d ago`** — a presence line — as the only per-person hint next to the checkbox.
That reports *observed activity*, which the subject does not control and which does not answer
the question the picker is asking. So this is a **substitution, not an addition**.

Two independent things:

| | Kind | Field | Expires | Blocks |
|---|---|---|---|---|
| **Only important requests** | standing disposition | `is_limited` (bool) | **never** | no |
| **Not taking new requests** | temporary episode | `resume_on` (**date**) | **always** (≤ 90d) | yes |

Neither set ⇒ **open**, which stores no row and renders nothing to others. Both may be set at
once; the pause wins while live and falls back to `limited` when it lapses.

`resume_on` is a bare UTC calendar date — the first day the person is available again. It is the
*whole* temporal contract: no instant is stored, exposed, or reconstructed anywhere. That makes
expiry one shared pure comparison, leaks no timezone, and lets the client compute its own next
boundary for a rebuild.

Three single-purpose mutations (`…SetLimited`, `…Pause`, `…Resume`) replace one polymorphic
patch. Each owns exactly one field, so there is no omitted-vs-null ambiguity to detect and no
lost-update race to serialize.

The forward gate lives **inside** the edge-insert transaction, not before it, and the delivery
result is typed — so "which recipients actually received this" is answered by the server rather
than inferred by the client.

Storage is a sparse side table copying `user_presence`'s **Hasura permission shape** and
deliberately not its DDL. The blast radius is **not** small; §8 carries the real list.

---

## 1. Decisions this architecture encodes

| # | Decision |
|---|---|
| **D1** | **Two orthogonal fields, not a three-valued enum.** A permanent `is_limited` and a temporary `resume_on`. The view (`open`/`limited`/`paused`) is derived, never stored. |
| **D2** | **Expiry distinguishes the two.** `resume_on` is mandatory and bounded (≤ 90 days); `is_limited` never expires. Honest framing: `limited` can still rot *as a public statement* — the claim is that its rot is low-impact because it blocks nothing, not that dispositions do not rot. |
| **D3** | **Expiry is lazy and shared.** One pure comparison, identical on client and server: paused ⇔ `todayUtc < resumeOn`. No scheduled job on the correctness path. |
| **D4** | **Open deletes the row.** `CHECK (is_limited OR resume_on IS NOT NULL)` makes an all-default row unrepresentable. Scoped honestly by D29. |
| **D5** | **Side table copying `user_presence`'s permission shape, not its DDL.** Copy: object relationship, `hidden_for_viewer` over `block_hides`, select-only permission, fragment slot. Do **not** copy `UNLOGGED` (`m0007.dart:15`), the `on_user_created` insert, or the backfill. |
| **D6** | **`updated_at` is never exposed.** Ops only; exposing it reconstructs the history D4 prevents. |
| **D7** | **No free-text reason.** |
| **D8** | **No Hasura write permissions.** All writes go through V2 so the clamp cannot be bypassed. |
| **D9** | **Three single-purpose mutations, not one patch.** `userAvailabilitySetLimited(isLimited: Boolean!)`, `userAvailabilityPause(resumeOn: String!)`, `userAvailabilityResume`. *(Rev 2 used one mutation with "omitted = preserve, null = clear" — not expressible here: Ferry's generated document always contains the argument, and `schema.dart:120-130` coerces the unset variable to null and inserts the key, so `args.containsKey` cannot distinguish.)* Each mutation owns one field, which also eliminates the concurrent-patch race (D30). |
| **D10** | **The forward gate is inside the insert transaction.** *(Rev 2's pre-read was TOCTOU.)* A pre-read in `ForwardCase.forward` is fine for UX but is not the gate; `createBatch` predicates each insert on current availability in the same transaction that inserts it (§7). |
| **D11** | **No silent drops.** Any recipient skipped for availability is reported. The Hasura permission-wall precedent is a *read* convention for rows you may not know exist; a paused person is visible and was named by the sender. |
| **D12** | **Availability occupies the presence slot, subject to the row's real precedence** (§9.4). Row height is *not* claimed invariant — the slot is a `Wrap`. |
| **D13** | **`limited` never changes ordering.** A silent rank penalty for honest signalling teaches people not to signal. |
| **D14** | **Others' profiles render only non-open states; your own always renders the current state.** |
| **D15** | **Own view uses tone; others' stays neutral.** |
| **D16** | **No badge, dot, ring, icon, or chip.** `TenturaStatusText` only. |
| **D17** | **No realtime entity, no push, no Updates entry.** Structurally guaranteed by D5 — the `profile` trigger (`m0114.dart:723-737`) fires only on `user` content columns. |
| **D18** | **Existing interactions are untouched.** Availability gates exactly one verb: *being newly forwarded to*. |
| **D19** | **Rendering follows the verb, over an enumerated host list** (§9.6). Rev 2's bare principle was not a closed set; the hosts are now named, including one that reuses the recipient row but must **not** render availability. |
| **D20** | **Weekday-or-date display extends `beaconCardCalendarDeadlineStatus`** (`DateFormat('EEE')`), not `profilePresenceDisplayLine`. Inside 7 days → weekday; beyond → localized date (the existing helper emits a weekday for *every* future date and needs the second branch added). |
| **D21** | **The temporal contract is a UTC calendar date.** One column, `resume_on date`, exposed. No instant is stored, exposed, or reconstructed. Rendered as a pure calendar date — **never** `toLocal()`, which would shift it a day. |
| **D22** | **`limited` is not severable.** It is the disposition half of the model. |
| **D23** | **Delivery reporting is server-typed, not client-inferred.** `createBatch` already returns the inserted pairs (`forward_edge_repository.dart:94-147`); `ForwardCase` currently discards them. A client-side post-send diff cannot distinguish an availability skip from a concurrent block, and the picker's reload is not awaited (`forward_cubit.dart:63-74`). |
| **D24** | **The picker gate lands on `visibleRecipients` and the two *reachable* scopes.** `computeBeaconListSections` is dead code; `all`/`bestNext` are unreachable UI (§11). |
| **D25** | **Read parity spans both sides of the boundary** — every server `UserPublicRecord` site (field **required**, so omission fails to compile) *and* every client adapter building `Profile` from a V2 user shape. |
| **D26** | **All three mutations registered in `_tenturaDirectOperationNames`** (`build_client.dart:182`) or they route to Hasura, which has no such mutations. |
| **D27** | *(Withdrawn in rev 3.)* Rev 2 required a shared smallint↔enum mapper — stale rev-1 machinery. The model is a bool plus a date; there is no availability smallint to map. Centralising the existing presence decoders is unrelated cleanup. |
| **D28** | **Beacon-tied invite acceptance is not gated — resolved, not open.** The edge is created only on recipient consumption (`user_repository.dart:112-145, 847-853`), acceptance is authenticated and rejects blocked pairs (`invitation_case.dart:262-315`), and the client shows the request before confirming (`invitation_accept_dialog.dart:40-92`). Informed recipient opt-in, not issuer push. |
| **D29** | **Lazy lapse leaves a readable past `resume_on` until cleanup — stated, not denied.** The privacy claim is narrowed to *"an explicit reset stores nothing; a lapsed pause may expose a past resume date until the janitor runs."* The read API suppresses expired rows (§6) so this is bounded, but it is not "structurally impossible". |
| **D30** | **One atomic operation per mutation, owned by a use case.** Validation, horizon clamp, and delete-on-empty are application rules, not resolver behaviour — matching how `UserCase` owns them today (`mutation_user.dart:28-49` is a thin delegate). |

---

## 2. What already exists (and what must not be reused)

| Existing thing | Relationship to this feature |
|---|---|
| `public.user_presence` — **Hasura config**: object relationship on `user`, `user_presence_hidden_for_viewer` (`m0136.dart:184-195`), select-only permission with `hidden_for_viewer = false` | **Copy this shape.** It is the visibility contract availability needs, and `block_hides` is symmetric (`m0135.dart:36-40`). |
| `public.user_presence` — **DDL**: `CREATE UNLOGGED TABLE` (`m0007.dart:15`), backfill, `on_user_created` trigger | **Do not copy.** Lifecycle is inverted and UNLOGGED means a crash wipes the table — fine for session telemetry, not for a user-declared 90-day pause. |
| `tentura_db.dart:88-149` / `:153-169` / `_migrations.dart` | Tables registered in `@DriftDatabase`; Drift runtime migrations disabled, `schemaVersion` stays 1; app DDL is hand-written migrant SQL. |
| `ForwardState.visibleRecipients` + `ForwardFilter` | **The live render path** (`forward_recipient_picker.dart:352`). |
| `ForwardScopeLinks` (`forward_scope_links.dart:108-119`) | **Only two scopes are reachable in production UI**: `unseen` (default) and `alreadyInvolved`. `all` and `bestNext` exist in state but have no tab. |
| `ForwardState.computeBeaconListSections()` | **Dead code**, zero call sites (ADR 0004 Amendment E). Rev 1 was written against it. |
| `ForwardCubit._loadCandidates` / `forward()` (`forward_cubit.dart:170-192, 385-390, 406-413`) | Pre-selection is intersected with *presence in the list*, not forwardability; `forward()` rejects the **whole batch**; and it returns early when nothing is selected — which is why "recompute at send" cannot rescue a row the user was never able to select (§4). |
| `forward_edge_repository.dart:94-147` `createBatch` | **Already transactional** (`withMutatingUser`) and **already returns `List<ForwardEdgeCreated>`**. The natural home for both D10 and D23. |
| `ForwardCase.forward` (`forward_case.dart:191-244, 248-271, 273-319`) | Block/visibility checks run *before* `_attention.runAction`; edges are inserted inside it; the inserted set is discarded and only `batchId` is returned. |
| `PersonActionPolicy` | Used by the profile screen **and** the graph side panel (`graph_person_context_panel.dart:38`), both fed by `UserModel`-fragment queries. |
| `PersonForwardState.canSend` (`person_forward_state.dart:28-29`) | Single person-level gate to extend. `PersonForwardBlock` stays untouched — it is a pure `(involvement, beacon.status)` function. |
| `schema.dart:120-130` | Nullable arguments present in the document are coerced to null **and inserted** into the resolver map. This is why D9 splits the mutations. |
| `build.yaml:37-76` | Scalar overrides exist for `Date`, `v2_Date`, `timestamptz` — **not** for Hasura's lowercase `date`. D21 requires adding one. |
| `_tenturaDirectOperationNames` (`build_client.dart:182`) | V2 routing allow-list; `ProfileUpdate` at line 252. |

**Must not be reused:** `UserPresenceStatus`, `websocket_path_user_presence.dart`,
`UserPresenceCase.touch/setStatus`, `last_seen_at`. Availability is declared, never observed.

---

## 3. State model

```
   is_limited : bool   ── standing disposition, never expires
   resume_on  : date   ── first UTC day available again; bounded (≤ 90d)

   effectiveView(todayUtc):
       resume_on != null && todayUtc < resume_on   →  paused
       else if is_limited                          →  limited
       else                                        →  open

   open ──set limited──► limited ──pause──► limited+paused
    ▲                       ▲                    │
    │                       └──── lapse ─────────┘   ← falls back to `limited`
    └──── clear limited ────┘
```

```dart
AvailabilityView effectiveOn(DateTime todayUtc) {
  if (resumeOn != null && todayUtc.isBefore(resumeOn!)) return AvailabilityView.paused;
  if (isLimited) return AvailabilityView.limited;
  return AvailabilityView.open;
}
```

Both operands are **dates at UTC midnight**. `todayUtc == resumeOn` ⇒ **available** (the resume
day is inclusive). This is one comparison of two zone-free values, so client and server cannot
disagree — which is what rev 2 claimed and could not deliver.

| Storage state | Derived view | Rendered to others | Blocks |
|---|---|---|---|
| no row | `open` | no | no |
| `{limited}` | `limited` | yes | no |
| `{resume_on}`, future | `paused` | yes | **yes** |
| `{resume_on}`, past | `open` (row stale, D29) | no | no |
| `{limited, resume_on}` future | `paused` | yes | **yes** |
| `{limited, resume_on}` past | `limited` (pair stale, D29) | yes | no |

Six storage states, three views. This is **not simpler** than rev 1's enum — it is more faithful.
The trade is explicit: an overlay you can explain instead of a hidden fallback rule, at the cost
of two ghost variants that the janitor and the read filter (§6) clean up.

---

## 4. Expiry, reset and time

Expiry applies to `resume_on` only. `is_limited` is cleared explicitly or not at all.

**Three exits from a pause:** lapse (no write, falls back per §3), explicit **Resume now**, or
replacement with a new date.

**The skew, stated honestly.** The boundary is UTC midnight, so a subject far from UTC becomes
available up to ~14 hours from their own local midnight. Consequences and mitigations:

- Presets resolve in **calendar days**, never instants: Tomorrow = `todayUtc + 1`; This weekend =
  next Monday's UTC date; One week = `+7`; One month = `+1 month`; Pick a date… = the chosen day.
- The sheet **echoes the resolved resume date** before committing, so the user sees the day they
  are choosing rather than inferring it.
- Near the date line the user's "tomorrow" and the UTC "tomorrow" can differ by one day. The
  picker resolves from the user's local calendar and the echoed date makes any mismatch visible
  and adjustable. This is accepted, documented, and cheaper than every alternative that either
  leaks the offset or breaks the shared comparison.

**Horizon.** `resume_on ≤ todayUtc + 90 days`, rejected if `≤ todayUtc`. Enforced in the use case
(D30), with the client picker's `lastDate` using the same constant.

**Silent lapse is deliberate** — a notification is a history event (D17). Discoverability comes
from D14 and from the echoed date at set time.

**The stale-row case, now actually closable.** Rev 2 claimed "recompute at send time" fixed a
pause lapsing mid-session. It does not: the row is disabled when built, its taps are inert
(`forward_recipient_row.dart:140-145, 474-517`), and with nothing selected the cubit returns
early (`forward_cubit.dart:385-390`) — there is no send to recompute on. Because D21's boundary
is a date the client *can* compute, the fix is available: **schedule a bounded rebuild at the
next known `resume_on` boundary**, plus re-evaluate on app resume. Any residual staleness is
fail-closed (the sender sees a pause that has ended), never fail-open.

**Janitor (hygiene, bounded by D29).** `DELETE … WHERE resume_on <= CURRENT_DATE AND NOT
is_limited` and `UPDATE … SET resume_on = NULL WHERE resume_on <= CURRENT_DATE`. It changes no
read result (§6 already suppresses expired rows) but bounds how long a past date is readable.

---

## 5. Storage and data model

```sql
CREATE TABLE public.user_availability (
  user_id     text PRIMARY KEY REFERENCES public."user"(id) ON DELETE CASCADE,
  is_limited  boolean     NOT NULL DEFAULT false,
  resume_on   date        NULL,
  updated_at  timestamptz NOT NULL DEFAULT now(),          -- ops only (D6)
  CONSTRAINT user_availability_not_empty
    CHECK (is_limited OR resume_on IS NOT NULL)
);

CREATE INDEX user_availability_resume_on_idx
  ON public.user_availability (resume_on) WHERE resume_on IS NOT NULL;

CREATE OR REPLACE FUNCTION public.user_availability_hidden_for_viewer(
  user_availability_row public.user_availability,
  hasura_session json
) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT public.block_hides(
    hasura_session ->> 'x-hasura-user-id',
    user_availability_row.user_id
  );
$$;
```

One nullable date replaces rev 2's instant/day pair, so the pair-consistency constraint is gone.
**Explicitly not** `UNLOGGED`; **no** creation trigger; **no** backfill (D5).

**Hasura** — object relationship `user_availability` on `user`; computed field
`hidden_for_viewer`; select permission for role `user` exposing **`is_limited`, `resume_on`,
`user_id` only**, never `updated_at`; **no insert/update/delete permission** (D8). The select
filter also suppresses expired pause-only rows (§6).

**Codegen prerequisite (D21).** `resume_on` surfaces as Hasura's lowercase `date` scalar, for
which `build.yaml:37-76` has **no override** (it covers `Date`, `v2_Date`, `timestamptz`). One
must be added, with a serializer that round-trips a bare calendar date **without** timezone
shifting on web or native.

**Domain types**

| Package | Type | Notes |
|---|---|---|
| `tentura_root` `lib/domain/enums.dart` (repo root) | `enum AvailabilityView { open, limited, paused }` | Derived, never stored. No ordinal is a wire value. |
| `packages/client/lib/domain/entity/availability.dart` | `@freezed class Availability { bool isLimited; DateTime? resumeOn; }` | `const Availability.open()`, `effectiveOn(todayUtc)`, `blocksNewRequestsOn(todayUtc)`. Pure. `resumeOn` is a UTC-midnight date and must never be `toLocal()`-ed. |
| `packages/client/lib/domain/entity/profile.dart` | `@Default(Availability.open()) Availability availability` | |
| `packages/server/lib/domain/entity/user_availability_entity.dart` | `UserAvailabilityEntity` | Same comparison. |
| `packages/server/lib/domain/entity/gql_public/user_availability_record.dart` | `UserAvailabilityRecord` | **Required** field on `UserPublicRecord` (D25). |

---

## 6. Read path

**Hasura (primary).** One field on `packages/client/lib/data/gql/user_model.graphql`:

```graphql
fragment UserModel on user {
  ...
  user_presence { last_seen_at status }
  user_availability { is_limited resume_on }
}
```

Consumers inherit it: `mutually_visible_users` (a `SETOF public."user"` function, so the nested
relationship resolves), `user_by_pk`, `users_fetch_by_ids`, mutual friends, the graph fetch.
**Room member lists do not** — `BeaconParticipantList` is a denormalized V2 shape, not `UserModel`.

**Expired-row suppression (D29).** The select permission filters out pause-only rows whose
`resume_on` has passed, so a lapsed pause is `null` ≡ open to every GraphQL reader rather than
waiting on the janitor. A `{limited, past resume_on}` row still returns, with the stale date; the
derived view is `limited`, and consumers must not render a past date.

**Mapping.** A null relationship maps to `const Availability.open()`. Expiry is **not** applied at
map time (D3) — consumers call `effectiveOn(todayUtc)`.

**Read parity spans both sides of the boundary (D25).**

*Server producers* — the field is **required** on `UserPublicRecord`, so all three constructors
fail to compile if missed:

| Site | Note |
|---|---|
| `user_profile_batch_lookup.dart:120` | batch-joins presence; must batch-join availability |
| `mutual_friends_repository.dart:112` | hand-built, and fetches presence **per user in a loop** — do not add a second N+1 |
| `invite_genealogy_gql_maps.dart:102` | currently omits presence entirely |
| `gql_public_user_maps.dart:35-46` | the serializer |
| `query_invitation.dart:52-58` | **not a record** — hand-patches `issuer['user_presence']` onto a map, so the compiler will not catch it |

*Client adapters* — these build `Profile` from V2 user shapes and would silently default to open,
because `Profile.availability` has a safe default:

| Site |
|---|
| `data/model/user_public_model.dart` |
| `features/profile_view/data/repository/mutual_friends_repository.dart:36-62` |
| `features/beacon_view/data/repository/coordination_repository.dart:241-259` |

Missing any of these fails **open** — safe direction, wrong result, invisible without an assertion.

---

## 7. Write path and enforcement

### 7.1 Three single-purpose mutations (D9)

```graphql
userAvailabilitySetLimited(isLimited: Boolean!): Boolean!
userAvailabilityPause(resumeOn: String!): Boolean!     # ISO calendar date, e.g. "2026-08-18"
userAvailabilityResume: Boolean!
```

Every argument is non-null, so there is nothing to distinguish an omitted variable from an
explicit null — the `schema.dart:120-130` coercion issue cannot arise. `resumeOn` is parsed as a
**calendar date**, not via `InputFieldDatetime` (whose force-UTC normalisation is for instants).
Subject is always `getCredentials(args).sub`; no admin override. All three registered per D26.

Resolvers stay thin and delegate to a `UserAvailabilityCase` that owns validation, the horizon
clamp, and delete-on-empty (D30) — matching how `UserCase` already owns `userUpdate`'s rules.

### 7.2 Concurrency (D30)

Because each mutation writes exactly one field and reads the other only to decide deletion, the
rev-2 lost-update race is gone by construction: two devices clearing `limited` and resuming
concurrently now touch disjoint columns. Each mutation is **one statement in one transaction**,
with the delete decided from the post-update row:

```sql
-- userAvailabilityResume
WITH upd AS (
  UPDATE public.user_availability SET resume_on = NULL, updated_at = now()
   WHERE user_id = $1 RETURNING *
)
DELETE FROM public.user_availability
 WHERE user_id = $1
   AND EXISTS (SELECT 1 FROM upd WHERE NOT is_limited AND resume_on IS NULL);
```

`SetLimited(true)` and `Pause` are `INSERT … ON CONFLICT (user_id) DO UPDATE SET <one column>`,
which is safe for concurrent first-inserts. `SetLimited(false)` follows the shape above. No
statement ever constructs the `{false, null}` insert candidate that would violate the CHECK.

Required evidence: two-connection PostgreSQL tests for clear-limited vs resume, pause vs clear,
and concurrent first-write.

### 7.3 The forward gate is inside the insert (D10)

A pre-read in `ForwardCase.forward` is TOCTOU: its block and visibility checks run before
`_attention.runAction` (`forward_case.dart:191-244`), while edges are inserted inside
(`:248-271`). Rev 3 puts the predicate where the insert is. `createBatch`
(`forward_edge_repository.dart:94-147`) already runs in `withMutatingUser` and already loops
per recipient, so each `_insertActiveEdge` becomes conditional on current availability evaluated
in the same transaction — the recipient is skipped, not the batch.

A use-case pre-read is still worth keeping for UX (it lets the picker explain itself), but it is
not the gate.

### 7.4 Typed delivery result (D23)

`createBatch` already returns `List<ForwardEdgeCreated>` and `ForwardCase.forward` discards it
(`forward_case.dart:273-319`). Rev 3 propagates it:

```
{ batchId, deliveredRecipientIds, availabilitySkippedRecipientIds }
```

This makes `beaconForward`'s `String!` return an object — a **breaking API change**, which is why
S11 resolves to raising `kDefaultMinClientVersion`. The alternative (client-side post-send diff)
is not a contract: the reload is not awaited (`forward_cubit.dart:63-74`), and a disappeared
recipient cannot be attributed to a pause rather than a concurrent block.

The client then builds both the snackbar and the beacon-create confirmation from
`deliveredRecipientIds` rather than the selection (`forward_cubit.dart:448-460`). If the client
strips a locally-ineligible id before sending (§11), it **stays in the requested denominator and
is reported** — otherwise the client has silently rewritten the user's action, which is exactly
what D11 forbids.

Cancel, update, help-offer, admission and room mutations are **not** gated (D18); neither is
beacon-tied invite acceptance (D28).

---

## 8. Layer allocation and blast radius

**Client — domain / pure**
```
tentura_root/lib/domain/enums.dart          AvailabilityView
client/lib/domain/entity/availability.dart  Availability (effectiveOn, blocksNewRequestsOn)
client/lib/domain/entity/profile.dart       +availability
client/lib/domain/util/availability_presets.dart      calendar-day presets (pure)
client/lib/ui/utils/availability_line.dart            display line (l10n-aware)
client/lib/ui/utils/beacon_card_deadline.dart         +beyond-7-days branch (D20)
```

**Client — data**
```
build.yaml                                  +lowercase `date` scalar override (D21)
data/gql/schema.graphql                      regenerated
data/gql/user_model.graphql                  +user_availability { … }
data/model/user_model.dart                   toEntity() mapping
data/model/user_public_model.dart            V2 shape (D25)
features/profile_view/data/repository/mutual_friends_repository.dart   V2 adapter (D25)
features/beacon_view/data/repository/coordination_repository.dart      V2 adapter (D25)
data/service/remote_api_client/build_client.dart   +3 operation names (D26)
features/profile/data/gql/availability_*.graphql   3 mutations
features/profile/data/repository/profile_repository.dart + port
```

**Client — UI**
```
features/profile/ui/sheet/availability_sheet.dart      new (§9.1)
features/profile/ui/bloc/profile_cubit.dart            +3 actions (single repo, no use case)
features/profile/ui/widget/profile_body.dart           own-profile row (does not exist today)
features/profile_view/ui/widget/profile_view_body.dart other-profile line + action gate
features/graph/ui/widget/graph_person_context_panel.dart  same policy, same line (D19)
ui/model/person_action_policy.dart                     explicit paused flag tuple (§9.3)
features/forward/domain/entity/forward_candidate.dart  canForwardToOn(todayUtc)
features/forward/ui/bloc/forward_state.dart            visibleRecipients + scope counts (§11)
features/forward/ui/bloc/forward_cubit.dart            pre-selection gating, typed result, rebuild timer
features/forward/ui/widget/forward_recipient_row.dart  slot precedence (§9.4)
features/forward/ui/widget/forward_band_strip.dart     band host (S10)
features/forward/ui/widget/forward_search_overlay.dart separate row host
features/forward/ui/widget/forward_scope_links.dart    unseen count semantics (§11)
features/forward/ui/widget/lineage_suggestions_sheet.dart  explicit **no-render** host (D19)
features/forward/ui/message/forward_messages.dart      partial-delivery copy
features/forward/ui/bloc/person_forward_state.dart + person_forward_cubit.dart + screen
features/beacon_create/ui/bloc/beacon_create_cubit.dart + beacon_send_confirmation_dialog.dart
```

**Server**
```
data/database/table/user_availability.dart   Drift table (registered in tentura_db.dart)
data/database/migration/mNNNN.dart           hand-written migrant SQL; schemaVersion stays 1
domain/entity/user_availability_entity.dart + gql_public/user_availability_record.dart
domain/port/user_availability_repository_port.dart + data/repository impl (atomic ops, D30)
domain/use_case/user_availability_case.dart  validation, clamp, delete-on-empty
domain/use_case/forward_case.dart            typed result (D23)
data/repository/forward_edge_repository.dart in-transaction gate (D10)
api/.../mutation_availability.dart + custom_types.dart (incl. typed forward result)
the five read-path producer sites in §6
hasura/metadata.json                          relationship, computed field, select permission
```

**Layer check.** `Availability` imports nothing outside domain; presets and line helpers are pure
with `todayUtc` injected; `ProfileCubit` stays a one-port cubit; server rules live in a use case
behind a port (D30), never in the resolver or repository.

**API-shape note.** `canForwardTo` is a getter and `visibleRecipients` is a clock-free getter.
Position: **UI getters may read the clock; the pure entity method takes `todayUtc` and is what
tests and the server exercise.** With D21 the client can also compute the next boundary, which is
what makes §4's scheduled rebuild possible.

---

## 9. UX surfaces and states

Design-system rules throughout: `context.tt` tokens, `TenturaText.*`/`textTheme`, `ColorScheme`
roles or `tt.*`, no raw `EdgeInsets`/`BorderRadius`/`fontSize`/`Color`. Tap targets ≥ 48dp.

### 9.1 The control — `AvailabilitySheet`

Two controls, mapping one-to-one onto the three mutations.

```
┌────────────────────────────────────────────────┐
│  Availability                                  │
│                                                │
│  Only important requests            [ ●——]     │  → SetLimited
│  People still see you; they'll see a note       │
│  asking them to be selective.                   │
│  ───────────────────────────────────────────   │
│  Not taking new requests                        │
│  You won't be offered when people pick          │
│  recipients. Requests and chats you're          │
│  already in aren't affected.                    │
│                                                │
│    [Tomorrow] [This weekend]                    │
│    [One week] [One month] [Pick a date…]        │
│    You'll receive requests again on Mon 18 Aug  │
│                                      [ Pause ]  │  → Pause
│                                                │
│  ▸ Resume now      (only while paused)          │  → Resume
└────────────────────────────────────────────────┘
```

The toggle applies immediately (no parameters); the pause applies on **Pause** (it needs a date).
Presets are `OutlinedButton`s in a `Wrap` (not `Chip`s); "Pick a date…" opens a themed
`showDatePicker` with `lastDate = todayUtc + 90d`. The resolved resume date is always echoed
(§4) — this is the only place the UTC-day boundary becomes visible, and it must be visible.

### 9.2 Your own profile

```
open              Open to requests                             Change
limited           Only important requests                      Change   (info)
paused            Not taking new requests · until Mon, 18 Aug  Change   (warn)
limited + paused  Not taking new requests · until Mon, 18 Aug  Change   (warn)
                  Then: only important requests                         (info, 2nd line)
```

The two-line case is what orthogonality buys: the user can see what they return to.

### 9.3 Someone else's profile, and the graph side panel

Rendered only when the derived view ≠ `open`, after the presence line, before trust relation.
One line, neutral tone, no icon, no chip, no dot.

**Explicit flag tuple.** Rev 1 said "reuse the `profileRequestUnavailable` pattern", but that text
renders only when `primaryAction == none && showRequestOptions && viewerExplicitlyTrustsSubject`,
and the same `showRequestOptions` also renders a live "Request options" door into person-forward
(`profile_view_body.dart:342-373`, `graph_person_context_panel.dart:174-200`). The paused branch
therefore sets **`primaryAction: none, showRequestOptions: false`** and renders its own copy —
otherwise "hard, no override" leaves an open door behind a "can't send" message.

### 9.4 Forward recipient row — full precedence

Line 2 has two overrides above the `Wrap` (`forward_recipient_row.dart:190-232`):

1. `tierEvidenceLabel != null` → band evidence replaces the whole line
2. `showPresenceLine == false` → no line at all (band exploration rows)
3. `notReachable` → existing relation label wins
4. **any already-ineligible involvement** — `author`, `declined`, `helpOffered`, `withdrawn`,
   `forwardedByMe` — keeps its own label. *(Rev 2 protected only `forwardedByMe`; the other four
   are equally ineligible under `canForwardTo` (`forward_candidate.dart:35-41`) and equally
   visible in the already-involved scope, so pause is not why those rows are unpickable and must
   not claim to be.)*
5. otherwise availability takes the presence slot; for `paused` it also replaces the relation label

| View | Line 2 | Checkbox |
|---|---|---|
| `open` | unchanged | as today |
| `limited` | `Only important requests` replaces presence; relation kept | enabled |
| `paused`, involvement `unseen`/`forwarded`/`watching` | `Not taking new requests until Monday` replaces presence **and** relation | **disabled** |
| `paused`, any already-ineligible involvement | unchanged | as today |

Cases 1–2 leave a paused person with a disabled checkbox and no reason — S10 must close before
planning: exclude paused users from band generation, or give the band row a pause line.

### 9.5 Person-forward screen

Person-level: extend `canSend` (`person_forward_state.dart:28-29`) **and** `PersonForwardCubit.send`,
and gate the "New request" path too (`person_forward_screen.dart:308-330`) — not just the
existing-request sends. Banner reuses the screen's existing unreachable pattern. The route is
deep-linkable, so hiding the profile button is not sufficient. `PersonForwardBlock` unchanged.

### 9.6 D19 host inventory

**Renders availability** (a subject displayed next to an affordance that can newly involve *that*
subject): other-profile primary/secondary actions; graph person context panel; person-forward
screen (including "New request"); and every recipient-row host in the picker — standard list,
lineage block, band strip, and the full-screen search overlay
(`forward_search_overlay.dart:271-335`).

**Does not render**: `lineage_suggestions_sheet.dart:133-149` — it reuses `ForwardRecipientRow`
but has **no send action**, so an unconditional row-level line would violate D19's "none that
don't" half. Availability is therefore a **host-supplied flag on the row**, not an intrinsic row
behaviour. Also excluded: chat/room member lists, inbox, My Work, contacts, search results, and
any avatar anywhere. A generic button that merely *opens* a picker does not show every possible
recipient's constraint; the picker does.

---

## 10. Copy and localization

Keys prefixed `availability*` in both `.arb` files. Values say **request**/**chat**, never
*beacon*/*room*.

| Key | en | ru |
|---|---|---|
| `availabilityLimitedTitle` | Only important requests | Только важные запросы |
| `availabilityPausedUntil` | Not taking new requests until {when} | Не принимает новые запросы до {when} |
| `availabilitySelfOpen` | Open to requests | Вы принимаете запросы |
| `availabilitySelfLimited` | Only important requests | Вы принимаете только важные запросы |
| `availabilitySelfPausedUntil` | Not taking new requests · until {when} | Вы не принимаете новые запросы до {when} |
| `availabilitySelfThenLimited` | Then: only important requests | Затем: только важные запросы |
| `availabilityResumeEcho` | You'll receive requests again on {when} | Вы снова начнёте получать запросы {when} |
| `availabilityPersonPaused` | {name} isn't taking new requests until {when}. | {name} не принимает новые запросы до {when}. |
| `availabilityUnaffectedNote` | Requests and chats you're already in aren't affected. | Уже начатые запросы и чаты это не затрагивает. |
| `availabilityResumeNow` | Resume now | Возобновить сейчас |
| `availabilityDeliveredPartial` | Delivered to {n} of {m} — {name} isn't taking new requests right now. | Отправлено {n} из {m} — {name} сейчас не принимает новые запросы. |

**Russian gender.** No predicative adjectives — *«Открыт»/«Открыта»* forces a gender the app does
not know. Third-person for others, second-person for self. A **human review item**; the existing
l10n contract test checks terminology, not grammar.

`{when}` renders `resume_on` as a pure calendar date via the D20 helper — **never** `toLocal()`.

---

## 11. Recipient-picker semantics

```dart
bool canForwardToOn(DateTime todayUtc) =>
    isReachable &&
    !profile.availability.blocksNewRequestsOn(todayUtc) &&
    involvement != forwardedByMe && ... ;   // existing clauses unchanged
```

**Only two scopes are reachable in production** (`forward_scope_links.dart:108-119`). Rev 2 spent
three of four table rows on `all`/`bestNext`, which have no tab — the same class of error as
rev 1's dead-code section.

| Reachable scope | Behaviour |
|---|---|
| **`unseen`** (default) | Keeps listing paused candidates, **disabled**, with the pause label. `isUnseen` needs **no change** — checkbox disablement already follows the eligibility predicate (`forward_recipient_row.dart:115-145, 352-356`). |
| **`alreadyInvolved`** | Unchanged — already involved is already involved (D18). |

`all` / `bestNext` inherit the predicate automatically if a tab is ever added; no design work is
owed to them now.

**The unseen count keeps row semantics.** *(Reverses rev 2.)* Rev 2 told `scopeCounts.unseen` to
exclude availability-blocked candidates while still listing them — producing "Unseen (0)" above
three visible rows, since the count is painted on the tab label
(`forward_scope_links.dart:49-65`). The count is a **row count**: paused unseen rows stay in it.

**Pre-selection must be gated** (`forward_cubit.dart:170-192`). `autoSelectIds` (lineage,
server-computed, availability-blind) and `initialSelectedIds` are intersected with *presence in
the list*, not forwardability; the row cannot be unchecked once disabled; and `forward()` rejects
the entire batch (`:406-413`). All three change: filter the pre-selection at load, allow deselect
when `isSelected && !canSelect`, and strip ineligible ids at send — **reporting the strip and
keeping those ids in the requested denominator** (§7.4), never silently.

**The lineage engine and capability band stay availability-blind by decision.** Both keep
recommending paused people; the gate is applied at selection and at insert. Making the server
suggestion paths availability-aware is out of v1 scope, but it is written down, because the
product's own recommender vouching for someone who opted out is visible, not invisible.

---

## 12. Privacy, abuse and failure modes

| Concern | Disposition |
|---|---|
| Coarse absence is revealed | Intended — it is the signal. Bounded by no free text (D7), day granularity (D21), the 90-day ceiling, and profile visibility. |
| Timezone / geography leak | **Closed.** A bare UTC date carries no offset (D21); no instant is stored or exposed. |
| Stored change history | No history table; open deletes the row (D4); `updated_at` unexposed (D6); no realtime event — structurally, since the `profile` trigger fires only on `user` content columns. |
| **Lapsed pause leaves a readable past date** | **Stated, not denied** (D29). The read filter suppresses expired pause-only rows and the janitor bounds the rest; a `{limited, past date}` row still carries a stale date that must not be rendered. |
| **"Who paused right after I asked"** | **Not prevented.** Current state is rendered on profiles and in the picker, so a viewer who remembers yesterday can diff; and D11's reporting is a deliberate real-time signal. The honest claim is **"no stored history and no mutation timestamp"** — which is strong enough. |
| Blocked users | Free via `user_availability_hidden_for_viewer` → `block_hides` (symmetric). |
| Pause used to hide from one person | It is not a block. `features/block` remains the tool; the two compose. |
| Client staleness | Window is the picker session; mitigated by the §4 rebuild timer, backstopped by the in-transaction gate (D10), reported by the typed result (D23). Residual staleness is fail-closed. |
| A read-path site forgotten | Fails **open**. D25 makes the server field required; the client adapters need explicit parity tests. |
| Mixed client versions | The typed forward result is a breaking change ⇒ S11 resolves to raising `kDefaultMinClientVersion`. |
| Dodging accountability mid-request | Out of scope by construction (D18). |

---

## 13. Rejected designs

| Rejected | Why |
|---|---|
| Free/busy or capacity | Forbidden by the brief; converts a boundary into a gameable queue. |
| Presence-derived availability | The anti-pattern being removed. |
| Working hours / schedules / calendars | Needs a rules engine and a per-rule timezone story. |
| Free-text status note | D7. |
| Indefinite **pause** | Core requirement, and the usual source of rot. |
| Mandatory expiry on `limited` | Forces a quarterly ritual whose forget-penalty is silent reversion to `open`. |
| Cutting `limited` from v1 | It is the disposition half, not a weak pause. |
| A three-valued enum | Cannot express "selective *and* away", and needs a hidden fallback rule on lapse. |
| **Subject-local expiry instants** | *(Rejected in rev 3.)* Either leaks the subject's UTC offset or breaks the shared client/server comparison. A UTC-date boundary keeps both, at a documented ≤14h skew. |
| **One patch mutation with omitted-vs-null semantics** | *(Rejected in rev 3.)* Not expressible through Ferry + `graphql_schema2`; and it reintroduces a lost-update race that three single-purpose mutations avoid entirely. |
| **A pre-read availability gate** | *(Rejected in rev 3.)* TOCTOU against edge insertion. |
| **Client-side post-send delivery diff** | *(Rejected in rev 3.)* Cannot distinguish an availability skip from a concurrent block; the reload is not awaited. |
| Silent partial drop | The permission-wall precedent is a *read* convention; a paused person is visible and was named. |
| Availability history | D4/D6/D29. |
| "Paused except close contacts" | Per-viewer evaluation on a batch-joined field; viewer-dependent labels. |
| Demoting `limited` in MR ordering | A hidden penalty for honest signalling. |
| "Send anyway" override | Makes the hard state advisory. |
| Availability on avatars / member lists | D16/D19. |
| Extending `userUpdate` | Different semantics, surface, and validation. |
| Columns on `user` | `updated_at` is Hasura-visible and the realtime trigger watches that table. |
| Cloning `user_presence`'s DDL | UNLOGGED plus a per-user creation trigger. |
| A `RealtimeEntityKind.availability` | Maintenance cost for data whose staleness is bounded. |

---

## 14. Invariants (the executable spec)

1. **One shared comparison.** Client and server derive the view from `(is_limited, resume_on,
   todayUtc)` by the same rule; `todayUtc == resumeOn` ⇒ available. Provable because both operands
   are zone-free.
2. **`resume_on` is never localised.** No `toLocal()` on the date, in any adapter, formatter, or
   widget — it would shift the day.
3. **A lapsing pause falls back to `limited`, not `open`,** when `is_limited` is set.
4. **Open stores nothing.** After an explicit reset, no row exists (CHECK-enforced).
5. **Expired pause-only rows are invisible to readers** via the select filter, independent of the
   janitor.
6. **No exposed mutation timestamp.** `updated_at` in no permission, map, type, or entity.
7. **Read parity on both sides** — three server constructors (compile-enforced), the serializer,
   the hand-patched invitation issuer, and three client V2 adapters.
8. **Concurrent independence.** Clearing `limited` and resuming a pause from two connections
   yields `open`, never a partially-applied row. Two-connection PostgreSQL test.
9. **The gate is transactional.** A pause committing between a forward's pre-read and its insert
   still produces no edge for that recipient.
10. **The confirmation matches reality.** Reported delivered count equals edges actually inserted;
    locally-stripped ids remain in the requested denominator and are reported.
11. **Row precedence.** `tierEvidenceLabel` and `notReachable` outrank availability; **no**
    already-ineligible involvement label is overridden.
12. **`limited` moves nobody.** Ordering is identical to the same candidate `open`.
13. **Pre-selection is gated** at load and at send.
14. **D19 host list is closed** — availability is a host-supplied row flag; the lineage
    suggestions sheet passes it off. Enforced by an enumerated host registry or an architecture
    test, not by convention.
15. **Horizon.** `resume_on ≤ todayUtc` and `> todayUtc + 90` rejected; the picker cannot select a
    date the use case would reject.

*Not machine-checkable, listed as human review items:* Russian gender-free copy (§10), and the
`date` scalar round-trip on web and native (§5) which needs a generated-schema smoke test.

---

## 15. Open decisions

**Resolved**

| # | Question | Resolution |
|---|---|---|
| S1 | Ship `limited`? | Yes — the disposition half, not a severable extra. |
| S2 | Hard pause, no override? | Hard. The time-box is the escape hatch. |
| S3 | Mandatory expiry on `limited`? | No — permanence is what makes it distinct. *(Product, 2026-08-13.)* |
| S4 | 90-day horizon? | Yes. |
| S5 / D28 | Do beacon-tied invites bypass a pause? | **Resolved: not gated.** Recipient-initiated, authenticated, and the request is shown before confirming. No issuer-side push. |
| S6 | Graph panel vs exclusion list | Follow the verb, over an enumerated host list (D19, §9.6). |
| S7 | Partial-skip UX | No silence; **and S7b is mandatory** — typed server result, not a client diff (D23). |
| S8 | Default-filter behaviour | Paused listed and disabled on `unseen`, kept in the row count (§11). |
| S9 | Clock | UI getters may read the clock; the entity method takes `todayUtc`. |
| **S13** | **Temporal contract** | **UTC-date boundary** *(product, 2026-08-13)*, with the skew documented in §4. |
| S11 | Raise `kDefaultMinClientVersion`? | **Yes** — the typed forward result is a breaking change to `beaconForward`. |

**Still open**

| # | Question | Recommendation |
|---|---|---|
| **S10** | Band rows: exclude paused users from band generation, or give the band row a pause line? | Exclude from generation — a band slot spent on someone unpickable is wasted. **Must close before planning**; it is row behaviour, not polish. |
| **S12** | Settings tile as a second door, or own-profile only? | Own-profile only for v1; `settings_screen.dart` has no hook today. Does not affect enforcement. |

**Needs a test, not a decision:** whether Hasura applies the `user` table's `limit: 10` select
permission to the `mutually_visible_users` SETOF function at runtime. If it does, the candidate
pool is capped at 10 and paused users consume capped slots. Pre-existing, not introduced here.

**Delivery constraints:** semver bump plus `web/index.html` cache-buster; `kDefaultMinClientVersion`
raise (S11); the migration joins the rollback simulation; `hasura/metadata.json` applied; both
`scripts/check-custom-lints.sh` gates and `check-user-facing-terminology.sh` green.
