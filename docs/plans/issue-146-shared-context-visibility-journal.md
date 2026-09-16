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
| done (`1f1ce43bc`) | **T02** parent reference auth |
| done (86f32279f) | **T03** close involvement leaks |
| done (a0ff4912c) | **T04** client copy + no involvement fetch |
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

---

## T01 — verify (read-only)

- **Range reviewed:** `d0e34d442a36de8b8903ba5e6439fe3acdbd1c17..HEAD` (`335402368`, `48b7fa789`); worktree dirty paths unchanged vs T00 pre-existing list (no T01 edits there).
- **Commits:** `335402368` = repository + new pg test only (2 files). `48b7fa789` = journal only. Focused ✓
- **Scope:** `listChildren` hunk only in `beacon_hierarchy_repository.dart`; `loadParentReference` untouched ✓. No changes to existing pg test files (only new `beacon_children_authorization_pg_test.dart`) ✓. No deleted/loosened assertions in committed range ✓
- **Plan SQL (T01 §steps 1–3):** parent preflight `beacon_can_read_linked_detail($1,$2)` → empty `BeaconHierarchyPage`; viewer appended after cursor vars with `$${variables.length}`; WHERE adds `NOT block_hides(b.user_id,$V)`, `(status <> 2 AND linked_detail(child)) OR (status = 2 AND effective_admission($1,$V))` after status `IN` and before cursor clause ✓
- **Stranger test:** uses `daveId` with explicit `linked_detail(A,dave)=false` precondition — correct given fixture help offer on A for `frankId` (not rationalization) ✓
- **Independent TEST_CMD re-run (2026-09-15 verify):**

| Command | Passed | Failed | Skipped | Exit |
|---|---|---|---|---|
| `beacon_children_authorization_pg_test.dart` | 4 | 0 | 0 | 0 |
| `beacon_hierarchy_repository_pg_test.dart` | 7 | 0 | 0 | 0 |
| `beacon_hierarchy_visibility_pg_test.dart` | 14 | 0 | 0 | 0 |
| `beacon_hierarchy_hasura_parity_test.dart` | 2 | 0 | 0 | 0 |
| `check-custom-lints.sh packages/server` | — | — | — | 0 (`tentura_lints` total 0, baseline 0 OK) |

- **Verdict:** **pass** — T01 “Done when” satisfied; ready for T02.

---

## T02 — Scout (read-only)

- **UNIT_BASE:** `ef63fbc53c2c7dd81bc47dc84c0f92ffcaa01a05` (= `HEAD` at scout time)
- **Task:** T02 — `beaconParentReference` / `loadParentReference` authorize child + parent

### Live code vs plan

