---
status: draft
kind: architecture
issue: 146
---

# Shared-context visibility — architecture

**Status:** architecture **rev 4**, ready for implementation
([implementation plan](issue-146-shared-context-visibility-implementation-plan.md)). Shape only, with no file-by-file
task list. The product decisions in §2 are binding. A later
`issue-146-shared-context-visibility-implementation-plan.md` will turn §9 into tasks.

**Date:** 2026-09-15. **Live-code baseline:** `8b62f67eb` plus working tree.

**Issue:** [#146](https://github.com/Intersubjective/tentura/issues/146)
(parent [#142](https://github.com/Intersubjective/tentura/issues/142), related
[#78](https://github.com/Intersubjective/tentura/issues/78),
[#144](https://github.com/Intersubjective/tentura/issues/144),
[#145](https://github.com/Intersubjective/tentura/issues/145)).

**Amends:** ADR 0008 (needs Amendment B, see §10). It also supersedes the
one-edge / linked-detail part of
[`nested-requests-implementation-plan.md`](nested-requests-implementation-plan.md) §3.2
and the matching rows in [`docs/beacon-visibility-matrix.md`](../beacon-visibility-matrix.md).

---

## 1. Problem

On 2026-09-14, product testing showed that nested requests do not work as shared
work:

- From child «Дочерний 1», the parent shows **«Родительский запрос недоступен»**.
- A parent participant sees child «Похихикать» listed under Active. Opening it
  shows **«Запрос недоступен»**.
- A co-participant's profile shows a full card together with the text **«Сейчас вы не
  видите {name}»**.

Some of these are local bugs (§3.3). Underneath them is a **structural corner
case**. Access to a request, and visibility between people, comes today from exactly
two sources, and **neither is the shared work itself**:

1. **Trust**: explicit reciprocal trust or MeritRank mutual visibility
   (`person_are_mutually_visible`). Through D11, this also opens discoverable requests.
2. **The forward chain**: an active inbound `beacon_forward_edge`, plus invites,
   which materialize as forward edges.

Admission to a request (level 1, §2) grants rights on **that request only**.
The failure looks like this:

- I am forwarded request **A**, offer help, and get admitted.
- A co-participant X creates sub-request **B** under A.
- X and I have no mutual trust visibility, and nobody forwards B to me.
- So I cannot see B. The reverse direction fails the same way: as a member of B,
  I cannot see A.
- Between people it fails too. We joined forces on A, but until A ends and we
  review each other, MeritRank may give us no visibility. Our profiles contradict
  what we just did together.

This needs a systemic fix, not a fix per screen.

## 2. Product decisions (binding)

### 2.1 The access model

For a viewer V, every request R has exactly one **access level**:

| Level | Name | Meaning |
|---|---|---|
| **0** | Author | Owns R. |
| **1** | Member | Admitted by the author (or a steward). Reads everything, including the discussion. Writes in the discussion, works on the Plan, and so on. |
| **2** | Observer | Reads the card, details and public facts only. Can **apply** (offer help). Once the author approves, the observer becomes level 1. |
| **3** | Stranger | Does not see R at all, even through a direct link. |

A level-2 viewer is always there **for a reason**: forwarded, applied, discovered,
or (new) shared context. The level decides what V can see. The reasons decide which
extra rights and explanations apply (§5).

### 2.2 Decisions taken for this issue

| # | Decision |
|---|---|
| **D1** | **Hierarchy scope = ancestors + immediate children.** Being a member (level ≤1) of request N makes V an observer of every **ancestor** of N (the full chain to the root) and of every **immediate child** of N. Siblings, grandchildren and other branches get nothing from this rule. |
| **D2** | **Context observers are ordinary observers.** They can apply, forward, invite and fork under the same lifecycle checks as any level-2 viewer. There is no separate class of weaker observers. |
| **D3** | **The co-participant bond lasts until the review window ends.** Two members of the same request are mutually visible as people while the request is open-family or `reviewOpen`. The bond ends when the request reaches `closed`, `cancelled` or `deleted`, or when either person stops being a member. From then on, only trust (for example, trust created by the reviews) decides visibility between them. |
| **D4** | **The bond never feeds discovery.** The D11 clause (discoverable request + mutual visibility with its author ⇒ observer) keeps using **trust visibility only**. Working with someone on one request does not open their other discoverable requests. |

### 2.3 Defaults this document derives (confirm in review)

| # | Default | Why |
|---|---|---|
| **D5** | The hierarchy grant (D1) lasts **as long as V is a member of N**, whatever N's lifecycle. Closed or cancelled N still grants it. | Keeps a finished effort navigable for the people who did it. This matches the nested plan's "closed/cancelled admission can still grant a link read" rule. D3 limits only the **person** bond, which has wider effects (forwarding reach). |
| **D6** | Context grants come **only from membership (level ≤1)**, never from observation (level 2). | Keeps the rule non-transitive and bounded. Without this, being an observer of A would make you an observer of A's other children, and so on. |
| **D7** | Stay with the four levels. **Parentage never grants level 1.** Only the author or stewards admit. | This is the nested plan's non-negotiable outcome 2, and it still holds. D2 relaxes only the reasoning that kept level 2 away from the hierarchy. |
| **D8** | Blocks override every reason, for requests and for people alike. | Existing rule (ADR 0008, `block_hides`). |

## 3. Current state and root cause

### 3.1 The levels exist only implicitly

None of the four levels is a first-class concept today. Each one is rebuilt from
a different set of predicates:

| Concept | Where it lives today |
|---|---|
| level 0 | `b.user_id = viewer` repeated in every predicate |
| level ≤1 | `beacon_effective_admission` (m0155); `_canUseRoom` in `beacon_room_case.dart` / `beacon_fact_card_case.dart`; `BeaconHierarchyPolicy.hasEffectiveAdmission` |
| level ≤2 | `beacon_can_read_content` (m0169 body); Dart `BeaconVisibility.canReadContent` |
| involvement | `beacon_can_read_involvement` (m0124) = content ∧ (author ∨ forward edge either side ∨ active help offer ∨ admitted) |
| hierarchy | `beacon_can_read_linked_detail` (m0155); Dart `BeaconVisibility.canReadLinkedDetail` |
| person visibility | `person_are_mutually_visible` (m0161); the client derives its own copy from raw scores in `Profile.isMutuallyVisible` |

### 3.2 Surfaces pick different predicates

The #146 symptoms come straight from this table. Each surface asks a different
question about the same relationship:

| Surface | Predicate used today | Result for the #146 viewer |
|---|---|---|
| Child list on P (`beaconChildren` → `BeaconHierarchyRepository.listChildren`) | none on the server (the client asks capabilities first) | lists every published child |
| Opening a child (`BeaconFetchById` → Hasura `beacon` row filter) | `can_read_content` | row dropped → «Запрос недоступен» |
| Parent reference (`beaconParentReference` → `loadParentReference`) | admission to **the parent** | «Родительский запрос недоступен» for child members |
| Profile eye / copy | client-side MR scores | "you don't see {name}" next to a full card |

The nested plan (§3.2) meant "normal content of C = existing rule OR admission to
C's parent". Adversarial review then narrowed this to a separate `can_read_linked_detail`
used by "card and summary projections only", because widening `can_read_content` would
also have given forward, help-offer and invite rights. That narrowing is exactly what
produces "listed but cannot be opened". D2 removes the reason for it.

### 3.3 Local defects found on the way (fix regardless of this architecture)

1. **Parent reference checks the wrong direction.** `loadParentReference`
   (`S/data/repository/beacon_hierarchy_repository.dart`) tests the viewer's admission to
   the *parent*. Both the plan and the matrix say a member of the child sees its parent.
2. **`beaconChildren` has no authorization at all.** The resolver
   (`S/api/controllers/graphql/query/query_beacon_hierarchy.dart`) and `listChildren` never
   use `viewerId`. Anyone who knows a parent id can read child titles and owners. Blocks on
   child owners are not applied either.
3. **The profile copy is about something else.** «Сейчас вы не видите {name}»
   (`C/features/profile_view/ui/widget/profile_view_body.dart`) describes one-way
   MeritRank reachability. Profile read access is a different thing: Hasura `user` is
   filtered only by `hidden_for_viewer`, which means blocks.
4. **To verify: involvement leaks through content-only gates.**
   `coordination_case.dart::helpOffersWithCoordination` is gated by `canReadContent` alone.
   It shows who offered help to a discover observer, and after this change also to a
   context observer. `BeaconFactCardCase.list` appears to gate only room-visibility facts,
   with no content-read check on the request. Both should use the rights table in §5.

## 4. The model

### 4.1 Access as (level, reasons)

```text
BeaconAccess(R, V) = (level ∈ {0,1,2,3}, reasons ⊆ Reason)

Reason = author | steward | admitted          -- membership reasons (level ≤ 1)
       | forwarded | applied | discovered      -- existing observer reasons
       | contextAncestor | contextChild        -- new observer reasons (this doc)
```

Evaluation order stays exactly as in ADR 0008 and m0155:

1. block → level 3, no reasons;
2. draft → level 0 for the author, otherwise 3;
3. deleted → no normal access (tombstone path only);
4. otherwise level = min over the reasons present: author→0, steward/admitted→1, any
   observer reason→2; with no reasons, level 3.

**Involvement is a separate fact set, not a reason.** `beacon_can_read_involvement`
(m0124) admits a content reader on **either end** of an active forward edge, including
the sender. A discovered or context observer who forwards R therefore becomes
involved without gaining any access reason. `BeaconRights` (§7.1) takes
`BeaconInvolvementFacts` (author, forward edge as sender or recipient, active help
offer, member) next to `BeaconAccess`. `forwarded` stays **recipient-only** as an
access reason.

The existing observer reasons stay as they are:

| Reason | Fact (unchanged) |
|---|---|
| `forwarded` | active `beacon_forward_edge` with `recipient_id = V` |
| `applied` | `beacon_help_offer.status = 0` by V |
| `discovered` | `is_discoverable` ∧ open-family ∧ published ∧ `person_are_mutually_visible(V, author)`, **trust only** (D4) |

### 4.2 Hierarchy context reasons (new)

`member(V, N)` means `effective_admission(N, V)`: author, steward, or
`room_access = admitted`. N must be published and not deleted, and V must not be
blocked by N's owner.

```text
contextChild(R, V)    ⇔ R.parent ≠ null ∧ member(V, R.parent)
contextAncestor(R, V) ⇔ ∃ N : R ∈ ancestors(N) ∧ member(V, N)
```

R itself must be published, not draft, not deleted, and not block-hidden (steps 1–3
above). Consequences:

- A member of A observes every child of A and every ancestor of A.
- A member of B observes B's parent A, A's parent, and so on up to the root. They do
  **not** observe B's siblings or grandchildren unless something else grants that.
- Membership is the only input (D6), so the grant never chains. Being an observer of
  A grants nothing on A's other children.
- Revocation is instant. Leaving N (`room_access = left`), being removed, or getting
  blocked drops the grant on the next read. Nothing is materialized per viewer.

### 4.3 Co-participant bond (new)

```text
bond(a, b) ⇔ a ≠ b ∧ ¬block_hides(a, b)
           ∧ ∃ R : member(a, R) ∧ member(b, R)
                 ∧ R.published ∧ R.status ∈ {open, needsMoreHelp, enoughHelp, reviewOpen}
```

The bond is symmetric by construction. It ends (D3) when R leaves
open-family ∪ `reviewOpen`, or when either person stops being a member. `reviewOpen`
spans the review window, so "until the review window ends" and "until R becomes
terminal" are the same condition. A request closed without a review window ends the
bond at closure.

`bond` is **not trust**. It never writes MeritRank or `user_trust_edge`, it never
feeds D11 (D4), and it never shows up as a trust edge in Constellation.

## 5. Rights table

The rights table replaces the scattered `canReadContent`-then-something gates. It is
a pure domain function over `BeaconAccess` (§7.1). Rows marked *(new)* change behavior.
Every other row states today's behavior explicitly.

| Right | L0 | L1 | L2 forwarded | L2 applied | L2 discovered | L2 context* | L3 |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| Read details, images, public facts | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ *(new)* | ❌ |
| Read room-only facts, discussion, Plan | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Apply (offer help), open-family only | — | — | ✅ | (already) | ✅ | ✅ *(new, D2)* | ❌ |
| Forward / invite, `allowsForward` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ *(new, D2)* | ❌ |
| Fork as lineage source | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ *(new, D2)* | ❌ |
| Involvement (forward chain, offerers, rejections) | ✅ | ✅ | ✅ | ✅ | ❌‡ | ❌‡ | ❌ |
| List children | ✅ | ✅ | ✅ filtered† | ✅ filtered† | ✅ filtered† | ✅ filtered† | ❌ |
| Create child | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Parent reference shown as a link | if level(parent) ≤ 2 | ← same | ← | ← | ← | ← | ❌ |

\* `contextAncestor` or `contextChild`.
† Children are filtered per child by the same access function (§7.4). For a member of
P, every child qualifies through `contextChild`.
‡ Unless the viewer is otherwise involved, for example as the **sender** of an active
forward edge (§4.1). The involvement row is computed from involvement facts, not from
reasons, which preserves today's m0124 behavior.

**Involvement stays closed to context observers.** They see *that* the child exists
and what it asks for. Who offered help, who forwarded it and who declined stay with
the involved set. This matches the nested plan's product choice: "one-edge hierarchy
access exposes ordinary request details, without discussion admission or involvement
visibility."

## 6. Person visibility

### 6.1 Two named relations

```text
trustVisible(a, b)  = person_are_mutually_visible(a, b, ctx)       -- unchanged
personVisible(a, b) = trustVisible(a, b) ∨ bond(a, b)              -- new
```

`trustVisible` stays exactly as it is. Consumers **opt in** to `personVisible` by
name. The shared function is not widened in place, because D4 needs at least one
consumer to stay trust-only.

### 6.2 Consumers

| Consumer | Uses | Notes |
|---|---|---|
| D11 discovery clause in `beacon_can_read_content` | `trustVisible` | D4. |
| Forward candidate list (`forward_candidates_sql.dart`) and server recipient check (`ForwardCase`) | `personVisible` | Collaborators can route requests to each other while the bond is active. |
| Profile eye / visibility section, avatar badge, `PersonActionPolicy` | `personVisible` **with reasons** | Fixes the #146 profile contradiction. The copy names the context (§7.6). |
| Capability projection subject view (`CapabilityProjectionCase._canViewSubject`) | `trustVisible` (rev 3: deferred) | Moving it to `personVisible` needs a check against the subjective help-tag evidence disclosure rules first. Out of scope for #146. |
| Constellation field, trust edges, `person_visible_peers_symmetric` | `trustVisible` | Constellation is a trust view, so the bond is not trust. Showing co-participants as nodes there is out of scope (§12). |

### 6.3 Lifetime and history

When the bond ends, `personVisible` falls back to `trustVisible`. If the reviews
produced reciprocal trust, the two people stay visible to each other, and that is
the intended path. Their membership and the request's People list remain readable on
the closed request itself (level ≤1 still reads closed requests). No separate
"worked together" history grant is added.

## 7. Architecture

### 7.1 Domain (server, pure)

- `BeaconAccessLevel { author, member, observer, stranger }` and
  `BeaconAccessReason` (the enum in §4.1). A value class `BeaconAccess(level, reasons)`.
- `BeaconAccessPolicy.resolve(BeaconAccessFacts)` → `BeaconAccess`. This is the one
  pure definition. `BeaconVisibility.canReadContent`, `canReadInvolvement`,
  `canReadLinkedDetail` and `BeaconHierarchyPolicy.hasEffectiveAdmission` all become
  thin derivations of it, then get deleted once callers move.
- `BeaconRights.of(BeaconAccess, BeaconInvolvementFacts, BeaconStatus)` → a record of
  booleans for the §5 table.
  Use cases stop combining `canReadContent` with their own ad-hoc checks and ask for
  one right by name (`rights.canForward`, `rights.canApply`, …).
- `PersonVisibility(trust: TrustVisibilityState, bondBeaconIds: Set<String>)` with
  `isVisible`. `PersonVisibilityPolicy` is pure and fed by facts from a port.
- Ports: `BeaconAccessGuard.access({beaconId, viewerId}) → BeaconAccess` (keep the
  existing boolean methods as wrappers during migration); `PersonVisibilityRepositoryPort`
  gains `personVisiblePeerIds` next to the trust-only method, with the reason returned.
- *Rev 3 implementation note:* D2 makes every observer reason carry the same rights,
  so the existing `canReadContent` call sites are already the exact gate for
  read/apply/forward/invite/fork. The per-use-case `BeaconRights` refactor is
  **deferred**. This issue implements `BeaconAccessPolicy` (level + reasons) and only
  fixes the gates that differ (involvement and facts, §3.3/4).

This follows ADR 0008 decision 2: the domain owns the rule, SQL is the shared
enforcement adapter, and a parity test keeps the two from drifting.

### 7.2 SQL: one clause catalog, composed predicates

- One named SQL function per reason: `beacon_reason_forwarded(b, v)`,
  `…_applied`, `…_discovered`, `…_member`, `…_context_child`, `…_context_ancestor`.
  Each one is a single EXISTS with no recursion. These are the only place the facts
  are spelled out.
- Composed predicates, each a short-circuit `CASE` over the catalog in cheapest-first
  order:
  - `beacon_access_level(b, v) → smallint`
  - `beacon_can_read_content(b, v)` ≡ level ≤ 2. **Same name, widened body.** Hasura
    `beacon` / `beacon_image` select and `beacon_help_offer` insert pick up D2
    automatically, with no metadata change.
  - `beacon_effective_admission(b, v)` ≡ level ≤ 1.
  - `beacon_can_read_involvement` keeps its explicit involved-set conjunct (§5).
  - `beacon_can_read_linked_detail` and its Hasura computed field are **dropped** in
    phase 2. No legacy client needs them (§9).
- `beacon_access_reasons(b, v) → int` (bitmask) evaluates **every** clause. It is used
  only for single-request projections that explain "why you see this", never inside
  row filters.
- **The ancestor closure table** `beacon_ancestor(beacon_id, ancestor_id, depth)`,
  PK `(beacon_id, ancestor_id)`, index `(ancestor_id)`. Parentage is immutable
  (insert-only, enforced by the existing trigger), so the table is written by a single
  AFTER INSERT trigger: copy the parent's rows with `depth + 1`, plus `(id, parent, 1)`.
  It is never updated. Draft hard-delete cascades. A migration backfills it with a
  recursive CTE. `contextAncestor` is driven from the viewer's memberships:

  ```sql
  EXISTS (SELECT 1 FROM beacon_member m          -- eligible members only
          JOIN beacon_ancestor a ON a.beacon_id = m.beacon_id
          WHERE m.user_id = v AND a.ancestor_id = b.id)
  ```

  This is one PK probe per membership of V, independent of tree size.
- `beacon_member(beacon_id, user_id)`: a view over author ∪ `beacon_steward` ∪
  `beacon_participant (role = steward OR room_access = admitted)`, backed by a partial
  index on `beacon_participant(user_id, beacon_id)`. It is the single definition of
  "member", shared by the context reasons and the bond. **The view must apply the §4.2
  source-eligibility rules itself.** It joins `beacon` and keeps a row only when the
  source N is published, not draft, not deleted, and
  `NOT block_hides(N.user_id, m.user_id)`, exactly like `beacon_effective_admission`
  (m0155). Without this, a viewer blocked by N's owner would keep ancestor and child
  access, and a bond, through a raw participant row. No context or bond query may
  read `beacon_participant` or `beacon_steward` directly.
- `person_bond(a, b)` and `person_bond_peers(v)` (list form, for the forward picker).
  Both join `beacon_member` to itself on active requests. The existing hierarchy
  mutation lock (m0155, advisory lock on participant, steward, block and status writes)
  already serializes the facts these depend on.

### 7.3 Hasura

- No filter changes: the widened `can_read_content` body covers it.
- New computed fields on `beacon`: `access_level` and `access_reasons`, the latter for
  the detail view only. The client stops inferring its mode from `can_read_content`.
- New computed field on `user`: `person_visibility` (trust state plus bond request ids
  the viewer can read, JSON). Bond request ids are filtered by the viewer's own access.
  A bond only exists through a request both people are members of, so this discloses
  nothing new.

### 7.4 V2 hierarchy endpoints

- `beaconChildren`: require the viewer to be able to list children
  (`BeaconRights.canListChildren` on the parent). Filter each row with
  `beacon_can_read_content(child, viewer)`. Keep deleted children as tombstones under
  the existing `canReadTombstone` rule.
- `beaconParentReference`: authorize **both ends**. First require
  `beacon_can_read_content(child, viewer)`. If that fails, return the same not-found
  result as for a missing id, so an observer of P cannot learn that a hidden or
  block-hidden child hangs under P. Then return `available` iff
  `beacon_can_read_content(parent, viewer)`. Otherwise return `none` (no parent) or
  `unavailable`, which should no longer happen for members of the child. Today's
  `loadParentReference` checks neither end correctly (§3.3/1).
- `beaconHierarchyCapabilities`: `canListChildren` = level ≤ 2 on the parent;
  `canCreateChild` = level ≤ 1 on the parent plus `allowsCoordination` (unchanged).

### 7.5 Client

- The beacon view renders by `access_level`:
  - **member** (0/1): today's full view;
  - **observer** (2): details, public facts, parent link and accessible children,
    plus a primary **Offer help** CTA while open-family, and Forward;
  - **stranger**: the existing unavailable state.
- **The observer view must not fetch member-only data.** No room, Plan, People or
  help-offer queries. The mixed Sentry group `TENTURA-CLIENT-2T` ("Discussion is
  read-only", `notEligible`) is this mistake, already happening for discover observers.
- The reason banner, from `access_reasons`: «Вы видите этот запрос как участник
  «{A}»» for context, «Вам переслал {name}» for forwarded, and so on. It reuses the
  #78 principle that access should be explainable.
- The eye state comes from server `person_visibility`, not from raw scores. Trust
  direction labels (MR in/out) may stay as information, but they no longer drive gating.

### 7.6 Copy (sketch; final strings go through l10n review)

| State | EN | RU |
|---|---|---|
| Bond only | "You're working together on «{title}»" | «Вы работаете вместе над «{title}»» |
| Bond, footnote | "Visible to each other until reviews for this request close." | «Видите друг друга, пока не закончатся отзывы по этому запросу.» |
| Trust one-way (replaces "You don't currently see {name}") | "{name} isn't in your trust network yet" | «{name} пока нет в вашей сети доверия» |

The last row fixes defect §3.3/3 even before bonds ship.

### 7.7 Revocation, realtime, notifications

- A change to membership of N (admit, leave, remove, steward change), or to N's status
  or to blocks, can change V's access to **ancestors(N) ∪ children(N)** and the bond
  with N's members. The realtime contract
  (`docs/contracts/realtime-entity-contract.json`) needs an access-invalidation hint for
  V over that neighborhood. The hint carries ids only, and the client re-fetches through
  the gated path. Open observer screens then fall to "unavailable" on the next fetch,
  as ADR 0008 decision 5 already requires.
- Notification filter-at-read (`filter_beacon_notifications.dart`) uses
  `can_read_content` and picks up context reasons automatically. Hierarchy notices
  currently send "structural ids only, no private ancestor title" to child-only
  participants. That payload can now carry the ancestor title, because the recipient
  is an observer. This is optional follow-up, not required for #146.
- *Rev 3:* realtime neighbourhood invalidation is **deferred** to a follow-up.
  Access is re-checked on every fetch, so only live refresh of an already-open screen
  is missing. The v1 reason banner uses generic copy ("a related request") without
  naming it.

## 8. Invariants and tests

This extends suite **S4** of
[`algorithm-invariant-suites-plan.md`](algorithm-invariant-suites-plan.md). The sweep
is exhaustive over a small tree world: root, child, grandchild, sibling; four users;
every membership, forward, apply and block combination; every status.

| id | Invariant |
|---|---|
| S4-09a | **No relationship disclosure through ids.** Hierarchy endpoints return nothing about a request V cannot read, not even its parent id or its existence under a readable parent. |
| S4-09 | **No listed-but-inaccessible.** Every request id that any projection returns to V (children, parent reference, Activity, notifications, profile lists) has level(V, ·) ≤ 2, or is an explicit tombstone. |
| S4-10 | **Non-transitivity.** Removing every level-≤1 fact of V leaves V with no context reason anywhere (D6). A block by N's owner, or N becoming draft or deleted, removes every context reason and bond sourced from N. |
| S4-11 | **Parentage never admits.** No combination of hierarchy facts yields level ≤ 1 (D7). |
| S4-12 | **Bond lifetime.** `bond(a,b)` holds iff a shared request is open-family or `reviewOpen` and both are members. It is symmetric, and blocks kill it (D3, D8). |
| S4-13 | **Discovery is trust-only.** A bond with the author never adds `discovered` (D4). |
| S4-14 | **Scope.** A member of B is never an observer of B's siblings or grandchildren through context alone (D1). |
| S4-15 | **SQL/Dart parity** of `beacon_access_level`, `beacon_access_reasons`, the composed predicates and `person_bond` against `BeaconAccessPolicy` / `PersonVisibilityPolicy`, over the same fact matrix, run as `-x pg` tests against the deployed functions (F6 lesson). |

Existing S4-01…08 must keep passing. S4-07 ("forwarding creates no social tie") is
untouched, because the bond comes from **membership**, not from forwarding.

Also add: Hasura user-session tests, not admin tests, for the widened row filter and
the new computed fields. Add EXPLAIN ANALYZE on the hot `beacon` list queries (Inbox,
My Work, profile lists, notifications) before and after the change.

## 9. Delivery phases

| Phase | Content | Behavior change |
|---|---|---|
| **0** | §3.3 defects: parent-reference direction, `beaconChildren` authorization and per-child filter, profile copy, the observer view not fetching member-only data. | Bug fixes only. Independent of D1–D4. |
| **1** | Domain `BeaconAccess` / `BeaconRights` / `PersonVisibility`, the SQL clause catalog, the `beacon_member` view, and composed predicates that **reproduce today's behavior exactly**. Move use cases to the rights table. Add parity and S4 tests. | None (proved by parity). |
| **2** | `beacon_ancestor` + backfill, context reasons in the catalog, the widened `can_read_content`, dropping linked-detail. | D1, D2, D5, D6. |
| **3** | `person_bond`, the `personVisible` consumers (§6.2), the `person_visibility` computed field. | D3, D4. |
| **4** | Client access modes, reason banner, eye and copy from server facts, realtime invalidation. | UX. |

**No legacy-client support.** There are no production users, and the web build is the
only client. All phases ship as one release: one client version bump, and
`kDefaultMinClientVersion` raised to exactly that version. The design therefore has
no compatibility shims, kept aliases or soft-fail responses for old clients.

## 10. Superseded decisions and documents to update

- **ADR 0008 → Amendment B**: shared context (membership of an adjacent node) is a
  content-read reason. The co-participant bond is a person-visibility reason, and it is
  not trust. Also update the "Related: beacon nesting" paragraph.
- **Nested-requests plan §3.2**: the one-edge rule and the "linked detail only for
  projections" split are superseded by D1/D2. The consumer table's reasoning ("widening
  gives forward/help/invite rights") is accepted as intended behavior. Outcome 2
  (parentage never admits) still holds.
- **`docs/beacon-visibility-matrix.md`**: the rows "Parent-only admittee viewing child
  content ❌" and "Child-only admittee viewing parent content ❌", and the linked-detail
  section. It should gain a level/reason column.
- **`CONTEXT.md`**: § Beacon visibility & sharing, § Linked-detail visibility.

## 11. Risks

| Risk | Mitigation |
|---|---|
| The widened row filter slows every `beacon` read | The context clauses run last in the `CASE`. They are driven from V's memberships through PK probes, and phase 2 is gated on EXPLAIN ANALYZE of hot queries. |
| Forward reach grows: context observers and bonded collaborators can forward | Intended (D2, D3). The recipient still has to pass `personVisible`, and `allowsForward` still applies. The bond expires. |
| Large efforts: a root with many subtrees exposes every root-level child to every root member | Intended by D1 (immediate children of your node). Grandchildren still need membership. |
| Browsers still running a pre-release build | `kDefaultMinClientVersion` = release version forces a reload (§9). |
| Involvement leaks through content-only gates (§3.3/4) get wider audiences | Move those gates to `BeaconRights` in phase 1, before phase 2 widens anything. |

## 12. Out of scope

- Co-participants as Constellation nodes, or any Constellation change.
- Any history grant ("worked together") after the bond ends, beyond what the reviews
  produce as trust.
- Changes to admission itself: auto-admission, forwarding-vs-admission (#78 follow-ups).
- Leaving and declining (#144) and stale child invites (#145), except that their
  revocation now also removes context reasons and bonds, which S4-10/12 must cover.

## 13. Change log

- **rev 1** (2026-09-15): initial draft. Decisions D1–D4 taken by the product owner.
  D5–D8 derived here.
- **rev 2** (2026-09-15): Astra (codex) review round 1, three findings accepted:
  (high) `beacon_member` must enforce source eligibility (published, not deleted,
  owner block), otherwise blocks leak through context/bond, §7.2, S4-10;
  (high) the parent reference must authorize the child before revealing its parent,
  §7.4, S4-09a; (medium) involvement is a separate fact set, because a forward
  *sender* is involved without an access reason, §4.1, §5 ‡, §7.1.
- **rev 4** (2026-09-15): no legacy-client support (product owner). Linked-detail is
  dropped in phase 2, one release with a mandatory minimum client version raise (§9).
- **rev 3** (2026-09-15): implementation plan written. Deferred: the per-use-case
  `BeaconRights` refactor (§7.1 note), capability projection on the bond (§6.2),
  realtime neighbourhood invalidation and naming the related request in the banner
  (§7.7 note).
