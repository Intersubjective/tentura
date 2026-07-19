# Correction patch 1: preserve Dirichlet bins during multi-commitment consolidation

> Received 2026-07-19. Normative: supersedes the scalar request-outcome-strength and
> positive-only consolidation parts of `plan_forward.md` and of
> `typed-trust-source-graphs-plan.md` rev 2. Incorporated into the plan as rev 3
> (see plan Appendix C for the incorporation record and interpretation notes).

---

## 1. Core correction

Do not collapse several author-evaluated commitments into one scalar:

```text
request_outcome_strength
```

Do not select one final outcome bin for the whole request.

Do not convert:

```text
good      → 0.5
very_good → 1.0
```

into a scalar routing value before evidence is assigned.

Forward propagation must preserve the original non-negative Dirichlet bin of every author-evaluated commitment:

```text
no_effect
good
very_good
```

Negative author evaluations:

```text
bad
very_bad
```

must not automatically propagate through the forwarding path in v1.

They remain direct `commitment` evidence only.

---

## 2. Separate evidence quantity from evidence value

The Dirichlet bin and the evidence count have different semantics.

The bin represents outcome value:

```text
no_effect → neutral outcome
good      → good outcome
very_good → very good outcome
```

The count represents the amount or confidence of evidence.

In v1, every finalized author evaluation contributes the same base observation count:

```text
commitment_observation_weight = 1.0
```

regardless of whether the bin is:

```text
no_effect
good
very_good
```

The different impact of the bins is already encoded by the existing Dirichlet utility mapping:

```text
no_effect → 0
good      → 1
very_good → 5
```

Do not additionally weight `very_good` more heavily during request-level normalization unless an explicit future policy intentionally chooses double weighting.

A future `observation_weight` may represent confidence, scope or reliability, but it must be orthogonal to the outcome bin and must not implicitly derive from `good` versus `very_good`.

---

## 3. Per-commitment causal calculation

For every author-evaluated non-negative commitment `k`:

1. Record its original bin:

```text
bin(k) ∈ {
    no_effect,
    good,
    very_good
}
```

2. Build its eligible rooted temporal author-to-committer forwarding DAG.

3. Propagate one terminal raw causal mass backward.

4. Normalize raw mass locally for every participating sender.

For sender `u` and immediate recipient `v`, this produces:

```text
q_k(u, v)
```

with:

```text
Σ_v q_k(u, v) = 1
```

for every sender that participates in the causal graph of commitment `k`.

`q_k` represents the relative causal share of the sender’s immediate choices for that commitment.

It does not determine the Dirichlet bin.

The author’s evaluation determines the bin.

---

## 4. Accumulate support separately by Dirichlet bin

For every sender-recipient pair and every non-negative bin, calculate:

```text
R_bin(u, v) =
    Σ over commitments k where bin(k) = bin:
        observation_weight(k)
        × q_k(u, v)
```

For v1:

```text
observation_weight(k) = 1.0
```

Maintain separate support values:

```text
R_no_effect(u, v)
R_good(u, v)
R_very_good(u, v)
```

Do not sum these into one scalar before normalization.

Do not choose the maximum bin.

Do not average bin labels.

---

## 5. Normalize total observation mass per sender

For each sender `u`, calculate total evaluated-outcome support:

```text
Z(u) =
    Σ over recipients v:
        R_no_effect(u, v)
        + R_good(u, v)
        + R_very_good(u, v)
```

If:

```text
Z(u) = 0
```

emit no evaluated-outcome forward evidence for that sender.

For v1, define one bounded request-level evaluated-outcome budget:

```text
evaluated_outcome_budget(u, request) = 1.0
```

The budget is divided across both:

* recipients;
* Dirichlet bins.

For every non-zero bin support:

```text
delta_bin(u, v) =
    evaluated_outcome_budget
    × R_bin(u, v)
    / Z(u)
```

Required invariant:

```text
Σ over recipients and non-negative bins:
    delta_bin(u, v)
= evaluated_outcome_budget
```

within floating-point tolerance.

The normalization distributes evidence count.

It does not compare or normalize the utility values of different bins.

Dirichlet utility is applied later when the edge weight is calculated.

---

