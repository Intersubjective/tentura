---
status: draft
kind: design
---
# Blocking a user in a two-graph network — conceptual design

**Status:** draft, 2026-08-02. Conceptual + backend design only. UI is explicitly out
of scope (a later pass); this doc fixes *semantics, data model, enforcement points,
performance envelope, and network-dynamics consequences* so the UI has something
stable to render.

**Question this doc answers:** what does "block" mean in a product where the social
substrate is two graphs — the invite genealogy (a forest, immutable, historical) and
the MeritRank trust graph (weighted, decaying, ego-rooted) — and how do we implement
it without corrupting either one.

**Implementation:** [`user-block-implementation-spec.md`](./user-block-implementation-spec.md)
turns this into exact files, SQL, UI, tests, and a subtask breakdown. This document stays
the authority on *why*; the spec is the authority on *what to type*.

---

## 1. Grounded facts (what already exists)

Everything below was read out of the current tree, not assumed.

| Fact | Where |
|---|---|
| **No block/mute of users exists today.** `notification_beacon_mute` mutes a *beacon*, not a person. `complaint` is a report-to-admin email path with no enforcement. | `m0095`, `complaint_case.dart` |
| **Invite genealogy is a parent-pointer forest**, one row per descendant, with anonymize-on-delete and a chronology CHECK (`ancestor_created_at < descendant_created_at`) that makes cycles impossible. Indexed on `ancestor_node_key`. | `m0106` |
| **Trust math is typed and layered.** `user_trust_source_edge (trust_context, subject, object, s_*)` holds per-context Dirichlet accumulators; `trust_rebuild_effective_edge()` sums contexts × `trust_context_config.evidence_multiplier` × decay into `user_trust_edge`, then epsilon-gates a `mr_put_edge` publish. Contexts today: `personal`, `commitment`, `forward`, `legacy`. | `m0122` |
| **Evidence is append-only.** `trust_apply_source_evidence` only ever does `s_x = s_x + bump`. `setUserVote(amount: 0)` records `no_effect` mass — it does **not** subtract previously recorded `bad` mass. | `m0122`, `trust_math.dart` |
| **A negative user→user edge already exists as a product feature.** `userVote(objectId, amount: -1)` → bin `bad` → negative `prev_sent_weight`. Graph legend renders negative edges **red**. | `mutation_user_vote.dart`, `docs/relationship-states.md` |
| **MeritRank is ego-rooted.** `graph(focus, context, positive_only, hasura_session)` calls `mr_graph(<viewer id>, focus, …)`; `mutual_friends` calls `mr_mutual_scores` pairwise. **There is no global reputation scalar in this system.** | `m0108`, `mutual_friends` docs |
| **The beacon permission wall is a single chokepoint.** Hasura `beacon` select permission is `filter: {can_read_content: {_eq: true}}`, backed by one SQL function `beacon_can_read_content(beacon_id, viewer_id)`. | `hasura/metadata.json`, `m0124` |
| **`user`, `edge`, `mutual_score`, `graph_score` have `filter: {}`** — no row scoping at all. `user` is capped at `limit: 10`. | `hasura/metadata.json` |
| **`graph_edges_between(node_ids[], positive_only)` is exposed to role `user` with *no session argument*.** Any authenticated user can pass any pair of ids and read the exact signed `prev_sent_weight`. | `m0134`, `hasura/metadata.json` |
| **Background work has a home**: `TaskWorkerCase` + `trust_rebuild_effective_batch` cursor-batched sweep with a time budget. | `task_worker_case.dart`, `trust_maintenance_case.dart` |

---

## 2. The proposal contains three different features

The dialog as sketched ("only this user" / "+ everyone they invited" / "+ lower their
trust network's reputation") bundles three mechanisms with radically different blast
radius, reversibility, and abuse profile. Keeping them in one dialog is a UI question;
keeping them in one *mechanism* would be a mistake.

| | What it is | Blast radius | Reversible? | Who is affected |
|---|---|---|---|---|
| **B1 Shield** | viewer-scoped visibility + interaction filter | 1 pair | fully | blocker only |
| **B2 Cascade** | same filter, applied to a computed set | up to a whole invite subtree | fully | blocker only |
| **B3 Withdrawal** | zero the blocker's published MeritRank edge (§7) — **not optional, implied by any block** | those who route through the blocker, bounded by what the blocker had endorsed | fully | the blocker's own outgoing endorsement |

**B1 and B2 are pure filters.** They read like `WHERE NOT blocked` and can be undone by
deleting a row.

**B3 was originally scoped as negative evidence into the shared trust graph, and that
scoping is rejected** (§7). It would have been an *assertion about the world* that other
people's routing consumes, and — because `trust_apply_source_evidence` is additive — an
irreversible one: unblocking could only add `no_effect` mass to dilute the `very_bad`
mass, taking ~182 days per half-life to fade. *"Block, then unblock 30 seconds later"
would have permanently damaged the edge.*

**B3 is instead a publish gate: the blocker's outgoing MeritRank edge is zeroed while
the block stands, and the underlying evidence is untouched.** That makes it a
*projection* rather than an accumulation, which is what buys back full reversibility.
**Product decision: B3 is not a separate choice.** Blocking someone *is* ceasing to vouch
for them — offering that as a second checkbox would invite the incoherent state where the
blocker hides a person while still routing other people's requests toward them. So B1 and
B3 fire together, and the UI states the consequence rather than asking about it. Its blast
radius is bounded above by what the blocker had already endorsed, which means it is a
no-op against strangers and there is nothing to opt out of in the common case.

---

## 3. Block semantics

**This is not a shadowban, and the term is deliberately not used.** Product decision:
a block being *discoverable* by the blocked user is acceptable. Tentura's trust graph is
deliberately transparent — edge weights are readable, negative edges render red — and a
block is a legitimate, ordinary act that does not need to be disguised. That decision
removes a large amount of otherwise-unavoidable work: no disguised error codes, no
undetectability budget, no divergence between what MeritRank is told and what the graph
renders.

It also matches reality. In a graph product, information-theoretic undetectability is
unachievable anyway: Alice blocks Bob; Bob's mutual friend Carol still sees Alice, so
Bob can infer. Engineering against that was always going to be effort spent on an
outcome we could not deliver.

What we still do **not** do is *announce* it — there is no push, no inbox item, no "X
blocked you" banner. Discoverable is not the same as advertised. (D1a in §12 is the
knob if product wants to go further and show it explicitly.)

