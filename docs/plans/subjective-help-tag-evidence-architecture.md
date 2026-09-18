# Subjective Help-Tag Evidence — Architecture

**Status:** architecture draft, rev 5, awaiting approval. Shape only — no implementation steps, no file-by-file task breakdown, no migration numbering. Product decisions D1–D14 were taken interactively during design (2026-08-12) and are binding on any implementation plan derived from this document; D15–D24 were forced by two adversarial review passes and are equally binding. All open decisions blocking implementation are now closed; §20 lists only calibration and copy questions.

**Revision history:** rev 5 — Kimi K3's pass (the strongest single review of the five): tier precedence re-derived as channel-first after rev 4's Tier A split inverted seed-vs-outcome; §17.3 named a regression mechanism that is dead code (the real path is `viewerVisible` ← `fetchDeduplicatedCapabilities` ← source 2); §16.1's `acknowledgeHelp` predicate rejected the author and former committers, who are exactly the subjects D21 permits; §5.5's early return skipped Tier A for a brand-new ego; §13.4 conflated admission with sufficiency (single-observation sufficiency holds only near `m = 1`); §12.1's "never revealed" softened to "not exposed by any read API" after block- and context-diff oracles; the MeritRank quantile claim now cites its out-of-repo source; §13.1 arithmetic corrected to 0.448.

rev 4 — multi-model adversarial pass (Grok 4.5, Gemini 3.6 Flash, Kimi K3) plus a third codex pass. **D23 withdrawn** as non-monotone (§7); the disclosure machinery the plan had already deleted was still specified here in §4.1/§4.2/§5.5, making the two documents mutually executable only if one were ignored; the personalised-PageRank mass-conservation claim in §13.2 was overstated and is now qualified — eligibility, not mass, is the load-bearing defence; single-observation sufficiency (`0.333 > θ_out`) documented honestly in §13.4, including that an inviter is decisive for every invitee; Tier A split by channel so own-routing stops rendering as own-outcome; §15 no longer calls cells authoritative; profile context recorded as decided (D24), not open.

rev 3 — second adversarial pass, which verified only one of rev 2's ten claimed fixes. Corrections: rev 2's own projection SQL reverted D15 by summing all witnesses then applying `bool_or` (§14); D19 had no storage representation, so pre- and post-disclosure mass could not be separated (§4.1); D16 had no atomic submit/finalize cutover and `ReviewCloseSnapshot` carried no acknowledgement set (§6.1); `forwardContext` could not implement its own band because ordering needs `S`, which may not cross the API boundary (§16); ego tombstones were keyed on the witness and so could never match (§5.5); the block matrix omitted witness↔subject (§16.2); the profile/seed rules contradicted each other via Tier A (§5.4 matrix, D22); `myRoutingTags` was an objective subject-tag signal (§12.2); exploration was not total or stable (§9); rev 2's "structural" MR margin was itself an over-correction — publication is epsilon-gated and failure is swallowed (§13.2); the 24-month window had no enforcement path and cited a dropped function as precedent (§7); D8's "author" was contradicted by an authorization table admitting every evaluator (D21).

rev 1 — initial design. rev 2 — corrected against an adversarial architecture review (codex, `architecture_reviewer` posture, clean-architecture skill). Five blocking findings: outcome evidence was not tied to a positive or finalized outcome (D16); ledger/cell/rebuild had no atomicity or locking contract (§14.1); the Forward composer had two contradictory seed write paths (D17); `forwardContext` could not use the Forward screen's selected MR context (§16); no operation had an authorization contract (§16.1). Plus one unsound formula (existential eligibility gate → D15), one stale precedent (m0122 restructured trust; `vote_user` is *not* decoupled from MR — §2.1, §13.2), two false privacy claims (forward reasons are sender/recipient-only; a deployment timestamp is not consent — §17.1), and a missing layer allocation (§4.5).

**Scope:** the mechanism by which Tentura accumulates *subjective typed memory of cooperation* and spends it in the Forward flow. Not a people-search feature, not a skills profile, not a reputation layer.

---

## 0. One-page summary

The premise of the brief — "build subjective typed evidence" — is already half-true in shipped code. `person_capability_event` has stored `(observer, subject, tag_slug, source_type, beacon_id)` since m0048; four sources write to it live; the Forward screen already renders capability chips prioritised by the request's `needs`; and the 37-slug help taxonomy (`CapabilityTag` ↔ `beacon.needs` ↔ `beacon.primary_need_slug`) already spans request creation, forwarding and closure.

What does **not** exist is the thing that makes it subjective: there is no witness layer. Today a viewer sees only evidence they authored themselves — plus one leak. And the leak is the exact anti-pattern the brief forbids: `commitRole` events are written with `observerId == subjectId` (a self-declaration) and read **subject-scoped** rather than observer-scoped, so every viewer sees them. That is `Carol.skills = [...]`, shipped, self-editable by committing to any request.

So this architecture is **an extension and a correction**, not a new subsystem:

1. **Correct** the subjectivity violation — `commitRole` is excluded from every projection, self-view included (D18). The *candidate set* an author picks from when acknowledging help comes from the active help-offer state, not from ledger history.
2. **Add** a derived accumulator layer (`capability_evidence_edge`) that mirrors the `user_trust_source_edge` pattern — inflated bumps against a fixed anchor, lazy decay at read — one row per `(witness, subject, tag)`.
3. **Add** the witness layer: third-party evidence reaches an ego only after being weighted by that ego's MeritRank score for the witness, and only from witnesses the ego admits — the bar being a percentile of the ego's own explicit vote list, not a fixed constant (§5.2.1).
4. **Spend** the result in a capped, labelled band above the Forward list, with reserved exploration slots — never as a filter, never as a score, never as a verdict.

Nothing is materialised per `ego × target × tag`. MeritRank is read-only to this feature; tag evidence never writes back into MR.

---

## 1. Decisions this architecture encodes

| # | Decision |
|---|---|
| **D1** | **Reject tags-as-Dirichlet-bins.** Bins in `user_trust_edge` are mutually-exclusive outcomes of one trial; tags are not exclusive. Reuse the *mechanism* (inflated accumulators, fixed anchor, lazy decay, saturating posterior mean with prior mass K) per `(witness, subject, tag)` cell, not the bin semantics. |
| **D2** | **`commitRole` (source_type 2) is dropped as evidence entirely.** Events keep being written for audit only. Superseded in scope by D18: excluded from *every* projection, self-view included. |
| **D3** | **Forward ranking uses a reserved context band** above the untouched MR-ordered list — 3 evidence slots + 2 exploration slots. Tag evidence can never reorder the main list. |
| **D4** | **Subject control is a per-tag routing mute.** Aggregate view, no witness names, no counts. Muting suppresses third-party projection only; it never suppresses a viewer's own first-hand evidence. |
| **D5** | **Two seed paths:** the `invite_accepted` Update prompt (newcomers) and `forwardReason` on a forward edge (behavioural, already captured). Private labels are **never** seeds. |
| **D6** | **Profile shows own evidence + witness-derived outcome only.** Seed-derived tags appear in Forward only. |
| **D7** | **No sensitive-tag class in v1.** All 37 slugs behave identically. Residual risk documented in §13.6. |
| **D8** | **Outcome tags** are chosen from `beacon.needs ∪ activeHelpOffer(subject).helpTypes`. (Chooser widened from "the author" to author + co-committers by D21.) |
| **D9** | **Band matches all of the request's needs**; a row labels only the tags that actually matched, primary first, capped at 2 labels. |
| **D10** | **Memory horizon:** `H_out = 365d`, `H_seed = 90d`, hard 24-month exclusion window. |
| **D11** | **Exploration is deterministic:** no-evidence candidates, MR-ordered, minus anyone forwarded to in the last 30 days, rotated by `hash(request_id)`. |
| **D12** | **Cap 3 tags per `(subject, beacon)`** — across *all* acknowledging evaluators, not per evaluator. Under D21 a per-evaluator cap would let N committers inflate one request into 3N rows for the same person. |
| **D13** | **Display gate:** `θ_out = 0.30`, `θ_seed = 0.25`. Eligibility is **not** a constant: it is the 33rd percentile of the ego's own explicitly-trusted peers by `forward_mr` ("top 67%"), computed as a SQL quantile. **Only eligible witnesses contribute to `S` at all** — see D15. |
| **D14** | **Acknowledgements are revocable indefinitely.** Withdrawal is a witness correcting their own memory, not a request re-opening (S3 untouched); the cell is rebuilt from the 24-month ledger window. |
| **D15** | **Eligibility gates the contributing set, not a boolean.** `S` sums over eligible witnesses only; ineligible witnesses contribute zero rather than mass behind an existential flag. Supersedes the earlier `S ≥ θ ∧ ∃ eligible` formulation, which was unsound (§19.13). |
| **D16** | **Outcome evidence is emitted at review *finalization*, not at evaluation submission**, and only for evaluations whose finalized value is `pos1` or `pos2`. Acknowledgement selections are mutable evaluation state until the window closes. |
| **D17** | **`source_type 4` is invite-only.** The Forward composer writes forward reasons through the Forward mutation alone; it never writes a standing attestation. |
| **D18** | **`commitRole` is excluded from every projection, including self-view.** D8's candidate set comes from the *active help-offer state*, not from ledger history. |
| **D19** | **Aggregation eligibility is a source-type rule, not a consent gate.** `privateLabel` and `commitRole` never aggregate; `forwardReason`, `closeAcknowledgement` and `seedRoutingAttestation` always do. Pre-launch decision (2026-08-12): with no production deployment and no shipped clients, there are no rows written under a narrower promise and no client that could write without showing the wording, so the former disclosure-version interlock was removed as insurance against a risk that does not exist. Disclosure wording remains a **launch requirement**, enforced by product review rather than by the data model. |
| **D20** | **Every new operation carries an explicit authorization predicate** (§16.1). Actor identity is JWT-derived; no operation trusts a client-supplied actor. |
| **D21** | **Author and co-committers may acknowledge; forwarders may not.** Roles `author`, `committer`, `formerCommitter` qualify. Forwarders are excluded because they never observed the work and already express routing judgement through the seed channel — granting them outcome rights would let "seen helping with" be minted by someone who only passed a message along. Supersedes D8's "chosen by the author" wording. |
| ~~D23~~ | **Withdrawn, on two independent grounds.** *Mechanically* it is non-monotone: weights are burned into ledger rows ego-independently while admission is per-ego, so an extra acknowledger a given ego does *not* admit drops that ego's `S` below θ and **erases** evidence a trusted witness supplied — corroboration must never subtract, and every weight-division scheme has this property. *Conceptually* it was correcting the wrong quantity: a budget guards against inflating **intensity** ("how much has Carol done"), but this system measures **evidential quality** ("is it true Carol helps with this"), for which independent attestations of one event legitimately do accumulate. See §7. |
| **D24** | **Profile projection uses the canonical default context (`''`)**, not the viewer's selected context — a profile is not a browsing-context-scoped object, and having the same person's profile change as the viewer switches contexts is confusing and untestable. Closes the former §20.6b. |

| **D22** | **Profiles render the outcome channel only, at any tier** (§5.4 matrix). Tier alone does not authorise a surface; the channel does. |

---

## 2. Current state

### 2.1 What exists

