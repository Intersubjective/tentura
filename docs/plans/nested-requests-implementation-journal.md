# Nested requests and General-only discussions — implementation journal

Objective: implement `docs/plans/nested-requests-implementation-plan.md` (revision 2)
end to end, task by task, per the plan's execution contract (§1) and ordered work
packets (§7). Architecture source: `docs/plans/nested-requests-architecture.md`.

Orchestrator: Claude Code overseer skill, driving fresh `cursor-agent --model composer-2.5`
workers, one at a time, no `--resume`/`--continue`.

## Repository state at orchestration start

- Repository: `/home/vader/MY_SRC/tentura`
- Branch: `main`
- Starting HEAD: `104786666 fix(client): ignore EvaluationCubit emits after dispose` (2026-09-06 13:57:28 +0200)
- Latest migration at plan baseline: `m0153`. Confirmed still latest at orchestration start.
- `cursor-agent` version `2026.09.02-c22c1a3`, logged in, `composer-2.5` (non-fast) confirmed available via `--list-models`.
- Local infra confirmed running: `postgres` (5432, healthy), `hasura`, `meritrank`, `minio`, `pgadmin` (docker compose).
- Postgres admin credentials available via root `.env` (`POSTGRES_HOST=127.0.0.1`, `POSTGRES_PORT=5432`, `POSTGRES_USERNAME=postgres`, password present, not logged). `packages/server/.env` was empty/absent of POSTGRES_* keys — workers must load root `.env` or export vars explicitly per §8's representative invocation.

### Pre-existing worktree changes at orchestration start (NOT owned by this plan; preserve, do not stash/reset/commit)

```
 M docs/README.md
?? CLAUDE.local.md
?? dart-defines
?? docs/plans/algorithm-invariant-suites-plan.md
?? docs/plans/availability-request-receptiveness-architecture.md
?? docs/plans/availability-request-receptiveness-implementation-plan.md
?? docs/plans/availability-review-codex.md
?? docs/plans/availability-review-grok46.md
?? docs/plans/availability-review-kimik3.md
?? docs/plans/graph-navigation-implementation-guide.md
?? docs/plans/graph-navigation-rework-plan.md
?? docs/plans/issue-100-people-graph-person-context-implementation-plan.md
?? docs/plans/issue-110-forward-explicit-architecture.md
?? docs/plans/issue-110-forward-explicit-implementation-plan.md
?? docs/plans/issue-115-reply-to-message-implementation-journal.md
?? docs/plans/issue-115-reply-to-message-plan.md
?? docs/plans/mention-without-handle-plan.md
?? docs/plans/mention-without-handle-review-sol.md
?? docs/plans/nested-requests-architecture.md
?? docs/plans/nested-requests-implementation-plan.md   (now also this journal, added by orchestration)
?? docs/plans/post-request-evaluation-detail-sheet-implementation-journal.md
?? docs/plans/post-request-evaluation-detail-sheet-plan.md
?? docs/plans/received-reviews-trust-changes-plan.md
?? docs/plans/request-threads-architecture.md
?? docs/plans/request-threads-implementation-plan.md
?? docs/plans/subjective-help-tag-evidence-architecture.md
?? docs/plans/subjective-help-tag-evidence-implementation-plan.md
?? graph-ego-neighbors-layout-issue.md
?? key.fb
?? out.key
?? product_testing_compact_buglist.md
?? product_testing_detailed_report.md
?? reports/
?? tg_style_research.md
```

Workers must stage/commit only task-owned paths (new/changed files each task names).
Never `git add -A`, never touch the files above except `docs/plans/nested-requests-*`
which this plan/orchestration owns.

## User-approved run parameters (2026-09-06)

- Run continuously through all 16 tasks (00–15) without per-task check-in; only stop
  for genuine blockers or plan/live-code contradictions requiring a product decision.
- Task 09 (irreversible-shaped legacy cleanup migration): follow the plan exactly as
  written — disposable/uniquely-named test databases only, migration-upgrade fixture,
  backup/restore rehearsal documented but not executed against real data, no production
  activation. No extra manual-hold gate beyond the plan's own acceptance criteria.

## Ordered work manifest (from plan §7, dependencies as stated)

| # | Task | Depends on | Status |
|---|---|---|---|
| 00 | Inventory, journal, and fixture harness | none | complete |
| 01 | Pure contracts and policies | 00 | pending |
| 02 | Additive hierarchy storage and repository adapter | 01 | pending |
| 03 | Authorization, SQL/Hasura parity, and mutation locking | 02 | pending |
| 04 | Shared normal creation and atomic child commands | 03 | pending |
| 05 | Lifecycle producers and retained status audience | 04 | pending |
| 06 | Durable hierarchy delivery worker | 05 | pending |
| 07 | Enforce General-only public product | 06 | pending |
| 08 | Safe request deletion and account erasure | 07 | pending |
| 09 | Scoped legacy cleanup migration | 08 | pending |
| 10 | V2 hierarchy schema and generated client transport | 09 | pending |
| 11 | Extend existing composer/save flow | 10 | pending |
| 12 | Child request surface, General host, and safe navigation | 11 | pending |
| 13 | Typed notices and promoted-source footer | 12 | pending |
| 14 | Realtime producers and convergence | 13 | pending |
| 15 | Whole-product regression and release documentation | 14 | pending |