## 6. Worked example: good versus very_good

Suppose:

```text
B → C1 leads to one good commitment
B → C2 leads to one very_good commitment
```

and both paths have equal causal share.

Support:

```text
R_good(B, C1) = 1
R_very_good(B, C2) = 1
```

Total:

```text
Z(B) = 2
```

Evidence:

```text
forward[B, C1].good += 0.5
forward[B, C2].very_good += 0.5
```

This does not make both edges equivalent.

With the existing utility mapping:

```text
good      → 1
very_good → 5
```

the equal evidence count placed in `very_good` has substantially greater positive impact than the equal count placed in `good`.

Do not introduce an additional default bin multiplier during normalization.

---

## 7. Worked example: mixed observations on one edge

Suppose:

```text
B → C
```

belongs to:

* one `very_good` commitment path;
* one `good` commitment path;
* one `no_effect` commitment path.

Then:

```text
R_very_good(B, C) = 1
R_good(B, C) = 1
R_no_effect(B, C) = 1
```

If B has no other successful evaluated recipient:

```text
Z(B) = 3
```

Write:

```text
forward[B, C].very_good += 1/3
forward[B, C].good += 1/3
forward[B, C].no_effect += 1/3
```

This mixed evidence is intentional.

Do not collapse it into a single average bin before applying it to the source Dirichlet state.

---

## 8. Neutral evaluated commitments versus unsuccessful forwards

Distinguish two uses of the `no_effect` bin.

### Neutral evaluated commitment path

The author evaluated a completed commitment as neutral:

```text
source_type =
    neutral_commitment_forward_path
```

The neutral observation propagates through the commitment’s causal path and participates in the bounded evaluated-outcome budget.

### Unsuccessful forwarding relation

A sender-recipient relation produced no finalized evaluated commitment:

```text
source_type =
    unsuccessful_request_forward
```

This is a separate route-failure observation.

It remains outside the evaluated-outcome budget and may receive its own configured count:

```text
unsuccessful_forward_no_effect_count = 1.0
```

Do not divide this count as part of the evaluated-outcome budget.

When classifying unsuccessful forwarding relations, exclude every sender-recipient pair belonging to the causal path of any finalized author-evaluated commitment, including:

```text
no_effect
good
very_good
```

A path leading to a neutral evaluated outcome is observed and neutral; it is not an unobserved failed route.

---

## 9. Revised finalization algorithm

Replace the scalar request-outcome consolidation with:

```text
onRequestOutcomeFinalized(request):
    evaluated_commitments =
        all finalized commitments
        evaluated by the request author
        with bin in {
            no_effect,
            good,
            very_good
        }

    per_bin_support = empty map
    observed_pairs = empty set

    for each commitment k in evaluated_commitments:
        rooted_dag =
            buildEligibleAuthorRootedForwardDag(
                request,
                commitment.committer,
                commitment.created_at
            )

        if rooted_dag has no author-to-committer path:
            continue

        raw_edge_mass =
            propagateTerminalMassBackward(
                terminal_mass = 1.0,
                attribution priority:
                    explicit attribution
                    recorded parent
                    opened-via
                    fallback equal
            )

        local_shares =
            normalizeRawMassPerSender(raw_edge_mass)

        bin =
            mapAuthorEvaluationToDirichletBin(
                commitment.author_evaluation
            )

        for each pair (sender, recipient):
            q = local_shares(sender, recipient)

            per_bin_support[
                sender,
                recipient,
                bin
            ] += observation_weight(commitment) × q

            observed_pairs.add(
                sender,
                recipient
            )

        store raw mass and local shares for audit

    for each sender represented in per_bin_support:
        Z =
            sum support across:
                all recipients
                and all non-negative bins

        if Z <= 0:
            continue

        for each non-zero (
            sender,
            recipient,
            bin
        ):
            count =
                evaluated_outcome_budget
                × support(sender, recipient, bin)
                / Z

            insert idempotent evidence event:
                context = forward
                subject = sender
                object = recipient
                bin = bin
                count = count
                source_type =
                    propagated_author_evaluated_commitment
                metadata includes:
                    supporting commitments
                    original bin
                    raw masses
                    commitment-local shares
                    per-bin support
                    normalization denominator
                    final count

    eligible_pairs =
        all eligible author-originating sender-recipient pairs
        with sufficient opportunity time

    for each pair in eligible_pairs:
        if pair in observed_pairs:
            continue

        insert idempotent evidence event:
            context = forward
            subject = pair.sender
            object = pair.recipient
            bin = no_effect
            count =
                unsuccessful_forward_no_effect_count
            source_type =
                unsuccessful_request_forward

    apply source events
    rebuild touched effective edges once
```

