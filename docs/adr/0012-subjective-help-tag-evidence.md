# ADR 0012: Subjective help-tag evidence

## Status

Accepted (2026-08-13). Records architecture decisions from
[`docs/plans/subjective-help-tag-evidence-architecture.md`](../plans/subjective-help-tag-evidence-architecture.md)
(D1–D24), implementation deviations from
[`docs/plans/subjective-help-tag-evidence-implementation-plan.md`](../plans/subjective-help-tag-evidence-implementation-plan.md)
§3, and one production remediation discovered during G1c prep.

Authority for live behavior remains code; this ADR is the durable decision log.

## Context

Tentura needed witness-weighted, decaying, subjective capability memory
(help tags) for forward routing and profile surfaces — without turning tags
into global reputation or MeritRank bins. The architecture doc encodes
product/model choices (D1–D24). The implementation plan made explicit
deviations where rebuild-on-write and launch constraints simplified the
storage model. Mid-implementation, witness-window caching was specified but
never wired, blocking all network-derived projection until fixed.

Related: user→user trust storage was restructured in m0122; see
[`docs/features/trust_edges.md`](../features/trust_edges.md).

## Decision — architecture (D1–D24)

| # | Decision |
|---|----------|
| **D1** | **Reject tags-as-Dirichlet-bins.** Bins in `user_trust_edge` are mutually-exclusive outcomes of one trial; tags are not exclusive. Reuse the *mechanism* (inflated accumulators, fixed anchor, lazy decay, saturating posterior mean with prior mass K) per `(witness, subject, tag)` cell, not the bin semantics. |
| **D2** | **`commitRole` (source_type 2) is dropped as evidence entirely.** Events keep being written for audit only. Superseded in scope by D18: excluded from *every* projection, self-view included. |
| **D3** | **Forward ranking uses a reserved context band** above the untouched MR-ordered list — 3 evidence slots + 2 exploration slots. Tag evidence can never reorder the main list. |
| **D4** | **Subject control is a per-tag routing mute.** Aggregate view, no witness names, no counts. Muting suppresses third-party projection only; it never suppresses a viewer's own first-hand evidence. |
| **D5** | **Two seed paths:** the `invite_accepted` Update prompt (newcomers) and `forwardReason` on a forward edge (behavioural, already captured). Private labels are **never** seeds. |
| **D6** | **Profile shows own evidence + witness-derived outcome only.** Seed-derived tags appear in Forward only. |
| **D7** | **No sensitive-tag class in v1.** All 37 slugs behave identically. Residual risk documented in architecture §13.6. |
| **D8** | **Outcome tags** are chosen from `beacon.needs ∪ activeHelpOffer(subject).helpTypes`. (Chooser widened from "the author" to author + co-committers by D21.) |
| **D9** | **Band matches all of the request's needs**; a row labels only the tags that actually matched, primary first, capped at 2 labels. |
| **D10** | **Memory horizon:** `H_out = 365d`, `H_seed = 90d`, hard 24-month exclusion window. |
| **D11** | **Exploration is deterministic:** no-evidence candidates, MR-ordered, minus anyone forwarded to in the last 30 days, rotated by `hash(request_id)`. |
| **D12** | **Cap 3 tags per `(subject, beacon)`** — across *all* acknowledging evaluators, not per evaluator. Under D21 a per-evaluator cap would let N committers inflate one request into 3N rows for the same person. |
| **D13** | **Display gate:** `θ_out = 0.30`, `θ_seed = 0.25`. Eligibility is **not** a constant: it is the 33rd percentile of the ego's own explicitly-trusted peers by `forward_mr` ("top 67%"), computed as a SQL quantile. **Only eligible witnesses contribute to `S` at all** — see D15. |
| **D14** | **Acknowledgements are revocable indefinitely.** Withdrawal is a witness correcting their own memory, not a request re-opening (S3 untouched); the cell is rebuilt from the 24-month ledger window. |
| **D15** | **Eligibility gates the contributing set, not a boolean.** `S` sums over eligible witnesses only; ineligible witnesses contribute zero rather than mass behind an existential flag. Supersedes the earlier `S ≥ θ ∧ ∃ eligible` formulation. |
| **D16** | **Outcome evidence is emitted at review *finalization*, not at evaluation submission**, and only for evaluations whose finalized value is `pos1` or `pos2`. Acknowledgement selections are mutable evaluation state until the window closes. |
| **D17** | **`source_type 4` is invite-only.** The Forward composer writes forward reasons through the Forward mutation alone; it never writes a standing attestation. |
| **D18** | **`commitRole` is excluded from every projection, including self-view.** D8's candidate set comes from the *active help-offer state*, not from ledger history. |
| **D19** | **Aggregation eligibility is a source-type rule, not a consent gate.** `privateLabel` and `commitRole` never aggregate; `forwardReason`, `closeAcknowledgement` and `seedRoutingAttestation` always do. Pre-launch (2026-08-12): disclosure-version interlock removed; disclosure wording remains a launch requirement via product review. |
| **D20** | **Every new operation carries an explicit authorization predicate** (architecture §16.1). Actor identity is JWT-derived; no operation trusts a client-supplied actor. |
| **D21** | **Author and co-committers may acknowledge; forwarders may not.** Roles `author`, `committer`, `formerCommitter` qualify. Forwarders are excluded because they never observed the work and already express routing judgement through the seed channel. Supersedes D8's "chosen by the author" wording. |
| **D22** | **Profiles render the outcome channel only, at any tier** (architecture §5.4 matrix). Tier alone does not authorise a surface; the channel does. |
| ~~**D23**~~ | **Withdrawn** (architecture §7). *Mechanically* non-monotone: weights are stored ego-independently in ledger rows while admission is per-ego, so an extra acknowledger a given ego does *not* admit can drop that ego's `S` below θ and **erase** evidence a trusted witness supplied — corroboration must never subtract, and every weight-division scheme shares this property. *Conceptually* it corrected the wrong quantity: a budget guards **intensity** ("how much has Carol done"), but this system measures **evidential quality** ("is it true Carol helps with this"), for which independent attestations of one event legitimately accumulate. |
| **D24** | **Profile projection uses the canonical default context (`''`)**, not the viewer's selected context — a profile is not a browsing-context-scoped object. Closes architecture §20.6b. |