| Artifact | Where | Role after this change |
|---|---|---|
| 37-slug taxonomy | `CapabilityTag`, `beacon.needs`, `beacon.primary_need_slug` | Unchanged. The single ontology for requests, evidence, seeds and projection. |
| `person_capability_event` | m0048 + successors | Becomes the immutable **provenance ledger**. |
| `privateLabel` (0) | viewer's own notes; unique per `(observer, subject, tag)` | **Ego tier only, forever.** Never witness-aggregated, and never surfaced on the subject's own routing screen (§12.2). |
| `forwardReason` (1) | written on forward edges; readable by **sender or recipient only** (`observer = viewer OR subject = viewer`) | Becomes **seed evidence** under D19. |
| `commitRole` (2) | self-declared help types, `observer == subject` | **Dropped as evidence, including self-view (D18).** |
| `closeAcknowledgement` (3) | written at evaluation; observer-scoped **plus a subject self-view branch** | Becomes **outcome evidence**, emitted at finalization (D16). |
| `is_negative` tombstones | viewer-scoped hide; unique index on active tombstones | Unchanged. Ego-scoped suppression of any tier. |
| `person_visibility_peers(viewer, ctx)` | m0140 | Canonical source of `forward_mr` and `viewer_explicitly_trusts_subject`. |
| `invite_accepted` | Updates receipt kind | Host for the seeding prompt. |
| `user_trust_source_edge` / `user_trust_edge` | m0122 | Pattern donor — see the correction below. |

**Correction — the trust precedent is not what earlier revisions of this document claimed.** m0122 restructured it: `trust_apply_evidence`, `meritrank_sweep`, `trust_recompute_all` and `trust_resync_source` were **dropped**. Fixed-anchor accumulators now live in **`user_trust_source_edge`**, keyed by `(trust_context, subject, object)`; `user_trust_edge` is an **effective projection** whose anchor is reset on rebuild. `docs/features/trust_edges.md` still documents the old m0088 world and is stale.

Two things follow. First, the pattern this design borrows is the *source-edge* accumulator, not `user_trust_edge`. Second — and more consequentially — **`vote_user` is not decoupled from MeritRank.** `userVote` writes trust evidence with `TrustSourceType.userVote`, which rebuilds and publishes the MR edge. An explicit vouch therefore does create a direct subject→object contribution to MR, which makes the eligibility floor's safety margin substantially stronger than §13.2 previously conceded.

### 2.2 What is wrong today

- **Subjectivity violation.** `commitRole` is read subject-scoped, so a self-authored claim is globally visible. Fixed by D2.
- **No witness layer.** Evidence produced by anyone other than the viewer is invisible, so the core loop of the brief does not exist.
- **No decay, no saturation, no weighting.** Ranking is `COUNT(*)`. Ten repetitions from one account beat one confirmation from a trusted friend.
- **Retro-exposure hazard.** `privateLabel` rows were written under a private-note promise; `closeAcknowledgement` rows were viewer-scoped. Neither is ever aggregated — a source-type rule, not a timing rule (§17.1).

---

## 3. Recommended architecture

Four layers, each with one job:

```
  LEDGER          person_capability_event
                  append-only, provenance, soft-delete
                        │  (bump on write / rebuild on revoke)
                        ▼
  CELLS           capability_evidence_edge(witness, subject, tag)
                  s_out, s_seed, anchor_at
                  per-witness saturation + lazy decay
                        │  (joined at read)
                        ▼
  WITNESS WEIGHT  ego_witness_window(ego, context, witness, m, admitted)
                  weight      m = min(1, forward_mr / R_ego)
                  eligibility explicit trust OR forward_mr ≥ 33rd pct of
                              the ego's own vote list
                  cached, MR read-only
                        │
                        ▼
  PROJECTION      computed on demand, never materialised
                  Tier A (own) / Tier B (witness outcome) / Tier C (witness seed)
```

Load-bearing properties of this split:

- **Saturation is per-witness, in the cell.** One account cannot out-shout the network no matter how much it writes.
- **Credibility is per-ego, in the window.** The same cell is worth different amounts to different egos. This is where subjectivity physically lives.
- **Nothing recursive.** A cell's witness is always the person who directly observed the event. Beliefs are never inputs to other beliefs; MeritRank already carries transitivity, and re-deriving it here would double-count and let one witness launder a farm.
- **One-directional dependency on MR.** Tag evidence reads `forward_mr` and never writes any MR edge. A feedback loop between two subjective layers would be unanalysable.

---

## 4. Domain / data model

### 4.1 Ledger — `person_capability_event` (existing, extended)

Adds one source type:

```
source_type 4 = seed_routing_attestation
```

Uniqueness rules that carry real weight:

| Source | Unique on | Effect |
|---|---|---|
| `seed_routing_attestation` (4) | `(observer, subject, tag)` where not deleted | One standing attestation per witness per tag. Re-answering the invite prompt replaces, never stacks. |
| `forwardReason` (1) | `(observer, subject, tag, forward_edge)` | See the edit-semantics note below — keying by beacon is wrong. |
| `closeAcknowledgement` (3) | `(observer, subject, tag, beacon)` | One outcome observation per request. Farming requires distinct requests. |
| `privateLabel` (0) | `(observer, subject, tag)` (already exists) | Unchanged. |

**Forward-reason edit semantics.** An earlier revision keyed these by `(observer, subject, tag, beacon)` and claimed re-editing a forward's reasons would not accumulate. It does not hold: the key carries no forward-edge identity, so two distinct forwards to the same recipient on the same request collapse into one row, while changing a reason from Transport to Pets leaves the stale Transport row active and adds Pets. Reasons are **current-edge state, not event history** — they are keyed by forward edge and reconciled as a set on every edit, so withdrawing a reason withdraws its evidence.

**And that reconciliation is transactional.** Both live paths are best-effort today: creation catches a reason-write failure and commits the forward anyway; the update path commits the note first, then catches an append-only reason failure. Set reconciliation cannot be built on either — a partial write leaves the edge saying one thing and the ledger another, with no signal that they diverged. **The forward edge, its reason set and the resulting cell mutation are one mutation boundary**, for create and edit alike; failure rolls back the whole state change. This is the same rule §14.1 applies to acknowledgements, and it has the same reason: a derived cell is only as trustworthy as the atomicity of the write that fed it.

**Constraints, stated accurately.** Source 0 is not the only uniqueness rule today — there is also a unique index on active tombstones. `source_type` has **no database CHECK constraint**, which this design should add rather than assume. And the ledger is not strictly immutable: soft-deletion and replacement mutate rows, so "append-only" describes intent, not the schema.

**Provenance.** Every cell is reconstructible from its ledger rows within the 24-month window. Not every row names a beacon — private labels and invite attestations are beaconless by nature — so provenance is carried by a source-specific reference (forward edge, beacon, or invitation), not by `beacon_id` alone.

### 4.2 Cells — `capability_evidence_edge` (new, derived)

```
PK (observer_user_id, subject_user_id, tag_slug)
    s_out           real         -- inflated accumulator, outcome channel
    s_seed          real         -- inflated accumulator, seed channel
    anchor_at       timestamptz  -- fixed at row creation, never advanced
    built_from_gen  bigint       -- ledger generation this cell was built from (§14.1)
    next_expiry_at  timestamptz  -- oldest contributing row's exit from the window (§7)
    updated_at      timestamptz
```

Cardinality is O(distinct evidence triples), not O(users²·tags) — sparse, comparable to the ledger's own row count.

The cell is built from `forwardReason`, `closeAcknowledgement` and `seedRoutingAttestation` rows only. `privateLabel` and `commitRole` never reach a cell, so their exclusion cannot be forgotten at a read site — there is nothing to filter, because it was never accumulated.

### 4.3 Witness window — `ego_witness_window` (new, cached)

```
PK (ego_user_id, context, witness_user_id)
    m             real     -- min(1, forward_mr / R_ego)         → weight
    admitted      boolean  -- explicit trust OR forward_mr ≥ floor → CONTRIBUTES (D15)
    computed_at   timestamptz
```

Both columns come from the same `person_visibility_peers(ego, context)` pass, which already returns `forward_mr` and `viewer_explicitly_trusts_subject` on one row; `floor` is one `percentile_cont` aggregate over that result set.

**On `admitted` and layer ownership.** Materialising a boolean that encodes a business rule inside a cache table is, read strictly, the data layer deciding witness admission. The resolution is that the **domain owns the rule and supplies its parameters**; the cache stores the raw facts (`forward_mr`, `viewer_explicitly_trusts_subject`) plus the derived `floor`, and `admitted` is a mechanical materialisation of a predicate the domain handed down — not a policy the repository chose. If the admission rule ever needs inputs the cache cannot see, `admitted` must be dropped and the predicate applied in the domain over raw facts, at the cost of a larger intermediate result. The rule of thumb: this column may encode *the domain's* predicate; it may never *define* one.

Top **K = 200** peers by `forward_mr` from `person_visibility_peers(ego, context)`. Peers outside the window contribute exactly zero — an approximation that can only ever *remove* evidence, and Sybils live in the tail.

`context` is the same string the Forward candidate query already passes. Witness credibility lives in the same MR context as visibility. This is **not** per-tag MeritRank (§19.8).

### 4.4 Mute — `capability_routing_mute` (new)

```
PK (user_id, tag_slug)
```

### 4.5 Layer allocation

§3's four "layers" are **storage stages, not Clean Architecture layers**, and naming them that way invited exactly the wrong reading: allocate tables and API operations, leave cross-table validation and rebuild policy to whoever writes the repository. `UI → Data → Domain → nothing` still governs, and every piece below has an owner.

| Concept | Layer | Owner |
|---|---|---|
| `CapabilityEvidence`, `TagProjection`, `EvidenceChannel`, `ProjectionTier` | **domain** | Freezed types. No Drift, no Ferry, no JSON. |
| Acknowledgement set, qualifying-value rule, cap enforcement | **domain use case** | review finalization orchestration — the evidence emission joins the existing finalization workflow rather than sitting beside it |
| Tier policy, thresholds, precedence, mute application, band composition, exploration | **domain use case** | a capability-projection use case; these are product rules and must be unit-testable without Postgres |
| Cell arithmetic (inflate, deflate, saturate) | **data / SQL** | behind a port. Atomic implementation detail, not policy. |
| Ledger + cell persistence, rebuild, sweep | **data repository** | implements domain ports; performs each mutation atomically (§14.1) |
| `ego_witness_window` cache | **data** | an adapter over `person_visibility_peers`; the domain sees a witness-weight port, never a cache table |
| GraphQL resolvers | **api** | call use cases only; never a repository directly |

Two consequences worth stating because both are easy to get wrong:

- **"Math lives in SQL" applies to arithmetic, not policy.** Decay and saturation belong in SQL for atomicity, exactly as the trust accumulators do. Thresholds, witness admission, tier assignment, precedence, caps, mutes and visible ordering are business rules; a repository query that decides what a user sees has moved policy out of the domain. The trust precedent does *not* license this — that design wraps its SQL arithmetic in typed domain evidence and use-case orchestration.
- **Server use cases import `domain/port/` only.** D8's validation reads the committer's declared help types, which the domain entity currently exposes as a **nullable JSON string** while writes accept `List<String>`. Implementing D8 against that shape forces a use case to parse storage JSON. The port must decode in data and expose a typed collection.

### 4.6 What is deliberately absent

No `Person.skills[]`. No global tag counter. No `(ego, subject, tag)` materialisation. No per-tag graph. No score column anywhere that a UI could accidentally render.

---

## 5. Derivation algorithm (exact)

### 5.1 Cell strength

Write (VSIDS inflate against the fixed anchor — identical in spirit to `trust_apply_evidence`):