| Topic | Plan | Live @ UNIT_BASE |
|---|---|---|
| `loadParentReference` child gate | `beacon_can_read_content(child, viewer)` → `none` | **Missing** — loads parent id first, never checks child read |
| Parent gate | `beacon_can_read_linked_detail(parent, viewer)` → `available` with id+title | Uses `_loadAdmissionFacts` + `BeaconHierarchyPolicy.isAdmittedToImmediateParent` (effective admission on **parent only**) → **bob on B gets `unavailable`** (#146 bug) |
| Deleted parent | `unavailable` | Policy path: `resolveParentReference` maps deleted → `unavailable` ✓ (new path must keep `parent.status == deleted` → `unavailable` before linked_detail) |
| SQL predicates | `(p_beacon_id text, p_viewer_id text) RETURNS boolean` | **`m0169`** `beacon_can_read_content`; **`m0155`** `beacon_can_read_linked_detail` (delegates to content + one-edge child/parent admission branches) |
| `_predicate` helper | Mirror `BeaconAccessRepository._callPredicate` | `BeaconAccessRepository` uses `getSingle()` + `read<bool>('allowed')`; `listChildren` inlines linked_detail (T01) — T02 adds repo-private `_predicate(fn, beaconId, viewerId)` per plan |
| `loadImmediateParentBeaconId` | Plan name | **Exists** @ L278 — `SELECT parent_beacon_id FROM beacon WHERE id = $1` |
| `_loadBeaconRow` | Plan name | **Exists** @ L321 — `id, user_id, title, status` |
| `BeaconParentReference` | `none` / `unavailable` / `available`+fields | `lib/domain/entity/beacon_parent_reference.dart` — static `none`, `unavailable`; enum `BeaconParentReferenceState` |
| Constructor / guard injection | No `BeaconAccessGuard` in repository | `BeaconHierarchyRepository(this._database)` only — auth via SQL predicates ✓ |
| Policy cleanup | Leave `resolveParentReference` / `isAdmittedToImmediateParent` | Still used only from `loadParentReference` today — after T02, **unused in repo** but do not delete (T10) |

### Fixture notes (A→B→C, A→D)

- Admissions: **alice→A**, **bob→B**, **carol→C** (`beacon_hierarchy_fixture.dart` `_seedAdmissions`).
- **Bob** is the #146 scenario-1 viewer: `beacon_effective_admission(A, bob)=false`, `beacon_can_read_content(B, bob)=true`, `beacon_can_read_linked_detail(A, bob)=true` (child-admission branch in m0155).
- **Stranger to B:** reuse **`daveId`** (T01 pattern) — no content/linked_detail on B or A; parent exists on B.
- **Reads B, no path to A:** insert `beacon_forward_edge` on **B** with `recipient_id=daveId` (pattern: fixture `_seedForwardToAliceForB` / `issue_145_stale_child_invite_pg_test.dart` INSERT). Preconditions: `beacon_can_read_content(B, dave)=true`, `beacon_can_read_linked_detail(A, dave)=false`.
- Parent title for bob assertion: seeded **`Request A`** for `beaconA`.

### Implementer brief (Opus, low effort)

1. **Commit 1 (test-first):** `fix(server): authorize both ends of the parent reference` — add `packages/server/test/data/repository/beacon_parent_reference_authorization_pg_test.dart` (`@Tags(['pg'])`), copy disposable setup from `beacon_children_authorization_pg_test.dart` (`seedTree` = `seedFullTopology` + `seedPublishedHierarchyTree` + participant re-seed). Three tests with SQL preconditions where non-obvious.
2. **Commit 2 (same commit OK):** In `beacon_hierarchy_repository.dart` only `loadParentReference` + new private `Future<bool> _predicate(String fn, String beaconId, String viewerId)` — exact body from plan §T02 step 1; use `BeaconStatus.fromSmallint(parent.status) == BeaconStatus.deleted` (status **2** per §0.4). Drop `_loadAdmissionFacts` / policy calls from `loadParentReference` only.
3. **Do not** touch `listChildren`, `beacon_hierarchy_policy.dart`, GraphQL resolvers.

### TEST_CMD

```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test -t pg test/data/repository/beacon_parent_reference_authorization_pg_test.dart

cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test -t pg test/data/repository/beacon_hierarchy_visibility_pg_test.dart

cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test -t pg test/data/repository/beacon_children_authorization_pg_test.dart

cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test -t pg test/data/repository/beacon_hierarchy_repository_pg_test.dart

cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test -t pg test/api/beacon_hierarchy_hasura_parity_test.dart

./scripts/run_with_test_cleanup.sh --timeout 10m -- ./scripts/check-custom-lints.sh packages/server
```

### RISKS

- **`beacon_hierarchy_graphql_contract_test.dart`** › `beaconParentReference: unauthorized viewer` uses **`eveId`** on child **B**; eve cannot `beacon_can_read_content(B, eve)` → T02 returns **`none`**, test expects **`unavailable`**. File is **out of T02 touch scope** — full “Done when” may fail CI until contract test is updated in a follow-up or scope exception.
- Architecture §7.4 long-term target uses `beacon_can_read_content` on **parent**; **T02 plan explicitly uses `beacon_can_read_linked_detail` on parent** — do not alias (T09/T10).
- Per-file `-t pg` only (T00 flake).

- **Next (implementer):** land T02, journal inner log, mark T02 done.

---

## T02 — inner (implementer) — BLOCKED on scope

- **No commit.** HEAD stays `ef63fbc53`. Work is left **uncommitted** in the tree (backup `/tmp/issue146-T02.patch`):
  - `packages/server/lib/data/repository/beacon_hierarchy_repository.dart`: `loadParentReference` rewritten per plan §T02 step 1; new private `_predicate` (mirror of `BeaconAccessRepository._callPredicate`). `listChildren` and policy untouched.
  - new `packages/server/test/data/repository/beacon_parent_reference_authorization_pg_test.dart` (bob → available `Request A`; dave stranger → none; dave as forward recipient of B → unavailable, with SQL preconditions).
  - `beacon_hierarchy_graphql_contract_test.dart`: eve test renamed to `viewer who cannot read the child gets no reference`, expects `none` (eve confirmed stranger to B).
- **Tests (each its own wrapped `dart test -t pg`):**

| File | RED (pre-fix) | GREEN (post-fix) |
|---|---|---|
| `beacon_parent_reference_authorization_pg_test.dart` (new) | +1 −2 (bob got `unavailable`; dave got `unavailable` not `none`; forward case already passed) | +3 −0 |
| `beacon_hierarchy_visibility_pg_test.dart` | — | +14 −0 |
| `beacon_children_authorization_pg_test.dart` | — | +4 −0 |
| `beacon_hierarchy_repository_pg_test.dart` | — | +7 −0 |
| `api/beacon_hierarchy_hasura_parity_test.dart` | — | +2 −0 |
| `api/beacon_hierarchy_graphql_contract_test.dart` | baseline +11 −0 | **+10 −1** |
| `check-custom-lints.sh packages/server` | — | total 0 (baseline 0) OK |

- **Blocker:** `beacon_hierarchy_graphql_contract_test.dart` › `beaconParentReference: admitted viewer sees the parent link` now gets `none` (was `available`). In that test `seedPublishedHierarchyTree` recreates B, which drops the fixture forward edge `FhierfwdB01` (frank→alice on B) and there is no re-seed of participants; alice is admitted to A only, so `beacon_can_read_content(B, alice)` is false and S4-09a correctly returns `none`. The brief declared this test "unaffected" and untouchable. Parent-member reads of children (contextChild) only arrive in T08+T09.
- **Needs overseer decision (one of):** (a) under plan §0 "Superseded tests", give alice a real read path to B in that test (e.g. re-seed the forward edge or admit her to B) and keep `available` — preserves the test's intent; (b) change it to expect `none` until T09 and rename; then commit `fix(server): authorize both ends of the parent reference`.

---

## T02 — inner (implementer) — resumed, done

- **Decision (overseer):** superseded-test rule (plan §0 rule 7). `beaconParentReference: admitted viewer sees the parent link` now authenticates as **bob** instead of alice; name kept; comment rewritten to the S4-09a rule (viewer must read child B; parent then gated by `beacon_can_read_linked_detail` on A). Expectation unchanged (`available`, `beaconId == beaconA`).
- **Verified bob's access holds after re-seed:** `seedPublishedHierarchyTree` DELETE+INSERT of B cascades away `PhierbobB01`, but re-inserts B with `ownerId: bobId`, so bob reads B as **owner**; he has no participant row on A. The comment therefore says "bob owns B" rather than "admitted".
- **Commit:** `1f1ce43bc` `fix(server): authorize both ends of the parent reference` (repo `loadParentReference` + `_predicate`, new `beacon_parent_reference_authorization_pg_test.dart`, contract-test eve rename + bob fix).
- **Tests (each its own wrapped `dart test -t pg`), all GREEN:**

| File | Result |
|---|---|
| `beacon_parent_reference_authorization_pg_test.dart` | +3 −0 |
| `api/beacon_hierarchy_graphql_contract_test.dart` | +11 −0 |
| `beacon_hierarchy_visibility_pg_test.dart` | +14 −0 |
| `beacon_children_authorization_pg_test.dart` | +4 −0 |
| `beacon_hierarchy_repository_pg_test.dart` | +7 −0 |
| `api/beacon_hierarchy_hasura_parity_test.dart` | +2 −0 |
| `check-custom-lints.sh packages/server` | total 0 (baseline 0) OK |

- **Note:** `BeaconHierarchyPolicy.resolveParentReference` / `isAdmittedToImmediateParent` and repo `_loadAdmissionFacts` are no longer called from `loadParentReference`; left in place per scout (cleanup is T10).
- **Next:** T03 (implementer)

---

## T03 — Scout (read-only)

- **UNIT_BASE:** `0f9f4dbb20587da5622f863cc2d1026c452dcded` (= `HEAD` at scout time)
- **Task:** T03 — close involvement leaks in content-only gates (`helpOffersWithCoordination`, `BeaconFactCardCase.list`)

### Live code vs plan

| Topic | Plan | Live @ UNIT_BASE |
|---|---|---|
| `helpOffersWithCoordination` gate | `canReadInvolvement` → `'Viewer cannot read request involvement'` | **`canReadContent`** → `'Viewer cannot read request content'` @ `coordination_case.dart` L103–107 |
| `BeaconFactCardCase.list` gate | Top-of-method `canReadContent` via injected `_guard` | **No guard** — only room-visibility filter (`_canUseRoom` / `BeaconFactCardVisibilityBits.room`) @ L145–191 |
| `BeaconFactCardCase` DI | Inject `BeaconAccessGuard`; regen `build_runner` | Constructor has facts/room/hierarchy + env/logger only; `di.config.dart` L1513–1520 has **no** `BeaconAccessGuard` param |
| `CoordinationCase` DI | Already has guard | `required BeaconAccessGuard guard` ✓ — no DI regen for coordination |
| m0124 implication | One involvement check enough | `beacon_can_read_involvement` = `beacon_can_read_content` **AND** involved-set EXISTS (author, forward sender/recipient, active help offer, steward/admitted participant) — involvement ⇒ content ✓ |
| Pure-policy analogue | Discover observer reads content, not involvement | `BeaconVisibility.canReadInvolvement` requires content then excludes discover-only path (`beacon_visibility.dart` L127–134) — unit tests should use `FakeBeaconAccessGuard(contentAllowed: true, involvementAllowed: false)` |
| Unit test files (grep) | `ST/domain/use_case/` | **`beacon_fact_card_case_test.dart`** (Fake stubs, no guard today). **`beacon_room_admission_matrix_test.dart`** — `helpOffersWithCoordination` redaction test + gate throw @ L1083 (`contentAllowed: false`). **No** dedicated `coordination_case_*` file for this gate |
| Pg regression | `beacon_hierarchy_visibility_pg_test.dart` › non-transitivity › `coordination_case helpOffersWithCoordination` | Frank admitted **parent A only** (`admitFrankToParentAOnly`); on child **B**: `canReadContent`=false, `canReadLinkedDetail`=true (L172–186). Real `BeaconAccessRepository` in harness — refusal should remain after gate swap |
| `HierarchyOnlyViewerHarness` comment | — | Still says “`canReadContent` gates” (L28–29) — stale after T03 for coordination only; file **not** in T03 edit list |

### Implementer brief (Opus, low effort)

**One commit:** `fix(server): gate help-offer list by involvement and facts by content` (plan “Done when”).

1. **Test-first (coordination):** Add a focused group (new `coordination_case_help_offers_access_gate_test.dart` or extend `beacon_room_admission_matrix_test.dart` — prefer small new file to avoid bloating matrix):
   - `FakeBeaconAccessGuard(contentAllowed: true, involvementAllowed: false)` → `helpOffersWithCoordination` throws `UnauthorizedException` with description **`Viewer cannot read request involvement`** (stub repo so gate is hit before I/O).
   - Default guard (both true) + stubbed rows → involved viewer (e.g. author `_authorId` pattern from matrix) still returns rows.
   - `involvementAllowed: false` (content irrelevant) → stranger throws same involvement message.
   - **Fix regression:** matrix test L1083 `buildSut(guard: FakeBeaconAccessGuard(contentAllowed: false))` must become **`involvementAllowed: false`** (with `contentAllowed: true` if you want to prove involvement is the gate); otherwise post-change test stays green while not exercising the new check.
2. **Production:** `coordination_case.dart` — swap gate per plan step 1 (exact exception string).
3. **Test-first (fact card):** In `beacon_fact_card_case_test.dart`:
   - Introduce `FakeBeaconAccessGuard` in `setUp` (default `contentAllowed: true`) passed into `BeaconFactCardCase` constructor.
   - New test: `contentAllowed: false` → `list` throws `'Viewer cannot read request content'` **before** public-only rows (today `denyRoomAccess` + public fact returns 1 row — that scenario stays valid when guard content true).
4. **Production:** `beacon_fact_card_case.dart` — add `required BeaconAccessGuard guard`, `_guard` field, top-of-`list` check per plan step 2; **do not** change room-visibility loop.
5. **Codegen:** `cd packages/server && dart run build_runner build -d` — updates `lib/app/di.config.dart` to pass `gh<BeaconAccessGuard>()` into `BeaconFactCardCase` (no new `@GenerateMocks` unless you choose Mockito for fact-card tests; `FakeBeaconAccessGuard` matches existing coordination tests).
6. **Pg regression (read-only file):** Run single-file `beacon_hierarchy_visibility_pg_test.dart` — group `non-transitivity — production call sites refuse hierarchy-only viewer` › `coordination_case helpOffersWithCoordination` must stay green (Frank still lacks involvement on B).

### TEST_CMD

```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test --exclude-tags pg test/domain/use_case/beacon_fact_card_case_test.dart

cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test --exclude-tags pg test/domain/use_case/beacon_room_admission_matrix_test.dart

# if new coordination gate file added, run it too:
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test --exclude-tags pg test/domain/use_case/coordination_case_help_offers_access_gate_test.dart

cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test -t pg test/data/repository/beacon_hierarchy_visibility_pg_test.dart

./scripts/run_with_test_cleanup.sh --timeout 10m -- ./scripts/check-custom-lints.sh packages/server
```

### RISKS

- **`beacon_room_admission_matrix_test.dart` L1083** — must retarget fake guard to **`involvementAllowed: false`** or CI fails silently on wrong gate.
- **Existing fact-card list tests** — all construct `BeaconFactCardCase` without guard; constructor change breaks compile until tests + `build_runner` land together.
- **Frank / hierarchy-only pg** — passes today via **content** denial; after T03 via **involvement** denial — verify SQL: `beacon_can_read_involvement(B, frank)` false (content already false). No pg file edit expected.
- **m0124 vs Dart discoverability** — SQL `beacon_can_read_content` in m0124 may not include D11 discover path; involvement leak fix for discover observers is still correct at use-case layer using guard/SQL as deployed — do not widen scope to migration changes.
- **No `BeaconFactCardCase` pg test** in non-transitivity group — content gate on facts is unit-test-only in this unit.

- **Next (implementer):** land T03 commit, journal inner log, mark T03 done.

---

## T03 — Scout (read-only)

- **UNIT_BASE:** `0f9f4dbb20587da5622f863cc2d1026c452dcded` (= `HEAD` at scout time)
- **Task:** T03 — close involvement leaks in content-only gates (`helpOffersWithCoordination`, `BeaconFactCardCase.list`)

### Live code vs plan

| Topic | Plan | Live @ UNIT_BASE |
|---|---|---|
| `helpOffersWithCoordination` gate | `canReadInvolvement` → `'Viewer cannot read request involvement'` | **`canReadContent`** → `'Viewer cannot read request content'` @ `coordination_case.dart` L103–107 |
| `BeaconFactCardCase.list` gate | Top-of-method `canReadContent` via injected `_guard` | **No guard** — only room-visibility filter (`_canUseRoom` / `BeaconFactCardVisibilityBits.room`) @ L145–191 |
| `BeaconFactCardCase` DI | Inject `BeaconAccessGuard`; regen `build_runner` | Constructor has facts/room/hierarchy + env/logger only; `di.config.dart` L1513–1520 has **no** `BeaconAccessGuard` param |
| `CoordinationCase` DI | Already has guard | `required BeaconAccessGuard guard` ✓ — no DI regen for coordination |
| m0124 implication | One involvement check enough | `beacon_can_read_involvement` = `beacon_can_read_content` **AND** involved-set EXISTS (author, forward sender/recipient, active help offer, steward/admitted participant) — involvement ⇒ content ✓ |
| Pure-policy analogue | Discover observer reads content, not involvement | `BeaconVisibility.canReadInvolvement` requires content then excludes discover-only path (`beacon_visibility.dart` L127–134) — unit tests should use `FakeBeaconAccessGuard(contentAllowed: true, involvementAllowed: false)` |
| Unit test files (grep) | `ST/domain/use_case/` | **`beacon_fact_card_case_test.dart`** (Fake stubs, no guard today). **`beacon_room_admission_matrix_test.dart`** — `helpOffersWithCoordination` redaction test + gate throw @ L1083 (`contentAllowed: false`). **No** dedicated `coordination_case_*` file for this gate |
| Pg regression | `beacon_hierarchy_visibility_pg_test.dart` › non-transitivity › `coordination_case helpOffersWithCoordination` | Frank admitted **parent A only** (`admitFrankToParentAOnly`); on child **B**: `canReadContent`=false, `canReadLinkedDetail`=true (L172–186). Real `BeaconAccessRepository` in harness — refusal should remain after gate swap |
| `HierarchyOnlyViewerHarness` comment | — | Still says “`canReadContent` gates” (L28–29) — stale after T03 for coordination only; file **not** in T03 edit list |

### Implementer brief (Opus, low effort)

**One commit:** `fix(server): gate help-offer list by involvement and facts by content` (plan “Done when”).

1. **Test-first (coordination):** Add a focused group (new `coordination_case_help_offers_access_gate_test.dart` or extend `beacon_room_admission_matrix_test.dart` — prefer small new file to avoid bloating matrix):
   - `FakeBeaconAccessGuard(contentAllowed: true, involvementAllowed: false)` → `helpOffersWithCoordination` throws `UnauthorizedException` with description **`Viewer cannot read request involvement`** (stub repo so gate is hit before I/O).
   - Default guard (both true) + stubbed rows → involved viewer (e.g. author `_authorId` pattern from matrix) still returns rows.
   - `involvementAllowed: false` (content irrelevant) → stranger throws same involvement message.
   - **Fix regression:** matrix test L1083 `buildSut(guard: FakeBeaconAccessGuard(contentAllowed: false))` must become **`involvementAllowed: false`** (with `contentAllowed: true` if you want to prove involvement is the gate); otherwise post-change test stays green while not exercising the new check.
2. **Production:** `coordination_case.dart` — swap gate per plan step 1 (exact exception string).
3. **Test-first (fact card):** In `beacon_fact_card_case_test.dart`:
   - Introduce `FakeBeaconAccessGuard` in `setUp` (default `contentAllowed: true`) passed into `BeaconFactCardCase` constructor.
   - New test: `contentAllowed: false` → `list` throws `'Viewer cannot read request content'` **before** public-only rows (today `denyRoomAccess` + public fact returns 1 row — that scenario stays valid when guard content true).
4. **Production:** `beacon_fact_card_case.dart` — add `required BeaconAccessGuard guard`, `_guard` field, top-of-`list` check per plan step 2; **do not** change room-visibility loop.
5. **Codegen:** `cd packages/server && dart run build_runner build -d` — updates `lib/app/di.config.dart` to pass `gh<BeaconAccessGuard>()` into `BeaconFactCardCase` (no new `@GenerateMocks` unless you choose Mockito for fact-card tests; `FakeBeaconAccessGuard` matches existing coordination tests).
6. **Pg regression (read-only file):** Run single-file `beacon_hierarchy_visibility_pg_test.dart` — group `non-transitivity — production call sites refuse hierarchy-only viewer` › `coordination_case helpOffersWithCoordination` must stay green (Frank still lacks involvement on B).

### TEST_CMD

```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test --exclude-tags pg test/domain/use_case/beacon_fact_card_case_test.dart

cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test --exclude-tags pg test/domain/use_case/beacon_room_admission_matrix_test.dart

# if new coordination gate file added, run it too:
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test --exclude-tags pg test/domain/use_case/coordination_case_help_offers_access_gate_test.dart

cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test -t pg test/data/repository/beacon_hierarchy_visibility_pg_test.dart

./scripts/run_with_test_cleanup.sh --timeout 10m -- ./scripts/check-custom-lints.sh packages/server
```

Optional broader unit sweep after green focused files:

```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test --exclude-tags pg test/domain/use_case/
```

### RISKS

- **`beacon_room_admission_matrix_test.dart` L1083** — must retarget fake guard to **`involvementAllowed: false`** or CI fails silently on wrong gate.
- **Existing fact-card list tests** — all construct `BeaconFactCardCase` without guard; constructor change breaks compile until tests + `build_runner` land together.
- **Frank / hierarchy-only pg** — passes today via **content** denial; after T03 via **involvement** denial — verify SQL: `beacon_can_read_involvement(B, frank)` false (content already false). No pg file edit expected.
- **m0124 vs Dart discoverability** — SQL `beacon_can_read_content` in m0124 may not include D11 discover path; involvement leak fix for discover observers is still correct at use-case layer using guard/SQL as deployed — do not widen scope to migration changes.
- **No `BeaconFactCardCase` pg test** in non-transitivity group — content gate on facts is unit-test-only in this unit.

- **Next (implementer):** land T03 commit, journal inner log, mark T03 done.

## T03 — Inner (implementer)

- **Commit:** `86f32279f` fix(server): gate help-offer list by involvement and facts by content (`issue-146 T03`).
- **Coordination tests:** folded into `beacon_room_admission_matrix_test.dart` (no new file). The old `contentAllowed: false` check at ~L1083 now runs as two checks: (a) `involvementAllowed: false` with content still readable → `'Viewer cannot read request involvement'`; this was a genuine red against the old code (the call returned rows); (b) stranger (content and involvement both false) → `UnauthorizedException`. Author/helper/outsider row checks still pass with the default guard.
- **Fact-card tests:** `beacon_fact_card_case_test.dart` now passes `FakeBeaconAccessGuard` to the case. New test: stranger (`contentAllowed = false`) → `'Viewer cannot read request content'`, and `listForBeacon` is never called (the stub now counts calls). The red was a compile failure caused by the new constructor argument. The existing "non-admitted user sees only public facts" test is unchanged and still green.
- **Production:** `coordination_case.dart` now makes a single `canReadInvolvement` check. `beacon_fact_card_case.dart` injects `BeaconAccessGuard` (4th positional argument) and checks it at the top of `list`; the room-visibility loop is unchanged. Also updated the matrix file's exit-access `BeaconFactCardCase(...)` construction.
- **DI:** `build_runner build -d` wires `gh<BeaconAccessGuard>()` into the case. `lib/app/di.config.dart` is gitignored, so it is not in the commit.
- **Verify:** fact_card 22 pass, matrix 19 pass, `beacon_hierarchy_visibility_pg_test.dart` 14 pass (including coordination hierarchy-only refusal), `check-custom-lints` server OK (0/0).
- **Note:** the `HierarchyOnlyViewerHarness` comment about "`canReadContent` gates" is out of date for coordination; the file was untouchable here.
- **Next:** T04.

---

## T03 — verify (read-only)

- **Range reviewed:** `0f9f4dbb20587da5622f863cc2d1026c452dcded..86f32279f` (4 files only). Pre-existing dirty worktree (`.serena/project.yml`, client tests) not touched by commit ✓; `beacon_hierarchy_repository.dart` not in range ✓.
- **Production gates (direct read):**
  - `helpOffersWithCoordination`: exactly one `_guard.canReadInvolvement` check; old `canReadContent` removed (not duplicated elsewhere in that method) ✓
  - `BeaconFactCardCase.list`: `canReadContent` gate before `final admitted = …`; remainder of method byte-identical to UNIT_BASE (`diff` empty from `final admitted` through closing brace) ✓
- **Regression trap:** matrix ~L1084–1096 `FakeBeaconAccessGuard(involvementAllowed: false)` with default `contentAllowed: true` on `_outsiderId` + exact involvement message — meaningful red for old content-only gate ✓. Fact-card stranger test uses `contentAllowed: false` (old gate would also refuse; correct signal for fact-card leak is `listForBeaconCalls == 0`).
- **Involved viewer rows:** same matrix test still loads author/helper/outsider rows under default guard before gate assertions ✓.
- **TEST_CMD re-run (2026-09-16):**

| Command | + | − | Failed | Exit |
|---|---|---|---|---|
| `beacon_fact_card_case_test.dart` | 22 | 0 | 0 | 0 |
| `beacon_room_admission_matrix_test.dart` | 19 | 0 | 0 | 0 |
| `beacon_hierarchy_visibility_pg_test.dart` (`-t pg`) | 14 | 0 | 0 | 0 (1st run: +0 −2 `setUpAll` RaceCondition; immediate retry green) |
| `check-custom-lints.sh packages/server` | — | — | 0 | 0 (`tentura_lints` 0/0) |

- **Verdict:** **pass** — plan T03 “Done when” met; proceed T04 after journal commit.

---

## T04 — Scout (read-only)

- **UNIT_BASE:** `b81c38b71ece8836e3a4ef71d7684712835a54e0` (= `HEAD` at scout time)
- **Task:** T04 — honest profile trust-network copy; expose `can_read_involvement`; skip involvement fetches in `BeaconViewCubit` for observers

### Live code vs plan

| Topic | Plan | Live @ UNIT_BASE |
|---|---|---|
| l10n four keys | Trust-network copy (§7.6 table) | `app_en.arb` / `app_ru.arb` still use visibility wording (“You can see {name}”, “can't see you yet”, etc.) @ ~L1693–L1720 |
| Hasura `beacon` computed_fields (`user`) | Append `can_read_involvement` | `computed_fields`: `is_pinned`, `my_vote`, `can_read_content` only @ `metadata.json` ~L269–273; field **defined** on table @ L207–215 |
| `help_offers` select filter | — | Already filters `beacon.can_read_involvement = true` @ L1502–1507 (metadata ahead of beacon row exposure) |
| `schema.graphql` | Add `can_read_involvement` to `beacon`, `beacon_bool_exp`, `beacon_order_by` | **Absent** — only `can_read_content` @ L139–141, L464, L1715 |
| `BeaconModel` fragment | Below `can_read_content` | Only `can_read_content` @ `beacon_model.graphql` L61 |
| `Beacon` entity | `canReadInvolvement` default true | Only `canReadContent` @ `beacon.dart` L75–76 |
| `BeaconModel.toEntity` | `canReadInvolvement: i.can_read_involvement ?? true` | Only `canReadContent` @ `beacon_model.dart` L57 |
| Cubit involvement fetches | Skip 3 futures when `!beacon.canReadInvolvement` | `_fetchBeaconByIdWithTimeline` always calls all 7 @ `beacon_view_cubit.dart` L981–990 |
| Tests with old copy literals | grep four patterns | **Only** `packages/client/test/l10n/issue_100_wu13_localization_test.dart` (L70–87). `profile_view_body_action_policy_test.dart` uses `l10n.profileVisibility*` — no hardcoded old EN strings |
| Version bump | None (T16) | N/A |

### `_fetchBeaconByIdWithTimeline` — exact `Future.wait` contract

List order (unchanged); replace **indices 0, 4, 5** when `!beacon.canReadInvolvement`:

| Index | Live call | Stand-in |
|---|---|---|
| 0 | `_case.fetchHelpOffersWithCoordination(beaconId: beaconId)` | `Future.value(const <({String beaconId, String userId, Profile user, String message, String? helpType, int status, String? withdrawReason, DateTime createdAt, DateTime updatedAt, int? responseType, DateTime? responseUpdatedAt, String? responseAuthorUserId, int? roomAccess, int? admissionAction, String? lastDeclineReason, String? lastRemoveReason, int stakeState, int offerKind, bool isDirectAuthorForward})>[])` — same record shape as cast @ L993–1017 |
| 1–3, 6 | inbox, fact cards, room participants, display status | **Still call** |
| 4 | `_case.fetchRoomStateIfAllowed(beaconId)` | `Future<BeaconRoomState?>.value()` → `null` |
| 5 | `_case.fetchRoomActivityEvents(beaconId)` | `Future.value(const <BeaconActivityEvent>[])` |

Casts @ L993–1029 stay as-is. `fetchOpenCoordinationBlocker` only runs when `beaconRoomCue != null` (L1030–1032) — skipped when room state stand-in is null.

Case delegation for spies: `fetchHelpOffersWithCoordination` → `CoordinationRepository`; `fetchRoomStateIfAllowed` → `_beaconRoomCase.fetchBeaconRoomState`; `fetchRoomActivityEvents` → `_activityEvents.list`.

### New cubit test pattern

Mirror `beacon_view_initial_load_test.dart`: `buildTestBeaconViewCase` + `TrackingBeaconRepository` returning `Beacon(..., canReadContent: true, canReadInvolvement: false)`. Count via fakes: `FakeBeaconViewRoomRepository.fetchBeaconRoomStateCalls` (exists); subclass `FakeBeaconViewCoordinationRepository` / `FakeBeaconViewActivityEventRepository` in the **new test file** for help-offer and activity `list` call counts (do not edit unrelated client tests). Assert `beaconContextLoaded` and all three counts `== 0`.

### Schema hand-edit template (mirror `can_read_content`)

`type beacon` after L141:

```graphql
  """
  A computed field, executes function "beacon_get_can_read_involvement"
  """
  can_read_involvement: Boolean
```

`beacon_bool_exp`: `can_read_involvement: Boolean_comparison_exp` after L464.  
`beacon_order_by`: `can_read_involvement: order_by` after L1715.

### Implementer brief (Opus, low effort)

**One commit:** `fix(client): honest trust-network copy; skip involvement fetches for observers`.

1. l10n values only (four keys) → `flutter gen-l10n` → update `issue_100_wu13_localization_test.dart` expectations to plan EN/RU table → `bash scripts/check-user-facing-terminology.sh`.
2. `hasura/metadata.json` append `"can_read_involvement"` to `beacon` `user` `select_permissions[0].permission.computed_fields` (after `can_read_content`). Optional local `./scripts/hasura_apply_metadata.sh` (not required for CI unit tests).
3. `schema.graphql` + `beacon_model.graphql` fragment field → `beacon.dart` + `beacon_model.dart` mapper → `cd packages/client && dart run build_runner build -d` (Freezed + Ferry).
4. `beacon_view_cubit.dart` conditional futures (use local `final skipInvolvement = !beacon.canReadInvolvement` before `Future.wait`).
5. New test e.g. `beacon_view_involvement_fetch_gate_test.dart` beside `beacon_view_initial_load_test.dart`.

**Do not:** bump `pubspec.yaml`, add `access_level`/`access_reasons`, touch server T01–T03 files, edit `.serena/project.yml` or the two in-progress constellation/router tests.

- **Next (implementer):** land T04 commit, journal inner log, mark T04 done.

## T04 — Inner (implementer, Opus 5)

- **Commit:** `a0ff4912c` fix(client): honest trust-network copy; skip involvement fetches for observers
- **Changes:** 4 EN/RU profile visibility values; `can_read_involvement` exposed to `user` role on `beacon` (metadata.json computed_fields only, filter untouched); schema.graphql (type/bool_exp/order_by) + BeaconModel fragment; `Beacon.canReadInvolvement` (`@Default(true)`, mapper `?? true`); cubit `skipInvolvement` swaps help-offer coordination / room state / room activity futures for typed no-op stand-ins (order + casts unchanged).
- **Test:** new `beacon_view_involvement_fetch_gate_test.dart` (test-local counting subclasses; observer case asserts 0/0/0 calls + content loaded + fact cards fetched; control case asserts involved viewer still fetches). RED verified by disabling the gate (1 fail) → GREEN restored.
- **Verify:** gen-l10n ok; terminology ok; build_runner ok (generated files gitignored, no diff); flutter test 4 files +31 all passed; check-custom-lints client OK (30/30 baseline); server pg `beacon_hierarchy_hasura_parity_test` +2 passed.
- **Not done:** `./scripts/hasura_apply_metadata.sh` not run (optional); no version bump (T16).
- **Next:** T04 verify.
