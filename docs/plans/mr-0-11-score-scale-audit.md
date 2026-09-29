# MeritRank v0.11.0 — absolute score threshold audit (P0.3)

**Scope:** `packages/server/lib` and SQL migrations (`packages/server/lib/data/database/migration/`).  
**Pinned runtime:** pgmer2 / MeritRank service **v0.11.0** (`compose.dev.yaml`, `compose.prod.yaml`, CI).  
**Scale note:** Under v0.11.0, raw MR magnitudes are roughly **~6× smaller** than pre-0.11 baselines used in early closure drafts. This audit only flags comparisons that embed a **numeric cutoff on returned MR scores**; sign-only `> 0` filters are **scale-invariant** (multiplying all scores by a positive constant leaves membership unchanged).

**Out of scope (not MR score policy):** polling scores 0–5 (`polling_case.dart`), capability θ in `capability_consts.dart` (weighted evidence, not raw MR), client `Profile.forwardMeritRankPositive => score > 0`.

## Scale direction

P0.3 (`episode-closure-implementation-steps.md`) states that MR **v0.11.0** raw scores are roughly **~6× smaller** than pre-0.11 baselines. The product plan’s **U0.3** (`episode-closure-implementation-plan.md`) instead says magnitudes **grew ~6×** (fixed walk denominator in 0.11.0). The directions disagree on whether magnitudes shrank or grew, but **rescaling verdicts in this file are unchanged either way**: every inventoried comparison is **sign-only** `> 0`, which is invariant under any positive scalar on all returned scores. For MR service semantics and the v0.11.0 baseline, see `~/MY_SRC/meritrank-rust/NEGATIVE_EDGES_FEATURE.md` (pinned with pgmer2 in compose/CI).

## Mapper / lookup (no absolute MR cutoff)

| Artifact | Role |
|----------|------|
| `data/repository/mappers/mr_score_value.dart` | `mrScoreAsDouble` — null → 0; no threshold. |
| `data/repository/merit_score_lookup.dart` | SQL mutual-positive peer lookup; thresholds listed below in the inventory. |

## `mr_graph` / `mr_scores` — `0` and `100` are **not** score thresholds

These arguments are **offset / limit (pagination)** caps on graph/score rows, mirroring Hasura `graph()` / `my_field()` contracts — **not** minimum or maximum MR score cutoffs.

| Location | Call | Note |
|----------|------|------|
| `data/repository/forward_candidate_context_sql.dart` | `mr_graph(..., true, 0, 100)` | Pagination offset `0`, limit `100`. |
| `data/database/migration/m0193.dart` (≈1817–1823) | `mr_graph(..., 0, 100)` | Same pattern in `graph()` SQL function. |
| `data/database/migration/m0193.dart` (≈2291–2301) | `mr_scores(..., 0, 100)` | Same pattern in `my_field()` SQL function. |

## Inventory — absolute MR score comparisons (`> 0`)

Each row is one live site matched by the P0.3 scanner (`score_value_of_src|dst`, `forward_mr`, `reverse_mr` compared to zero). **Rescale verdict:** whether the literal `0` cutoff must be divided/multiplied when MR magnitudes shrink (~6×) — **no** for all entries below because only **strict positivity** is tested, not a fixed magnitude.

---

### `data/repository/merit_score_lookup.dart:36`

- **Literal:** `> 0::double precision` on `ms.score_value_of_src`
- **Snippet:** `AND ms.score_value_of_src > 0::double precision`
- **Rescale verdict:** **no** — sign-only; reciprocal-positive peer filter.

### `data/repository/merit_score_lookup.dart:37`

- **Literal:** `> 0::double precision` on `ms.score_value_of_dst`
- **Snippet:** `AND ms.score_value_of_dst > 0::double precision`
- **Rescale verdict:** **no** — sign-only.

---

### `data/repository/witness_window_repository.dart:30`

- **Literal:** `forward_mr > 0`
- **Snippet:** `WHERE forward_mr > 0`
- **Rescale verdict:** **no** — trusted peer set for witness-window floor; sign-only.