```
s_out  += count · 2^( (now − anchor_at) / H_out  )
s_seed += count · 2^( (now − anchor_at) / H_seed )
```

Read (deflate with the matching factor):

```
f_o = 2^( −(now − anchor_at) / H_out  )        H_out  = 365d,  K_o = 2
f_s = 2^( −(now − anchor_at) / H_seed )        H_seed =  90d,  K_s = 1

e_out (w,c,T) = f_o·s_out  / (K_o + f_o·s_out )      ∈ [0,1)
e_seed(w,c,T) = f_s·s_seed / (K_s + f_s·s_seed)      ∈ [0,1)
```

Two accumulators share one anchor; only the exponent differs. Overflow of the inflation factor is accepted, as it already is for trust edges (≈250 years at `H_seed`).

Outcome saturation table (`K_o = 2`, undecayed):

| observations | 1 | 2 | 3 | 5 | 10 | 50 |
|---|---|---|---|---|---|---|
| `e_out` | 0.33 | 0.50 | 0.60 | 0.71 | 0.83 | 0.96 |

### 5.2 Witness weight

```
R_ego     = median( top-3 forward_mr in ego's window )   -- max() when fewer than 3 peers
m(ego, w) = min(1, forward_mr(ego, w) / R_ego)
```

`R_ego` is a **per-ego constant**, independent of the query, of the target, and of which witnesses happen to hold evidence. That independence is the whole Sybil argument (§13.2) and it is the one thing in this document that must not be "optimised" later into a per-query normalisation.

`median` rather than `mean` because the estimator draws on three samples and one dominant contact would otherwise wreck it: with scores `0.5, 0.02, 0.015`, the mean is `0.178`, so the ego's *second-closest* contact scores `m = 0.11` and the feature quietly dies for that ego. The median gives `0.02`, and #1 and #2 both clamp to `1.0`. Dividing by any query-independent constant preserves the Sybil bound, so the choice of estimator is free on that axis and should be made purely for robustness.

`R_ego` calibrates the **evidence threshold** `θ` — it puts `S` on an interpretable scale. It plays no part in eligibility, which is §5.2.1's job. Two questions, two mechanisms, no shared constant.

### 5.2.1 Sole-witness eligibility

A witness may carry a tag **alone** only if the ego's own revealed standard admits them:

```
pop(A)   = { forward_mr(A,v) : v explicitly trusted by A (vote_user), forward_mr > 0 }
floor(A) = percentile_cont(0.33) WITHIN GROUP (ORDER BY forward_mr) over pop(A)

sole_witness_eligible(A,w)  iff  explicitly_trusted(A,w)
                             OR  forward_mr(A,w) ≥ floor(A)
```

The ego's explicit `vote_user` edges are a revealed-preference calibration of *whose word she would take*. Dropping the weakest third of that list sets her bar; anyone MeritRank places at or above it may stand alone. There is no tunable constant, the standard is self-calibrating per ego, and it is unforgeable — an attacker cannot insert themselves into Alice's vote list.

Three properties worth stating explicitly, because each has a plausible-looking variant that breaks:

- **The population must be the ego's vote list, not the ego's window.** MeritRank's quantile bounds are *rank*-based — `position = i · scores.len() / num_quantiles`, over every node with `score >= f64::EPSILON` (engine source, outside this repository: `meritrank-rust` `service/src/aug_graph/scores.rs` → `service/src/utils/quantiles.rs`; verified 2026-08-12). Note the live path (m0140) does not use quantiles at all — this argument concerns a rejected alternative, so a bar of "top 67% of your window" has boundaries the attacker controls: 30 real peers plus 100 reachable Sybils makes the top 67% cover 87 nodes, of which 57 are Sybils, all now eligible. Reachability alone would buy eligibility. Anchored to the vote list, stuffing lifts the bar exactly as fast as it lifts the attackers (§13.2) and the population itself cannot be stuffed.
- **A percentile, not a `min`.** `min` is the 0th percentile, and one stale vouch to a low-but-positive-MR account would collapse the bar, leaving `θ` as the only barrier — which is precisely the regime a sponsored swarm survives. The 33rd percentile is the robust form of the same idea.
- **Empty `pop(A)` yields no eligibility at all.** `percentile_cont` over an empty set is NULL, the comparison fails, and the ego sees Tier A only. Correct, and needs no special case.

  **But this is an edge case, not the bootstrap.** Tentura is invite-only, and invite consumption (`bindFriendship: true`) writes a **mutual `vote_user` pair in both directions** *and* reciprocal `userVote` trust evidence, which publishes the MR edge. So every organically-signed-up user has `|pop(A)| ≥ 1` from their first session.

**Two qualifications the first draft of this paragraph overstated.** The vote pair reliably makes `viewer_explicitly_trusts_subject` true, but the *MR* half is conditional: the reciprocal evidence publishes only into the **default context `''`**, and `mr_put_edge` failure is swallowed as a warning. Since admission requires `forward_mr > 0`, an ego in a non-default context, or one whose publication failed, has **no floor** after all. And the inviter is not necessarily admitted at `m = 1`: `R_ego` is the median of the ego's top three peers and can exceed the inviter's own score. "The inviter is typically the ego's strongest edge" is an empirical hypothesis worth measuring (§21), not a consequence of the code. The empty case is reached only by accounts created outside that path — seed/admin/test accounts, and users who took the `_acceptBeaconInviteOnly` route (`bindFriendship: false`), which deliberately grants access to one request without forming a friendship.

- **The `n = 1` case is the normal bootstrap, and it behaves well.** With a single vouch, `percentile_cont(0.33)` returns that vouch's own score, so `floor(A) = forward_mr(A, inviter)`. Early on the inviter is typically the ego's strongest edge, which means **the inviter is the ego's first and only admitted witness** — a clean story: the person who brought you in is the first person whose observations count for you. No special case is needed at small `n` (unlike `R_ego`, where median-of-top-3 over two peers returns their *average* and is semantically wrong for a reference scale; here the percentile degrades sensibly).

- **The risk direction is a weak inviter.** `floor(A)` is set by the ego's own vouch list, so an ego invited by a low-MR account inherits a **low bar** and admits far more of their window than an ego invited by a strong one. Two egos with identical networks can therefore have very different admission thresholds because of who happened to invite them. See §13.4 on invitation farming, which this sharpens.

Note the launch consequence: with the disclosure gate removed (D19), nothing holds the witness layer dark. Invite-only signup guarantees every organic ego a vouch, so `floor(A)` is defined from their first session and the feature is **live for every user immediately** — beginning with their inviter as their sole admitted witness, and widening as they vouch for more people. The former "two independent mechanisms keep it dark for months" framing was wrong on both counts.

### 5.2.2 Witness admission

- `forward_mr(ego, w) > 0` — ego can see w. Mutual visibility is **not** required; whether w can see ego is irrelevant to whether ego weights w's observations.
- `w ≠ ego` — ego's own evidence is Tier A, never aggregated.
- `w ≠ c` — **no self-witnessing, ever.** This is the generalisation of the `commitRole` lesson into an invariant.
- No block in either direction between ego and w.

### 5.3 Ego aggregation

```
W_A^elig     = { w ∈ W_A : sole_witness_eligible(A,w) }
S_out(A,c,T) = Σ_{w ∈ W_A^elig}  m(A,w) · e_out(w,c,T)

display Tier B  iff  S_out  ≥ θ_out  (0.30)
display Tier C  iff  S_seed ≥ θ_seed (0.25)
```

**Eligibility gates the summation itself** (D15). Witnesses below the ego's own bar contribute zero — not reduced weight, zero.

An earlier formulation paired an unrestricted sum with an existential flag (`S ≥ θ ∧ ∃ eligible witness`). It is unsound, and the failure is cheap to reach: one eligible witness with nearly-expired evidence sets the flag while an ineligible coalition supplies almost all the mass. At the 24-month boundary a single outcome observation is still worth `0.25/(2+0.25) = 0.111`, so the coalition needs only `0.189` of the `0.30` — and a coalition is exactly what eligibility existed to stop. Restricting the sum closes it structurally rather than by threshold arithmetic.

What this costs, stated plainly: a target with twenty mid-trust witnesses and none above the ego's bar now shows nothing. That is the intended reading of the invariant — evidence matters when it comes from people the ego meaningfully weights — but it does make the feature sparser than the earlier formulation implied, and it is the change most likely to show up as a lower band-fill rate in §21.

### 5.4 Tiers

Tier A splits by **channel**, because the two halves need different sentences and a single `own` tier would render "You worked together on Transport" for a tag the ego merely routed. Any type crossing the API must therefore carry channel, not just tier — and the same four-way distinction is what `tagExplanation` returns (`ownOutcome | ownRouting | networkOutcome | networkRouting`).

Tiers are assigned **per `(subject, tag)`**, never per candidate row. A candidate may legitimately hold Tier A on one matched tag and Tier C on another; §8.1 defines how such a row is reduced for display and ordering.