Each task may be split into sub-units by the manager if too large for one worker
turn; splits are recorded here when they happen, preserving dependency order.

## Applicable acceptance / verification commands

See plan §8 in full for the authoritative commands. Summary:

- Per-task focused tests as named in each task's Acceptance section.
- PG tests: uniquely named disposable DB per run, `SELECT current_database()`
  proof, migrations applied, `dart test -t pg -j 1`, serial execution.
- Repo-root gates before declaring the whole plan complete:
  `packages/tentura_lints` tests, `scripts/check-custom-lints.sh` (client+server),
  `packages/server` `dart test --exclude-tags pg`, `packages/client` `flutter test`,
  `scripts/check-user-facing-terminology.sh`, `git diff --check`.
- Web artifact + multiclient realtime gates only late (Task 14/15).

## Decisions / blockers log

(none yet)

## Task checkpoints

### Task 00 — not started

### Task 00 — in progress (Cursor CLI worker, 2026-09-06)

**Owned paths:** `docs/plans/nested-requests-boundary-inventory.json`,
`packages/server/test/support/beacon_hierarchy_fixture.dart`,
`packages/server/test/support/beacon_hierarchy_fixture_pg_test.dart`,
`docs/plans/nested-requests-implementation-journal.md` (append only).

**PG environment (no secrets logged):**
- Load: `export $(grep -E '^POSTGRES_' /home/vader/MY_SRC/tentura/.env | xargs)`
- Vars used: `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_USERNAME`, `POSTGRES_PASSWORD`, `POSTGRES_ADMIN_DBNAME` (defaults `postgres`), optional `TENTURA_BEACON_HIERARCHY_PG_TEST_DB`
- Create DB (docker, no local `createdb`): `docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres psql -U "$POSTGRES_USERNAME" -d postgres -c "CREATE DATABASE \"$POSTGRES_DBNAME\""`
- Verify: `docker exec ... psql ... -d "$POSTGRES_DBNAME" -t -A -c 'SELECT current_database()'`
- Migrations in tests: `migrateDbSchema(connection)` after `SET check_function_bodies = false` (same as existing PG tests). Plan §8 `run_migrations_once.dart` attempted on disposable DB but failed mid-migration (`mr_node_score` missing on fresh DB before MeritRank extension wiring); fixture/tests use in-test `migrateDbSchema` like `beacon_threads_repository_pg_test.dart`.
- Tests: `cd packages/server && dart test test/support/beacon_hierarchy_fixture_pg_test.dart -t pg -j 1`
- Cleanup: `docker exec ... psql ... -c 'DROP DATABASE IF EXISTS "<name>" WITH (FORCE)'`

**Baseline captured:**
- Latest migration: `m0153` (`S/data/database/migration/_migrations.dart`)
- Migration registration: `migrateDbSchema` / `Database(PostgreSQLGateway(connection)).upgrade(InMemory([m0001..m0153]))`; one-off: `packages/server/bin/utils/run_migrations_once.dart`
- Schema fetch: `docker compose run --rm schema_fetcher` (plan §8)
- Custom lint: server total 0 (baseline 0); client total 32 (baseline 32, 22 `no_raw_edge_insets`, 10 `no_raw_border_radius`)

**transactional_attention_producer_inventory_test.dart review:**
- Static architecture test ensuring domain use cases record attention through `TransactionalAttentionCase.runAction`, not legacy `notify*` methods or detached `unawaited`.
- `migratedProducers` map covers coordination-item cases (including retired ask/promise/blocker) and core flows; `newProducerTokens` covers `requestStatusChanged` in beacon/evaluation/coordination/expiry paths.
- Counts `requestStatusChanged` per file (beacon_case:2, coordination:1, evaluation:4, attention_expiry_sweep:1) and asserts `TaskWorkerCase` calls `_attentionExpirySweep!.runDue`.
- **Task 05 extension:** add hierarchy lifecycle intent producer (`beaconHierarchyStatusChanged` or reuse with distinct occurrence keys) alongside `requestStatusChanged`; extend `newProducerTokens` / `expectedIntentSites` when `BeaconLifecycleEffectsCase` lands; keep retired coordination producers listed until Task 07 removes cases.

**Manifest:** `docs/plans/nested-requests-boundary-inventory.json` — 193 entries covering §5.2 surfaces, §4.3 producers, `canReadContent` callers, 59 `public.user(id)` FK rows from live `pg_constraint` on disposable migrated DB, routes, notification destinations, mutation-lock candidates.

### Task 00 — complete (Cursor CLI worker, 2026-09-06)
