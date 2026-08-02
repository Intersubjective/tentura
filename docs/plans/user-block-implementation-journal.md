---
status: in-progress
kind: journal
---
# User blocking — implementation journal

**Plan source:** [`user-block-design.md`](./user-block-design.md) (rationale) +
[`user-block-implementation-spec.md`](./user-block-implementation-spec.md) (§12 has the
S1–S24 subtask manifest — read it before touching any unit).

**Repository:** `/home/vader/MY_SRC/tentura` (pub workspace: `packages/client`,
`packages/server`, `packages/tentura_lints`).

**Branch:** `feature/user-block`, created off `main` at commit `8f714f9e` (which includes
the just-merged PR #95 "Fix graph tap explore vs rollback intent" and one pre-existing
unrelated local commit `8f714f9e` "Expand graph local fan by chord constraints"). Do not
rebase or rewrite this branch's history.

**Pre-existing worktree state at branch creation (untouched, not ours to clean up):**
untracked `dart-defines`, `key.fb`, `out.key`, and two unrelated plan docs
(`docs/plans/graph-navigation-implementation-guide.md`,
`docs/plans/graph-navigation-rework-plan.md`). Leave these alone.

**Local dev stack:** postgres, hasura, meritrank, minio already running via docker compose
(`docker ps` confirms all healthy). `.env` present at repo root. `cursor-agent` authenticated,
default model `composer-2.5` confirmed current (not `-fast`).

## Scope for this run

Full plan, all 24 subtasks (S1–S24), per user decision — not just the design doc's v1
(B1+B3) scope. Cascade (S12–S14) and B3 (S15–S16) both ship in this pass, in the spec's
own subtask order (cascade before B3, matching the implementation spec's Phase 4/5 — the
design doc's "B3 ships inside v1" is about product framing, not implementation order).

## Ordered unit manifest (from spec §12)

Phase 1 — schema:
- [x] S1 — migration m0135 (tables + predicates) — no deps
- [ ] S2 — Drift tables + entities — deps: S1

Phase 2 — server data & domain:
- [ ] S3 — UserBlockRepositoryPort + repository — deps: S2
- [ ] S4 — UserBlockCase + cleanup orchestration — deps: S3
- [ ] S5 — V2 GraphQL API — deps: S4

Phase 3 — enforcement:
- [ ] S6 — migration m0136 part 1: beacon wall + trigger — deps: S1
- [ ] S7 — migration m0136 part 2: graph, mutual friends, computed fields — deps: S6
- [ ] S8 — Hasura metadata — deps: S7
- [ ] S9 — server-side write guards (E2,E4,E5,E6,E7,E14) — deps: S4
- [ ] S10 — attention recipient filtering (E8) — deps: S4
- [ ] S11 — genealogy placeholder (E13) — deps: S4

Phase 4 — cascade:
- [ ] S12 — block_cascade_candidates verification (test-only) — deps: S1
- [ ] S13 — cascade materialization job — deps: S12, S5
- [ ] S14 — release sweep — deps: S13

Phase 5 — B3:
- [ ] S15 — migration m0137: withdrawal gate — deps: S1
- [ ] S16 — wire withdrawal through block/unblock/cascade/release — deps: S15, S13

Phase 6 — client:
- [ ] S17 — client data + domain — deps: S5
- [ ] S18 — cubit + state — deps: S17
- [ ] S19 — block sheet — deps: S18
- [ ] S20 — blocked list screen — deps: S18
- [ ] S21 — profile entry point + blocked-profile rendering — deps: S19
- [ ] S22 — l10n + cache invalidation — deps: S19, S20, S21

Phase 7 — hardening:
- [ ] S23 — adversarial suite — deps: S16, S14
- [ ] S24 — docs + release note — deps: S23

**Execution order chosen** (respects deps, one unit at a time): S1, S2, S3, S4, S5, S6, S7,
S8, S9, S10, S11, S12, S13, S14, S15, S16, S17, S18, S19, S20, S21, S22, S23, S24.

## Acceptance / verification commands (spec §12 final gate)

```bash
cd packages/server && dart analyze && dart test -x pg && dart test -t pg
cd packages/client && flutter analyze --no-fatal-warnings --no-fatal-infos
cd packages/client && flutter test --dart-define=ENV=test
cd packages/tentura_lints && dart test
./scripts/check-custom-lints.sh          # baseline: client 115, server 0 — must not grow
rg "package:tentura_server/data/repository" packages/server/lib/domain   # must be empty
```

## Unresolved decisions / blockers

(none yet)

## Checkpoints

- 2026-08-02: Journal created. Branch `feature/user-block` set up off `main`. Beginning
  S1.
- 2026-08-02 (S1 complete): Added `m0135` — `user_block`, `user_block_intent`, and
  predicates `block_hides`, `block_cascade_unattached`, `block_cascade_candidates`.
  Registered in `_migrations.dart`. Applied to shared dev DB via
  `dart run bin/utils/run_migrations_once.dart` (sourced root `.env`; harmless
  `PUBLIC`/`PRIVATE` shell noise from multiline JWT keys in `.env`). Did **not** create a
  scratch DB — dev postgres already had m0001–m0134; m0135 applied idempotently on top.
  **Schema ownership:** confirmed precedent from m0134 commit `d473957b` — migration-only
  PR, no Drift tables in same commit. S2 owns Drift registration.
  **Verification:** `\d public.user_block` shows both indexes + `user_block__no_self`;
  `SELECT public.block_hides('U1','U2')` → `false` (no user rows needed — function reads
  empty table only); server boot (`dart run bin/tentura.dart`, 25s) passed migrate + DI +
  worker start; `dart analyze` on changed migration files — info-only
  `unnecessary_raw_strings` on `r'''` SQL blocks (matches house style in m0133/m0134).
