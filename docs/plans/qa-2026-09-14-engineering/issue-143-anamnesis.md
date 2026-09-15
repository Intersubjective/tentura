# Issue #143 — BeaconClose `beacon_evaluation_participant_pkey` (23505)

**GitHub:** [Intersubjective/tentura#143](https://github.com/Intersubjective/tentura/issues/143)  
**Sentry:** [TENTURA-SERVER-M](https://vadim-bulavintsev.sentry.io/issues/TENTURA-SERVER-M)

## Symptom

- User action **Complete for review** (`graphql` `beaconClose`) fails with Postgres `UniqueViolationException` (`23505`) on constraint `beacon_evaluation_participant_pkey`.
- Example key: `(beacon_id, user_id)=(B678bc1ca1d1e, U6fca01549512) already exists`.
- Request stays **In progress** (open family) because the close transaction aborts.
- Raw Postgres error text can surface to the client instead of a domain-safe message.

## Root cause

`EvaluationCase.beaconClose` always calls plain `insertParticipant` for every row in the participant graph after `deleteReviewScaffoldingForBeacon` (`evaluation_case.dart` ~265–302). That is not idempotent:

1. **Orphan participant rows** — If `beacon_evaluation_participants` still contains `(beacon_id, user_id)` when close runs (partial prior attempt, data left outside a successful scaffolding wipe, or scaffolding delete not clearing participants in the failing deployment path), the blind insert hits the primary key and throws `23505`.
2. **Duplicate users in the close graph** — `EvaluationParticipantGraphBuilder.build` (`evaluation_participant_graph_builder.dart` ~83–147) always adds the author, then adds each ever-acknowledged committer without deduplicating by `userId`. When the author is also an acknowledged committer, `beaconClose` issues two `insertParticipant` calls for the same `(beacon_id, user_id)` in one transaction → same `23505`.

`deleteReviewScaffoldingForBeacon` in `evaluation_repository.dart` (~596–615) *does* delete participant rows when it runs successfully, but that does not help orphan rows that were never part of scaffolding cleanup or duplicate inserts in the same close pass.

## Relevant code

| Area | Path | Symbol / lines |
|------|------|----------------|
| Use case | `packages/server/lib/domain/use_case/evaluation_case.dart` | `beaconClose` ~163–345; `insertParticipant` loop ~294–302 |
| Participant graph | `packages/server/lib/domain/use_case/evaluation/evaluation_participant_graph_builder.dart` | `build` ~38–168 (author + committers, no dedupe) |
| Port | `packages/server/lib/domain/port/evaluation_repository_port.dart` | `insertParticipant`, `deleteReviewScaffoldingForBeacon` |
| Repository | `packages/server/lib/data/repository/evaluation_repository.dart` | `insertParticipant` ~56–72; `deleteReviewScaffoldingForBeacon` ~596–615 |

## Failing tests (TDD — expected red)

**File:** `packages/server/test/domain/evaluation/evaluation_case_test.dart`  
**Group:** `beaconClose participant row idempotency (issue #143)`

1. `closes into review when orphan participant row already exists` — PK-enforcing fake keeps a pre-seeded `(beacon_id, helper1)` row across scaffolding delete; close must still open review.
2. `inserts each participant user at most once when author is also committer` — author + self-committer graph must not double-insert the author’s `user_id`.

**Harness:** `_ParticipantPkeyEnforcingEvaluationRepository` in the same test file simulates Postgres `beacon_evaluation_participant_pkey` via `UniqueViolationException` (`23505`).

**Command (from `packages/server`):**

```bash
../../scripts/run_with_test_cleanup.sh --timeout 10m -- dart test \
  test/domain/evaluation/evaluation_case_test.dart \
  --exclude-tags pg \
  --name "issue #143"
```

**Observed result (2026-09-15):** `+0 -2` — both tests fail with `23505` / `beacon_evaluation_participant_pkey` thrown from `insertParticipant` at `evaluation_case.dart:295`.

Log snapshot: `/tmp/issue-143-test.log` (local agent run).

## Expected behavior (fix acceptance)

- `beaconClose` succeeds when participant rows already exist for the same users (idempotent insert: `ON CONFLICT` reuse/update, or skip-if-exists after verified delete).
- Request transitions to **review window** (`BeaconStatus.reviewOpen`) with review scaffolding created.
- Retrying close (or completing after a prior partial failure) does not raise `23505`.
- GraphQL/clients receive `EvaluationException` or success — never raw Postgres constraint text.
- At most one participant row per `(beacon_id, user_id)` per close; author+committer same user must not produce two inserts.

## Recommended fix (for implementer)

1. **Repository / port:** Change `insertParticipant` (or add `upsertParticipant` / `ensureParticipant`) to use Drift `insertOnConflictUpdate` / `insertOrIgnore` + update semantics aligned with product (reuse row, refresh role/summary if needed). Keep API on `EvaluationRepositoryPort`; implement in `evaluation_repository.dart` only.
2. **Use case:** Optionally dedupe `participants` by `userId` before insert in `beaconClose` (defense in depth); prefer single canonical row per user from graph builder if product allows merging author+committer copy.
3. **Scaffolding delete:** Confirm `deleteReviewScaffoldingForBeacon` runs in the same DB transaction as inserts during close; ensure orphans from failed closes are removed or made harmless via (1).
4. **API layer:** Map `UniqueViolationException` on this path to a stable `EvaluationException` if any insert remains non-idempotent.

Do **not** rely on the unit-test fake’s `orphanParticipantKeys` in production — it only models stale DB state.

## Codex / agent edit boundaries

**May touch:**

- `packages/server/lib/domain/use_case/evaluation_case.dart`
- `packages/server/lib/domain/use_case/evaluation/evaluation_participant_graph_builder.dart` (dedupe only if product-correct)
- `packages/server/lib/domain/port/evaluation_repository_port.dart`
- `packages/server/lib/data/repository/evaluation_repository.dart`
- `packages/server/test/domain/evaluation/evaluation_case_test.dart` (green the #143 group)
- Optional focused pg-tagged integration test under `packages/server/test/` if idempotency needs real Postgres

**Do not touch:**

- Generated `*.g.dart`, `*.freezed.dart`, Drift generated table code (regenerate via build_runner)
- Client UI/l10n except if separately required for error copy (this bug is server-side); never user-facing noun **beacon** in copy
- Unrelated in-flight client work (e.g. constellation) or other `docs/plans/*` files unless explicitly scoped
- `packages/client/lib/**` for this server-only fix

## Architecture constraints

- Server use cases depend on **ports**, not concrete repositories (`evaluation_repository_port.dart`).
- No edits to generated files; run codegen after GraphQL/schema changes only if needed.
- Terminology: internal **Beacon** / `beaconClose`; user-facing **Request** / complete for review — do not rename domain routes or expose “beacon” in user strings.