**Source-by-surface matrix.** Tier alone does not determine what a surface may render — the *channel* matters too, and conflating them let seed evidence onto profiles by a chain of individually-correct rules (Tier A includes the ego's own forward reasons; forward reasons are a seed channel; profiles render Tier A). This matrix is authoritative wherever the prose disagrees:

| Source | Channel | Tier | Forward band | Profile |
|---|---|---|---|---|
| own close-ack | outcome | A | yes | yes |
| own forward reason | seed | A | yes | **no** |
| own private label | seed | A | yes | **no** |
| own seed attestation | seed | A | yes | **no** |
| witness outcome | outcome | B | yes | yes |
| witness seed | seed | C | yes | **no** |
| `commitRole` | — | — | no | no |

The rule underneath it: **profiles render the outcome channel only, at any tier.** "Seen helping with" must mean someone observed help, whether that someone was the viewer or a witness. Routing intent — mine or anyone's — is a Forward-time consideration and stays there.

| Tier | Source | Gate | Label |
|---|---|---|---|
| **A-outcome** | ego's own close-ack | none — one shared request is always worth showing | "You worked together on Transport" |
| **A-routing** | ego's own forward reason, seed attestation or private label | none | "You've routed Transport here" |
| **B** | witness outcome | `S_out ≥ θ_out` over eligible witnesses | "Seen helping with Transport" |
| **C** | witness seed | `S_seed ≥ θ_seed` over eligible witnesses | "Suggested for Transport" |

Precedence is **structural, not numeric**, and it orders by **channel first, then origin**: `ownOutcome > networkOutcome > ownRouting > networkSeed`. Splitting Tier A by channel without re-deriving precedence would put an ego's own cheap *routing* tag above a *witnessed outcome* — inverting the very rule this paragraph exists to state. A strong seed never outranks a weak outcome. This is how "seed is weaker than demonstrated outcome" is enforced — by channel, not by arithmetic, which keeps both channels independently calibratable.

Ego's own evidence is excluded from the weighted sum entirely. It lives on a different scale, it deserves a different sentence, and mixing it in would require an arbitrary `λ_self` constant that does no work.

### 5.5 Pseudocode

```
project(ego, targets[], tags[], context):
    W     ← window(ego, context)                # cached, top-200, m per witness
    floor ← percentile(explicit_trust_scores(ego), 0.33)   # NULL when ego has never voted
    if W empty: skip to the own-evidence loop   # Tier A still applies

    cells ← SELECT observer, subject, tag, s_out, s_seed, anchor_at
             FROM capability_evidence_edge
             WHERE subject = ANY(targets) AND tag = ANY(tags)
               AND observer = ANY(W.admitted_keys)   # D15: admitted witnesses only
               AND (subject, tag) NOT IN <routing mutes>
               AND (ego, subject, tag) NOT IN <ego tombstones>   # keyed on EGO
               AND observer ≠ subject
               AND observer ≠ ego                # ego handled as Tier A
               AND no block between (ego, observer)
               AND no block between (observer, subject)   # §16.1 matrix

    out ← {}
    for (subject, tag) group in cells:
        S_out  ← Σ  W[observer] · e_out(cell)     # admitted observers only
        S_seed ← Σ  W[observer] · e_seed(cell)
        if S_out ≥ θ_out:       out[subject][tag] ← (B, S_out)
        elif S_seed ≥ θ_seed:   out[subject][tag] ← (C, S_seed)

    for (subject, tag) in own_evidence(ego, targets, tags):
        if (ego, subject, tag) in <ego tombstones>: continue    # A is suppressible too
        out[subject][tag] ← (A, ∞)               # overrides B/C for that tag

    return out
```

One grouped scan. No per-candidate round-trips, no recursion, no per-tag graph.

---

## 6. Seed vs outcome weighting

Not a blend — **two channels with different constants, different lifetimes and different sentences.**

### 6.1 When outcome evidence comes into being

The shipped path is not usable as-is. `evaluationSubmit` writes `acknowledgedHelpTags` immediately, in a best-effort `try/catch`, **independent of the evaluation's `value`** — so a reviewer can file a negative evaluation and mint positive help evidence in the same call, and can edit the evaluation afterwards without the evidence following. Two of this document's own claims ("produced by the author's acknowledgement at closure", "the feature learns from real cooperation") are false against that path.

Corrected lifecycle (D16):

```
review window open
  evaluationSubmit(..., acknowledgedHelpTags)
      → stored as MUTABLE evaluation state, reconciled as a SET
        per (evaluator, subject, beacon); no ledger row, no cell bump
      → takes the review-window lock (see below)

review window finalizes  (ReviewFinalizationCase)
  for each finalized evaluation where
        value ∈ {pos1, pos2}
    AND evaluator role ∈ {author, committer, formerCommitter}   (D21)
      → emit ledger rows for its acknowledged tags,
        ≤ 3 per (subject, beacon) across ALL evaluators (D12),
      → bump cells in the same transaction, locks in canonical order (§14.1)
  values noBasis / neg2 / neg1 / zero emit NO outcome evidence
  forwarder-role evaluators emit NO outcome evidence
```

**Submission and closure must serialize on the review-window lock.** They do not today: `evaluationSubmit` reads the open window and upserts outside the finalization transaction, while `closeReviewWindow` reads the window without locking it. A submit can pass the open check, lose the race to the finalization snapshot, and then write an evaluation back to `submitted` after finalization has already run — stranding its acknowledgements in a state that will never be emitted and never be cleaned up.

**`ReviewCloseSnapshot` must carry the acknowledgement set.** It currently holds only evaluator, subject and value, so finalization has no access to the acknowledged tags. The snapshot is the transactional boundary; anything finalization needs must be captured atomically inside it, not re-read afterwards.

`zero` is excluded deliberately: it maps to the `no_effect` trust bin, and "made no difference" is not evidence of useful help. Only `pos1`/`pos2` — the values that map to `good`/`very_good` — qualify.

This also closes the cap-3 bypass. A per-call cap limits a payload, not the active row count: repeated submissions with disjoint tag sets accumulate past three, and concurrent submissions do so too. Because acknowledgement is now **set-reconciled evaluation state** and emitted once at finalization, the cap binds on the set, which is the only place it can be enforced.

### 6.2 Channel comparison

|  | Seed | Outcome |
|---|---|---|
| Produced by | invite attestation; forward reason | finalized `pos1`/`pos2` evaluation with acknowledged tags |
| Means | "I would route X here" | "I saw X actually happen" |
| Half-life | 90d | 365d |
| Prior mass | `K_s = 1` | `K_o = 2` |
| First unit worth | 0.50 | 0.33 |
| Display threshold | 0.25 | 0.30 |
| Shown on profile | never | yes |
| Shown in Forward | yes, as "Suggested for" | yes, as "Seen helping with" |

The seed channel deliberately starts *higher* per unit (0.50 vs 0.33) and dies *faster* (90d vs 365d). A routing attestation is cheap to give and therefore informative only while fresh; a confirmed outcome is expensive and therefore durable. Precedence (§5.4) guarantees the higher per-unit seed value never lets a seed outrank an outcome.

An invite-time seed from a full-weight witness stays visible for roughly 3–5 months — the bootstrap window. Forward reasons renew and accumulate the channel (one per distinct request), so an established router of transport work keeps a live seed signal without any prompt ever firing.

---

## 7. Saturation, decay and the memory horizon

Four mechanisms, each aimed at a distinct failure:

| Failure | Mechanism |
|---|---|
| One witness repeating themselves | Per-cell posterior saturation. On the **outcome** channel (`K_o = 2`) 10 observations are worth 2.5× one, not 10×; on the **seed** channel (`K_s = 1`) the same ratio is 1.82×. |
| Duplicate writes for one event | Ledger uniqueness per `(observer, subject, tag, beacon)`. |
| Historical role capture | 24-month hard window + decay. |
| Ancient evidence lingering faintly | Half-life decay, lazily applied. |

**Independent witnesses beat repetition, provably.** At equal witness weight `m`, `k` witnesses with one observation each yield `k·m/(K+1)`; one witness with `k` observations yields `k·m/(K+k)`. For `k > 1` the first is strictly larger. Two witnesses at full weight → 0.67; one witness with three observations → 0.60.

**A caveat on that proof: independence is per-event, not per-witness.** It assumes each witness observed a *different* occasion. Under D21 several co-committers may acknowledge the same person on the same request, which is one event observed severally. Their contributions do add up, so a single request with three admitted witnesses outranks one with a single witness.

**An earlier revision tried to correct this with a per-request budget (D23) and the mechanism was withdrawn**, because it is non-monotone. Weights would be written into ledger rows ego-independently at finalization, while admission is decided per-ego at read time. So an acknowledger whom a particular ego does *not* admit still shrinks everyone else's share for that ego:

```
author alone, weight 1.0        → e = 1/3     = 0.333   ≥ θ, displays
author + 1 co-acker, 0.5 each   → e = 0.5/2.5 = 0.200
   ego admitting only the author → S = 0.200  < θ, shows NOTHING
```

Corroboration that *destroys* evidence is worse than the over-counting it was meant to prevent, and any scheme that shrinks existing witnesses' weight when a new one joins shares the defect. Repairing it properly would require per-beacon provenance carried into ego aggregation — either beacon-keyed cells, which explode cardinality and lose cross-request saturation, or a provenance side-table consulted on every read.

**And on reflection there is no over-counting to correct.** D23 imported a fix for the wrong quantity. Two things could be measured here:

| | Question | Does one event observed three times inflate it? |
|---|---|---|
| **Intensity** | "How much transport work has Carol done?" | **Yes** — counting one job three times is double-counting. |
| **Evidential quality** | "Is it true that Carol shows up usefully in transport situations?" | **No** — three independent attestations are stronger support for the claim. |

**Tentura measures the second.** This is a reliable ledger of who has been seen helping, not a competition for best carpenter. The event is the thing attested; the witnesses are independent channels of attestation, and more channels reporting the same fact is ordinary confidence accumulation. The surface already says exactly this — *"Seen helping with Transport"* asserts that something was observed, never a magnitude.

That also explains why the two axes correctly compose differently: **per-witness saturation** handles quantity, so a witness's tenth observation adds little; **cross-witness summation** handles confidence, so it should not saturate. They are different dimensions. And it is a further reason `S` is never displayed — a confidence measure rendered on screen would be read as a skill score within a week.

**The one honest caveat:** co-committers on a single request are not *fully* independent witnesses. They shared a room, may defer to one another, and are exposed to correlated error — all plausibly convinced by the same appearance of help. Strict updating under correlated witnesses yields somewhat less than a linear gain. Modelling that correlation is not worth its complexity here, and its adversarial end is already the accepted §13.3 residual. Bounded meanwhile by: each co-witness must independently clear the ego's admission bar (D15); per-cell saturation still applies per witness; and `S` decides a threshold and a three-slot ordering, not a visible magnitude.


**The hard window** is enforced by rebuild, not by the accumulator (which has no per-event memory). Two corrections to an earlier revision, which called the window "hard" without an enforcement path:

- **There is no `meritrank_sweep` to model this on** — m0122 dropped it, as §2.1 itself records. Citing it as precedent was self-contradictory.
- **A cell must know when it next goes stale.** `(observer, updated_at)` cannot locate the next event expiring inside a cell, so the cell carries a **`next_expiry_at`** — the timestamp at which its oldest contributing ledger row leaves the window. The sweep claims work by `next_expiry_at <= now()` under a task lease, which makes expiry an indexed range scan rather than a full table walk. Read-time validity is checked against the same field, so a cell that is overdue is rebuilt on read rather than served stale.
- **Maximum lateness must be stated**, because until the sweep runs, expired mass is still readable. The window is hard to within one sweep interval, and that interval — not the phrase "hard window" — is the guarantee.

The claim that the cutoff is invisible is also wrong: dropping an event at exactly 24 months discards `2^-2 = 0.25` of one observation, which is bounded per-event but can move a `(subject, tag)` across `θ` when several near-boundary witnesses expire together. Bounded, not imperceptible.

---

## 8. Forward ranking

The candidate set is **unchanged**: tag evidence never adds, removes or filters a candidate, and the main list keeps its current MR ordering, untouched.

One precision the earlier text got wrong: the Forward surface is not *only* `mutually_visible_users`. The main list comes from that function, but **lineage suggestions are loaded separately** and can pull in profiles absent from it, filtered for mutual visibility on the client. Two consequences: lineage rows do **not** participate in the band in v1 (they already have their own grouping and reason codes, and mixing two suggestion rationales in one strip would make neither legible), and their authorization must rest on the canonical server-side projection rather than on client-side filtering.

Above it, a capped band renders **only when it has at least one evidence row**:

```
For this request
  Carol   You worked together on Transport        [Forward]      ← Tier A
  Alex    Seen helping with Transport · Tools     [Forward]      ← Tier B
  Julia   Suggested for Transport                 [Forward]      ← Tier C
  ── new to this kind of request ──
  Peter                                           [Forward]      ← exploration
  Mira                                            [Forward]      ← exploration

All contacts                                                     ← unchanged MR order
  ...
```

- **3 evidence slots**, ordered Tier A → B → C, then by `S` descending, then by `forward_mr` descending.
- **2 exploration slots** (§9).
- Band members are removed from the main list to avoid duplicate rows.
- A row labels **only the tags that matched this request's needs**, primary need first, capped at 2 labels. Carol's Pets and Legal evidence is never rendered here (§11 of the brief). Note the asymmetry with D12: up to 3 tags may be *recorded* per acknowledgement while up to 2 are *displayed* in a band row; the third remains visible on the profile projection.

### 8.1 Reducing a mixed-tier row

Tiers are per `(subject, tag)`, so a candidate can hold Tier A on `transport` and Tier C on `tools` at once. A single row-level tier would either mislabel one tag or silently drop evidence, and nothing would define which `S` orders the row. The reduction is explicit:

- **Row tier** = the strongest tier among that candidate's matched tags (A > B > C). It governs which sentence the row gets.
- **Row sort key** = `(row tier, max S among tags AT that tier, forward_mr, user_id)`, descending except the last. Taking the max resolves the case of several tags sharing the strongest tier, which "the S of the strongest-tier tag" left undefined; `user_id` makes the order total.
- **Labels list only tags that share the row tier.** An earlier revision listed all matched tags regardless of tier, with an escape clause for "where that conflation would mislead" — a clause with no predicate, which meant the claimed honesty did not follow from the mechanism. It does not survive its own example: "You worked together on Transport · Tools" asserts shared work on both when Tools may be nothing more than a stranger's routing hint. Same-tier labelling makes the sentence true of every tag it names, and a lower-tier tag simply goes unmentioned in this row.
- When no candidate has matching evidence, the screen is byte-for-byte what it is today. No band, no exploration slots, no noise.

The band is the entire mechanism by which tag evidence influences ordering. Its cap is the bound on that influence — not a tuning constant buried in a weighted sum, but a visible, countable, explainable structure. The user is still choosing whom to forward to; Tentura has put three names within reach and labelled why.

---

## 9. Exploration

Reserved slots, deterministic fill:

```
pool ← candidates with no matched evidence
       minus anyone ego forwarded to in the last 30 days
       ordered by (forward_mr DESC, user_id ASC)     -- tie-break is mandatory
if |pool| = 0: no exploration slots, band renders with evidence rows only
if |pool| = 1: one exploration slot
else:
    offset ← fnv1a64(request_id) mod |pool|          -- named, stable, cross-platform
    pick   ← pool[offset], pool[(offset+1) mod |pool|]
```

Every clause above fixes a way the earlier three-line version was not actually deterministic: an empty pool made `mod |pool|` undefined, a one-person pool returned the same person twice after wrapping, no hash was named (so client and server could disagree), and MR ties left `pool` order unspecified — which alone would have made the "an integration test can assert exactly which two names appear" claim false.

The promise is **deterministic derivation**, not guaranteed variety: two different request IDs can collide modulo a small pool and surface the same pair. That is acceptable — the mechanism exists to prevent systematic monopoly, not to guarantee novelty on every request.

Exploration slots ride with the band rather than existing independently, because their purpose is to counter the band's gravity. On a screen with no band there is nothing to counterbalance — the full MR-ordered list is already the unbiased view.

The 30-day exclusion is what stops the same two "new" people being surfaced forever, and the `hash(request_id)` rotation is what stops the top of the MR tail monopolising the slots.

---

## 10. Profile projection

```
Seen helping with

Transport · Pets · Legal
```

- Derived per viewer; two viewers legitimately see different sets.
- **Outcome channel only, at any tier** (D22). "Tier A + Tier B" was the wrong axis and quietly contradicted itself: Tier A includes the ego's own forward reasons and own seed attestations, which are seed-channel, so following the rule literally rendered seed evidence on profiles — the precise outcome the next sentence forbids. What belongs here is the ego's own *close-acks* and witness *outcome* evidence. A profile that renders "people would route Legal here" is an endorsement page, and that is the drift the whole design exists to prevent.
- Top 3 tags, own-outcome first, then witness-outcome by `S`, then `slug` for a total order.
- No counts, no numbers, no stars, no percentages, no witness names, no leaderboard, and not editable by its subject.
- Absent entirely when nothing clears the gates — an empty section, not a "no tags yet" prompt, which would invite self-description.

**Anti-pattern check.** Can this be used as a standalone expertise directory? Partially — a determined user could walk their contact list reading tags. It is bounded by: no search, no filter, no sort by tag, no reverse index from tag to people, top-3 only, and viewer-specific results that are useless to share. The reverse index is the line: the moment any query answers "who has tag T", the feature has become Happenstance. There is no such query in this architecture, and adding one should require re-opening this document.

---

## 11. Invitation seeding flow

Hosted on the existing `invite_accepted` Update:

```
Carol joined Tentura

What kinds of requests would you feel
comfortable sending Carol?

[Transport]  [Pets]  [Local help]  [+]

Skip
```

- Optional; skipping is a first-class outcome.

**Prompt state is modelled separately from attestation rows.** The attestation operation alone cannot distinguish *never answered*, *skipped*, *answered then cleared*, and *answered with zero tags* — they all leave no row, so the receipt would re-prompt or suppress incorrectly. A prompt-state record (`pending | answered | skipped`) on the invite receipt carries that, independent of whatever attestations exist. This also makes §20's open question about prompt lifetime answerable without a schema change: re-offering is a state transition, not a new table.
- Never interrupts Carol's onboarding — it is addressed to Bob, asynchronously, after the fact.
- Chips are drawn from the 37-slug taxonomy; a small suggested subset up front, full list behind `[+]`.
- Soft-capped at ~3 selections. Framed as routing ("would you feel comfortable sending"), never as qualification ("what is Carol good at", "endorse Carol for").
- Editable and withdrawable later from Carol's profile as seen by Bob.
- Writes `source_type 4`, unique per `(Bob, Carol, tag)` — re-answering replaces.

**Carol does not approve these.** They are Bob's routing judgement about his own future behaviour, not a claim about Carol that requires her consent to be true. What Carol gets instead is control over the consequence (§12) — she can mute a tag's third-party routing effect without anyone adjudicating whether Bob was right.

Seeding stays **inviter-only** as a prompt. No connection-time prompt, no "tag your friends" surface, no prompting many people about the same newcomer. The second seed path (forward reasons) is behavioural and needs no prompt at all: it is emitted as a by-product of actually routing a request.

---

## 12. Privacy and identity control

### 12.1 What is never revealed

- Witness identities behind Tier B/C — **not exposed by any read API**. The explanation is a static sentence: *"Based on your own experience and observations from people in your trusted network."*

  The weaker phrasing is deliberate. Two oracles can leak a witness by inference: an ego may block a suspected witness and watch a row vanish, or diff band membership across self-created contexts whose windows differ. Both are self-limiting — blocking is socially costly and fresh contexts have sparse graphs — but "never revealed" was an absolute this design does not actually deliver. Accepted residual risk.
- Counts, scores, `S` values, `m` values, MR values. None of these cross the API boundary in any form a UI could render.
- The underlying requests behind third-party evidence. Only **ego's own** evidence may name its beacon ("You worked together on «Move the piano»"), because ego was there.

### 12.2 Carol's surface

A "How requests reach you" screen rendering **the fixed 37-slug taxonomy with Carol's mute state on each** — and nothing derived from evidence at all.

That is a deliberate retreat from two earlier formulations, both of which leaked:

- *"Every tag any live evidence exists for"* would let a **private label** put a tag on Carol's screen, revealing that someone privately categorised her. That breaks the same private-note promise §17.1 invokes to exclude those rows in the first place.
- *"Every tag that could reach a third party"* is worse than it sounds. The operation has no ego and no context, so it cannot express *subjective* projectability; the only thing it can compute is **global existence of projectable evidence about Carol** — an objective subject↔tag signal, visible to Carol, in a design whose first invariant is that no such signal exists. It also makes mute irreversible from its own surface: hide the muted rows and there is no way back to unmute.

Rendering the taxonomy sidesteps all of it. Carol sets routing preferences over the same vocabulary everyone else uses, learns nothing about who has observed what, and can always unmute. The screen answers "how do I want to be reached", which is the question she actually has, rather than "what does the network think of me", which is the question this design refuses to answer for anyone.

- Muting suppresses Tier B and Tier C for **all** viewers.
- Muting never suppresses Tier A. Bob's memory of working with Carol is Bob's; Carol cannot edit other people's experience, only its routing consequence.
- Mute is reversible, invisible to others, and generates no notification to witnesses. There is nothing to contest and no one to contest it with — which is precisely the point of choosing a routing preference over a dispute mechanism.

### 12.3 Negative evidence

None in v1. Failed and disputed outcomes flow through the existing evaluation and trust-evidence path, where they already belong. The `is_negative` tombstone stays what it is today — a viewer-scoped "don't show me this", not a claim about the subject.

### 12.4 Blocks

A block in either direction removes the pair from witness eligibility and from projection, both ways.

---

## 13. Sybil and collusion analysis

### 13.1 Worked example — Alice → MR → Bob → evidence → Carol

Bob acknowledged Carol on `transport` at the close of one request, 30 days ago. Bob is Alice's closest contact.

```
cell(Bob, Carol, transport)
  effective count = 1 · 2^(−30/365) = 0.945
  e_out           = 0.945 / (2 + 0.945) = 0.321

Alice's window: forward_mr(Alice,Bob) = 0.052, R_Alice = 0.052 → m = 1.0
Alice explicitly trusts Bob (vote_user)      → ADMITTED, so Bob contributes

S_out = 1.0 × 0.321 = 0.321  ≥ θ_out (0.30)   ✓
→ "Seen helping with Transport"
```

Add Dave, a mid-weight contact (`m = 0.5`), who acknowledged Carol on `transport` 200 days ago:

```
e_out(Dave)  = 0.685 / 2.685 = 0.255
S_out        = 0.321 + 0.5×0.255 = 0.448
```

Stronger, and correctly so — a second independent observer. Contrast with Bob alone acknowledging Carol across three separate requests: `e_out = 2.8/4.8 = 0.583` at `m = 1.0`. At equal witness weight, breadth wins (§7).

Eve, meanwhile, does not weight Bob at all (`forward_mr(Eve,Bob) = 0`). Eve sees nothing. `tags(Alice, Carol) ≠ tags(Eve, Carol)` is not a policy in this design — it is arithmetic.

### 13.2 Worked example — the Sybil farm

Carol creates 100 Sybils. Each authors fake `transport` requests, Carol commits, each closes and acknowledges her. Each cell reaches `e_out ≈ 1.0`.

```
Case 1 — no path from Alice to the Sybils:
  forward_mr(Alice, sybil_i) = 0 for all i → not in Alice's window → S = 0.
  Nothing displays.

Case 2 — one real user, Mallory (m = 0.30), vouched for them:
  No sybil_i is explicitly trusted by Alice, and each sits far below
  floor(Alice) — the 33rd percentile of people Alice actually vouched for.
  None is ADMITTED, so none enters the sum at all:
  S_out = 0 → nothing displays.

  (Even had they been admitted, mass conservation caps them:
   Σ_i m(Alice, sybil_i) ≤ m(Alice, Mallory) = 0.30. But under D15
   that bound is never reached, because the sum never includes them.)
```

The two guards are not equally strong, and an earlier revision overstated the first.

**Eligibility is the load-bearing defence**: however the sum is assembled, at least one witness meeting the ego's own revealed standard must stand behind it, and an attacker cannot insert themselves into the ego's vote list.

**The mass argument is directional support, not a proof.** Earlier text asserted that personalised-PageRank mass conservation bounds `Σ m(sybil_i) ≤ m(sponsor)` — that a clique can only ever split its sponsor's mass. That inequality does not hold in general: a clique whose edges point mostly inward retains and recirculates mass, and its total stationary score can exceed the gateway node's own. MeritRank is specifically designed to bound that gain, but this document should not lean on an unqualified conservation claim. Score-proportional weighting still means fan-out buys *far* less than rank-proportional weighting would; it just is not a hard cap.

Note what eligibility actually accomplishes — it does not prevent the attack, it makes **fan-out worthless**. An attacker's best response is to concentrate rather than spread: a single account holding all of the sponsor's mass clears the bar whenever the sponsor does. So the guard converts "100 cheap accounts" into "one identity the ego's network genuinely weights," at which point it is no longer a Sybil attack but a trusted person lying — the residual of §13.3, which no system solves.

Three transformations look like tidy normalisation and each restores the attack:

1. **Rank-proportional weighting.** Under `m = 1/(1 + rank/R)`, 100 Sybils at rank 200 carry ≈0.05 each and sum to 5.0. Score-proportional weighting is not a preference; it is the defence.
2. **Renormalising `m` over the witnesses holding evidence for a query.** Divides away the very dilution that defeats them.
3. **Setting the eligibility bar as a percentile of the ego's *window* rather than their vote list.** MeritRank's quantile bounds are rank-based over every reachable node with positive score, so the attacker controls the denominator: 30 real peers plus 100 Sybils makes a "top 67%" bar cover 87 nodes, 57 of them Sybils, every one eligible. Anchoring to the vote list is what makes the bar invariant under stuffing — both sides of the comparison move together:

```
30 real + 1000 sybils:
  sybils occupy the bottom 97% of the reachable population
  Alice's explicitly-trusted peers are all real, and rank above them
  floor(Alice) = 33rd pct of Alice's own vouches → still above every sybil
  → E = false, unchanged
```

**On the margin — and this has now been wrong in both directions.** Rev 1 called the floor's safety empirical, reasoning from m0088's dropped trigger that `vote_user` no longer touched MR; that read a superseded architecture. Rev 2 over-corrected to "structural", claiming `userVote` rebuilds and publishes the MR edge.

The accurate statement is narrower than rev 2's. `userVote` does write `TrustSourceType.userVote` source evidence and does invoke a rebuild — but **publication is epsilon-gated, and an `mr_put_edge` failure is swallowed as a warning**. So an explicit vouch can exist while the MR edge remains stale or unpublished, and the "directly-voted nodes structurally outrank multi-hop nodes" claim does not hold unconditionally.

The margin is better than rev 1 conceded and weaker than rev 2 asserted: **strongly expected, not guaranteed.** It stays in telemetry (§21) as a soundness check, not merely a calibration one. (Also imprecise in rev 2: m0122 drops an old `trust_resync_source` signature and immediately creates a new one — "dropped" alone misdescribes it.)

### 13.3 Reciprocal endorsement rings

Two genuinely trusted users, A′ and B′, farm each other across ten fake requests on one tag:

```
e_out = 10/12 = 0.83, at m = 1.0 → S = 0.83, passes comfortably.
```

**This works, and v1 accepts it.** The honest framing: the attack requires the victim to *already* trust A′ highly, and a highly-trusted A′ can simply tell Alice "Carol is great at transport" out of band. The feature adds little surface beyond what social trust already grants.

What limits it: per-cell saturation makes the yield asymptotic (0.83 for ten fakes, 0.96 for fifty — the hundredth fake request is worth nothing), it only affects tags the pair actually touched, and each fake request also carries real cost in the evaluation and trust layer, which independently penalises fabricated closures. Detection is a monitoring problem, not a formula problem: **acknowledgement reciprocity between pairs with no third-party overlap** is the metric to watch (§21).

### 13.4 Other attacks

| Attack | Outcome |
|---|---|
| **Invitation farming** — mass-invite accounts, seed them all | Seeds are unique per `(witness, subject, tag)` and the farmer is one witness; total influence on any ego is capped at `m(ego, farmer)` and `H_seed = 90d` erases it. **Sharper than it first looks, though:** because invite consumption is what creates an ego's first vouch, an attacker who owns an invite subtree sets each invitee's *only* vouch — and therefore their eligibility floor — while also populating the peers that clear it. Bounded by MR mass conservation (§13.2) and by invitees being fresh accounts with little reach, but it is the honest edge of "your trust graph is only as good as whoever invited you" — a property of invite-only networks generally, not one this feature introduces. |
| **One trusted witness tagging everybody** | Their evidence is real to those who trust them — correct behaviour. Their *per-cell* contribution saturates, they cannot exceed `m = 1`, and they cannot clear `θ_out` for anyone if their own `m` is low. Breadth of tagging does not increase per-target weight. |
| **Stuffing the ego's reachable population** | The eligibility bar is a percentile of the ego's **vote list**, not of the reachable window, so added accounts move the attackers and the bar together (§13.2). |
| **Repeated outcome farming, one pair** | Ledger uniqueness per `(observer, subject, tag, beacon)` forces distinct requests; saturation makes each worth less than the last. |
| **One fabricated close by an *admitted* witness** | **Not defended against, by design.** An undecayed single observation is worth `1/3 = 0.333 > θ_out`, so one acknowledgement from a witness the ego admits **at full weight** is sufficient on its own for roughly 80 days. Admission is not sufficiency: an admitted witness at `m = 0.8` yields `0.267 < θ_out`, and at `m = 0.5`, `0.167`. The case that matters is the inviter bootstrap, where `m` is typically near 1. The defence is not multi-observation cost — it is *whose word the ego already accepts*. Note the sharp edge for newcomers: invite-only signup makes the inviter the sole admitted witness at `m = 1`, so an inviter's single acknowledgement is decisive for every one of their invitees' Tier B. Raising `θ_out` above one observation, or requiring two distinct admitted witnesses, would close this — at the cost of making the feature inert for exactly the newcomers it is supposed to bootstrap. Kept as a calibration decision, watched via §21's floor-margin and eligible-witness metrics. |
| **Stale seed evidence** | 90d half-life, superseded by outcome via structural precedence, hard-dropped at 24 months. |
| **Identity capture in an old role** | 24-month window + decay + capped band + mandatory exploration slots. Nobody is frozen, and nobody's absence of evidence excludes them (D3). |
| **Brigading** — many accounts tagging one person | Eligibility gate. Volume without one witness meeting the ego's own standard is worth zero. |
| **Provenance leakage** | No witness names, no counts, no request references outside ego's own evidence. |

### 13.5 What subjective MR does *not* solve

MeritRank answers "whose observations should matter to Alice". It does not answer whether a trusted person is *right*, and it offers no defence when the attacker is someone Alice genuinely trusts (§13.3). It also cannot help an ego with an empty window — a brand-new user sees Tier A only, which is correct but means the feature is inert for them until they have a network.

### 13.6 Accepted residual risk — no sensitive-tag class (D7)

All 37 slugs project identically, so a viewer may learn that Carol has helped with `medical_navigation` or `money`. The exposure is milder than it first appears: evidence always describes the **helper** role, so it reads "Carol helps with medical things", not "Carol had a medical problem". The residual risks are (a) role-typing someone into a sensitive category, and (b) confirming that *some* request of that kind existed in the network. Mitigations already present: no request is named, no witness is named, and Carol can mute any tag. If abuse appears, a restricted subset is a config change, not a re-architecture — the gate would live in the projection query.

---

## 14. Storage and indexing

| Table | Key | Hot access path |
|---|---|---|
| `person_capability_event` | existing | Cell rebuild by `(observer, subject, tag)`; ego's own evidence by `(observer, subject)`. |
| `capability_evidence_edge` | `(observer, subject, tag)` | **`(subject, tag)` covering `observer, s_out, s_seed, anchor_at`** — the Forward projection scan. Secondary `(observer, updated_at)` for the rebuild sweep. |
| `ego_witness_window` | `(ego, context, witness)` | Full-window fetch by `(ego, context)`. |
| `capability_routing_mute` | `(user_id, tag_slug)` | Anti-join in projection. |

### 14.1 Atomicity and locking

The plan previously described writes and rebuilds without saying what shares a transaction. That is not a detail — the derived cell is a second representation, and every unsynchronised path between the two produces a wrong projection from a correct ledger.

**Contract:**

- **One pair lock per cell, acquired in canonical order.** Every mutation of `(observer, subject, tag)` — ledger insert, soft-delete, rebuild, sweep — acquires an advisory lock on that triple first. This mirrors `trust_pair_lock` in the typed-trust design, and for the same reason: a writer racing a rebuild otherwise has its bump overwritten, and two concurrent rebuilds install stale snapshots. Because finalization touches **many cells at once** (every acknowledged tag for every acknowledged person), all affected locks must be acquired in **lexicographic order of the triple**; without a canonical order, two finalizations with overlapping cells deadlock.
- **Ledger row and cell bump share one transaction.** Never best-effort. The shipped `recordCloseAcknowledgement` call site deliberately swallows failures so evidence loss cannot block an evaluation; under D16 the emission moves into finalization, where it must be atomic with the finalization itself.
- **Cross-table orchestration lives in a domain use case** driving `MutatingUnitOfWorkPort`, not in a repository and not in a resolver.
- **Cells are derived only — never authoritative.** The earlier text called them both a cache and authoritative; they are a cache, and the ledger within the 24-month window is the sole truth.
- **Drift detection needs an authoritative generation source, not a number on the cache.** An earlier revision put a `rebuilt_from_generation` marker on the cell and claimed a reader could detect drift from it. It cannot: a value stored only on the cache cannot reveal that a later ledger mutation was missed, because the missed mutation is precisely what would have updated it. The generation counter is therefore **owned by the ledger side of the pair** — incremented on every mutation of that triple within the lock — and the cell stores the generation it was built from. A reader comparing the two detects staleness; equality is the only proof of freshness. The rebuild owner is the repository behind the cell port, and it is the only writer.
- **Revocation** (D14) soft-deletes the ledger row and rebuilds the cell inside the same locked transaction.

Projection query shape:

```sql
-- `admitted` is the ONLY witness set that reaches the sum (D15).
WITH win AS (SELECT witness_user_id, m FROM ego_witness_window
             WHERE ego_user_id = $ego AND context = $ctx
               AND admitted)                       -- eligibility filters HERE
SELECT c.subject_user_id, c.tag_slug,
       sum(win.m * e_out(c))  AS s_out,
       sum(win.m * e_seed(c)) AS s_seed
FROM capability_evidence_edge c
JOIN win ON win.witness_user_id = c.observer_user_id
WHERE c.subject_user_id = ANY($candidates)
  AND c.tag_slug        = ANY($needs)
  AND c.observer_user_id <> $ego
  AND c.observer_user_id <> c.subject_user_id
  AND NOT EXISTS (routing mute on (c.subject_user_id, c.tag_slug))
  AND NOT EXISTS (ego tombstone on ($ego, c.subject_user_id, c.tag_slug))
GROUP BY 1, 2
```

Three corrections to the earlier sketch, each of which silently reverted a decision:

- **The eligibility filter must precede the sum.** The earlier sketch joined every window row, summed every `m`, then applied `bool_or(sole_eligible)` — reconstructing exactly the unrestricted-sum-plus-existential-flag design D15 rejects. The column is renamed `admitted` because it governs *contribution*, not a sole-witness flag.
- **`s_seed` must be summed alongside `s_out`.** The earlier sketch elided it, leaving Tier C's gate undefined in SQL.
- **The ego tombstone anti-join is keyed `(ego, subject, tag)`, not on the cell's observer.** The earlier text compared cell tuples against ego tombstones, but network cells are authored by *witnesses*, never by the ego — so the suppression could never match and a viewer's "don't show me this" silently did nothing for exactly the tier it most needed to suppress. Tier A rows must pass the same anti-join before insertion.

Bounded by `|candidates| × |needs| × cells-per-triple`. One round trip per Forward screen open, one per profile open.

**Math lives in SQL**, consistent with the existing trust convention (`trust_edge_weight`) — `e_out`/`e_seed` are SQL functions, and Dart passes ids, tag lists and config from `Env`. Nothing in the Dart layer reimplements the decay.

Per §20 of the brief: **nothing is materialised per `ego × target × tag`**, and no benchmark has yet justified doing so.

---

## 15. Caching and invalidation

| Cached | TTL | Invalidated by | Staleness tolerance |
|---|---|---|---|
| `ego_witness_window` | 15 min + epoch | **MR publish epoch** (see below), block changes in either direction, ego's own vote changes | Minutes, with the caveat below. |
| Cells | n/a (derived cache; read-through rebuild on stale generation or expiry — §14.1) | write-through on evidence; rebuild on revoke; periodic window sweep | None — read-through. |
| Projection | not cached server-side in v1 | — | — |
| Forward band | client, screen lifetime | screen reopen | Seconds. |

**The earlier invalidation story was wrong in four ways, and the corrections are not cosmetic:**

- There is no periodic "trust/MR sweep" to hang invalidation on — m0122 dropped it. **Ordinary trust evidence rebuilds and may publish MR edges synchronously**, so the window can go stale at any write, not on a schedule. Invalidation must key off an **MR publish epoch / version counter**, not a timer.
- **Blocks** can withdraw published weight and were not covered at all. A block must invalidate both parties' windows immediately, in both directions.
- **A TTL is not eviction.** Rows must actually be deleted, or the table grows without bound.
- **Raw `context` in the primary key permits unbounded row growth** across arbitrary context strings. Contexts must be normalized and bounded before they can key a cache.

And the staleness claim needs qualifying: 15 minutes is imperceptible for a *weight*, but crossing the eligibility floor or a `θ` threshold visibly adds or removes a row. Staleness is therefore tolerable in magnitude and not in gating — which is a further argument for epoch-based invalidation over a pure timer.

Evidence writes bust nothing but their own cell, because projection is computed on demand. This is the payoff for not materialising: invalidation is cheap, and the only genuinely cached artifact is the witness window.

Profile and Forward differ as the brief anticipated: Forward is latency-sensitive and batched across ~50 candidates; profile is one subject and can afford the same query unbatched. If benchmarks later demand it, the first thing to cache is the *projection for the ego's top-N contacts*, keyed by `(ego, subject)` with the witness-window TTL — not the full space.

---

## 16. API contracts

```
subjectiveTags(targetId): [{ slug, tier }]
    Profile projection. Tier ∈ {ownOutcome, networkOutcome} — the outcome
    channel only (D22). The four-value ProjectionTier is shared with the
    band; profile simply never returns the two routing values. Top 3. No scores, no names, no counts.

forwardContext(beaconId, context): {
    band: [ { userId, rowTier, labels: [{slug, tier}], rank, isExploration } ],
  }
    THE SERVER COMPOSES AND ORDERS THE BAND. It does not return raw evidence
    for the client to sort.

    Rationale: §5.4 forbids S from crossing the API boundary, and §8.1 orders
    same-tier rows by S. A client handed only {userId, tags[]} therefore
    cannot implement the specified ordering, cannot pick the strongest-tier
    tag, and cannot apply the 30-day exploration exclusion. Returning tags
    and leaving order implicit in array position is not a contract.

    The server is the only party with both S and the canonical candidate
    projection, so band membership, ordering, label selection and exploration
    slots are all decided server-side and returned as an explicit `rank`.
    `isExploration` marks the reserved slots so the client can render the
    divider without inferring it.

    Candidates the client cannot act on (author, declined, blocked, already
    forwarded, `canForwardTo == false`) are excluded server-side; the client's
    own candidate collection is not authorization and must not be the filter.
    Lineage suggestions do not participate (§8).

    `context` is REQUIRED and must be the canonical normalized context (§16.2).

seedRoutingAttestation(subjectId, slugs: [slug])
    Create / replace / clear. Idempotent per (observer, subject).
    INVITE-ONLY (D17). The Forward composer must NOT call this — it already
    records forward reasons through the Forward mutation, and calling both
    would record one decision twice, making a single action worth two seed
    units while converting a request-specific reason into a standing,
    beaconless attestation.

acknowledgeHelp — extends the existing evaluation_submit.acknowledgedHelpTags
    Server-validated against beacon.needs ∪ activeHelpOffer(subject).helpTypes.
    SET-RECONCILED per (evaluator, subject, beacon) — replaces, never appends —
    so the cap of 3 binds on active rows rather than on one payload.
    Stored as mutable evaluation state; emits NO ledger row and NO cell bump
    until finalization (D16).

revokeAcknowledgement(beaconId, subjectId, slug)
    Post-finalization only. Soft-deletes the ledger row and rebuilds the cell
    from the 24-month window, in one locked transaction (§14.1).
    Pre-finalization, editing the acknowledgement set is an ordinary edit.

myRoutingTags(): [{ slug, muted }]
setRoutingMute(slug, muted)
    Carol's surface. Aggregate only — no witnesses, no counts.

tagExplanation(targetId, slug): enum
    { ownOutcome | ownRouting | networkOutcome | networkRouting }
    A static enum, not a provenance query. Cards never call it; it is on-demand
    behind an affordance, so no visible card pays for provenance.
```

### 16.1 Authorization

Shape is not a contract. Every operation below states its predicate; the actor is always JWT-derived and never client-supplied. The existing `query_capability.dart` resolver is the cautionary example — authenticated but unguarded on the target.

| Operation | Predicate |
|---|---|
| `subjectiveTags(target)` | actor must be able to see `target` under existing visibility rules; no block in either direction. Fails closed. |
| `forwardContext(beacon, context)` | actor must be the beacon author or an authorized forwarder for that beacon; returned candidates must independently satisfy the canonical server-side visibility projection — the client's candidate list is not evidence of authorization. |
| `seedRoutingAttestation` | actor must be the **direct inviter** of `subject`, and `subject` must have **accepted** that invitation. Directional: the invitee may not seed the inviter through this path. `actor != subject`. Observer is the actor, never a parameter. "Stands in the invite relationship" was too loose — it admits any invite-adjacent pair in either direction. |
| `acknowledgeHelp` | actor's role ∈ {`author`, `committer`, `formerCommitter`} (D21 — **forwarders excluded**); the `(actor, subject)` pair must exist in `beacon_evaluation_visibility`; review window open; subject must be an **evaluation-visible participant** of that beacon; tags are validated per D8. Not "must have an active help offer" — the author never has one, and a `formerCommitter`'s is withdrawn, so that predicate would reject exactly the acknowledgements D21 exists to permit. |
| `revokeAcknowledgement` | actor must be the **original observer** of the row. No one may revoke another observer's memory. |
| `myRoutingTags` / `setRoutingMute` | self only. |
| `tagExplanation(target, slug)` | same predicate as `subjectiveTags`, and it may reveal only the tier enum — never a witness, count or score. |

### 16.2 The block matrix

"Blocks are checked in both directions" was too vague to implement, and the gap it hid is real: witness admission covered only ego↔witness, so **a witness's evidence kept projecting after the witness and the subject blocked each other**. Three distinct pairs, three distinct rules:

| Pair | Rule |
|---|---|
| ego ↔ target | Target is not a candidate and has no projection. Fails closed. |
| ego ↔ witness | Witness is not admitted; contributes nothing. |
| witness ↔ subject | **That witness's cells for that subject are excluded.** A block between them retracts the observation's reach, in either direction. |

Writes are the exception that proves the rule: **owner revocation must survive a block.** Refusing every blocked write would strand evidence permanently — the observer could never withdraw a row about someone who has since blocked them, contradicting D14's "revocable indefinitely". Revocation by the original observer is therefore always permitted; only creation is blocked.

### 16.3 Canonical context

Passing `context` explicitly (rev 2) narrowed the problem without solving it. The client passes a **raw** `ContextCubit.state.selected`, and `person_visibility_peers` merely coalesces null — it performs none of the bounded normalization §15 requires to key a cache. Normalizing only the new endpoint would split its witness window from the candidate query's population; not normalizing leaves cache growth unbounded.

**One server-owned normalization**, applied identically by candidate visibility, window lookup and projection. And `subjectiveTags` needs one too — it takes no context argument because **D24 fixes it to the canonical default `''`**. That is decided, not open; a profile is not a browsing-context-scoped object.

Blocked pairs fail closed rather than returning an empty projection that leaks nothing but costs a query.

There is deliberately **no** `usersByTag`, `searchPeople`, `findHelpers` or any endpoint whose input is a tag and whose output is people. That absence is the architecture's load-bearing anti-LinkedIn guarantee, and it should be enforced by review, not by convention.

---

## 17. Integration and migration

### 17.1 Aggregation eligibility

**Which sources aggregate is a property of the source, not of when a row was written.**

- `privateLabel` — written under an explicit private-note promise. **Never** aggregated, under any circumstance. This is the one rule here that is genuinely non-negotiable, and it is independent of everything below.
- `commitRole` — self-declaration. Never aggregated (D18).
- `forwardReason`, `closeAcknowledgement`, `seedRoutingAttestation` — aggregate.

Earlier revisions gated aggregation on a cutover timestamp (rev 1), then on a stored disclosure version asserted by the client (rev 2), to protect rows written before users were told their input would reach their network. **Both were removed pre-launch (D19):** Tentura has no production deployment and no shipped clients, so no such rows exist and no client can write without having shown the wording it ships with.

**Ownership:** the wording is a **launch checklist item owned by product**, not an implementation unit — no unit in the plan gates on it, and none should, since gating is precisely what D19 removed. It must nonetheless be written before the first real user. What this does *not* remove: the three entry points still need honest wording before real users exist — forward reasons are today readable only by sender and recipient, and acknowledgements are observer-scoped, so both genuinely widen. That is now ordinary launch copy on a normal review path, not a runtime interlock.

If a source's scope is ever widened again *after* launch, the versioned mechanism is the right answer and should be reintroduced then — it is a one-column migration.

### 17.2 Source-type disposition

| Source | Ledger | Tier A | Cells (B/C) |
|---|---|---|---|
| 0 `privateLabel` | keeps writing | yes | **never** |
| 1 `forwardReason` | keeps writing | yes | seed |
| 2 `commitRole` | keeps writing (audit only) | **no** | **never** |
| 3 `closeAcknowledgement` | written at finalization (D16) | yes | outcome |
| 4 `seed_routing_attestation` | new, invite-only (D17) | yes | seed |

`commitRole` gets a single disposition, not three. Earlier text variously called it "dropped as evidence entirely", "evidence for its author only", and "self-view only" — those are different policies, and the last one preserves precisely what D2 set out to remove: a self-editable capability rendered back as though observed. It is excluded from every projection. It survives in the ledger for audit, and nothing reads it.

### 17.3 Known client-side consequences of D2 / D18

**The regression path is `viewerVisible`, not the two cue getters.** Earlier text named `PersonCapabilityCues.profileBeaconCueSlugs` / `strongestNetworkCueSlugs` as the mechanism — but those have **no production call sites** (tests only), so removing them changes nothing a user sees.

What actually darkens existing profile strips is C5: the shipped chips render `state.cues.viewerVisible`, fed by `fetchDeduplicatedCapabilities`, which today reads `source_type = 2` **subject-scoped** — every viewer sees every commit role. Removing that read is the visible change, and it is the correct one: what those strips display today is a self-declaration rendered as though it were observed fact.

### 17.4a D8's candidate set

D8 draws acknowledgement candidates from `beacon.needs ∪ helpTypes(that person's commitment)`. The second half must read the **active help-offer state**, not `commitRole` ledger history — the ledger is append-only and would offer tags from withdrawn or superseded offers. Per §4.5, the help types must reach the domain as a typed collection through a port; the entity's current nullable-JSON-string shape must not surface in a use case.

### 17.4b MeritRank integration

Read-only, via `person_visibility_peers(viewer, context).forward_mr`. No new MR edges, no new trust evidence, no writes to `user_trust_edge`, no new context graphs. The dependency is strictly one-directional and must stay that way: tag evidence feeding MR would create a loop between two subjective layers whose combined behaviour nobody can reason about.

### 17.5 Taxonomy

Unchanged — the same 37 slugs across request creation, commitment, closure, seeding, projection and Forward. No new vocabulary, no free text, no synonyms, no user-created tags.

---

## 18. v1 scope vs later

**In v1:** ledger extension; cells; witness window; two-channel projection; Forward band with exploration; profile projection; invite seeding; forward-reason seeding; routing mute; revocation.

**Explicitly deferred:**

| Later | Why not now |
|---|---|
| Per-context or per-tag witness credibility | §8 of the brief. General MR as witness prior is the cheap hypothesis; the limitation is documented in §13.5 and should be measured before being solved. |
| Negative tag evidence | §19 of the brief. Severe identity implications; the existing evaluation path already carries negative outcomes. |
| "Looking for: Transport ▾" context override | §16 of the brief. Needs a concrete use case where a request needs a different kind of recipient than its own type. |
| Named provenance with witness consent | Requires a consent model that does not exist. |
| Materialised projections | Requires benchmarks that do not exist. |
| Sensitive-tag restriction | D7. A config change if abuse appears. |
| Cross-request occurrence store | Out of scope; the ledger already carries what would be needed. |

---

## 19. Rejected architectures

1. **Tags as Dirichlet bins.** Bins are mutually-exclusive outcomes of one trial; tags are not. Normalisation would punish breadth — 5 transport + 5 pets scores 0.5 on transport, *below* a person with one transport observation — and adding pets evidence would *lower* transport belief. Rejected in D1.
2. **Rank-proportional witness weight.** 100 Sybils at rank 200 carry ≈0.05 each and sum to 5.0. Score-proportional weighting is not a preference; it is the Sybil defence.
3. **Per-query renormalisation of `m` over evidence-holding witnesses.** Looks like tidy normalisation, divides away exactly the mass dilution that defeats Sybils.
3b. **An eligibility bar set as a percentile of the ego's reachable window.** MeritRank's quantile bounds are rank-based over every node with positive score, so reachability alone buys eligibility and the attacker controls the denominator (§13.2, transformation 3). The bar must be a percentile of the ego's own `vote_user` list, which cannot be stuffed by anyone but the ego.
3c. **A fixed `m_min` ratio constant.** The original design. Its selectivity varies uncontrollably across egos because it is a ratio against each ego's own score distribution, whose *shape* changes with network size and structure — the same 0.25 admits fifteen contacts for one user and two for another, with no product intent behind the difference.
4. **Recursive belief propagation** (Dave observes → Bob believes → Alice counts Bob's belief). MeritRank already provides transitivity; compounding it double-counts and lets one witness launder a farm. Evidence stays first-hand, always.
5. **Materialised `ego × target × tag`.** Quadratic in users, invalidated by every MR change, and unnecessary — §14's scan is bounded.
6. **Global capability score / `usersByTag` search.** The LinkedIn attractor. Once a reverse index exists, everything else in this design is decoration.
7. **Hard-filtering the recipient list by tag.** Creates the `no history → never shown → no history` trap the brief names, and turns subjective memory into a caste mechanism.
8. **Per-tag MeritRank graphs in v1.** Expensive, and the general-MR hypothesis is untested. Note that Tentura's existing MR `context` parameter is used here — but only to keep witness weighting in the same space as visibility, which is not the same thing as a per-tag graph.
9. **Self-declared capability as evidence** (today's `commitRole`). A self-authored global skill claim. Rejected in D2, and generalised into the `w ≠ c` invariant.
10. **Free author choice of acknowledgement tags.** A closure becomes a free-form endorsement decoupled from the situation. Rejected in D8.
11. **Blending seed and outcome into one number.** Requires an arbitrary weight, hides which kind of evidence is speaking, and makes both harder to calibrate. Rejected in favour of two channels with structural precedence.
12. **Folding ego's own evidence into the weighted sum** with a `λ_self`. Different scale, different sentence, and the constant does no work. Ego evidence is Tier A.
13. **An unrestricted sum paired with an existential eligibility flag** (`S ≥ θ ∧ ∃ eligible witness`). Superseded by D15. One eligible witness holding nearly-expired evidence sets the flag while an ineligible coalition supplies the mass — at 24 months a single observation is still worth `0.111`, leaving a coalition only `0.189` to find. Gate the contributing set, not a boolean.
14. **Emitting outcome evidence at evaluation submission.** Value-independent and pre-finalization: a negative evaluation could mint positive evidence, and later edits would not retract it. Superseded by D16.
15. **Calling `seedRoutingAttestation` from the Forward composer.** Double-counts one decision and converts a request-specific reason into a standing beaconless attestation. Superseded by D17.
16. **Gating aggregation on `created_at >= deployment`.** A timestamp is not consent. Briefly replaced by a client-asserted disclosure version, then removed entirely pre-launch (D19) — with no production and no shipped clients, neither mechanism protects anything real.

---

## 20. Open product decisions

1. **Final copy** for the three tier labels, in every supported locale. "Seen helping with" and "Suggested for" are placeholders that happen to satisfy §12 of the brief; they have not been through copy review.
2. **Invite prompt lifetime** — fires once and dismisses permanently, or re-offerable? Now a state transition on the prompt-state record (§11), so either answer is a product choice with no schema consequence.
2b. **Disclosure wording** for the forward-reason and acknowledgement entry points. No longer a gate on the witness layer (D19) — but still a launch requirement, since both surfaces widen in reach. Needs product review before real users exist.
3. **Tier C visual treatment** — is wording alone enough to separate "suggested" from "seen", or does the band need a second visual register? Risk of a two-tier badge system if overdone.
4. **`θ` recalibration** after real data. The values in D13 are hypotheses calibrated against synthetic cases; the band-fill rate is the metric that should move them. The eligibility bar has only one free parameter left — the 33rd percentile — and it should move only if the measured floor turns out to sit at or below the sponsored-Sybil band (§21).
5. **Ack cap 3 vs display cap 2.** A recorded third tag is invisible in the band but visible on the profile. Acceptable, or should the caps be equal?
6. ~~Forward-reason visibility~~ — **resolved, not open.** The live reader is sender-or-recipient scoped (`observer = viewer OR subject = viewer`), and that scope is now **binding**. An earlier revision left this as an open question phrased on the false premise that any beacon participant could read them; leaving it open invited a privacy-*expanding* implementation in direct conflict with D19.
6b. ~~Which context the profile projection uses~~ — **decided: canonical default `''` (D24).**
7. ~~What Carol's routing screen shows for a muted tag~~ — **dissolved.** The screen renders the fixed taxonomy (§12.2), so every tag is always present and mute is always reversible.
7b. ~~D21 — author-only or participant-witness?~~ — **decided 2026-08-12: author + co-committers, forwarders excluded, (D21); the per-beacon budget originally paired with it was later withdrawn — see §7.** The deciding considerations: forwarders already have the seed channel and never observed the work; co-committers are frequently the *best*-informed witnesses and are concentrated on exactly the multi-person requests where routing memory has value; D15 already neutralises the ring amplification for witnesses the ego does not admit, leaving only the §13.3 residual; and coverage — not abuse — is this feature's largest existential risk.

---

## 21. Telemetry

Minimum to know whether this works, and whether it is being gamed:

- **Band fill rate** — share of Forward screens where the band renders at all, and slot occupancy by tier. If network-outcome tiers are near-zero after a quarter, `θ_out` or the admission bar is wrong.
- **Band conversion** — forwards initiated from a band row vs the main list, split by tier and by exploration slot. Exploration slots converting at ~0 means they are noise; converting well means the MR ordering is under-serving the tail.
- **Seed decay reality** — how many seeds are ever renewed by a forward reason before expiring.
- **Acknowledgement reciprocity** — pairs whose acknowledgements are mutual and who share no third-party collaborators. The §13.3 detector.
- **Mute rate per tag** — a tag muted far above baseline is a taxonomy or wording problem, not a user problem.
- **Window coverage** — share of egos whose witness window is empty, and separately the share whose `vote_user` list is empty (no eligibility floor, hence Tier A only). These are independent and both bound how much of the userbase the feature can serve at all.
- **Floor margin.** Distribution of `floor(A)` against the score band occupied by 2-hop-sponsored nodes. Under m0122 an explicit vouch does contribute directly to MR, so this is a calibration check rather than a soundness question — but the vouch's contribution depends on bin, count and rebuild timing, so overlap is still worth watching. If the distributions overlap, the 33rd percentile is the parameter to raise.
- **Eligible-witness coverage.** Share of `(subject, tag)` pairs holding evidence that clears `θ` from eligible witnesses versus pairs holding evidence only from ineligible ones. D15 discards the latter entirely; this metric is how much the design gives up for that safety, and it is the number to bring to any argument for softening the gate.

---

## 21a. Qualitative invariants are the executable spec

The constants in this document — `θ_out`, `θ_seed`, `K_o`, `K_s`, the half-lives, the 33rd percentile — are **calibration hypotheses**, and §20/§21 expect them to move once there is real data. The **ordering relations** are not hypotheses; they are the design.

Implementation unit D4 pins the orderings as a property suite that asserts inequalities and never magnitudes, so that recalibrating a constant cannot silently invert the model. Its coverage maps directly onto this document: subjectivity (§5.3), channel precedence (§5.4), witness weighting and **monotonicity** (§5.2.1, §7), accumulation shape (§7), decay (§7), mute and tombstone (§12), exclusions (§13.4), and band behaviour (§8–9).

Two properties deserve their place there specifically because this design got them wrong at some point and a numeric test would not have caught either:

- **Adding a witness never decreases standing.** Violated by the withdrawn D23 budget.
- **A mute applies to exactly one `(subject, tag)` pair.** Violated by a port that returned an unkeyed set.

Every defect of that shape found across five adversarial passes was an *ordering* violation, not an arithmetic one.

---

## 22. The invariants

Any future change to this design must preserve all ten. They are restated here because every one of them has a cheap-looking optimisation that violates it.

1. **Tags are subjective.** `tags(Alice, Carol) ≠ tags(Eve, Carol)` by arithmetic, not by policy.
2. **Evidence is relational and event-based.** No canonical skill field on Person; the ledger is the truth and cells are a cache of it.
3. **Newcomers have a bootstrap path** — two, in fact, and neither requires the newcomer to describe themselves.
4. **Witness evidence is weighted by the ego's MeritRank**, score-proportional, never renormalised per query — and a witness may stand alone only against a bar drawn from the ego's own vote list, never from a population an attacker can inflate.
5. **Tags never hard-filter recipients.** The candidate set is untouched.
6. **Absence of evidence never excludes anyone**, and reserved exploration slots exist **whenever the band renders**. On a screen with no band the full MR-ordered list is already the unbiased view, so there is nothing to counterbalance — but the invariant is "no one is excluded", not "exploration slots always exist", and earlier text conflated the two.
7. **No people-by-tag search.** No endpoint takes a tag and returns people.
8. **The Forward UI shows only contextually relevant evidence** — matched needs only, never a mini-profile.
9. **The feature learns from real cooperation**, not self-description. `w ≠ c` is enforced in the query.
10. **Tentura does not become a public expertise marketplace.** No global counts, no scores, no leaderboards, no endorsements, no self-editable capabilities.