---

## 10. Ledger requirements

Evidence identity must preserve the bin.

A single request and sender-recipient pair may produce non-zero evidence in several bins:

```text
request
× sender
× recipient
× bin
```

Suggested uniqueness for propagated evaluated outcomes:

```text
UNIQUE(
    trust_context,
    source_type,
    request_id,
    subject_user_id,
    object_user_id,
    bin
)
```

The event metadata must preserve:

* supporting commitment IDs;
* original author-evaluation bins;
* observation weights;
* raw causal masses;
* commitment-local shares;
* pre-normalization per-bin support;
* sender normalization denominator;
* final emitted count.

---

## 11. Documentation correction

The design documentation must explicitly explain:

1. Bin identity represents outcome value.
2. Evidence count represents observation quantity or confidence.
3. Request-level normalization distributes evidence count, not utility.
4. `good` and `very_good` receive equal base observation weight in v1.
5. Their different impact comes from their distinct Dirichlet utilities.
6. Applying both a larger observation weight and a larger utility would double-weight outcome valence.
7. A future confidence weight must be orthogonal to the outcome bin.
8. One edge may receive mixed evidence in several bins from one request.
9. Neutral evaluated commitment paths and unobserved unsuccessful routes are semantically different despite sharing `no_effect`.

Include worked examples for:

* equal causal support with one `good` and one `very_good` outcome;
* mixed `no_effect`, `good` and `very_good` evidence on one edge;
* different bins on different recipients;
* a neutral evaluated path excluded from unsuccessful-forward classification.

---

## 12. Test corrections

Add or revise tests for:

### Bin preservation

* `no_effect` author evaluation propagates only to `no_effect`;
* `good` propagates only to `good`;
* `very_good` propagates only to `very_good`;
* negative bins do not automatically propagate in v1;
* several bins are never collapsed into one scalar outcome.

### Cross-bin normalization

* one `good` and one `very_good` observation with equal support each receive half of the evidence count;
* utility mapping, not normalization, produces their different posterior impact;
* the sum of counts across recipients and bins equals the sender’s evaluated-outcome budget;
* normalization is deterministic;
* zero support emits no evidence.

### Mixed evidence

* one pair may receive non-zero counts in several bins;
* mixed bin counts are applied atomically to the source Dirichlet row;
* mixed evidence is not averaged into one bin;
* repeated finalization is idempotent per bin.

### Neutral distinction

* a neutral evaluated commitment path receives propagated `no_effect`;
* the same path does not receive `unsuccessful_request_forward`;
* an unobserved failed relation may receive separate `no_effect`;
* unsuccessful counts remain outside the evaluated-outcome normalization budget.

### No implicit double weighting

* default observation weight is equal across `no_effect`, `good` and `very_good`;
* no hidden bin multiplier is used in request normalization;
* an optional future observation weight can change count without changing bin identity.

---

## 13. Acceptance-criteria correction

The revised implementation is complete when:

1. Every non-negative author-evaluated commitment retains its original Dirichlet bin through propagation.
2. Multi-commitment consolidation operates on a vector of per-bin support, not a scalar request outcome.
3. Request-level normalization limits total evidence count per sender while preserving bin identity.
4. `good` and `very_good` have equal default observation counts; their value difference is applied through the Dirichlet utility mapping.
5. One sender-recipient pair may receive evidence in several bins from one request.
6. Neutral evaluated paths are distinguished from unobserved unsuccessful routes.
7. Negative author evaluations remain direct commitment evidence and do not automatically propagate in v1.
8. Documentation explains the separation between evidence quantity and evidence value.
9. The implementation plan is revised to remove scalar outcome-strength and single-bin request consolidation assumptions.