### `data/repository/witness_window_repository.dart:49`

- **Literal:** `forward_mr > 0`
- **Snippet:** `AND forward_mr > 0`
- **Rescale verdict:** **no** — sign-only.

---

### `data/repository/band_candidate_repository.dart:140`

- **Literal:** `forward_mr > 0`
- **Snippet:** `WHERE forward_mr > 0`
- **Rescale verdict:** **no** — sign-only eligibility for band context.

---

### `data/repository/capability_telemetry_repository.dart:140`

- **Literal:** `forward_mr > 0`
- **Snippet:** `AND forward_mr > 0`
- **Rescale verdict:** **no** — sign-only in telemetry SQL.

### `data/repository/capability_telemetry_repository.dart:424`

- **Literal:** `forward_mr > 0`
- **Snippet:** `WHERE forward_mr > 0`
- **Rescale verdict:** **no** — sign-only.

### `data/repository/capability_telemetry_repository.dart:446`

- **Literal:** `forward_mr > 0`
- **Snippet:** `AND forward_mr > 0`
- **Rescale verdict:** **no** — sign-only.

---

### `data/database/migration/m0193.dart:2224`

- **Literal:** `> 0::double precision` on `ms.score_value_of_src`
- **Snippet:** `AND ms.score_value_of_src > 0::double precision`
- **Rescale verdict:** **no** — `mutual_friends` / peer visibility SQL; sign-only.

### `data/database/migration/m0193.dart:2225`

- **Literal:** `> 0::double precision` on `ms.score_value_of_dst`
- **Snippet:** `AND ms.score_value_of_dst > 0::double precision`
- **Rescale verdict:** **no** — sign-only.

### `data/database/migration/m0193.dart:2239`

- **Literal:** `> 0::double precision` on `ms.score_value_of_src`
- **Snippet:** `AND ms.score_value_of_src > 0::double precision`
- **Rescale verdict:** **no** — duplicate branch in same migration; sign-only.

### `data/database/migration/m0193.dart:2240`

- **Literal:** `> 0::double precision` on `ms.score_value_of_dst`
- **Snippet:** `AND ms.score_value_of_dst > 0::double precision`
- **Rescale verdict:** **no** — sign-only.

### `data/database/migration/m0193.dart:3807`

- **Literal:** `forward_mr > 0::double precision`
- **Snippet:** `(s.viewer_explicitly_trusts_subject OR s.forward_mr > 0::double precision)`
- **Rescale verdict:** **no** — `person_visibility_peers` forward leg; sign-only.

### `data/database/migration/m0193.dart:3809`

- **Literal:** `reverse_mr > 0::double precision`
- **Snippet:** `(s.subject_explicitly_trusts_viewer OR s.reverse_mr > 0::double precision)`
- **Rescale verdict:** **no** — reverse leg; sign-only.

### `data/database/migration/m0193.dart:3812`

- **Literal:** `forward_mr > 0::double precision`
- **Snippet:** `(s.viewer_explicitly_trusts_subject OR s.forward_mr > 0::double precision)`
- **Rescale verdict:** **no** — mutual visibility conjunction; sign-only.

### `data/database/migration/m0193.dart:3813`

- **Literal:** `reverse_mr > 0::double precision`
- **Snippet:** `AND (s.subject_explicitly_trusts_viewer OR s.reverse_mr > 0::double precision)`
- **Rescale verdict:** **no** — sign-only.

---

## Summary

| Rescale needed | Count |
|----------------|------:|
| **yes** | 0 |
| **no** (sign-only `> 0`) | 16 |

No in-repo server/migration logic compares MR scores to a **non-zero** absolute cutoff. Relative witness-window math (`forwardMr / rEgo`, percentile floors) scales numerator and denominator together and is scale-invariant; documented in `witness_window_policy.dart` but not listed above because it does not use `forward_mr > 0` on executable lines (only doc comments).

**Follow-up (outside P0.3):** If future closure work introduces literal MR cutoffs (e.g. immunity `τ_imm` on raw `T_recent`), re-run the P0.3 scanner and extend this file.
