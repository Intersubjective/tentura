# Forward trust propagation (v1)

Design reference for typed trust source graphs and request-outcome forward learning.
Normative outcome mapping (sign-off S1):

| Author evaluation | Direct commitment bin | Forward route evidence |
| --- | --- | --- |
| noBasis (0) | none | none |
| neg2 (1) | very_bad | no_effect, `negative_commitment_route_no_effect` |
| neg1 (2) | bad | no_effect, `negative_commitment_route_no_effect` |
| zero (3) | no_effect | no_effect, `propagated_author_evaluated_commitment` |
| pos1 (4) | good | good, `propagated_author_evaluated_commitment` |
| pos2 (5) | very_good | very_good, `propagated_author_evaluated_commitment` |

## Quantity vs value

- **Bin** = outcome value (Dirichlet utility mapping unchanged).
- **Count** = evidence quantity (budget-normalized for evaluated routes).
- Every bin-mappable author evaluation of a committer contributes observation
  weight `1.0`; utility differences come only from the bin mapping, not from
  extra count multipliers on `very_good`.

## Vector consolidation

Per commitment: build eligible author-rooted DAG → terminal mass 1.0 → backward
propagation (attribution → equal fallback per distinct sender) → local
normalization per sender. Accumulate support per `(sender, recipient, bin,
provenance)` where `provenance ∈ {evaluated, negativeRoute}`. One budget
`1.0` per sender normalizes across all cells; `unsuccessful_request_forward`
is outside the budget with full configured `no_effect` count per pair.

## Semantics

- `negative_commitment_route_no_effect`: observed negatively evaluated path
  (neutral route learning).
- `unsuccessful_request_forward`: eligible pair with no observed evaluated
  commitment on its path (not the same as negative route).

## Closed requests (S3)

Once finalized, a request never re-opens; users duplicate the request for another
round. Client shows a non-dismissible closed banner; server guards re-scaffold.

## Policy changes

Half-life/epsilon change only via quiesced migration (see plan §10.2): stop app,
optional re-anchor, rebuild effective projection in one transaction, `mr_reset()`
last, cold-start `meritrank_init` before workers.

## Audit metadata (S4)

Ledger `metadata` holds only `algorithm_version`, `supporting_commitment_ids`, and
`attribution_method` when applicable — no display names, notes, or intermediate
math.

## Constants (v1 hypotheses)

- `kForwardObservationWeight = 1.0`
- `kForwardEvaluatedOutcomeBudget = 1.0`
- `forward` context multiplier: `0.20` (SQL `trust_context_config`)
- `FORWARD_NO_EFFECT_COUNT`, `FORWARD_MIN_OPPORTUNITY` (env)

## Worked example (negative route)

Author evaluates one committer `bad`: direct `very_bad` commitment evidence to
the committer; along the forwarding path, `no_effect` route evidence with
`negative_commitment_route_no_effect`; unobserved eligible pairs receive
`unsuccessful_request_forward`.
