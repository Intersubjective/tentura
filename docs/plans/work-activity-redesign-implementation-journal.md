# Work / Activity redesign — implementation journal

Objective: execute `docs/plans/work-activity-redesign-implementation-plan.md` (UNITs 00–22) via the overseer skill.

Design source: `docs/plans/work-activity-redesign-plan.md` (rev 5). Implementation plan: revision 1, written against HEAD `d84acc940`.

## Execution environment

**Deviation from the plan's assumed environment.** The plan's §3 rule 3 lists pre-existing changes to preserve (`CONTEXT.md`, `docs/plans/inbox-activity-ia-architecture.md`, `packages/force_directed_graphview/analysis_options.yaml`, 35 untracked paths), assuming execution happens directly in the primary worktree at `/home/vader/MY_SRC/tentura` (branch `feature/pin_constellation`).

At kickoff, another live session had committed to that branch 8 minutes prior (last commit `d567523b3` at 2026-09-13T23:31:04+02:00), so the overseer created an **isolated git worktree** instead, to guarantee zero collision risk with any concurrent session and zero risk of ever touching the 35+ unrelated uncommitted paths (they simply don't exist here — this is a fresh checkout):

- Worktree: `/tmp/claude-1000/-home-vader-MY-SRC-tentura/4f632d59-f33a-4bba-bb53-0f45eca8975d/scratchpad/work-activity-redesign`
- Branch: `work-activity-redesign`, created from `feature/pin_constellation` at `d567523b3`
- `git status --short` in this worktree: **empty** (nothing to preserve here — the plan's §3 rule 3 list does not apply to this worktree).
- The user later confirmed all other agents on the repo were stopped, but the isolated worktree was kept anyway (already set up, strictly safer, no downside).
- Primary worktree (`/home/vader/MY_SRC/tentura`) was **not** touched by any step below.

**One-time bootstrap** (done by the overseer directly, not a Cursor worker — pure environment setup, zero code risk, nothing here is plan-unit work):
- Copied `.env` from the primary worktree (shared JWT keypair / QA knobs needed to talk to the already-running shared infra).
- Appended `COMPOSE_PROJECT_NAME=tentura` to this worktree's `.env` only. Rationale: `compose.yaml` uses `include: [compose.dev.yaml]`, so a bare `docker compose` picks up both files with no `-f` flags needed; but the default project name is the invoking directory's basename, which is `tentura` for the primary worktree and would otherwise be `work-activity-redesign` here — a mismatch that would make `docker compose run`/`up` from this worktree try to create competing `hasura`/`postgres`/`meritrank` containers (whose `container_name` is hardcoded, so a real conflict, not silent duplication). Pinning the project name makes this worktree join the same shared project.
- `flutter pub get` (client), `dart pub get` (server, tentura_lints) — pub workspace resolves once for all three packages.
- `flutter gen-l10n` (client).
- `dart run build_runner build -d` in `packages/client` (6442 outputs, 91s, exit 0, no new warnings) and `packages/server` (2523 outputs, 45s, exit 0). Fresh worktree checkouts have none of the gitignored `*.g.dart`/`*.gr.dart`/`*.config.dart` output, so this is required before anything compiles.
  - Server build_runner emitted a **pre-existing** DI warning, unrelated to this plan: `[CoordinationCase]`/`[EvaluationCase] depends on unregistered type [AttentionSystemSettlementPort]`. Not touched; not caused by this work.
- Started the local API server in this worktree: `./scripts/run-server-local.sh` (background, port 2080, confirmed listening).
- Applied Hasura metadata against the shared instance: `./scripts/hasura_apply_metadata.sh` → `is_consistent: true`.

## UNIT 00 — complete — 2026-09-13

Run directly by the overseer (not a Cursor worker): pure environment verification, no code changes, no ambiguity to resolve — delegating it would have cost a worker turn to re-discover the same facts with no risk reduction. UNIT 01 onward goes through fresh Cursor `composer-2.5` workers per the skill contract.

COMMITS: none (no code touched)

TESTS:
- `cd packages/server && dart test -t pg -j 1 test/data/repository/attention_repository_pg_test.dart` → **17/17 passed** (pg preflight: Postgres reachable, proves `-t pg` isn't silently skipping).
- `./scripts/check-custom-lints.sh packages/client` → `32 (baseline: 32)` — OK.
- `./scripts/check-custom-lints.sh packages/server` → `0 (baseline: 0)` — OK.
- Schema-fetch preflight: `COMPOSE_PROJECT_NAME=tentura docker compose run --rm schema_fetcher` (joined the shared `tentura` project; did not restart `hasura`/`postgres`/`meritrank`) → `git diff --stat packages/client/lib/data/gql/schema.graphql` is **empty**. Today's schema round-trips byte-for-byte.

FILES: this journal (new).

FINDINGS:
- Flutter 3.47.0 / Dart 3.13.0 (stable) locally — AGENTS.md's "3.44" note is for the Cursor Cloud snapshot only, not this machine.
- `compose.yaml`'s `include:` directive means no `-f` flags are ever needed for compose commands, in either worktree — only `COMPOSE_PROJECT_NAME` needs pinning here.
- See "Execution environment" above for the worktree/bootstrap deviation from the plan's assumed baseline.

DECISIONS:
- Isolated worktree instead of the primary checkout (safety; see above). All subsequent units operate in `/tmp/claude-1000/-home-vader-MY-SRC-tentura/4f632d59-f33a-4bba-bb53-0f45eca8975d/scratchpad/work-activity-redesign`, branch `work-activity-redesign`.
- UNIT 00 executed by the overseer directly rather than a Cursor worker (rationale above).

REMAINING: none. Proceed to UNIT 01.

## UNIT 01 — complete — 2026-09-13

COMMITS:
- `c37f34186` feat(server): add the responsibility scope function
- `aa1f15b64` test(server): cover responsibility scope base membership

TESTS:
- `cd packages/server && dart test -t pg -j 1 test/data/repository/responsibility_scope_pg_test.dart` → **8/8 passed**
- `./scripts/check-custom-lints.sh packages/server` → `0 (baseline: 0)` — OK

FILES:
- `packages/server/lib/data/database/migration/m0168.dart` (new)
- `packages/server/lib/data/database/migration/_migrations.dart` (edit)
- `packages/server/test/data/repository/responsibility_scope_pg_test.dart` (new)

FINDINGS: none

DECISIONS: none

REMAINING: none. Proceed to UNIT 02.

**Manager verdict: ACCEPTED.** Independently re-ran `dart test -t pg -j 1 test/data/repository/responsibility_scope_pg_test.dart` (8/8 passed) and `./scripts/check-custom-lints.sh packages/server` (0, baseline 0). Read both commits: `m0168.dart` matches §2.2's base-set definition verbatim (authored non-deleted ∪ active-help-offer non-deleted beacon), same style as `m0117.dart` (STABLE SECURITY INVOKER, search_path pinned). Test suite covers all 8 plan-listed membership cases using the established `DisposablePgTarget` pattern (already used by 5+ other pg test files, not invented). Commits are properly split (migration+registration, then tests, then journal). Nothing outside the Owns list touched. No leaked worker processes found.

## UNIT 02 — complete — 2026-09-13

COMMITS:
- `136479ca2` feat(server): add attention surface model and port contracts
- `d88d79225` feat(server): scope attention reads by surface
- `a83ffbbe6` test(server): cover attention surface reads and mark-all

TESTS:
- `cd packages/server && dart run build_runner build -d` → exit 0
- `cd packages/server && dart test -t pg -j 1 test/data/repository/attention_surface_pg_test.dart test/data/repository/attention_repository_pg_test.dart` → **28/28 passed** (11 surface + 17 existing repository)
- `cd packages/server && dart test test/api/controllers/graphql/attention_graphql_test.dart test/api/controllers/graphql/query_attention_payload_test.dart` → **15/15 passed**
- `./scripts/check-custom-lints.sh packages/server` → `0 (baseline: 0)` — OK

FILES:
- `packages/server/lib/domain/attention/attention_models.dart`
- `packages/server/lib/domain/port/attention_query_port.dart`
- `packages/server/lib/domain/port/attention_ack_port.dart`
- `packages/server/lib/data/repository/attention_repository.dart`
- `packages/server/lib/api/controllers/graphql/custom_types.dart`
- `packages/server/lib/api/controllers/graphql/query/query_attention.dart`
- `packages/server/lib/api/controllers/graphql/mutation/mutation_attention.dart`
- `packages/server/test/api/controllers/graphql/attention_graphql_test.dart`
- `packages/server/test/api/controllers/graphql/query_attention_payload_test.dart`
- `packages/server/test/domain/attention/legacy_canonical_compat_fixture_test.dart`
- `packages/server/test/data/repository/attention_surface_pg_test.dart` (new)

FINDINGS:
- Foreign-beacon obligation/pg fixtures need a read path (e.g. `beacon_forward_edge`) so receipts pass `visible_attention_receipts` before surface is asserted.
- `attention_models.freezed.dart` / `di.config.dart` are gitignored in this worktree; run `build_runner` after checkout.

DECISIONS: none

REMAINING: none. Proceed to UNIT 03.

## Ordered unit checklist

| Unit | Status |
|---|---|
| 00 | complete (overseer, this entry) |
| 01 | complete (accepted) |
| 02 | complete (this entry) |
| 03 | pending |
| 04 | pending |
| 05 | pending |
| 06 | pending |
| 07 | pending |
| 08 | pending |
| 09 | pending |
| 10 | pending |
| 11 | pending |
| 12 | pending |
| 13 | pending |
| 14 | pending |
| 15 | pending |
| 16 | pending |
| 17 | pending |
| 18 | pending |
| 19 | pending |
| 20 | pending |
| 21 | pending |
| 22 | pending |

## Unresolved decisions and blockers

None yet.
