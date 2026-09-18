# Algorithm invariant suites — findings, questions, draft plan

**Tracking:** parent issue
[#118](https://github.com/Intersubjective/tentura/issues/118); blocking questions
[#119](https://github.com/Intersubjective/tentura/issues/119)–[#124](https://github.com/Intersubjective/tentura/issues/124).

**Status:** draft rev 1 — **BLOCKED**. Questions Q1–Q6 in §3 must be resolved before any
unit in §5 is implemented. Four of the six change what the tests are supposed to assert,
not merely how they are written; writing the suite first would bake today's behaviour in
as the specification, which is the precise failure this plan exists to prevent.

**Scope:** `packages/server` and `packages/client`. Extends the D4 "model invariant suite"
discipline from
[`subjective-help-tag-evidence-implementation-plan.md`](subjective-help-tag-evidence-implementation-plan.md)
§ UNIT D4 to the algorithms that already ship.

**Not in scope:** remediation of the findings in §2. See Q2 — whether remediation joins
this plan is one of the blocking questions.

---

## 0. One-page summary

D4 established a discipline for the tag/trust model: assert **inequalities and qualitative
outcomes, never magnitudes**; drive every case through one fluent fixture builder; run pure
domain code with fake ports. Its constants are hypotheses; its ordering relations are the
design. That discipline was never applied to the algorithms that shipped before it.

Applying it retroactively turned out not to be a mechanical exercise. Reading the shipped
trust math against
[`Tentura_current_status_quo.md`](../Tentura_current_status_quo.md),
[`beacon-evaluation-principles.md`](../beacon-evaluation-principles.md) and
[`trust-forward-propagation.md`](../design/trust-forward-propagation.md) surfaced **five
places where the algorithm encodes a different theory of trust than the design documents
commit to**, plus one test-infrastructure defect that makes the current trust tests
non-evidence.

So this plan has two halves that must not be conflated:

- **Mechanical invariants** (§4, suites S1a/S2/S3/S4/S5/S6) — properties that hold today and
  should be pinned so recalibration cannot silently invert the model. Uncontroversial.
- **Ideology invariants** (§4, suite S1b) — properties the design documents assert and the
  code does **not** satisfy. Writing these as passing tests would ratify the divergence.
  They land only after §3 resolves whether each divergence is a defect or an accepted
  exception.

---

## 1. What the ideology commits to, reduced to testable form

Four commitments recur across the design corpus. Each is checkable.

| # | Commitment | Source |
|---|---|---|
| **I1** | **Selective percolation, not maximization.** "Inhibitors against redundant closure, corridor concentration, broker capture"; "preserve useful paths; do not maximize ties." | status quo §1, §2 |
| **I2** | **Bounded episode effects.** "Keep single-beacon effects bounded; no one beacon should define a person"; "never apply heavy MR consequences from one beacon without safeguards"; "keep effects local, decayed, and aggregated over time." | evaluation principles, core principles + hard no-go + required safeguards |
| **I3** | **Neutral is a real state, distinct from absent.** "Never conflate 'neutral' with 'no basis to judge'"; "No basis" is first-class. | evaluation principles, hard no-go |
| **I4** | **Forwarding is not punished and creates no social tie.** Negative author evaluations map to `no_effect` route evidence; "Anti-pattern: I saw content, therefore a social tie was created." | trust-forward-propagation §normative mapping; status quo §11 |

Two further architectural commitments are load-bearing and currently untested:

| # | Commitment | Source |
|---|---|---|
| **I5** | **One-directional MR dependency.** Tag evidence reads `forward_mr` and never writes an MR edge — "a feedback loop between two subjective layers would be unanalysable." | capability architecture §3 |
| **I6** | **No global reputation score.** MeritRank is "hidden procedural"; evaluation summaries are beacon-local; never public cumulative scores. | status quo §2, §10; evaluation principles hard no-go |

---

## 2. Findings

Each finding states what the ideology asserts, what the code does, and the invariant that
exposes the gap. Findings F1–F5 are behavioural; F6 is test infrastructure.

### F1 — `no_effect` is not neutral; it is a dilutant

`trust_edge_weight` (`sql/triggers.sql:121-133`) is a posterior mean with prior mass 5:

```
w = f·(−5·s_vb − s_b + s_g + 5·s_vg) / (5 + f·(s_vb + s_b + s_ne + s_g + s_vg))
```

`s_no_effect` appears **in the denominator only**. Every `no_effect` observation therefore
shrinks an existing positive edge toward zero.

[`trust-forward-propagation.md`](../design/trust-forward-propagation.md) maps every
negative author evaluation to `no_effect` route evidence
(`negative_commitment_route_no_effect`) specifically so that forwarders are not punished
for routing to someone who under-delivered. With `forward` multiplier `0.20`
(`m0122.dart:67-69`) and `kTrustForwardNoEffectCount = 1.0`
(`trust_bin.dart:23`), a forwarder holding a single vouch (`w = 3/8 = 0.375`) who routes
ten requests that end badly decays to `3/(5 + 3 + 0.2·10) = 0.30`, and continues
decaying without bound toward 0. `unsuccessful_request_forward` compounds this: it is
emitted for eligible pairs that never acted, at full configured count, per pair.

The mapping does not remove the penalty. It makes it slower and sign-preserving.

**Invariant that exposes it (currently false):** route evidence derived from a negative
outcome never decreases the forwarder's standing.

**Against:** I4.

### F2 — neutral computes to exactly zero, and zero means delete

Per the owner's ruling, the weight passed to `mr_put_edge` may be any signed double, and
**zero carries the special meaning "delete the edge."** `trust_edge_weight` returns
exactly `0` in three semantically distinct situations:

1. no evidence at all;
2. pure `no_effect` evidence of any magnitude;
3. exactly balanced positive and negative evidence.

Case 2 is the problem. "We cooperated repeatedly and it was consistently unremarkable" is
byte-identical to "these two people have never met," and the resulting publish deletes the
MeritRank edge. `trust_rebuild_effective_edge` (`sql/triggers.sql:269-331`) will publish
that zero whenever `abs(_w - _prev) > _eps`, so an edge decaying from `0.6` to `0` is
actively deleted rather than held as a weak tie.

This is the conflation that
[`beacon-evaluation-principles.md`](../beacon-evaluation-principles.md) forbids at the
review layer, reproduced one layer down in the trust math, and it removes a real relay
path.

**Existing mitigation worth pinning:** `person_visibility_peers`
(`m0140.dart:154-162`) computes
`viewer_can_see_subject = viewer_explicitly_trusts_subject OR forward_mr > 0`. An explicit
vouch therefore keeps a peer visible regardless of what the trust math does. Nothing
currently tests this floor.

**Invariants:** (a) an edge carrying real cooperation history is never published as the
delete sentinel; (b) an explicit vouch preserves visibility under every trust-math outcome.

**Against:** I1, I3.

### F3 — single-episode effects are not bounded

Configured magnitudes:

| Evidence | Bin | Utility | Count | Context multiplier | Numerator contribution |
|---|---|---|---|---|---|
| vote / subscribe | `good` | +1 | 3 (`trust_bin.dart:16`) | `personal` 1.0 | +3 |
| review `pos2` | `very_good` | +5 | 1 (`trust_bin.dart:19`) | `commitment` 1.0 | +5 |
| review `neg2` | `very_bad` | −5 | 1 | `commitment` 1.0 | −5 |

Worked case: Alice vouches for Bob → `w = 3/(5+3) = 0.375`. Alice then leaves one `neg2`
review → `(3−5)/(5+4) = −0.222`.

**One beacon inverts the sign of an explicit vouch.** A single `very_bad` review outweighs
a deliberate vouch by 5:3 on first evidence.

The friction safeguards the principles require (strong ratings need reasons; review is
bounded to a window) are present. The *magnitude* safeguard the same document requires —
"keep single-beacon effects bounded," "never apply heavy MR consequences from one beacon
without safeguards" — is not.

**Invariant that exposes it (currently false):** no single episode inverts the sign of an
edge established by explicit trust.

**Against:** I2.

### F4 — the Dirichlet trial-exclusivity premise has a documented exception

D1 of the capability architecture rejects tags-as-Dirichlet-bins on the grounds that
"bins in `user_trust_edge` are mutually-exclusive outcomes of **one trial**; tags are not
exclusive." That premise is what licenses the model for trust, so it must hold there.

It mostly does — the per-sender budget of `1.0` in
[`trust-forward-propagation.md`](../design/trust-forward-propagation.md) §Vector
consolidation is precisely the trial-boundary enforcement, implemented by
`ForwardLocalNormalizer` (`forward_local_normalizer.dart`). But the same section states
that `unsuccessful_request_forward` "is outside the budget with full configured
`no_effect` count per pair." One request can therefore contribute more than one trial's
worth of mass for a single sender.

Either the budget is the trial boundary or it is not. As written, the model's own validity
condition has an exception carved into it.

**Invariant:** one request contributes at most `1.0` total evidence mass per sender.

**Against:** the Dirichlet model's stated premise (capability architecture D1).

### F5 — no corridor-concentration inhibitor exists in the trust layer

I1 names corridor concentration and broker capture as the primary things to damp. The
trust math has exactly two dampers: saturation (`5n/(5+n)`, asymptote ±5) and time decay.
**Both are per-pair.** A corridor is a pattern across pairs, and neither damps it.

The only implemented anti-concentration mechanism in the system is the per-sender budget
normalization in forward propagation — a sender who forwards to many recipients has each
recipient's share diluted. That is genuinely aligned with I1 and should be pinned as such.

This is recorded as a **design gap, not a defect**. No test is proposed; the plan records
it so a future calibration pass has it in writing.

**Against:** I1 (as a gap).

### F6 — the current trust tests test a copy of the function, not the deployed one

`packages/server/test/domain/trust/trust_math_test.dart:40-55` issues its own
`CREATE OR REPLACE FUNCTION public.trust_edge_weight(...)` with an inlined body **before**
asserting against it. The test therefore validates a copy pasted into the test file, not
the function the migrations deploy. If `m0088`/`m0122` and the test body diverge, the test
stays green.

Compounding this, every assertion in that file is a bare magnitude —
`closeTo(0.375, 1e-9)`, `closeTo(1/6, 1e-9)` — the exact pattern D4 forbids, and all of
them sit behind the `pg` tag, which CI excludes (`.github/workflows/pipeline.yml:80`,
`dart test --exclude-tags pg`).

**Net effect: the Dirichlet core has zero invariants enforced in CI, and the five tests
that exist prove nothing about the deployed function.**

---

## 3. Blocking questions

**No unit in §5 may start before these are answered.** Q1, Q3, Q4 and Q5 change what the
tests assert; Q2 and Q6 change the plan's size and shape.

Tracked as GitHub issues under parent
[#118](https://github.com/Intersubjective/tentura/issues/118):
**Q1** → [#119](https://github.com/Intersubjective/tentura/issues/119) ·
**Q2** → [#120](https://github.com/Intersubjective/tentura/issues/120) ·
**Q3** → [#121](https://github.com/Intersubjective/tentura/issues/121) ·
**Q4** → [#122](https://github.com/Intersubjective/tentura/issues/122) ·
**Q5** → [#123](https://github.com/Intersubjective/tentura/issues/123) ·
**Q6** → [#124](https://github.com/Intersubjective/tentura/issues/124).

| # | Question | Why it blocks | Author's read |
|---|---|---|---|
| **Q1** | **F1 — is `no_effect` erosion of a positive edge intended?** If yes, the invariant is written to match the code and I4 gets a documented exception. If no, S1b lands a failing test. | Determines whether the S3 negative-route-neutrality invariant confirms the sign-off or contradicts it. | Most likely intended — it is the honest Bayesian reading. But the S1 sign-off's stated goal is then not achieved, and that should be written down. |
| **Q2** | **Does this plan carry remediation, or only exposure?** Tests-only keeps it self-contained. Remediation touches live trust math and MeritRank publication. | Changes unit count from ~9 to ~15+ and adds migration ownership. | Tests-only. Remediate under a separate plan once the findings are accepted. |
| **Q3** | **F2 — should a neutral-but-real edge be distinguishable from an absent one?** Options: reserve zero strictly for deletion and floor real edges to ±ε; keep the conflation and document it. | Decides whether S1b-02 is a failing test or an accepted-behaviour test. | Genuine defect. "Preserve useful paths" and the neutral/absent no-go both point the same way. |
| **Q4** | **F3 — is one-episode sign inversion of a vouch acceptable?** Options: cap per-episode delta; raise the vouch count; accept and document. | Decides whether S1b-03 is a failing test or an accepted-behaviour test. | Needs a cap or an explicit product justification. The hard no-go is unusually direct here. |
| **Q5** | **F4 — is `unsuccessful_request_forward` sitting outside the per-sender budget deliberate?** | Decides whether S3's trial-exclusivity invariant is written with an exception clause or without one. | Likely deliberate (it covers pairs with no observation at all), but it weakens the D1 premise and should be stated. |
| **Q6** | **Is a Postgres service in CI acceptable?** Without it, no SQL-backed invariant runs in CI and the core suite is decorative. | S1a/S1b/S2 are unrunnable in CI otherwise. See §6. | Required. There is no alternative that respects "no Dart mirror." |

---

## 4. Invariant suites

Naming follows D4: one test per invariant id, named after the id. The **one rule that
matters** is inherited verbatim — assert inequalities and qualitative outcomes, never
magnitudes.

### S0 — Ideology conformance (structural)

Lives in the existing `packages/server/test/architecture/`, which already hosts contract
tests of this kind.

| id | Invariant | Guards |
|---|---|---|
| S0-01 | No read path returns a cross-beacon cumulative person score. | I6 |
| S0-02 | Evaluation summaries are beacon-local; no aggregate-across-beacons surface exists. | I6 |
| S0-03 | No capability/tag code path writes an MR edge (`mr_put_edge` / `mr_delete_edge`). | I5 |

### S1a — Dirichlet weight, mechanical (SQL)

Runs against the **deployed** `trust_edge_weight`, loaded from migrations. No mirror.

| id | Invariant | Why it matters |
|---|---|---|
| S1a-01 | Sign fidelity: `sign(w) = sign(5·s_vg + s_g − s_b − 5·s_vb)` across the full lattice. | Sign inversion silently rewires routing product-wide with no error surfaced. |
| S1a-02 | Mirror antisymmetry: swapping `vb↔vg` and `b↔g` negates `w` exactly. | Pins the ±5/±1 ladder's symmetry without pinning its values. |
| S1a-03 | Per-bin monotonicity: `∂w/∂s_g ≥ 0`, `∂w/∂s_vb ≤ 0`, over every `(bins × f)` cell. | A lost monotonicity means more good evidence can lower trust. |
| S1a-04 | Bin ladder at equal count: `very_good > good > no_effect = 0 > bad > very_bad`. | The ordering is the design; the utilities are hypotheses. |
| S1a-05 | Strictly increasing in evidence count, with diminishing increments (concavity). | This is the saturation the capability architecture credits the model with. |
| S1a-06 | Deflation: `0 < f' < f ⇒ |w(f')| < |w(f)|`, sign preserved; `f → 0 ⇒ w → 0`. | Decay must pull toward the prior, never flip a verdict. |
| S1a-07 | Numerical safety: no `NaN`/`Inf` at `f = 0`, at very large `f`, at very large `s_*`. | `f = 0` with zero evidence is a `0/0` candidate. |

**No range invariant.** Per the owner's ruling, the value handed to `mr_put_edge` may be
any signed double; only zero is special (delete). S1a asserts nothing about `|w| ≤ 1`.

### S1b — Dirichlet weight, ideology (SQL) — **gated on Q1, Q3, Q4**

| id | Invariant | Finding | Expected today |
|---|---|---|---|
| S1b-01 | Route evidence from a negative outcome never decreases the forwarder's standing. | F1 | **FAILS** |
| S1b-02 | An edge carrying real cooperation history is never published as the zero delete-sentinel. | F2 | **FAILS** |
| S1b-03 | No single episode inverts the sign of an edge established by explicit trust. | F3 | **FAILS** |
| S1b-04 | An explicit vouch preserves `viewer_can_see_subject` under every trust-math outcome. | F2 (mitigation) | passes — pin it |

### S2 — Typed-trust composition and VSIDS decay (SQL)

| id | Invariant | Why it matters |
|---|---|---|
| S2-01 | Context additivity: a context with `evidence_multiplier = 0` changes nothing. | |
| S2-02 | **Context precedence:** the same quantity of `forward` evidence never outweighs `personal` evidence, independent of the constants. | Structural analogue of D4's C1/C5 — pins intent, not the 0.20. |
| S2-03 | Decay is per-source-anchor: fresh `forward` evidence does not refresh stale `personal` evidence. | Anchor coupling is a classic defect class here. |
| S2-04 | With no new evidence, `|w|` is monotone non-increasing in time and never flips sign. | |
| S2-05 | Rebuild idempotence: two rebuilds with no new evidence and no clock movement neither double-count nor re-anchor. | `trust_rebuild_effective_edge` rewrites `anchor_at` on every call. |
| S2-06 | Epsilon gating changes **when** MeritRank is told, never **what** the stored posterior is; `abs(published − true) ≤ ε` holds at all times. | |
| S2-07 | `legacy` refuses writes. | |
| S2-08 | **Trial exclusivity:** one request contributes at most `1.0` total evidence mass per sender. | F4 — the model's own validity condition. Exception clause depends on Q5. |

### S3 — Forward outcome mapping and mass propagation (pure Dart)

Cheapest suite: pure functions, no ports, no database.

| id | Invariant | Why it matters |
|---|---|---|
| S3-01 | Mass conservation: terminal mass `1.0` distributes exactly; per-recipient splits sum to 1. | |
| S3-02 | Per-sender normalized shares sum to exactly 1 for every sender with nonzero raw mass. | The budget is the trial boundary (F4). |
| S3-03 | Explicit attribution with equal weights is **identical** to the equal fallback. | Adding uninformative metadata must not be a behaviour change. |
| S3-04 | Attribution weights are scale-invariant: multiplying all of them by a constant changes nothing. | |
| S3-05 | Every negative author evaluation yields `no_effect` route evidence, never negative. | Binding S1 sign-off. Read together with S1b-01 (Q1). |
| S3-06 | Bin/count separation: count is always `1.0`; only the bin differs across evaluation values. | Sign-off S1's "quantity vs value" split. |
| S3-07 | `noBasis` produces nothing, anywhere. | Encodes I3 at the emission layer. |
| S3-08 | `unsuccessful_request_forward` never reduces an evaluated route's share. | |
| S3-09 | Determinism under edge-insertion permutation. | |
| S3-10 | **Anti-concentration:** forwarding to more recipients never increases any single recipient-edge's evidence. | The system's only real corridor inhibitor (F5). |
| S3-11 | Cycles are rejected by the DAG builder, not survived by the propagator. | `ForwardMassPropagator.distribute` recurses with no visited set — a cycle is a stack overflow, not a wrong number. |

### S4 — Visibility and disclosure lattice (pure Dart)

Different character from the rest: a boolean lattice, so the sweep is **exhaustive over
the full fact cross-product**, not sampled. Importance is categorically higher — a wrong
answer here is a privacy incident, not a ranking wobble.

| id | Invariant |
|---|---|
| S4-01 | Privilege monotonicity: gaining a role never removes visibility; losing one never adds it. |
| S4-02 | Block dominance: a block removes content under every role combination. |
| S4-03 | Tombstone dominance, with the exception set enumerated explicitly. |
| S4-04 | All-flags-false yields the least-visible result (fail-closed default). |
| S4-05 | Independence: an unrelated user's facts never move ego's visibility. |
| S4-06 | Totality: every combination returns; nothing throws. |
| S4-07 | **Forwarding creates no social tie** — a forward edge alone grants no general profile visibility. (Status quo §11 anti-pattern.) |
| S4-08 | **Trust alone opens nothing** — an explicit vouch without an involvement path does not open the vouchee's requests. (`relationship-states.md`.) |

### S5 — Attention/updates policy and display-status derivation (pure Dart)

| id | Invariant |
|---|---|
| S5-01 | Totality over `(state, event)`; no silent `_ =>` default absorbing a new enum value. |
| S5-02 | Replay idempotence on the dedupe key. |
| S5-03 | Expiry monotonicity: sweeping twice is a no-op; expired items never resurface. |
| S5-04 | Priority order is total and deterministic. |

### S6 — Client layout and ordering determinism (pure Dart)

| id | Invariant |
|---|---|
| S6-01 | Radial-hop child sectors partition the parent sector without overlap and without gaps beyond configured padding. |
| S6-02 | Angular coverage is monotone non-decreasing in child count. |
| S6-03 | Siblings respect the minimum angular separation. |
| S6-04 | Layered-DAG ranks are stable under input permutation. |
| S6-05 | My-work card ordering is total and deterministic; adding a card never reorders unrelated ones. |

Justification for S6 is concrete: the ego-neighbour wedge-collapse
(`graph-ego-neighbors-layout-issue.md`, client `5.6.18`) shipped and was caught by eye.
S6-01/S6-02 are one line each and would have failed loudly.

---

## 5. Unit manifest

Strictly sequential. One worker at a time. **U0 is gated on §3.**

| # | Unit | Depends on | Owns |
|---|---|---|---|
| U0 | Resolve Q1–Q6; record answers in this file's §3 | — | this document |
| U1 | Phase-space harness + CI Postgres job | U0 (Q6) | `test/support/phase_space.dart`, `.github/workflows/pipeline.yml` |
| U2 | Fix F6; quarantine magnitudes | U1 | `trust_math_test.dart` → real SQL loading; new `calibration_snapshot_test.dart` |
| U3 | S1a — Dirichlet mechanical | U2 | `test/domain/trust/dirichlet_model_invariant_test.dart` |
| U4 | S1b — Dirichlet ideology | U3, U0 (Q1/Q3/Q4) | `test/domain/trust/dirichlet_ideology_invariant_test.dart` |
| U5 | S3 — forward propagation | U1 | `test/domain/trust/forward_model_invariant_test.dart` |
| U6 | S2 — typed-trust composition | U3, U0 (Q5) | `test/domain/trust/typed_trust_model_invariant_test.dart` |
| U7 | S4 — visibility lattice | U1 | `test/domain/visibility_lattice_invariant_test.dart` |
| U8 | S0 — ideology conformance | U1 | `test/architecture/ideology_conformance_test.dart` |
| U9 | S5 — attention/display state machines | U1 | `test/domain/attention/attention_model_invariant_test.dart` |
| U10 | S6 — client layout/ordering | U1 | `packages/client/test/features/graph/layout_invariant_test.dart` |

Suggested order after U2: U5 (cheapest, zero prerequisites beyond the harness), then U3,
U7, U6, U4, U8, U9, U10.

---

## 6. Test infrastructure decisions

**No Dart mirror of the SQL.** Ruled by the owner: a mirror cannot be guaranteed to be
updated by later agents and would drift from the SQL. Every Dirichlet and typed-trust
invariant therefore executes the deployed SQL.

**The suite loads real migrations.** U2 removes the inlined `CREATE OR REPLACE` from
`trust_math_test.dart` (F6) and replaces it with migration/`sql/triggers.sql` loading, so
the object under test is the object that ships. No test may define the function it tests.

**CI must gain a Postgres service.** CI runs `dart test --exclude-tags pg`
(`.github/workflows/pipeline.yml:80`). With no mirror, every S1/S2 invariant carries the
`pg` tag and would never execute in CI. U1 adds a `services: postgres` block and a job
that runs the invariant tags. Without this the core suite is decorative — see Q6.

**Deterministic lattice sweeps, not randomized property testing.** Nested loops over a
small named parameter lattice; no new dependency; reproducible failures. The harness names
each cell and prints the offending cell on failure. This matches how D4 already works.

**Magnitudes are quarantined, not deleted.** The surviving numeric assertions move to a
clearly labelled `calibration_snapshot_test.dart` so a recalibration produces one obvious
intentional failure instead of a scatter of confusing ones.

---

## 7. Acceptance

- Every invariant id in §4 has a test named after it, except ids explicitly deferred by a
  §3 answer.
- **No test in an invariant suite asserts a bare numeric magnitude.** The only magnitudes
  in the tree live in `calibration_snapshot_test.dart`.
- **Perturbation check (inherited from D4):** re-run every suite with half-life, epsilon,
  context multipliers and evidence counts each nudged by a modest amount. Anything that
  fails was asserting a magnitude and must be rewritten. This is a required, recorded run,
  not an aspiration.
- No test defines or redefines the SQL object it tests (F6 closed).
- The invariant job runs in CI against a real Postgres and is required to pass.
- S1b tests that are expected to fail under a §3 answer are marked with the answer's
  reference, not silently skipped.

---

## 8. What this plan deliberately does not do

- It does not remediate F1–F4 (pending Q2).
- It does not propose a corridor-concentration inhibitor for F5 — that is recorded as a
  design gap for a future calibration pass.
- It does not revisit D4's own suite, which already meets the standard.
- It does not touch `docs/features/trust_edges.md`, which the capability architecture §2.1
  already flags as stale (it documents the dropped m0088 world). Correcting it is a
  separate docs task.