## Decision — implementation deviations (plan §3)

These are explicit implementation choices that **differ from** the architecture
doc; they are not renumbered D-decisions.

| # | Deviation |
|---|-----------|
| **3.1** | **Rebuild-on-write replaces inflate/deflate accumulators in cells.** Every ledger mutation bumps generation and fully rebuilds the cell from the eligible ledger window inside one transaction/lock. `anchor_at` is reset to rebuild time and contributions are deflated to it — algebraically equivalent to fixed-anchor VSIDS but a different storage invariant (architecture §5.1). |
| **3.2** | **No per-request observation budget** (follows withdrawn D23). Every acknowledgement emits at weight `1.0`; no `weight` column; C2 does no budget arithmetic. |
| **3.3** | **No disclosure gate** (architecture D19 narrowed at implementation). No `disclosure_version`, client token, or eligibility filter. Source-type rule only: `privateLabel`/`commitRole` never aggregate; `forwardReason`, `closeAcknowledgement`, `seedRoutingAttestation` always do. Witness layer is live when A–F land. |
| **3.4** | **Profile context:** `subjectiveTags` uses canonical default context `''`, not the viewer's selected browsing context. |
| **3.5** | **Context normalization contract:** `public.cap_normalize_context(text)` in SQL plus a pure Dart twin (not a SQL wrapper), parity-tested. Rule: `NULL` → `''`; trim; length outside 3–32 → `''`; otherwise trimmed value with **case preserved** (no lowercasing). |

## Remediation note — witness window read-through (not a design change)

Architecture §15 specified `ego_witness_window` as the only cached projection
artifact (read-through on miss). Implementation landed `WitnessWindowPort.storeWindow()`
and GC/invalidation but **no caller populated the table** until G1c prep
(2026-08-13). `CapabilityProjectionCase.project()` read `cachedWindow()` only,
so Tier B/C network evidence never rendered. Fix: read-through in
`CapabilityProjectionCase._loadWitnessWindow()` — on cache miss, compute via
`rawWindowFacts` + `computeWitnessWeights` + `storeWindow`, then use the
result for the current request. Zero-peer egos accept per-request recomputation
(no sentinel row); invite-only signup makes that rare.

## Consequences

- Tag evidence is subjective, witness-gated, and MR-read-only; trust edges
  remain the separate user→user MeritRank input (m0122 source/projection split).
- D23 withdrawal and plan §3.2 are coupled: never reintroduce per-request
  weight splitting without revisiting monotonicity under per-ego admission.
- Plan §3 deviations must be preserved in cell rebuild SQL/tests; treating
  cells as authoritative accumulators would drift from equivalence guarantees.
- Witness-window cache behavior is part of the projection contract; future
  changes should keep read-through on miss or an equivalent populate path.
- Disclosure copy is still required before real users despite D19/§3.3 removing
  the data-model gate.

## References

- Architecture: `docs/plans/subjective-help-tag-evidence-architecture.md`
- Implementation plan: `docs/plans/subjective-help-tag-evidence-implementation-plan.md`
- Trust edge storage (pattern donor): `docs/features/trust_edges.md`
- Implementation journal: `docs/plans/subjective-help-tag-evidence-implementation-journal.md` (G1c CRITICAL FINDING, witness-window fix)
