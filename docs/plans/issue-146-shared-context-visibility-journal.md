# Issue #146 — shared-context visibility — implementation journal

**Objective:** Implement shared-context visibility per architecture D1–D8 (issue #146).

**Plan source:** [`issue-146-shared-context-visibility-implementation-plan.md`](issue-146-shared-context-visibility-implementation-plan.md) (rev 2).

**Architecture (binding):** [`issue-146-shared-context-visibility-architecture.md`](issue-146-shared-context-visibility-architecture.md) (rev 4).

| Field | Value |
|---|---|
| Repository | `/home/vader/MY_SRC/tentura` |
| Branch | `issue-146-shared-context-visibility` |
| HEAD (T00 baseline) | `e6b858a9e365d8b5585544ee899fc1b758d3bdf7` |

---

## Pre-existing dirty worktree (T00; do not touch unless task-owned)

```
 M .serena/project.yml
 M packages/client/test/app/router/home_tab_branch_routing_test.dart
 M packages/client/test/features/constellation/constellation_body_test.dart
?? CLAUDE.local.md
?? dart-defines
?? docs/plans/algorithm-invariant-suites-plan.md
?? docs/plans/availability-request-receptiveness-architecture.md
?? docs/plans/availability-request-receptiveness-implementation-plan.md
?? docs/plans/availability-review-codex.md
?? docs/plans/availability-review-grok46.md
?? docs/plans/availability-review-kimik3.md
?? docs/plans/constellation-ui-remediation-plan.md
?? docs/plans/graph-navigation-implementation-guide.md
?? docs/plans/graph-navigation-rework-plan.md
?? docs/plans/issue-100-people-graph-person-context-implementation-plan.md
?? docs/plans/issue-110-forward-explicit-architecture.md
?? docs/plans/issue-110-forward-explicit-implementation-plan.md
?? docs/plans/issue-115-reply-to-message-implementation-journal.md
?? docs/plans/issue-115-reply-to-message-plan.md
?? docs/plans/issue-130-first-run-orientation-plan.md
?? docs/plans/mention-without-handle-plan.md
?? docs/plans/mention-without-handle-review-sol.md
?? docs/plans/nested-requests-architecture.md
?? docs/plans/nested-requests-cleanup-fk-manifest.json
?? docs/plans/nested-requests-implementation-plan.md
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
?? tg_style_research.md
```

---

## Unit checklist

| Status | Task |
|---|---|
| done | **T00** preflight (this unit) |
| done (`335402368`) | **T01** beaconChildren auth |
| pending | **T02** parent reference auth |
| pending | **T03** close involvement leaks |
| pending | **T04** client copy + no involvement fetch |
| pending | **T05** access enums + pure policy |
| pending | **T06** SQL member view/reasons/level |
| pending | **T07** expose access level+reasons |
| pending | **T08+T09** ancestor closure + widened content read (one migration, one commit) |
| pending | **T10** unify hierarchy predicate, drop linked-detail |
| pending | **T11** bond SQL + server consumers |
| pending | **T12** personSharedContexts query |
| pending | **T13** client bond-aware profile |
| pending | **T14** observer reason banner |
| pending | **T15** docs |
| pending | **T16** release gate |

---

## Migration number mapping (T00 step 2)

| Check | Result |
|---|---|
| Last entry in `MIG/_migrations.dart` `_allMigrations` | **`m0169`** (matches plan) |
| `m0170`–`m0173` on disk | **Not present** — free for T06 / T08+T09 / T10 / T11 as planned |

**Mechanical mapping for later units (if plan ids unchanged):**

| Plan slot | Migration id |
|---|---|
| T06 | `m0170` |
| T08+T09 (single migration) | `m0171` |
| T10 | `m0172` |
| T11 | `m0173` |

---

## T00 — Preflight symbol check (step 2)

All listed symbols/files present at HEAD:

| Location | Symbols |
|---|---|
| `S/data/repository/beacon_hierarchy_repository.dart` | `listChildren`, `loadParentReference`, `loadCapabilities`, `_loadAdmissionFacts` |
| `S/api/controllers/graphql/query/query_beacon_hierarchy.dart` | `QueryBeaconHierarchy`, `beaconChildren`, `beaconParentReference` |
| `S/domain/use_case/coordination_case.dart` | `helpOffersWithCoordination` |
| `S/domain/use_case/beacon_fact_card_case.dart` | `BeaconFactCardCase.list` |
| `S/domain/beacon_visibility.dart` | `BeaconVisibility.canReadLinkedDetail` |

---

## T00 — Baseline test results (step 4)

**Infra:** Postgres listening on `127.0.0.1:5432` at T00 time (no `docker compose up` required).

### Server unit (`--exclude-tags pg`)

```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test --exclude-tags pg \
  test/domain/beacon_visibility_test.dart \
  test/domain/beacon_hierarchy_policy_test.dart
```

| Result | Count |
|---|---|
| Passed | **47** |
| Failed | **0** |
| Skipped | **0** |
| Exit | **0** — `All tests passed!` |

### Server Postgres (`-t pg`) — plan single invocation (all three paths)

```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test -t pg \
  test/data/repository/beacon_hierarchy_visibility_pg_test.dart \
  test/data/repository/beacon_access_sql_parity_test.dart \
  test/api/beacon_hierarchy_hasura_parity_test.dart
```

| Result | Count |
|---|---|
| Passed | **14** |
| Failed | **2** |
| Skipped | **0** |
| Exit | **1** — `Some tests failed.` |

Failures (pre-existing baseline; not fixed in T00):

- `test/data/repository/beacon_hierarchy_visibility_pg_test.dart`: `(setUpAll)` — `Instance of 'RaceCondition'` during `migrateDbSchema` (parallel disposable-DB lifecycle).
- Same file: `(tearDownAll)` — `LateInitializationError: Local 'fixture' has not been initialized.` (cascade from failed setUpAll).

Other files in that combined run contributed passing cases (`beacon_access_sql_parity_test.dart`, `beacon_hierarchy_hasura_parity_test.dart`).

### Server Postgres (`-t pg`) — per-file serial re-runs (diagnostic; same wrapper)

Recorded because the combined run flaked; serial runs establish whether suites are green in isolation:

| File | Passed | Failed | Skipped | Exit |
|---|---|---|---|---|
| `test/data/repository/beacon_hierarchy_visibility_pg_test.dart` | 14 | 0 | 0 | 0 |
| `test/data/repository/beacon_access_sql_parity_test.dart` | 12 | 0 | 0 | 0 |
| `test/api/beacon_hierarchy_hasura_parity_test.dart` | 2 | 0 | 0 | 0 |

---

## T00 — Task log

- **Task:** T00 — Preflight and journal
- **Files changed:** `docs/plans/issue-146-shared-context-visibility-journal.md` (created)
- **Commands:** branch check; symbol grep; migration tail read; baseline suites above
- **Deviations:** Combined `-t pg` three-file run hit migration `RaceCondition` once; per-file serial baselines all pass
- **Commit:** (not created in scout pass — implementer commit: `docs: start issue-146 implementation journal`)
- **Next:** **T01**

---

## T01 — Scout (read-only)

- **UNIT_BASE:** `d0e34d442a36de8b8903ba5e6439fe3acdbd1c17` (matches `HEAD` at scout time)
- **Task:** T01 — `beaconChildren` / `listChildren` parent gate + per-child SQL filter

### Live code vs plan assumptions

| Topic | Plan | Live @ UNIT_BASE |
|---|---|---|
| `listChildren` uses `viewerId` | Must gate on viewer | Param exists; **never referenced** in method body (bug confirmed) |
| GraphQL `beaconChildren` | Implied server gate | `query_beacon_hierarchy.dart` passes `getCredentials(args).sub` into `listChildren` — fix belongs in repository only |
| Empty unauthorized page | `const BeaconHierarchyPage(summaries: [])` | Entity at `R/domain/entity/beacon_hierarchy_page.dart` — `summaries` required, `nextCursor` optional (default null) ✓ |
| SQL predicates | `beacon_can_read_linked_detail`, `block_hides`, `beacon_effective_admission` | All defined in migrations **`m0155`** (`beacon_can_read_linked_detail`, `beacon_effective_admission`) and **`m0135`** (`block_hides`); used elsewhere (e.g. `BeaconAccessRepository._callPredicate`) ✓ |
| Test file | `beacon_hierarchy_repository_pg_test.dart` or new `beacon_children_authorization_pg_test.dart` | **`beacon_hierarchy_repository_pg_test.dart` exists** with pagination/group tests using `aliceId`/`bobId` only (no auth regression tests yet). **`beacon_hierarchy_visibility_pg_test.dart`** exercises predicates + `loadParentReference` but **not** `listChildren` |
| Fixture topology | A→B→C, A→D | `BeaconHierarchyFixture` + `BeaconHierarchyTopology` in `ST/support/beacon_hierarchy_fixture.dart`; tree via `seedPublishedHierarchyTree` in `beacon_hierarchy_pg_helpers.dart` ✓ |
| Bind params | Viewer index `$3` / `$5` with cursor; compute via `variables.length + 1` | Current query: `$1` parent, `$2` limit, optional `$3`/`$4` cursor — viewer must be appended **after** cursor vars when present |
| Resolver change | Not listed | **None required** — authorization entirely in `listChildren` |

### Architecture vs implementation plan (follow the plan in phase 0)

- **§7.4 (rev 4)** names `BeaconRights.canListChildren` on the parent and **`beacon_can_read_content(child, viewer)`** per row, with deleted rows under **`canReadTombstone`**. **T01 explicitly overrides that for phase 0:** parent gate + non-deleted child filter use **`beacon_can_read_linked_detail`**; deleted-group branch uses **`beacon_effective_admission(parent, viewer)`** when `b.status = 2`, not `beacon_can_read_tombstone(child, viewer)`. T09/T10 migrate to widened content + drop linked-detail (plan §T08–T10).
- **§3.3/2** says resolver/`listChildren` “never use `viewerId`” — **half true:** resolver passes it; repository ignores it.
- **§3.2 table** says child list relies on “client asks capabilities first” — capabilities are separate; **unauthorized listing is still a server bug** regardless of client.

### Implementer brief (Opus)

1. **Single commit** (`fix(server): authorize beaconChildren by viewer`).
2. At start of `listChildren`, `SELECT public.beacon_can_read_linked_detail($1,$2)`; if false, return empty page (no throw).
3. Append `Variable<String>(viewerId)` to the existing `variables` list; inject `$V` into `WHERE` exactly as plan step 3 (`block_hides` on child owner; linked_detail for non-deleted; parent `beacon_effective_admission` for status 2). Status `2` = deleted per §0.4.
4. Reuse SQL call pattern from `BeaconAccessRepository` (`customSelect` + `read<bool>('allowed')`). T02 will add `_predicate` helper in the same file — optional duplicate for T01, not required.
5. **Pg tests** (`@Tags(['pg'])`): copy disposable-DB setup from `beacon_hierarchy_repository_pg_test.dart` or `beacon_hierarchy_visibility_pg_test.dart` (`BeaconHierarchyDisposablePgTarget`, `seedFullTopology`, `seedPublishedHierarchyTree`, `_reseedParticipantsAfterHierarchyTree` pattern from visibility test).
   - `frankId` without participant on A → `listChildren` on A `active` → empty summaries.
   - `aliceId` on A `active` → contains `beaconB` and `beaconD` (not `beaconC` — not direct child).
   - `carolId` admitted to A + `user_block` hiding D's owner (`eveId`) → page must not include `beaconD` (mirror block tests in visibility pg file).
   - Deleted child under A: insert or use helper with `BeaconStatus.deleted`; `aliceId` + `BeaconHierarchyChildGroup.deleted` sees tombstone; `frankId` stranger sees empty deleted group.
6. **Red test meaningful:** **yes** — today `frankId` would receive published children for parent A; new stranger test fails before repository change, passes after.
7. **Regression:** existing `beacon_hierarchy_repository_pg_test.dart` pagination test should stay green (uses authorized `aliceId`). Run visibility + hasura parity pg suites serially if combined run flakes (T00 journal).

### TEST_CMD (smallest first, after implementation)

```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test -t pg test/data/repository/beacon_children_authorization_pg_test.dart
# — or the path chosen if tests live in beacon_hierarchy_repository_pg_test.dart

cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test -t pg test/data/repository/beacon_hierarchy_repository_pg_test.dart

cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test -t pg test/data/repository/beacon_hierarchy_visibility_pg_test.dart

cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test -t pg test/api/beacon_hierarchy_hasura_parity_test.dart

./scripts/run_with_test_cleanup.sh --timeout 10m -- ./scripts/check-custom-lints.sh packages/server
```

### RISKS noted for implementer

- Combined three-file `-t pg` run flaked once in T00 (`RaceCondition` in `migrateDbSchema`); prefer **one dart test invocation per file**.
- Deleted-group SQL branch ≠ `beacon_can_read_tombstone` — **by plan**, not oversight.
- Pagination/`LIMIT $2` applies **after** filters; if `first+1` rows shrink, cursor behavior should remain correct but worth sanity-checking in tests if adding many hidden children.

- **Next (implementer):** land T01 commit, journal task log, mark T01 done in checklist.

---

## T01 — inner (implementer)

- **Commit:** `335402368` `fix(server): authorize beaconChildren by viewer` (body `issue-146 T01`)
- **Files:** `packages/server/lib/data/repository/beacon_hierarchy_repository.dart` (`listChildren` only); new `packages/server/test/data/repository/beacon_children_authorization_pg_test.dart`
- **Change:** parent gate `beacon_can_read_linked_detail(parent, viewer)` → empty page (no throw); viewer bound as `$${variables.length}` after optional cursor vars; row filter `NOT block_hides(child_owner, viewer)` + linked_detail for non-deleted / parent `beacon_effective_admission` for `status = 2`, inserted after status filter, before cursor SQL.
- **Tests (each file its own `dart test -t pg` invocation, wrapped):**

| File | RED (pre-fix) | GREEN |
|---|---|---|
| `beacon_children_authorization_pg_test.dart` (new) | +0 −4 | +4 −0 |
| `beacon_hierarchy_repository_pg_test.dart` | — | +7 −0 |
| `beacon_hierarchy_visibility_pg_test.dart` | — | +14 −0 |
| `api/beacon_hierarchy_hasura_parity_test.dart` | — | +2 −0 |
| `check-custom-lints.sh packages/server` | — | total 0 (baseline 0) OK |

- **Findings:**
  - `frankId` is **not** a stranger to A in the fixture: his help offer on A makes `beacon_can_read_linked_detail(A, frank)` true. Stranger case uses **`daveId`** (owner of C only; no admission/offer/forward on A or B), with an in-test precondition assert.
  - "Reads A but not admitted" is reachable: **bob** (admitted to child B → linked_detail on A via child branch) and **frank** (help offer). Tests assert bob sees only B (not sibling D) in `active` and neither bob nor frank sees the deleted tombstone; alice (admitted) does.
  - Each red failure is genuine behavior (preconditions pass); the alice-positive assertion alone would already pass pre-fix, so it's paired with the bob assertion in the same test.
  - No flake this run with per-file invocations.
- **Next:** T02