**Symmetric, not asymmetric.** Two readings of blocking:

- *Asymmetric* (classic shadowban): Bob still sees Alice and can still act; his actions
  are accepted and discarded. **Reject this.** It requires every write path to
  accept-and-void, producing ghost state everywhere (messages persisted but invisible,
  help offers accepted but never surfaced, forward edges that exist for one side only).
  The bug surface is enormous and the state is unauditable.
- *Symmetric* (recommended): neither sees the other on discovery surfaces; cross-pair
  writes are rejected at the entry point.

**Recommended block semantics (v1):**

| Dimension | Decision |
|---|---|
| Symmetry | symmetric hiding |
| Announcement | none — not notified, but not concealed either |
| Cross-pair writes | rejected at entry point; the error may be honest ("blocked"), no disguise required |
| Existing shared state | **not** retroactively destroyed (see §6.5 — rooms with open commitments) |
| Reversibility | full for B1/B2, and §7 keeps it full for B3 |
| Detectability | acceptable; no engineering spent on preventing it |

---

## 4. Data model

Two tables, neither exposed to Hasura (precedent: `account_credential` is
server-internal and absent from `hasura/metadata.json`). Keeping `user_block` out of
Hasura is a hard requirement: any client-readable projection of it defeats the whole
feature.

```sql
-- The materialized effective block set. One row per (blocker, blocked, why).
CREATE TABLE public.user_block (
  blocker_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  blocked_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  origin_id  text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_block_pkey PRIMARY KEY (blocker_id, blocked_id, origin_id),
  CONSTRAINT user_block__no_self CHECK (blocker_id <> blocked_id)
);
CREATE INDEX user_block_reverse_idx ON public.user_block (blocked_id, blocker_id);
CREATE INDEX user_block_origin_idx  ON public.user_block (blocker_id, origin_id);

-- The user's declared intent. One row per explicit block action.
CREATE TABLE public.user_block_intent (
  blocker_id     text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  blocked_id     text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  cascade_mode   smallint NOT NULL DEFAULT 0,   -- 0 none | 1 unattached | 2 all
  cascade_status smallint NOT NULL DEFAULT 0,   -- 0 pending | 1 running | 2 done | 3 capped
  cascade_cursor text,
  materialized_count integer NOT NULL DEFAULT 0,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_block_intent_pkey PRIMARY KEY (blocker_id, blocked_id)
);
```

`origin_id = blocked_id` marks a **direct** block; any other value marks a row
**inherited** from a cascade rooted at `origin_id`. This is why `origin_id` is in the
primary key: a user can be a descendant of two independently blocked roots, and
unblocking one must not un-hide them. Unblock is `DELETE … WHERE blocker_id = $1 AND
origin_id = $2` — one indexed range delete, correct under overlap.

**The single predicate every call site uses:**

```sql
CREATE OR REPLACE FUNCTION public.block_hides(_a text, _b text)
RETURNS boolean LANGUAGE sql STABLE PARALLEL SAFE AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_block WHERE blocker_id = _a AND blocked_id = _b)
      OR EXISTS (SELECT 1 FROM public.user_block WHERE blocker_id = _b AND blocked_id = _a);
$$;
```

Written as two `EXISTS` rather than one `OR` inside the `WHERE` so the planner gets two
clean index-only probes (PK prefix + `user_block_reverse_idx`) and can short-circuit.
One function name means the enforcement audit is a single `grep` — that matters when
the correctness argument is "we covered every surface".

---

## 5. Enforcement architecture

Two candidate strategies, and the reason the answer is a hybrid:

- **Read-time filtering everywhere.** Correct and reversible, but must be threaded
  through ~15 surfaces; one miss is a leak.
- **Write-time materialization** (delete the edges on block). Cheap reads, but
  destructive, unrestorable, and it mutates *third parties'* data (a room's participant
  list is not the blocker's to edit).

**Hybrid, in three layers:**

### 5.1 Layer 1 — read filter (the correctness backbone)

Ride the existing chokepoints instead of inventing new ones.

**The big win:** add the block clause *inside* `beacon_can_read_content`. Every surface
that already respects `can_read_content` — Hasura feed, beacon fetch, room access,
`beacon_can_read_involvement`, the forward guard in `ForwardCase` — inherits the block
with **zero Hasura metadata churn and zero new call sites**:

```sql
CREATE OR REPLACE FUNCTION public.beacon_can_read_content(p_beacon_id text, p_viewer_id text)
RETURNS boolean LANGUAGE sql STABLE AS $$
SELECT COALESCE((
  SELECT CASE
    WHEN public.block_hides(b.user_id, p_viewer_id) THEN false   -- NEW, first
    WHEN b.status = 3 THEN b.user_id = p_viewer_id
    …unchanged…
  END
  FROM public.beacon b WHERE b.id = p_beacon_id
), false);
$$;
```

This is consistent with the project's established preference for letting Hasura
silently drop unreadable rows rather than building parallel endpoints.

Remaining read surfaces, each needing an explicit filter:

| Surface | Mechanism |
|---|---|
| `user` (search / profile) | Hasura computed field `user.hidden_for_viewer(hasura_session)`, permission `filter: {hidden_for_viewer: {_eq: false}}`. Cheap: `limit: 10`. |
| `graph()` | wrap `mr_graph` output in `WHERE NOT block_hides(viewer, g.dst) AND NOT block_hides(viewer, g.src)` |
| `graph_edges_between()` | same, **plus** the session-scoping fix in §8.1 |
| `mutual_friends()` | filter both the result set and the two ego arguments |
| `user_presence` | add a permission filter |
| forward candidate lists (`beacon_lineage_suggestions_case`, `query_forward_graph`, `query_forward_inbound`) | filter recipients |
| `inbox_item`, attention recipients | filter in `AttentionIntentCase` recipient assembly, **before** the snapshot is recorded — recipients are frozen into an immutable payload, so filtering after the fact is not possible |
| invite genealogy | **anonymize, do not remove** — see §6.3 |

### 5.2 Layer 2 — write guards (prevent state that would need filtering)

Reject at the entry point so blocked interactions never create rows:

`ForwardCase.forward` (drop blocked recipients from the batch — the API is already
per-recipient result-keyed, so this is a natural per-recipient drop) · `HelpOfferCase` ·
`beaconRoomMessageSend` + room admission · `ContactCase.set` · invitation
accept (`/api/v2/invite/:code/accept-as-*`) · coordination item assignment.

Because §3 accepts detectability, these guards may return an **honest** error
("blocked by this user") rather than a disguised not-found. That is a real simplification:
disguising would have meant auditing every one of these paths for timing and error-shape
tells, and keeping that audit true forever.

### 5.3 Layer 3 — one-shot cleanup (only where leaving state would be worse)

On block, in the same transaction as the intent row:

- cancel pending `beacon_forward_edge` rows between the pair (`cancelled_at` is an
  existing modelled state — reversible-ish and non-destructive);
- withdraw the pair's `beacon_help_offer` rows in status 0;
- drop the pair's `user_contact` rows in both directions.

Deliberately **not** cleaned up: room participation with an open commitment (§6.4).

---

## 6. B2 — the invite cascade

**Direction: strictly downward.** The cascade set is the *descendants* of the blocked
user in `invite_genealogy` — everyone they invited, transitively. Ancestors are never
touched, and nothing in this section propagates upward. (§10.6 discusses a separate,
non-blocking moderation signal that does read upward; it is not part of the cascade.)

### 6.1 Descent alone is a bad membership criterion

The question is not *which direction* the cascade runs — it runs down — but *which
descendants belong in the set*.

The invite tree is a historical artifact, not a social structure. A user invited two
years ago by a bad actor may now be a well-integrated, high-trust member with hundreds
of independent edges. Taking the whole subtree hides people for who invited them — the
one attribute a user can never change. It also fails on its own terms: a sophisticated
spammer stops inviting from one account after the first ban.

**But the cascade has a real, legitimate purpose**: the actual threat is a burst of
sock puppets whose *only* connection to the network is the blocked account. So scope the
cascade by **standing, not by descent alone**:

```
cascade_mode 1 (default, recommended):
  descendants of the blocked root who have no independent standing —
  a *probationary* block, released automatically once they earn it (§6.3).

cascade_mode 2 (opt-in, depth- and size-capped):
  all descendants, permanently, until the block is lifted.
```

Mode 1 hits exactly the sock-puppet burst and leaves the integrated ex-invitee alone.

**"Independent standing" is blocker-relative, and that is what makes it cheap.** The
naive definition — "every positive inbound edge originates inside the blocked subtree" —
requires the subtree on every evaluation. It is also a proxy for the thing we actually
mean, which is simply: *does someone I trust vouch for this account?* Define it directly
and the subtree disappears from the predicate.

**Use mutual explicit trust, not a MeritRank edge, as the vouch primitive.** A single
`prev_sent_weight > 0` is far too weak: a one-way `userSubscribe` is a follow-grade act
that costs the voucher nothing, so one vouch releases a puppet. Mutual positive
`vote_user` — the product's canonical **"Mutual"** relationship state, already surfaced
as `is_mutual_friend` and already batch-queryable via
`VoteUserFriendshipLookupPort.reciprocalPositivePeerIds` — is the right primitive:

- **Higher intent.** It is a handshake, not a follow; both sides must act.
- **Deterministic.** `vote_user` is a plain table. `prev_sent_weight` is *the weight last
  published to MeritRank*, epsilon-gated and decaying, so it lags the live relationship —
  bad property for a predicate that gates visibility.
- **No MeritRank dependency.** The release path keeps working when the MR service is
  degraded.

Not `user_contact`: it is a private address-book label (you may well name someone you
distrust), and it is **auto-upserted on invite consumption** from
`invitation.addressee_name` (`m0085`) — a signal partly produced by the invite flow
itself is unusable as evidence about that same flow.

**Mutuality alone still does not stop a two-account attacker** — an attacker who keeps
one "clean" account outside the subtree owns both ends of the handshake and can vouch
every puppet out. The fix is the blocker-relative half: the voucher must be someone the
**blocker** mutually trusts. Then releasing a puppet requires subverting an account the
blocker has personally vouched for, which is a categorically harder problem (and if it
happened, the blocker has a bigger issue than this puppet).

**The blocker is their own strongest voucher.** "The voucher must be someone I mutually
trust" cannot be satisfied by the blocker themselves — that would require a self-vote —
so a naive reading of the rule would sweep up *people the blocker personally mutually
trusts* whenever one of their ancestors is blocked. That is the worst possible false
positive, and now that B3 keys off the effective set (§7.2) it would also silently
withdraw the blocker's endorsement of someone they explicitly vouched for. It needs its
own clause, checked first:

```sql
CREATE OR REPLACE FUNCTION public.block_cascade_unattached(
  _blocker text, _root text, _candidate text
) RETURNS boolean LANGUAGE sql STABLE PARALLEL SAFE AS $$
  SELECT NOT (
    -- (a) I mutually trust them myself — the strongest standing there is
    EXISTS (
      SELECT 1
      FROM public.vote_user m_out                   -- blocker -> candidate (PK probe)
      JOIN public.vote_user m_in                    -- candidate -> blocker (PK probe)
        ON m_in.subject = _candidate AND m_in.object = _blocker
      WHERE m_out.subject = _blocker AND m_out.object = _candidate
        AND m_out.amount > 0 AND m_in.amount > 0)
    -- (b) or someone I mutually trust vouches for them
    OR EXISTS (
      SELECT 1
      FROM public.vote_user v_out                   -- candidate -> voucher (PK range scan)
      JOIN public.vote_user v_in                    -- voucher -> candidate (PK probe)
        ON v_in.subject = v_out.object AND v_in.object = _candidate
      WHERE v_out.subject = _candidate
        AND v_out.amount > 0 AND v_in.amount > 0
        AND v_out.object <> _root
        -- a voucher I have blocked does not count
        AND NOT EXISTS (
          SELECT 1 FROM public.user_block ub
          WHERE ub.blocker_id = _blocker AND ub.blocked_id = v_out.object)
        -- and the voucher must be someone I mutually trust
        AND EXISTS (
          SELECT 1 FROM public.vote_user b_out      -- blocker -> voucher (PK probe)
          JOIN public.vote_user b_in                -- voucher -> blocker (PK probe)
            ON b_in.subject = b_out.object AND b_in.object = _blocker
          WHERE b_out.subject = _blocker AND b_out.object = v_out.object
            AND b_out.amount > 0 AND b_in.amount > 0))
  );
$$;
```

Properties that fall out of this formulation:

- **Sock puppets cannot vouch each other out.** A puppet's only mutual peers are other
  puppets in the same burst; they are in the blocker's block set (discarded by the first
  `NOT EXISTS`) and are certainly not mutually trusted by the blocker (discarded by the
  second `EXISTS`). Escaping requires a vouch from inside the blocker's own trusted
  circle — the same sybil-resistance principle MeritRank itself runs on, applied at the
  set level.
- **A fresh account always evaluates to `true`** (no `vote_user` rows at all), which is
  precisely why inheritance at signup is correct and free (§6.2).
- **No subtree walk, no reverse index.** Every access is a PK range scan or PK probe on
  `vote_user (subject, object)` plus a PK probe on `user_block`. The outer scan is bounded
  by the candidate's out-degree.
- **Tunable strictness.** Dropping the second `EXISTS` yields a laxer "anyone unblocked
  vouches" variant; keeping it is the recommended default. This is a one-clause dial, not
  a redesign.

The recursive CTE is still needed **once**, for the initial backfill of the root's
existing subtree. The chronology CHECK on `invite_genealogy`
(`ancestor_created_at < descendant_created_at`) makes it a DAG, so termination is
guaranteed without a visited-set:

```sql
WITH RECURSIVE sub AS (
  SELECT descendant_node_key AS k, descendant_user_id AS uid, 1 AS depth
  FROM public.invite_genealogy WHERE ancestor_user_id = _root
  UNION ALL
  SELECT g.descendant_node_key, g.descendant_user_id, sub.depth + 1
  FROM public.invite_genealogy g JOIN sub ON g.ancestor_node_key = sub.k
  WHERE sub.depth < _max_depth
)
SELECT uid FROM sub s WHERE s.uid IS NOT NULL
  AND (_mode = 2 OR public.block_cascade_unattached(_blocker, _root, s.uid));
```

### 6.2 Materialize, never compute on read

Evaluating that CTE inside a permission filter is not survivable. The cascade set is
**materialized** into `user_block`, by the task worker, cursor-batched, with a cap
(suggested: 5 000 rows / depth 6 per intent; `cascade_status = 3` when capped). During
materialization the block is partially applied — acceptable, and the direct block (the
part the user actually cares about) lands synchronously.

**New signups inherit for free — in both modes.** This is the part that actually stops
an ongoing sock-puppet stream: the blocked account keeps inviting *after* the block, and
those accounts are the threat. Because `invite_genealogy` stores only direct parent
edges, one AFTER INSERT trigger gives transitive correctness by induction — if the
parent is in the block set, the child is added when it appears:

```sql
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
SELECT ub.blocker_id, NEW.descendant_user_id, ub.origin_id
FROM public.user_block ub
WHERE ub.blocked_id = NEW.ancestor_user_id
  AND EXISTS (SELECT 1 FROM public.user_block_intent i
              WHERE i.blocker_id = ub.blocker_id
                AND i.blocked_id = ub.origin_id
                AND i.cascade_mode > 0)
ON CONFLICT DO NOTHING;
```

**The trigger needs no mode branch and no standing predicate.** An
`invite_genealogy` row is only ever written at signup, so at trigger time the descendant
is brand new and has no trust edges — `block_cascade_unattached` is unconditionally
`true` for it. Mode 1 and mode 2 therefore inherit identically; they differ only in
(a) the initial backfill of the *pre-existing* subtree (§6.1) and (b) whether the
probationary release sweep runs (§6.3). One indexed scan on `user_block_reverse_idx`
per signup.

**The propagation frontier gates itself.** If Bob is blocked, Bob invites Carol (who
later earns standing and is released), and Carol then invites Dave — Dave's parent is
Carol, Carol is no longer in `user_block`, so Dave does not inherit. Someone who came in
through a person with independent standing is not treated as a puppet. That behaviour
falls out of the induction for free; it does not need a rule of its own.

### 6.3 Release: a mode-1 inherited block is probation, not a sentence

Mode 1's promise is "hidden **until** you earn independent standing". Inheritance at
signup (§6.2) covers the sock-puppet stream; the release sweep is what keeps that from
becoming corruption of blood, and it is the direct answer to §10.2.

A periodic task-worker pass — same shape as `TrustMaintenanceCase.runDue`: cursor,
batch size, time budget, env knobs — deletes inherited rows whose subject has since
earned standing:

```sql
DELETE FROM public.user_block ub
USING public.user_block_intent i
WHERE i.blocker_id = ub.blocker_id
  AND i.blocked_id = ub.origin_id
  AND i.cascade_mode = 1
  AND ub.blocked_id <> ub.origin_id              -- inherited rows only, never the root
  AND NOT public.block_cascade_unattached(ub.blocker_id, ub.origin_id, ub.blocked_id);
```

Notes:

- **Never releases the directly blocked root** (`blocked_id <> origin_id`), and never
  touches a direct block the user made themselves.
- **Release republishes the trust edge.** Because B3's gate keys off `user_block` (§7.2),
  deleting an inherited row must be followed by
  `trust_rebuild_effective_edge(blocker_id, blocked_id, -1)` so the honest weight returns.
  One call per released row; skip it when the pair has no `user_trust_edge` row, which is
  the common case.
- **Mode 2 never releases** — "I want this whole branch gone" is explicit intent.
- **Promotion escape hatch.** If the blocker looks at an inherited entry and decides they
  want that person gone on their own merits, the UI writes a *direct* row
  (`origin_id = blocked_id`). Direct rows are outside the sweep's `WHERE`, so they are
  permanent until manually lifted. Inherited = provisional, direct = deliberate.
- **Cost.** Per blocker the sweep is bounded by their inherited-row count (itself capped
  at 5 000 per intent), and each row is a handful of PK probes. If it ever needs to get
  cheaper, hoist the blocker's mutual-trust peer set with
  `reciprocalPositivePeerIds` — one indexed round trip per blocker — and reduce the
  second `EXISTS` to a set-membership test.
- **Latency is fine.** Release is not security-critical in the urgent direction: being
  hidden one sweep-interval too long is a mild false positive, so this can run on a slow
  cadence (hours) with a small time budget.

### 6.4 Genealogy rendering: anonymize, don't delete

You cannot remove a node from a *tree* render without disconnecting its subtree. So
blocked users in the invite genealogy must become **placeholder nodes**, not absences.

This is nearly free: `invite_genealogy` already models anonymized nodes for deleted
users (`descendant_deleted_at` / `ancestor_deleted_at`, `user_id → NULL`), and
`_buildNodes` in `invite_genealogy_repository.dart` already handles `user == null`
nodes. Block-hiding maps directly onto the existing deleted-user placeholder path — a
few lines in the overlay assembly, no new rendering concept, and the placeholder is
indistinguishable from a deleted account, which is exactly the ambiguity we want.

The trust graph has no such constraint — it is not a tree, so blocked nodes are simply
omitted.

### 6.5 The open-commitment problem

If Bob is an active participant in a beacon room with an accepted commitment and Alice
(the author) blocks him, the §5.1 change ejects Bob from a room where he has a
real-world obligation. That is a product decision, not an engineering one:

- **(a) Hard eject** — simple, consistent, may break real coordination.
- **(b) Grandfather open commitments** — the block hides them from each other's
  *discovery* surfaces and blocks *new* contact, but an existing room with an open
  commitment stays readable until it closes. Requires an exception branch in
  `beacon_can_read_content` keyed on `beacon_commitment` status.
- **(c) Hard eject + a warning at block time** ("you have an open commitment with this
  person"), pushing the decision to the user.

**Recommendation: (c).** It keeps the SQL simple, keeps the semantics predictable, and
surfaces the cost to the person who is choosing to pay it.

---

## 7. B3 — withdrawal of endorsement (publish gate, not negative evidence)

**Decision (supersedes the negative-evidence design):** B3 zeroes the blocker's published
MeritRank edge into the blocked user. It is a **gate at publish time**, not a write into
the trust model. The evidence stays where it is; only what MeritRank is told changes.

### 7.1 What it actually does (the original UI wording is wrong)

"Lower the reputation of their whole trust network" describes a global scalar that does
not exist in this system. MeritRank here is **ego-rooted**: `mr_graph(viewer, focus, …)`,
`mr_mutual_scores(a, b)`. What zeroing the Alice→Bob edge actually does:

1. **Alice's own view** of Bob, and of everyone reachable primarily *through* Bob,
   drops — her walks no longer traverse that edge.
2. **Third parties whose walks pass through Alice** lose that path too, so Bob's cluster
   drops for them *proportionally to Alice's own standing with them.*
3. **Bob's "reputation" in any absolute sense: unchanged**, because there is none.

Property (2) is the elegant part and is worth stating in the product language:
**the weight of your withdrawal is your own standing.** A newcomer's block moves
nothing; a well-connected member's block moves a lot, for exactly the people who trust
them.

The honest one-line description is now **"stop vouching for them"**, not "reduce their
reputation" — and unlike the old wording, that one is accurate.

### 7.2 Implementation: gate `mr_put_edge`, touch nothing else

`trust_rebuild_effective_edge` (`m0122`) is the single publish chokepoint. The whole
feature is one branch in it:

```sql
  -- … unchanged: _w computed from user_trust_source_edge × context multipliers × decay,
  -- and user_trust_edge.s_* written with the honest projection …

  _target := CASE
    WHEN EXISTS (SELECT 1 FROM public.user_block
                 WHERE blocker_id = _subject AND blocked_id = _object)
    THEN 0 ELSE _w END;

  IF abs(_target - _prev) > _eps THEN
    PERFORM mr_put_edge(_subject, _object, _target, ''::text, 0);
    UPDATE public.user_trust_edge SET prev_sent_weight = _target, updated_at = now()
    WHERE subject = _subject AND object = _object;
  END IF;
```

Block and unblock both become: write/delete the `user_block` row, then call
`trust_rebuild_effective_edge(blocker, blocked, -1)`. The `-1` is the existing
epsilon-bypass already used by `trust_resync_source` — needed because the *target*
changed while `_w` did not, so the normal epsilon gate would suppress the republish.

Why this is strictly better than the negative-evidence design it replaces:

- **No new schema at all.** No `block` trust context, no widened CHECKs, no
  `trust_set_block_edge`, no calibration constant. One `CASE` expression.
- **Genuinely no information loss.** `user_trust_source_edge`, `trust_evidence_event`,
  and `user_trust_edge.s_*` are all written exactly as today. `prev_sent_weight` keeps
  its documented meaning — *what was last published* — so the epsilon bookkeeping stays
  honest. Unblock replays the honest weight bit-for-bit; there is nothing to reconstruct.
- **It cannot be aimed at strangers.** If Alice never endorsed Bob, the edge is already
  ~0 and zeroing is a **no-op**. The action's power is bounded by what the blocker
  previously gave. The negative-evidence design had the opposite property: it *created*
  an edge where none existed, manufacturing a relationship in order to make it negative.
- **It removes the §8.3 dependency entirely.** Deleting an edge from a random walk has
  well-defined semantics in every PPR-family algorithm; propagating a *penalty* along a
  negative edge does not, and was unverified. B3 is now implementable without that
  experiment.
- **Reversible by construction**, so §8.2 (append-only evidence) simply does not apply.

None of these reasons depend on concealment, so §3's decision that blocks may be visible
does not reopen the penalty design. Zeroing wins on reversibility, on not being aimable at
strangers, and on not resting on an unverified MeritRank property — independently of who
can see what.

**One verification item, much smaller than the old §8.3:** confirm that
meritrank-service treats a 0-weight edge as inert rather than pathologically (e.g.
divide-by-zero during normalization). If it does misbehave, switch to `mr_delete_edge`
plus the existing `meritrank_edge_tombstone` retry path from `m0122` — that machinery
already exists. `mr_put_edge(…, 0)` is preferred because it keeps MeritRank's edge set
stable, making unblock a plain re-publish.

**Directionality: gate the blocker's outgoing edge only.** Alice blocks Bob ⇒ gate
Alice→Bob. Do **not** gate Bob→Alice: Bob's endorsement is Bob's to give and Alice's to
benefit from, so zeroing it would punish the blocker, and Bob would see his own edge
vanish from his own graph. Note this differs from B1, where *visibility* is symmetric —
visibility is symmetric, endorsement withdrawal is one-directional.

**Cascade interaction: B3 keys off the effective block set, i.e. B2's result.** The
`EXISTS` above queries `user_block`, which is the *materialized effective set* — direct
and inherited rows alike. It therefore covers cascade members with no extra code;
restricting B3 to direct blocks would mean *adding* a clause (`AND blocked_id = origin_id`),
not removing one. Do not add it.

This is the coherent choice, not merely the cheap one. If Alice hides a puppet from her
own view but keeps publishing a positive edge to it, she goes on **vouching for that
account to the entire network** — routing other people's requests toward someone she has
declared she wants nothing to do with, while being blind to the consequences of her own
endorsement. The visibility filter and the routing endorsement must not disagree.

The earlier objection ("bulk withdrawal destroys the blocker's own graph") was a leftover
from the penalty design and does not survive: nothing is destroyed. Source accumulators
and the evidence ledger are untouched, so release or unblock republishes the honest weight
bit-for-bit.

Two operational notes:

- **Bound the work by edges, not by subtree size.** The block/unblock path should issue
  `trust_rebuild_effective_edge` only for pairs that actually have a published edge:
  `… WHERE EXISTS (SELECT 1 FROM user_trust_edge e WHERE e.subject = _blocker AND
  e.object = ub.blocked_id AND e.prev_sent_weight <> 0)`. For a puppet burst this is
  empty — fresh accounts have no edge from the blocker — so the common case costs
  nothing regardless of cascade size.
- **Release must republish.** The §6.3 sweep, when it deletes an inherited row, calls
  `trust_rebuild_effective_edge(blocker, released, -1)` to restore the honest weight.
  One call per released row, and releases are rare by construction.

### 7.3 How the gate interacts with graph rendering

Since §3 accepts that the trust graph is publicly readable, there is nothing to hide
here — but two mechanical consequences still matter:

- **The B1 graph filter is still required.** Zeroing Alice→Bob does not zero Bob→Alice,
  so `graph_edges_between([alice, bob])` would still return Bob's row. The explicit
  `block_hides` filter on graph reads (§5.1) does that work; the gate does not replace it.
- **Positive-only views self-clean.** `user_trust_edge_degree(positive_only)` and
  `graph_edges_between(positive_only)` both key off `prev_sent_weight`, so the gate makes
  the blocker's own edge drop out of those views automatically — no extra filter needed
  for that direction.

The two-column `posterior_weight` scheme considered earlier is **dropped**: it existed
only to hide a penalty from the target, and neither the penalty nor the hiding survives.

---

## 8. Findings in current code that this feature touches

### 8.1 `graph_edges_between` is globally readable — accepted, by decision

`graph_edges_between(node_ids text[], positive_only boolean)` is exposed to role `user`
with **no `hasura_session` argument** (`hasura/metadata.json`), and `graph_score` has
`filter: {}`. Any authenticated user can pass any array of user ids and read the exact
signed `prev_sent_weight` of every edge among them, including edges they have no
relationship to.

**Product decision: this is intended, not a defect.** The trust graph is deliberately
transparent (§3) — weights are readable and negative edges render red — so an open
pairwise-weight endpoint is consistent with the product rather than a leak. It is
recorded here only so the property is explicit rather than accidental. The one factual
consequence to hold in mind: because the endpoint is unscoped and takes an arbitrary id
array, the full pairwise trust graph is harvestable by an authenticated client. That is
the same decision, stated at scale.

Nothing in this design depends on changing it. B1's `block_hides` filter on this function
(§5.1) is still required — for the *filtering* semantics, not for concealment.

### 8.2 Evidence is append-only, so any toggle built on it is a one-way door

`trust_apply_source_evidence` only ever does `s_x = s_x + bump`; `setUserVote(0)` adds
`no_effect` mass rather than removing `bad` mass. **B3 as now designed sidesteps this
entirely** (it is a publish gate, not a write). The finding is kept because it applies to
*any* future "reversible reputational action": if it writes evidence, it is not
reversible, and a toggle built on it is a one-way door. Design such features as
projections, not as accumulations.

### 8.3 MeritRank's negative-edge semantics — no longer blocking

Whether meritrank-service `v0.9.0` propagates penalties along negative edges, or merely
treats a negative weight as a near-zero transition probability, was **the** open risk
under the negative-evidence design. **B3 no longer depends on it** — removing an edge
from a random walk is well-defined in every PPR-family algorithm.

It still matters for the *pre-existing* `userVote(-1)` feature and for the red-edge graph
legend, both of which are live today and both of which quietly assume propagation. Worth
running on the local stack when convenient, but it no longer gates this work:

1. Seed a small synthetic graph: `A → B → C → D`, all positive.
2. Record `mr_node_score(A, D)` and `mr_graph(A, …)`.
3. `mr_put_edge(A, B, -1.0, '', 0)`; re-read.
4. If C and D drop *from A's ego* → penalties propagate. If only B changes, then
   `userVote(-1)` is operationally just an unsubscribe, and the product language around
   it should be corrected.

The *new*, much smaller verification item — does a 0-weight edge behave inertly, or does
it need `mr_delete_edge` — is described in §7.2.

### 8.4 Degree counts are computed on the unfiltered graph

`user_trust_edge_degree()` counts the unfiltered graph, so after blocking, a neighbour's
displayed degree will exceed the number of nodes the blocker can actually expand.
Recomputing it filtered is a per-row correlated subquery on a hot path. **Accept**: under
§3 there is nothing to conceal, and the cosmetic mismatch is visible only to the blocker,
about their own action.

---

## 9. Performance and database impact

**Table size.** `user_block` is negligible for B1 (most users block 0–5 people). B2 is
the only scaling risk: a cascade over a hub's subtree is O(subtree). Mitigated by the
mode-1 default (sock puppets only), the 5 000-row cap, and task-worker batching. Even a
pathological 100 k-row materialization is unremarkable for Postgres — what matters is
that it never happens inside a request transaction.

**Read amplification.** One or two index-only probes per candidate row on filtered
surfaces. On the beacon feed, `can_read_content` is *already* a per-row `STABLE`
function doing up to four `EXISTS` subqueries; adding a fifth is a marginal delta
(expect <10%, but measure with `EXPLAIN (ANALYZE, BUFFERS)` on a seeded feed before and
after). The `user` search surface is capped at `limit: 10` — irrelevant.

**The genuinely hot path** is `graph()`, which calls `user_trust_edge_degree` once per
returned node, and each call scans `subject = n OR object = n`. There is an index on
`user_trust_edge(object)` (`m0114`) and the PK covers `subject`, so this is a BitmapOr
of two index scans per node × up to 100 nodes. Adding a `block_hides` filter is cheaper
than the degree call already there; it should be applied as an outer filter so blocked
nodes never reach the degree computation.

**Write cost of block/unblock.** Direct block: 2 inserts + a handful of cancels + (if B3)
one `trust_rebuild_effective_edge(…, -1)` — a pair advisory lock, a recompute over that
pair's source contexts, and one `mr_put_edge`. Bounded and synchronous; the epsilon
bypass makes the publish unconditional, which is the point. Unblock is the identical
call. Cascade: async.

**Client cache invalidation.** Ferry caches feed/graph/profile lists aggressively. A
block must invalidate a broad set of cached queries at once — reuse the machinery in
`docs/plans/beacon-cross-screen-invalidation-refactor.md` rather than inventing a
per-screen refresh. This is often where "the block didn't work" bug reports come from.

**Rate limiting.** Blocks — especially with cascade — are a resource. Reuse the existing
env-knob rate-limit pattern from the security hardening pass. Suggested: N blocks/day per
account. B3 no longer needs its own *scarcity* budget (it cannot exceed what the blocker
already endorsed), but a limit is still worth having so bulk scripted withdrawal shows up
in telemetry (§10.5).

---

## 10. Consequences for network dynamics

This is the part most likely to be underestimated, so it gets the most space.

**1. Blocking a hub silently amputates the blocker's own reach.** In a network whose
value proposition is *routing requests along trust paths*, removing a well-connected
node removes every path through it. The user experiences this as "the app got quieter"
and will not attribute it to their own block. **Mitigation: quantify the cost at block
time** — "this will hide N people currently reachable through them" is one
`mr_graph`-backed count and turns an invisible consequence into an informed choice.

**2. A whole-subtree cascade is corruption of blood.** The cascade runs downward — that
part is right; the risk is taking *every* descendant. Addressed by the mode-1 default
(§6.1). Worth restating as a principle: *the cascade's purpose is anti-sybil, so it must
be scoped by sybil-ness.* Any design that hides people for who invited them, rather than
for what they are, will eventually hide someone valuable and will never tell them why.

**3. Exclusion without recourse — mitigated on two fronts.** A user can be excluded from
a large part of the network with no explicit signal. Two things keep this from being a
trap. First, B1/B2 are **viewer-scoped**: no single block ever removes anyone from the
*network*, only from one person's view. That is the invariant that keeps the feature
safe — guard it, and never let B1/B2 write shared state. Second, §3's decision that blocks
need not be concealed means a user who suspects they have been blocked can find out, and
an appeal is at least *possible* — which it would not have been under a true shadowban.

B3-as-withdrawal is the one action that reaches past the viewer, but it reaches only as
far as the blocker's own prior endorsement, so it cannot exclude anyone the blocker had
not previously vouched for.

**4. Polarization and fragmentation — much reduced by the withdrawal design, not gone.**
Under the rejected negative-evidence design this was the headline risk: correlated blocks
would inject negative mass, MeritRank would do exactly what it is designed to do, and the
graph would separate into components that cannot reach each other — the network stops
working while every individual score still looks healthy.

Zeroing is far more benign: it removes endorsement rather than manufacturing accusation,
so a blocked cluster loses *inbound flow from the blockers* and nothing more. There is no
amplification beyond withdrawal, and no mechanism by which two communities can push each
other below zero. What remains is ordinary graph thinning: if two clusters mutually
withdraw at scale, the paths between them do disappear. That is a real risk, but it is
linear in the number of blocks rather than super-linear, and it is exactly what the
watch metrics in item 7 are for. It is still enough reason to keep B3 a deliberate
graph thinning that the watch metrics in item 7 exist to catch. Since B3 fires with every
block and follows B2's effective set (§7.2), the pacing control is not a separate opt-in —
it is the block rate limit plus the fact that withdrawal is bounded by prior endorsement.

**5. Standing-weighted withdrawal is proportionate, unlike a standing-weighted penalty.**
Property (2) in §7.1 cuts both ways: a high-standing user's withdrawal moves a lot. But
the ceiling is what they had already given, which makes this closer to "a respected
member stops vouching" than to "a respected member issues a sanction". The remaining
mitigations are cheap and still worth having: (a) audit-log every B3 action with ids only
— consistent with the existing id-only audit-metadata invariant, so account deletion
needs no ledger scrub; (b) a modest per-account rate limit, mainly to make bulk scripted
withdrawal visible. The "ramp the effect in over days" idea from the penalty design is
**dropped** — with no accusation to detect early, it would only add latency and
confusion.

**6. A separate upward *signal* (not a cascade) is worth harvesting.** The blocking
cascade itself stays downward (§6). But if the invite tree exists to make inviters
accountable for who they bring in, then blocks also carry information in the other
direction: "many independent users blocked people this account invited" says something
about the *inviter*. That belongs in a **moderation dashboard**, never as automatic
propagation — automatic upward blocking would recreate corruption of blood mirrored.
Cheap to compute from `user_block` + `invite_genealogy`, and entirely optional.

**7. Watch metrics.** Cheap to add, and they are how you find out the feature is being
abused before users tell you: distribution of blocks issued per account; distribution of
blocks received; accounts with high inbound blocks and zero complaints (moderation
signal); accounts issuing many blocks (griefing signal); cascade materialization sizes;
count of pairs where a block cut the last path between two otherwise-connected
components (fragmentation early warning).

---

## 11. Recommended scope

**v1 — B1 + B3.**
`user_block` + `user_block_intent` + `block_hides` + the `beacon_can_read_content`
clause + the enforcement matrix in §5 + the withdrawal gate (§7.2). Symmetric, fully
reversible. This alone satisfies "stop this person from bothering me", which is the actual
user need behind ~95% of block presses.

B3 rides along because it is one `CASE` expression and because a block that leaves a
positive published edge standing is incoherent. The only shared state it touches is the
blocker's own outgoing endorsement, bounded by what they had already given.

**v2 — B2 (cascade), mode 1 only.**
Task-worker materialization, inheritance trigger (§6.2), release sweep (§6.3), genealogy
placeholder rendering, size/depth caps. Mode 2 ("all descendants") stays behind a cap and
is not the default.

**B3 (withdrawal) ships inside v1, not as a later phase.**
One `CASE` in `trust_rebuild_effective_edge` plus the epsilon-bypass rebuild on
block/unblock (§7.2). The only prerequisite is the small 0-weight-edge check in §7.2.
It applies to the whole effective block set, so when v2 lands it follows the cascade with
no further work.

The earlier draft kept it as a separate opt-in phase; product folded it in, because a
block that leaves a positive published edge standing is incoherent — the blocker would go
on routing other people toward someone they have hidden. What remains is an id-only audit
record and the shared block rate limit.

---

## 12. Open decisions for product

| # | Decision | Recommendation |
|---|---|---|
| D1 | Symmetric or asymmetric hiding? | Symmetric (§3) |
| D1a | Is the block *shown* to the blocked user, or merely discoverable? | **Decided: not a shadowban** — detectability is accepted and no effort is spent concealing it, but there is no notification or explicit indicator either. Flipping to an explicit indicator later is a UI change only (§3) |
| D2 | Eject from rooms with an open commitment? | Hard eject + warning at block time (§6.5) |
| D3 | Cascade default: sybil-scoped or all descendants? | Sybil-scoped, mode 1 (§6.1) |
| D3a | Vouch primitive for "independent standing" | Mutual positive `vote_user`, **and** the voucher must be mutually trusted by the blocker (§6.1) |
| D3b | Do inherited mode-1 blocks auto-release once standing is earned? | Yes — that is what makes mode 1 defensible (§6.3) |
| D4 | ~~Is B3 silent or public?~~ | **Obsolete** — §3 accepts visibility, so there is nothing to conceal and no column split (§7.3) |
| D4c | Is B3 opt-in? | **No** — every block withdraws. The UI states it as a consequence, never as a checkbox; there is no `penalize` flag anywhere in the schema (§2) |
| D4a | Does B3 gate the reverse edge (blocked → blocker) too? | No — withdrawal is one-directional even though visibility is symmetric (§7.2) |
| D4b | Does B3 apply to cascade members? | **Yes** — it keys off the effective block set, so B2's result drives it; the alternative would require extra code and would leave the blocker vouching for people they have hidden (§7.2) |
| D5 | Do blocked users' messages disappear from *third-party* rooms both are in? | Defer past v1; if adopted, use placeholders (removal breaks reply threading) |
| D6 | Does the pre-existing `userVote(-1)` remain a separate, independently reachable action? | Yes, and it stays semantically distinct: `userVote(-1)` **asserts distrust** (negative edge, renders red), B3 **withdraws endorsement** (edge goes to 0). Both are visible; they mean different things. Do not merge them |
| D7 | ~~Penalty mass / multiplier~~ | **Obsolete** — no penalty mass exists under the withdrawal design |
