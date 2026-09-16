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
| done (46a394b4b) | **T05** access enums + pure policy |
| done (7e1700366) | **T06** SQL member view/reasons/level |
| done (892452a10) | **T07** expose access level+reasons |
| done | **T08+T09** ancestor closure + widened content read (one migration, one commit) |
| done (`ffc232a3f`) | **T10** unify hierarchy predicate, drop linked-detail |
| done (`a3adbd47d`) | **T11** bond SQL + server consumers |
| done (`70b34aabd`) | **T12** personSharedContexts query |
| done (`a3c2acd38`) | **T13** client bond-aware profile |
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

---

## T04 — verify (read-only)

- **Range reviewed:** `b81c38b71ece8836e3a4ef71d7684712835a54e0..HEAD` (`a0ff4912c` implementation, `f06dcce92` journal). Pre-existing dirty worktree (`.serena/project.yml`, constellation/router tests) unchanged by T04 commits ✓. No `packages/server/` or `pubspec.yaml` / `web/index.html` in range ✓. No `access_level` / `access_reasons` in `packages/client/lib` ✓.
- **l10n:** Four EN/RU **values** match plan §T04 table exactly (keys/placeholder metadata unchanged); `issue_100_wu13_localization_test.dart` expectations aligned ✓.
- **Hasura metadata:** Only `computed_fields` append on `beacon` `user` select; `filter` still `can_read_content` only ✓.
- **GraphQL / entity:** `can_read_involvement` mirrored next to `can_read_content` in schema + fragment; `canReadInvolvement` `@Default(true)` + mapper `?? true` adjacent to `canReadContent` ✓.
- **Cubit:** `skipInvolvement = !beacon.canReadInvolvement` gates **only** indices 0/4/5 in `Future.wait` (help offers, room state, activity); stand-ins match cast types; list length/order and `results[n]` casts unchanged ✓. `fetchOpenCoordinationBlocker` still guarded by `beaconRoomCue != null` — not a fourth explicit gate; null room-state stand-in skips it for observers only ✓. Positive test (`canReadInvolvement: true`) still hits all three repos ✓.
- **TEST_CMD re-run (2026-09-16 verify):**

| Command | Passed | Failed | Exit |
|---|---|---|---|
| `flutter gen-l10n` | — | — | 0 |
| `check-user-facing-terminology.sh` | — | — | 0 (`ok`) |
| `build_runner build -d` (client) | — | — | 0 (0 outputs; already current) |
| flutter test (4 files) | 31 | 0 | 0 |
| `check-custom-lints.sh packages/client` | — | — | 0 (30/30 baseline OK) |
| `beacon_hierarchy_hasura_parity_test.dart` (`-t pg`) | 2 | 0 | 0 |

- **Verdict:** **pass** — T04 “Done when” satisfied; proceed **T05**.

---

## T05 — Scout (read-only)

- **UNIT_BASE:** `8dccbe2703bfe688b0501270b24edce00b13a641` (= `HEAD` at scout time)
- **Task:** T05 — shared access enums (`tentura_root`) + pure `BeaconAccessPolicy` (server); parity vs `BeaconVisibility.canReadContent`; no wiring.

### Live code vs plan

| Topic | Plan | Live @ UNIT_BASE |
|---|---|---|
| `beacon_access.dart` | New under `R/domain/entity/` | **Absent** — create `lib/domain/entity/beacon_access.dart` |
| `beacon_access_policy.dart` | New `S/domain/` | **Absent** |
| `BeaconContentVisibilityFacts` fields | 8 fields for parity mapping | Exact names @ `packages/server/lib/domain/beacon_visibility.dart` L4–23 — **no `isBlocked`** (blocks applied before facts in SQL; parity only when `isBlocked == false`) |
| Parity mapping | `isRoomAdmittedOrSteward = isSteward \|\| isAdmitted`; `isMutuallyVisibleWithAuthor = isTrustVisibleWithAuthor`; others 1:1 | Live uses `isMutuallyVisibleWithAuthor` on facts type; policy facts use `isTrustVisibleWithAuthor` per plan ✓ |
| Open-family for `discovered` | `status.isOpenFamily` | `BeaconStatus.isOpenFamily` getter @ `lib/domain/entity/beacon_status.dart` L31 (`openFamilyValues = {0,7,8}`) — **not** named `isOpenFamily` on a separate helper |
| `allowsCoordination` (§0.4 bond) | {0,5,7,8} | `BeaconStatus.allowsCoordination` = `isOpenFamily \|\| reviewOpen` @ L48 — **not used in T05 `discovered` rule** (discover uses `isOpenFamily` only, matching `BeaconVisibility.canReadContent` L118–121) |
| `BeaconStatus` sweep | 8 enum values | `open, cancelled, deleted, draft, reviewOpen, closed, needsMoreHelp, enoughHelp` @ `beacon_status.dart` |
| Root tests | `R/test/domain/entity/beacon_access_test.dart` | Pattern: `test/domain/entity/beacon_status_discussion_writes_test.dart` imports `package:tentura_root/...` + `package:test/test.dart` |
| Server policy tests | `ST/domain/beacon_access_policy_test.dart` | Mirror style of `beacon_visibility_test.dart` (`_content` helper already exists there — **new file**, do not edit `beacon_visibility_test.dart`) |
| CI / wiring | None | Nothing imports new types yet (T06–T07) ✓ |

### Verbatim `lib/domain/entity/beacon_access.dart` (from plan §T05 step 1 — paste as-is)

```dart
/// Viewer's access level to one request (issue #146 architecture §2.1).
enum BeaconAccessLevel {
  author(0),
  member(1),
  observer(2),
  stranger(3);

  const BeaconAccessLevel(this.value);
  final int value;

  static BeaconAccessLevel fromInt(int? v) => switch (v) {
    0 => author,
    1 => member,
    2 => observer,
    _ => stranger,
  };

  bool get canReadContent => value <= 2;
  bool get isMember => value <= 1;
}

/// Why the viewer has access. Bit values are persisted contracts (never renumber).
enum BeaconAccessReason {
  author(1),
  steward(2),
  admitted(4),
  forwarded(8),
  applied(16),
  discovered(32),
  contextChild(64),
  contextAncestor(128);

  const BeaconAccessReason(this.bit);
  final int bit;

  static Set<BeaconAccessReason> decode(int mask) =>
      {for (final r in values) if (mask & r.bit != 0) r};

  static int encode(Iterable<BeaconAccessReason> reasons) =>
      reasons.fold(0, (m, r) => m | r.bit);
}

BeaconAccessLevel beaconAccessLevelFromReasons(int mask) {
  if (mask & 1 != 0) return BeaconAccessLevel.author;
  if (mask & (2 | 4) != 0) return BeaconAccessLevel.member;
  if (mask & (8 | 16 | 32 | 64 | 128) != 0) return BeaconAccessLevel.observer;
  return BeaconAccessLevel.stranger;
}
```

**Sanity vs §0.4:** bit table and level derivation match (author=1, steward=2, admitted=4, forwarded=8, applied=16, discovered=32, contextChild=64, contextAncestor=128; level 0/1/2/3 from bits 0 / 1–2 / 3–7 / none).

### `BeaconAccessPolicy` — exact `reasons` logic (plan §T05 step 2)

`BeaconAccessFacts` — `const` class, all **required**: `BeaconStatus status`, `bool isBlocked`, `bool isAuthor`, `bool isSteward`, `bool isAdmitted`, `bool hasActiveForwardEdgeAsRecipient`, `bool isActiveHelpOfferer`, `bool isDiscoverable`, `bool isPublished`, `bool isTrustVisibleWithAuthor`, `bool isMemberOfImmediateParent`, `bool isMemberOfDescendant`.

`abstract final class BeaconAccessPolicy` with private constructor pattern like `BeaconVisibility`:

1. If `f.isBlocked` → return `0`.
2. Else if `f.status == BeaconStatus.draft` → return `f.isAuthor ? BeaconAccessReason.author.bit : 0`.
3. Else if `f.status == BeaconStatus.deleted` → return `0`.
4. Else OR bits:
   - `author` if `f.isAuthor`;
   - `steward` if `f.isSteward`;
   - `admitted` if `f.isAdmitted`;
   - `forwarded` if `f.hasActiveForwardEdgeAsRecipient`;
   - `applied` if `f.isActiveHelpOfferer`;
   - `discovered` if `f.isDiscoverable && f.isPublished && f.status.isOpenFamily && f.isTrustVisibleWithAuthor`;
   - `contextChild` if `f.isPublished && f.isMemberOfImmediateParent`;
   - `contextAncestor` if `f.isPublished && f.isMemberOfDescendant`.

`static BeaconAccessLevel level(BeaconAccessFacts f) => beaconAccessLevelFromReasons(reasons(f));`

**Doc comment on `BeaconAccessPolicy`:** phase-1 callers pass `false` for `isMemberOfImmediateParent` and `isMemberOfDescendant` until T09 (context reasons never set in production until then).

**Imports:** `package:tentura_root/domain/entity/beacon_access.dart`, `package:tentura_root/domain/entity/beacon_status.dart`.

### Parity helper (for exhaustive test)

When `!f.isBlocked && !f.isMemberOfImmediateParent && !f.isMemberOfDescendant`:

```dart
BeaconContentVisibilityFacts(
  status: f.status,
  isAuthor: f.isAuthor,
  hasActiveForwardEdgeAsRecipient: f.hasActiveForwardEdgeAsRecipient,
  isRoomAdmittedOrSteward: f.isSteward || f.isAdmitted,
  isActiveHelpOfferer: f.isActiveHelpOfferer,
  isDiscoverable: f.isDiscoverable,
  isPublished: f.isPublished,
  isMutuallyVisibleWithAuthor: f.isTrustVisibleWithAuthor,
)
```

Assert `BeaconAccessPolicy.level(f).canReadContent == BeaconVisibility.canReadContent(...)`.

### Exhaustive sweep (16384 cases)

- Nested loops: 11 booleans (bit index 0..10 for the list above) × `BeaconStatus.values` (8).
- **S4-11:** For each case where **only** context could fire (`isMemberOfImmediateParent` or `isMemberOfDescendant` true, all membership/observer reason facts false, `!isBlocked`, status not draft/deleted): `level(f).value > 1` (never author/member from context alone).
- **S4-02:** `isBlocked` → `level == stranger`.
- **Draft/deleted:** `status == draft` → level ∈ {author, stranger}; `status == deleted` → stranger.
- **Parity:** as above when context false and not blocked.
- **S4-01:** With `isBlocked == false`, for each baseline `f`, for each of the 10 non-block booleans, compare `level(f)` vs `level(f with that bool true)` — `newLevel.value <= oldLevel.value` (more facts never worsen access).

**Performance:** 16k × cheap int/bool logic — expect **&lt;1s** on CI; no concern.

### Implementer brief (Opus 5, low effort)

**One commit:** `feat(server): add explicit beacon access level policy` (body `issue-146 T05`). Stage only the four new files.

1. **Red — root:** Add `beacon_access_test.dart` (will not compile until entity file exists — acceptable); then add `beacon_access.dart` verbatim; green root test.
2. **Red — server:** Add `beacon_access_policy_test.dart` with exhaustive sweep + invariants; then `beacon_access_policy.dart`; green server test.
3. **Verify:** commands below + `check-custom-lints.sh` only if analyzer complains (new domain files should be clean).

**Red meaningful:** **yes** — policy test parity line fails until `BeaconAccessPolicy` matches `BeaconVisibility`; root round-trip fails without entity.

### TEST_CMD

```bash
cd /home/vader/MY_SRC/tentura && ./scripts/run_with_test_cleanup.sh --timeout 10m -- \
  dart test test/domain/entity/beacon_access_test.dart

cd /home/vader/MY_SRC/tentura/packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 10m -- \
  dart test --exclude-tags pg test/domain/beacon_access_policy_test.dart

cd /home/vader/MY_SRC/tentura && ./scripts/run_with_test_cleanup.sh --timeout 10m -- \
  ./scripts/check-custom-lints.sh packages/server
```

### RISKS

- **Steward vs admitted split:** Policy sets separate bits; parity **must** OR them for `isRoomAdmittedOrSteward` — easy to wire 1:1 wrongly.
- **`discovered` vs `allowsCoordination`:** §0.4 mentions bond statuses including `reviewOpen(5)`; **discovered** reason uses **`isOpenFamily` only** — same as live `canReadContent` (closed/reviewOpen/cancelled do not get discover path).
- **Deleted author:** Policy `reasons` → 0 → stranger → `canReadContent` false; matches `BeaconVisibility` (author cannot read deleted via content predicate).
- **Monotonicity with draft/deleted early returns:** Run S4-01 only when `isBlocked == false`; flipping facts under draft/deleted may not change level — still must not increase level number.

- **Next (implementer):** land T05 commit, journal inner log, mark T05 done.

---

## T05 — inner (implementer)

- **Commit:** `46a394b4b` `feat(server): add explicit beacon access level policy` (body `issue-146 T05`)
- **Files (4):** `lib/domain/entity/beacon_access.dart`, `test/domain/entity/beacon_access_test.dart`, `packages/server/lib/domain/beacon_access_policy.dart`, `packages/server/test/domain/beacon_access_policy_test.dart`
- **Tests:** root 2/2; server policy 2/2; `check-custom-lints.sh packages/server` 0/0 OK
- **Next:** T05 verify

---

## T05 — verify (read-only)

- **Range reviewed:** `8dccbe2703bfe688b0501270b24edce00b13a641..46a394b4b` — **4 files only**, +290 lines, no other paths in commit ✓
- **`beacon_access.dart` vs plan §T05 step 1:** Semantically identical contract — bit values 1/2/4/8/16/32/64/128; `fromInt`/`canReadContent`/`isMember`; `beaconAccessLevelFromReasons` branches `&1`, `&(2|4)`, `&(8|16|32|64|128)`, else stranger. Whitespace/indent differs from markdown fence only ✓
- **`BeaconAccessPolicy.reasons`:** Order blocked→0; `draft`→author bit or 0; `deleted`→0; else OR eight conditions. **`discovered`** uses `f.status.isOpenFamily` (L64), not `allowsCoordination` ✓. Phase-1 doc comment on facts ✓. `level` → `beaconAccessLevelFromReasons(reasons(f))` ✓
- **Exhaustive test:** `1 << 11` × `BeaconStatus.values` (8) with `expect(cases, 16384)` ✓. Parity calls **`BeaconVisibility.canReadContent(_visibilityFacts(f))`** (live import), mapping `isRoomAdmittedOrSteward = isSteward || isAdmitted`, `isMutuallyVisibleWithAuthor = isTrustVisibleWithAuthor` ✓; 2048 parity rows (`!blocked` ∧ context bits clear = 256×8). **S4-01:** `isBlocked` skipped; single-bit flip `v | (1<<i)` for `i in 1..10`; `after <= before` on `.value`; `expect(flips, 40960)` ✓
- **Wiring:** Grep — only the four new files reference `beacon_access` / `beacon_access_policy` ✓
- **TEST_CMD re-run (2026-09-16 verify):**

| Command | + | − | Failed | Exit |
|---|---|---|---|---|
| `dart test test/domain/entity/beacon_access_test.dart` (repo root) | 2 | 0 | 0 | 0 |
| `dart test --exclude-tags pg test/domain/beacon_access_policy_test.dart` | 2 | 0 | 0 | 0 |
| `check-custom-lints.sh packages/server` | — | — | 0 | 0 (total 0, baseline 0 OK) |

- **Verdict:** **pass** — T05 “Done when” satisfied; proceed **T06**.

## T05 — Inner (Opus 5)

- **Commit:** `46a394b4b` feat(server): add explicit beacon access level policy (body `issue-146 T05`).
- **Files:** `lib/domain/entity/beacon_access.dart` (verbatim), `test/domain/entity/beacon_access_test.dart`, `packages/server/lib/domain/beacon_access_policy.dart`, `packages/server/test/domain/beacon_access_policy_test.dart`.
- **Red:** both tests failed at load before their source files existed.
- **Green:** root 2/2 (256 round-trips + 9 levels); server 2/2 (16384-case sweep incl. 2048 parity cases; 40960 single-fact flips for S4-01), <1s test time.
- **Lints:** `check-custom-lints.sh packages/server` → total 0 (baseline 0), OK.
- **Notes:** `BeaconStatus` has no `isDraft`/`isDeleted` getters — policy uses `== BeaconStatus.draft/deleted` (same as `BeaconVisibility`). Parity mapping onto `BeaconContentVisibilityFacts` complete (8 fields; steward‖admitted → `isRoomAdmittedOrSteward`, trust → `isMutuallyVisibleWithAuthor`). `dart format` would re-indent the verbatim `fromInt` switch in `beacon_access.dart`; left verbatim per brief.

---

## T06 — Scout (read-only)

- **UNIT_BASE:** `f1d9e510bde9bc7e8d90c771f070e6791c6de50d` (= `HEAD` at scout time)
- **Task:** T06 — `beacon_member` view, `beacon_access_reasons` / `beacon_access_level`, Hasura wrappers; parity pg test

### Migration slot

| Check | Result |
|---|---|
| `m0170` on disk | **Absent** — still free (T00 mapping holds) |
| `_migrations.dart` tail | `part 'm0169.dart';` / list ends `m0169` — append `m0170` after |

### Index grep (`ON public.beacon (user_id` in `MIG/*.dart`)

| File | Line | Index |
|---|---|---|
| `m0160.dart` | 18–20 | `beacon_discoverable_author_idx ON public.beacon (user_id) WHERE is_discoverable AND status IN (0, 7, 8) AND published_at IS NOT NULL` |

**No** `beacon_user_id_published_idx`. Per plan T06 (“If it does, drop step 5”): **omit migration statement #5** — an index on `beacon(user_id)` already exists (narrower partial). Record in commit message body if desired.

### `setBeaconSteward` write pattern (`beacon_room_repository.dart` L1076–1098)

1. `INSERT … ON CONFLICT UPDATE` into `beacon_steward` for `(beacon_id, stewardUserId)`.
2. `UPDATE beacon_participant SET role = BeaconParticipantRoleBits.steward` for **existing** row matching `(beaconId, stewardUserId)` — **does not insert** a participant.

Parity fixtures for steward viewers must **INSERT both** `beacon_steward` **and** `beacon_participant` with `role = 1` (or insert participant then call `setBeaconSteward`).

### vs `beacon_access_sql_parity_test.dart`

That file uses shared `TenturaDb` + `migrateDbSchema` + `Uvisparity*` ids; tests `beacon_can_read_content` / involvement / tombstone vs `BeaconVisibility`. **No** `beacon_access_level` / `beacon_member`. Plan names **new** `beacon_access_level_parity_pg_test.dart` — use **`BeaconHierarchyDisposablePgTarget`** + `openBeaconHierarchyPgSession` (same as `beacon_hierarchy_visibility_pg_test.dart`), not extend the old parity file.

### Hasura wrapper mirror

Copy shape from `m0155.dart` `beacon_get_can_read_linked_detail` (table `beacon_row`, `hasura_session` → `x-hasura-user-id`); T06 plan SQL delegates to `beacon_access_level` / `beacon_access_reasons`.

### Live SQL

Grep: **no** `beacon_member`, `beacon_access_reasons`, or `beacon_access_level` in repo yet — T06 is first wiring.

- **Next (implementer):** land T06 per brief below, journal inner log, mark T06 done.

---

## T06 — verify (read-only)

- **Range reviewed:** `f1d9e510bde9bc7e8d90c771f070e6791c6de50d..7e1700366` (3 files). Pre-existing dirty worktree unchanged by commit ✓
- **Commit:** `7e1700366` `feat(server): add beacon_member view and access level SQL` — body `issue-146 T06`, index-skip note ✓
- **`m0170.dart` vs plan SQL:** Statements 1–3 byte-match plan §T06. Statement 4 split into two migration strings (lines 98–111); SQL text of both `CREATE OR REPLACE FUNCTION` bodies matches plan (comment retained on first wrapper only). **No** statement 5 / `beacon_user_id_published_idx` ✓
- **`_migrations.dart`:** `part 'm0170.dart';` + `m0170` after `m0169` ✓
- **Untouchables:** No changes to `beacon_access_policy.dart`, `beacon_access.dart`, Hasura, client, repos/guards/use cases in range ✓
- **Parity test:** 10 personas (`_author` … `_blocked`); 8×8 status×persona loop; `isMemberOfImmediateParent`/`isMemberOfDescendant` always `false`; draft beacon relationship-free; `beacon_member` draft/deleted/blocked cases present ✓
- **Draft / `beacon_effective_admission`:** `m0155` `beacon_effective_admission` has **no** `b.status` filter (author/steward/participant only). Mismatch with `beacon_access_level` on draft+membership is **pre-existing**, not introduced by T06; test avoids by seeding draft without steward/participant/forward/offer rows (matches create path: `published_at` null, no room graph). Not a T06 acceptance gap.
- **TEST_CMD re-run (2026-09-16 verify):**

| Command | + | − | Failed | Exit |
|---|---|---|---|---|
| `beacon_access_level_parity_pg_test.dart` (`-t pg`) | 3 | 0 | 0 | 0 |
| `beacon_access_sql_parity_test.dart` (`-t pg`) | 12 | 0 | 0 | 0 |
| `check-custom-lints.sh packages/server` | — | — | 0 | 0 (`tentura_lints` 0/0 OK) |

- **Verdict:** **pass** — T06 “Done when” satisfied; mark T06 done in checklist when journal committed.

## T06 — Inner (Opus 5)

- **Commit:** `7e1700366` feat(server): add beacon_member view and access level SQL (body `issue-146 T06`; notes the step-5 index omission).
- **Files:** `MIG/m0170.dart`, `MIG/_migrations.dart` (part + list), `ST/data/repository/beacon_access_level_parity_pg_test.dart`.
- **Red:** parity test 0/3 — `function public.beacon_access_reasons(unknown, unknown) does not exist`, `relation "public.beacon_member" does not exist`.
- **Green:** parity test 3/3 (10 personas × all 8 `BeaconStatus` values: reasons == policy, level == policy, level≤2 ⇔ can_read_content, non-deleted level≤1 ⇔ effective_admission; beacon_member open/draft/deleted/blocked). `beacon_access_sql_parity_test.dart` 12/12. `check-custom-lints.sh packages/server` total 0 (baseline 0).
- **Step 5 (index):** omitted — `m0160` `beacon_discoverable_author_idx` already covers `beacon(user_id)`.
- **Findings:**
  - Statement 4 (two `CREATE FUNCTION`s) had to be two migration strings — migrant rejects multiple commands in one prepared statement. SQL text otherwise verbatim.
  - Fixture: changing one beacon's status in place trips the `inbox_item` tombstone trigger → seeded one beacon per status instead.
  - `beacon_effective_admission` ignores status, so a steward/admitted row on a **draft** gives admission=true but level=3. Production drafts have `published_at = NULL` (`BeaconRepository.create`), and room/steward/forward/offer rows need a published request, so the draft fixture is unpublished and relationship-free (author/stranger/trusted/blocked facts only). The plan's "non-deleted ⇒ level≤1 ⇔ admission" invariant only holds for realistic drafts; T08+ should keep that in mind if admission is ever evaluated on drafts.
  - `beacon_steward` PK is `beacon_id` (one steward per beacon).
  - `pgTestPublicKey` uses only a 2-char namespace tag and slots 1–9 → the 10th user rolls over to namespace `ad`.

---

## T07 — Scout (read-only)

- **UNIT_BASE:** `5f0e142f6e6179a9354b29987c7f583a0fd4c1fb` (= `HEAD` at scout time)
- **Task:** T07 — wire `beacon_get_access_level` / `beacon_get_access_reasons` into Hasura metadata; client schema/fragment/entity; pg Hasura test with user JWT (no UI)

### Live code vs plan

| Topic | Plan | Live @ UNIT_BASE |
|---|---|---|
| SQL wrappers | `beacon_get_access_level` / `beacon_get_access_reasons` in m0170 | Present @ `packages/server/lib/data/database/migration/m0170.dart` L100–111 ✓ |
| Hasura `beacon.computed_fields` | Add `access_level`, `access_reasons` like `can_read_linked_detail` | Has `can_read_linked_detail` @ L217–227; **no** `access_*` entries |
| `user` `computed_fields` | Append `access_level`, `access_reasons` next to T04’s `can_read_involvement` | Array @ L269–274: `is_pinned`, `my_vote`, `can_read_content`, `can_read_involvement` only |
| `schema.graphql` | `access_level` / `access_reasons` on `beacon`, `beacon_bool_exp`, `beacon_order_by` | **Absent**; `can_read_involvement` @ L143–146, bool_exp L469–470, order_by L1721–1722 |
| Int computed-field template | Mirror `my_vote` | `my_vote: Int` + doc comment @ L223–226; `Int_comparison_exp` / `order_by` @ L489, L1740 |
| `BeaconModel` fragment | Add both fields | Ends with `can_read_content`, `can_read_involvement` @ `beacon_model.graphql` L61–62 |
| `Beacon` entity | `BeaconAccessLevel? accessLevel`, `@Default(0) int accessReasons` | Only `canReadContent` / `canReadInvolvement` @ `beacon.dart` L75–79 |
| Mapper | `fromInt` + `?? 0` | `beacon_model.dart` L57–58 — no access fields |
| Root import path | `package:tentura_root/domain/entity/beacon_access.dart` | Same pattern as `beacon_status.dart` in `beacon.dart` / `beacon_model.dart` ✓ |
| Client `access_*` grep | — | **Zero** matches under `packages/client` ✓ |
| Hasura pg harness | User JWT, not admin | `beacon_hierarchy_hasura_parity_test.dart`: `IsolatedHasuraSession.start` → `applyRepoMetadata()` (reads repo `hasura/metadata.json`), `authCase.issueAccessToken(userId)`, `_queryBeaconByPk` with `Authorization: Bearer` ✓ |
| Plan author fixture `reasons = 1` | Author row | **Trap:** `seedFullTopology` admits **alice→A** and **bob→B** (`_seedAdmissions`) → SQL mask **5** (author\|admitted), not **1**. Use **owner without admitted row** (e.g. **eve on `beaconD`**) or omit participant re-seed for the author assertion |

### m0124 involvement (forward recipient `true`)

`beacon_can_read_involvement` = `beacon_can_read_content` **AND** (author **OR** forward sender/recipient **OR** active offer **OR** steward/admitted participant) @ `m0124.dart` L52–76. Forward **recipient** is in the forward-edge branch → **`can_read_involvement` true** when content is readable (dave on B with bob→dave forward matches `beacon_parent_reference_authorization_pg_test.dart` preconditions).

### Implementer brief (Opus 5, low effort)

**One commit — message exactly:** `feat: expose beacon access level and reasons` (**no** `(server)` / `(client)` scope prefix; single commit spans Hasura + client + server test).

1. **Red — pg:** Add test (prefer new `packages/server/test/api/beacon_access_hasura_test.dart` cloned from parity harness: disposable PG, `IsolatedHasuraSession`, JWT). Cases:
   - **Forward recipient:** `seedFullTopology` + `seedPublishedHierarchyTree` + re-seed bob/carol/alice participants (copy `beacon_parent_reference_authorization_pg_test.dart` `seedTree`); INSERT forward `bobId` → `daveId` on `beaconB`; JWT `daveId`; `beacon_by_pk` fields `access_level access_reasons can_read_involvement` → **2, 8, true**.
   - **Author:** `seedFullTopology()` only; JWT **`eveId`** on **`beaconD`** (owner, no admitted participant on D) → **0, 1, true**. (Do **not** use alice on A unless you drop her participant row — mask would be 5.)
2. **Metadata:** In `hasura/metadata.json`, append two `computed_fields` entries after `can_read_linked_detail` (same JSON shape as L217–227): `access_level` → `beacon_get_access_level`, `access_reasons` → `beacon_get_access_reasons`. Append both names to `user` `select_permissions[0].permission.computed_fields` after `can_read_involvement`. **Do not** change `filter` (`can_read_content` only).
3. **Green pg:** Re-run test — isolated Hasura picks up metadata via `applyRepoMetadata()` (no `hasura_apply_metadata.sh` required for this suite).
4. **Client schema:** Hand-edit `schema.graphql` — three sites, doc comments like `my_vote`, function names `beacon_get_access_level` / `beacon_get_access_reasons`, types `Int` / `Int_comparison_exp` / `order_by`. Place `access_level` & `access_reasons` adjacent to other access computeds (`can_read_*` block) or alphabetically in bool_exp (before `address_label`).
5. **Fragment:** `beacon_model.graphql` — add `access_level` and `access_reasons` after `can_read_involvement`.
6. **Entity + mapper:** `beacon.dart` import `beacon_access.dart`; fields after `canReadInvolvement`. `beacon_model.dart` mapper per plan. **`cd packages/client && dart run build_runner build -d`** (Freezed + Ferry).
7. **Verify:** `check-custom-lints.sh` both packages; regression `beacon_hierarchy_hasura_parity_test.dart` (`-t pg`, per-file invocation).

**Do not:** UI/cubit usage of new fields; `m0170`; `beacon_access_policy.dart` / `beacon_access.dart`; version bump; `hasura_apply_metadata.sh` unless manually exercising compose Hasura on :8080.

### TEST_CMD

```bash
# After implementation (test-first: run once RED before metadata/client, then GREEN)

cd /home/vader/MY_SRC/tentura/packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test -t pg test/api/beacon_access_hasura_test.dart

cd /home/vader/MY_SRC/tentura/packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test -t pg test/api/beacon_hierarchy_hasura_parity_test.dart

cd /home/vader/MY_SRC/tentura/packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 15m -- \
  dart run build_runner build -d

cd /home/vader/MY_SRC/tentura && ./scripts/run_with_test_cleanup.sh --timeout 10m -- \
  ./scripts/check-custom-lints.sh packages/server

cd /home/vader/MY_SRC/tentura && ./scripts/run_with_test_cleanup.sh --timeout 10m -- \
  ./scripts/check-custom-lints.sh packages/client
```

Optional local compose (not required for pg test): `./scripts/hasura_apply_metadata.sh` after metadata edit.

### RISKS

- **Author `access_reasons == 1`:** Default hierarchy fixture owners alice/bob also have `room_access = 3` participant rows → bitmask **5**; use **eve/`beaconD`** or strip participant for the author case.
- **Isolated vs compose Hasura:** Pg tests reload metadata from disk at `applyRepoMetadata()` — editing `metadata.json` is sufficient; long-running :8080 needs `hasura_apply_metadata.sh` only for manual QA.
- **Row visibility:** `beacon_by_pk` still gated by `can_read_content` filter — forward recipient and author must have content access (dave forward on B; eve owns D).
- **Parity metadata test:** Existing parity test asserts `can_read_linked_detail` **not** in user `computed_fields`; optional follow-up assert `access_level`/`access_reasons` **are** listed (only if extending that file).
- **Freezed:** New nullable `accessLevel` defaults null for local `Beacon(...)`; no mass test edits expected if defaults hold.

- **Next (implementer):** land T07 commit, journal inner log, mark T07 done.

---

## T07 — inner (implementer)

- **Commit:** `892452a10` `feat: expose beacon access level and reasons` (body `issue-146 T07`; no scope prefix)
- **Files (6 in commit):** `hasura/metadata.json`, client schema/fragment/entity/mapper, new `beacon_access_hasura_test.dart`
- **RED/GREEN:** Hasura test failed on missing GraphQL fields pre-metadata; 2/2 green post. Parity 2/2. `build_runner` OK. Lints server 0/0, client 30/30.
- **Fixture notes:** Author case uses **eve/`beaconD`** (scout trap avoided). Forward case: no participant re-seed — `seedPublishedHierarchyTree` DELETE cascades B’s participant/help rows; dave gets forward edge only → mask **8**.
- **Next:** T07 verify

---

## T07 — verify (read-only)

- **Range reviewed:** `5f0e142f6e6179a9354b29987c7f583a0fd4c1fb..HEAD` — **single commit** `892452a10`, 6 files (+267/−1), no `m0170`/policy/UI/cubit/version bump ✓
- **Metadata:** `access_level` / `access_reasons` computed_field definitions match `can_read_linked_detail` shape (`function` + `session_argument: hasura_session` + `table_argument: beacon_row`); appended to `user` `computed_fields` after `can_read_involvement`; `filter` still `can_read_content: {_eq: true}` only ✓
- **Client:** `schema.graphql` Int fields + bool_exp/order_by; fragment after `can_read_involvement`; `BeaconAccessLevel? accessLevel`, `@Default(0) accessReasons`; import `package:tentura_root/domain/entity/beacon_access.dart` (same as `beacon_status`) ✓
- **UI wiring:** `grep accessLevel|accessReasons` under `packages/client` — only `beacon.dart` + `beacon_model.dart` ✓
- **Fixture correctness (read `beacon_hierarchy_fixture.dart` + test):** Eve owns D, no `_seedAdmissions` row for eve on D; after tree re-insert, cascades clear carol’s D offer/participant — author-only mask **1**. Dave on B: not owner/admitted/offerer; tree delete clears alice’s B offer; test INSERT bob→dave → **8** only ✓
- **Worktree integrity:** `git stash list` unchanged pattern (no new stash from T07); pre-existing modified tests still **+32** / **+54** line stats on router + constellation files ✓
- **TEST_CMD re-run (2026-09-16 verify):**

| Command | + | − | Failed | Exit | Notes |
|---|---|---|---|---|---|
| `beacon_access_hasura_test.dart` (`-t pg`) | 2 | 0 | 0 | 0 | 1st run: +2 −0 then `PathNotFoundException` on kernel copy (exit 255); immediate retry green |
| `beacon_hierarchy_hasura_parity_test.dart` (`-t pg`) | 2 | 0 | 0 | 0 | |
| `build_runner build -d` (client) | — | — | — | 0 | 0 outputs (current) |
| `check-custom-lints.sh packages/server` | — | — | 0 | 0 | total 0, baseline 0 OK |
| `check-custom-lints.sh packages/client` | — | — | 0 | 0 | total 30, baseline 30 OK |

- **Verdict:** **pass** — T07 “Done when” satisfied; proceed **T08+T09** (or journal commit).

## T07 — Inner (Opus 5)

- **Commit:** `892452a10` feat: expose beacon access level and reasons (body `issue-146 T07`; no scope prefix; server + client in one commit).
- **Files:** `hasura/metadata.json`, `C/data/gql/schema.graphql`, `C/data/gql/beacon_model.graphql`, `C/domain/entity/beacon.dart`, `C/data/model/beacon_model.dart`, `ST/api/beacon_access_hasura_test.dart` (new).
- **Red:** `beacon_access_hasura_test.dart` 0/2 — `field 'access_level' not found in type: 'beacon'` (validation-failed).
- **Green:** `beacon_access_hasura_test.dart` 2/2 (dave on B via bob→dave forward → 2/8/true; eve on D → 0/1/true; real user JWT). `beacon_hierarchy_hasura_parity_test.dart` 2/2. Client `build_runner build -d` OK (4571 outputs). `check-custom-lints.sh`: server 0 (baseline 0), client 30 (baseline 30).
- **Findings:**
  - Generated Freezed/Ferry output is gitignored (`packages/client/.gitignore`: `**.freezed.dart`, `**_g/`) → no generated diffs to commit.
  - The forward-recipient case needed no participant re-seed; `seedFullTopology` + `seedPublishedHierarchyTree` + the forward edge was enough.
  - Schema fields placed alphabetically before `address_label` in `type beacon` / `beacon_bool_exp` / `beacon_order_by`.
  - `dart analyze` on `beacon_model.dart` shows `dead_code`/`dead_null_aware_expression` on the existing `is_discoverable ?? true` line (not added by T07).
  - `BeaconAccessLevel.fromInt` already takes `int?`, so the mapper's null check is only there to keep `accessLevel` null (the plan's wording).
  - Operator slip: a `git stash -- <2 client files>` was run by mistake and popped right away; the working tree was restored before the commit, and no other stash entries were touched.

---

## T08+T09 — Scout (read-only)

- **UNIT_BASE:** `92c86b8a073825e846000445aacacebf29feb251` (= `HEAD` at scout time)
- **Task:** T08 ancestor closure + T09 context reasons / widened `beacon_can_read_content` — **one** `m0171`, **one** commit after all steps green
- **Scout brief:** see agent output in session (full STEPS/SQL/TEST_CMD for implementer)
- **Next (implementer):** Opus 5 low effort — follow brief; journal "T08 done, uncommitted" after closure tests only; single commit at end

---

## T08+T09 — Inner checkpoint

- **T08 done, uncommitted.** `m0171.dart` (closure statements only, one string each) registered; `beacon_ancestor_pg_test.dart` RED 0/4 (m0171 unregistered) → GREEN 4/4 (trigger closure, E under C, draft hard-delete cascade, backfill via `migrateDbSchemaThrough('0170')` + full migrate). Continuing with T09 in the same working tree.

---

## T08+T09 — Scout (escalation, read-only)

- **UNIT_BASE:** `92c86b8a073825e846000445aacacebf29feb251` (unchanged)
- **Trigger:** T09 step 10 performance gate failed after functional tests green; overseer escalated **diagnosis** (and safe `m0171`-only fix if exists) to Astra.
- **Repro:** `packages/server/test/zz_scratch_perf_146_pg_test.dart` (throwaway, uncommitted). Scout re-ran full scratch test 2026-09-16 (~5.5 min) — ratios match prior worker log.

### Measured (median, disposable DB, ~9.7k beacons, viewer `Uperf00001`)

| Metric | Before (≤0170) | After (m0171) | Ratio |
|---|---|---|---|
| predicate stranger@root | 0.711 ms | 1.720 ms | **2.42×** |
| predicate ctx-member@root | 0.699 ms | 3.193 ms | **4.57×** ( **> 2 ms** cap) |
| predicate stranger@grandchild | 1.183 ms | 2.029 ms | 1.72× |
| gql InboxFetch | 796.6 ms (301 rows) | 5225.2 ms (401 rows) | **6.56×** |
| sql InboxFetch.inbox_item | 785.8 ms | 5167.9 ms | **6.58×** |
| gql MyWorkInit | 829.3 ms | 3347.6 ms | **4.04×** |
| sql MyWorkInit.helpOfferedNonArchived | 693.8 ms | 2938.0 ms | 4.23× |

Hasura HTTP ≈ Postgres SQL for Inbox (6.56× vs 6.58×) — **not** Hasura-only overhead.

### Root cause (empirical)

1. **List queries evaluate `beacon_can_read_content` per candidate row, many times.** Hasura-generated Inbox SQL (after m0171) filters with  
   `beacon_can_read_content(id, viewer) AND beacon_can_read_content(id, viewer)` on the inbox→beacon join (**duplicate** predicate in one filter) over **901** inbox rows → ~**1.8k** function calls per Inbox fetch, plus more on nested beacon projections (`loops=401` on surviving rows).

2. **New `contextAncestor` / `contextChild` branches use `EXISTS (… FROM beacon_member m …)`.** `beacon_member` is a **three-way `UNION ALL` view** (author / steward / participant, each joining `beacon` with status/published/block predicates). In an **inlined** plan equivalent to m0171’s CASE (ctx-member @ `Bproot1`), `contextAncestor` becomes **SubPlan 11**: `Hash Join` between `beacon_ancestor` (20 rows for that root) and an **Append** of the three view branches. The **participant branch** does `Seq Scan on beacon` (~4.3k published rows) **hash-joined** to the viewer’s participant rows — even though only **~20 descendant beacon_ids** are relevant for that ancestor probe. That shape runs for **every** predicate evaluation that reaches the context clauses (including **strangers** and rows that ultimately fail earlier WHENs only after cheaper EXISTSs).

3. **Function-call opacity in isolation.** `EXPLAIN (ANALYZE) SELECT beacon_can_read_content(...)` shows a bare `Result` node (~1.7–3.2 ms) — little planner detail — but **inlined CASE** EXPLAIN confirms buffer growth (22 → 89–255 hits) and the `beacon_member` Append pathology above.

4. **Row count increase is real but not sufficient to explain 6×.** Inbox visible rows 301 → 401 (+33%); latency 6.6× ⇒ **per-evaluation cost** dominates.

5. **Indexes are not the primary gap.** `beacon_participant_user_beacon_idx (user_id, beacon_id)` exists (`m0114`); `beacon_ancestor_ancestor_idx (ancestor_id)` exists (m0171). The planner loses when membership is expressed through the **view** inside a per-row `EXISTS`, not for lack of a simple `(user_id)` index.

### Safe fix direction for Astra (behavior-identical; `m0171.dart` only)

- Rewrite **contextChild** / **contextAncestor** (and matching `beacon_access_reasons` CASE EXISTS blocks) to probe **base tables** with the **same semantics as `beacon_member`** (published, non-draft/deleted, `block_hides` on steward/participant paths) **without** referencing `public.beacon_member`.
- Prefer **ancestor-driven** shapes: `beacon_ancestor WHERE ancestor_id = <current beacon>` → for each `beacon_id` at most ~20 in fixture trees, **index nested loop** into `beacon_participant` / `beacon_steward` / author check on `beacon` — **not** viewer-wide membership Append × full-beacon seq scan.
- Keep `beacon_member` view **unchanged** (T11 `person_bond` depends on it).
- Do **not** mark `beacon_can_read_content` `IMMUTABLE`; stay `STABLE`.
- Re-run scratch gate + full unit pg list below; target **< 2×** list medians and **< 2 ms** single-row predicate (ctx-member case).

### Out of scope (note for overseer if SQL-only fix insufficient)

- Hasura **duplicate** `beacon_can_read_content` in Inbox filter (metadata/query shape) — would need client/metadata change, not m0171.
- Post-filter lateral work (e.g. SubPlan 7 ~10 ms × 401 rows on Inbox EXPLAIN after m0171) — investigate only if predicate rewrite alone misses 2× gate.

- **Next:** Astra inner on `m0171.dart` per escalation brief (session output).


---

## T08+T09 — Codex escalation: independent findings (2026-09-16)

Scope: only SQL in `m0171.dart` and append-only journal entries. No commit.
The pre-existing working tree was hashed before edits; original migration and
benchmark evidence are retained under `/tmp/issue146-*`.

### FINDINGS before any SQL rewrite — TEST_RED

Re-ran the unchanged `zz_scratch_perf_146_pg_test.dart` via the cleanup wrapper
against its disposable PostgreSQL/Hasura target. Its seed actually creates
**9,100 beacons**, 500 users and 10,800 closure rows (300 trees, 20 descendants
per root), rather than the earlier approximate 9,700. It prints the gate but
does not assert it: its process exited 0 despite these performance failures.

| Metric (median ms) | Through 0170 | Original 0171 | Ratio |
|---|---:|---:|---:|
| predicate stranger@root | 0.332 | 1.735 | 5.23x |
| predicate ctx-member@root | 0.330 | 3.220 | 9.76x; exceeds 2 ms |
| predicate stranger@grandchild | 0.360 | 1.722 | 4.78x |
| gql InboxFetch | 849.489 | 5427.516 | 6.39x |
| sql InboxFetch.inbox_item | 786.219 | 5457.168 | 6.94x |
| gql MyWorkInit | 832.964 | 3394.068 | 4.07x |
| sql MyWorkInit.authoredNonArchived | 117.577 | 410.161 | 3.49x |
| sql MyWorkInit.helpOfferedNonArchived | 698.839 | 3038.018 | 4.35x |
| sql MyWorkInit.archivedIdHints | 0.019 | 0.014 | 0.74x |
| sql MyWorkInit.obligationBeacons | 3.060 | 35.145 | 11.49x |

Independent `EXPLAIN (ANALYZE, BUFFERS)` on a restored disposable copy of that
fixture confirms and refines the scout's diagnosis:

- Expanded **unchanged** content CASE, warm run: contextAncestor **SubPlan 7**
  is a `Hash Join (cost=31.28..729.26, actual time=0.825..0.827, rows=1)`.
  Its membership `Append (cost=5.31..702.85)` emits 101 rows. The participant
  branch uses `Hash Join (cost=214.84..528.74, actual time=0.756..0.756)` over
  `Seq Scan on beacon b_5 (cost=0.00..289.75, actual time=0.002..0.455,
  rows=4301, loops=1, shared hit=73)`, while the closure side's
  `Bitmap Heap Scan (cost=4.34..25.88)` returns only **20** rows. The ancestor
  branch totals 94 buffer hits. Full expanded query: planning 3.731 ms,
  execution 2.675 ms. The opaque function's paired benchmark is the reliable
  gate measurement; this expanded plan exposes its internal work.
- Generated Inbox SQL: `Index Only Scan using beacon_pkey`, **loops=901**,
  filter literally contains `beacon_can_read_content(id, viewer) AND
  beacon_can_read_content(id, viewer)`. This is two predicate expressions,
  not necessarily 1,802 executions: boolean short-circuiting can skip the
  second call for rejected rows. Surviving rows remain **401**, vs 301 before.
- The Inbox nested projection **SubPlan 7 Result** costs `0.00..1.51` but
  takes **10.749 ms x 401 loops** (whole diagnostic query 6068.700 ms).
  Consequently the bitmask/level projection must be optimized together
  with the filter; duplicated filter calls alone do not explain the cost.
- Verified live indexes: `beacon_ancestor_ancestor_idx (ancestor_id)`,
  `beacon_participant_user_beacon_idx (user_id, beacon_id)`,
  `beacon_participant_unique_pair (beacon_id, user_id)`, and
  `beacon_steward_pkey (beacon_id)`. No missing lookup index is indicated.
- Line-by-line m0170 cross-check: all three membership branches require
  `status NOT IN (2, 3)` and `published_at IS NOT NULL`; author membership
  requires non-null owner and **has no block predicate**; steward and
  participant membership require `NOT block_hides(owner, member)`; only
  participant membership requires `(role = 1 OR room_access = 3)`.
  This author-vs-non-author distinction must be preserved in the rewrite.

Evidence: `/tmp/issue146-perf-before.log`,
`/tmp/issue146-explain-before-warm.log`, `/tmp/issue146-inbox-before.plan`.

### Fix and behavior preservation

Only the two access functions in m0171 changed. The eight closure statements
and the linked-detail alias are byte-identical to the incoming working tree.
No indexes, migration files, metadata, client, policy, repository, or test
changes were made; m0170 and its canonical `beacon_member` view are untouched.

1. Replaced each contextChild/bit-64 probe with a primary-key lookup of the
   immediate parent, and each contextAncestor/bit-128 probe with
   `beacon_ancestor WHERE ancestor_id = b.id` joined to the source beacon.
   Both functions use the same inline eligibility expression.
2. Source eligibility matches the three m0170 view branches: published and
   status neither 2 nor 3; non-null matching author, OR an unblocked matching
   `beacon_steward`, OR an unblocked matching participant with
   `role = 1 OR room_access = 3`. No participant status condition was added.
   The author branch remains outside the block predicate, exactly as in the
   canonical view. Target-beacon guards, CASE priority, bits 1–32, null/blank
   viewer handling and fallback values remain unchanged.
3. Used a CASE for the non-author branch so `block_hides` executes only after
   a matching steward/eligible participant exists. This changes evaluation
   work, not the boolean membership condition. Comments identify m0170 as
   canonical and require the two probes to remain in sync with it.
4. Changed only these two function bodies from SQL to PL/pgSQL
   `BEGIN RETURN COALESCE((SELECT ...), fallback); END`, retaining **STABLE**,
   signatures and default invoker security. PL/pgSQL reuses prepared query
   plans; no authorization results or membership data are cached. Both
   original and rewritten stable functions use the calling statement's
   snapshot and observe table changes in subsequent statements.

The direct-table rewrite alone was insufficient: the warmed diagnostic
context predicate was **1.325 ms**, but Inbox SQL remained **2837.697 ms**.
The same expressions with PL/pgSQL plan reuse reduced that Inbox diagnostic
median to **967.284 ms**, demonstrating a second cost beyond broad view
scans: repeated planning of the larger SQL function expressions.

The first full cached-plan benchmark brought Inbox SQL to 939.231 ms
(1.19x), My Work GraphQL to 516.153 ms (0.61x), and context-member@root to
0.325 ms, but **obligationBeacons still failed**: 2.837 → 6.514 ms (2.30x).
That failure motivated the explicit membership-before-block CASE in step 3;
no gate was waived. Evidence: `/tmp/issue146-perf-cached-before-conditional.log`.

### Functional baseline and final comparison — unchanged, but not all green

Every mandated functional file was run separately through the cleanup wrapper
**before any migration edit and after the final edit**. JSON reporter results
were compared by full test name, outcome, skipped flag, and failure message.
All nine files match exactly: **81 passed, 3 failed, 0 skipped** in each run.
Tests and assertion expectations are byte-identical to the incoming worktree.

| File | Before pass/fail | Final pass/fail |
|---|---:|---:|
| `beacon_ancestor_pg_test.dart` | 4/0 | 4/0 |
| `shared_context_visibility_pg_test.dart` | 9/0 | 9/0 |
| `beacon_hierarchy_visibility_pg_test.dart` | 14/0 | 14/0 |
| `beacon_hierarchy_hasura_parity_test.dart` | 2/0 | 2/0 |
| `beacon_access_level_parity_pg_test.dart` | 4/0 | 4/0 |
| `beacon_visibility_test.dart` | 32/0 | 32/0 |
| `beacon_access_sql_parity_test.dart` | 12/0 | 12/0 |
| `beacon_children_authorization_pg_test.dart` | 3/1 | 3/1 |
| `beacon_parent_reference_authorization_pg_test.dart` | 1/2 | 1/2 |

**Previously unreported acceptance blockers, reproduced on original m0171:**

- Child authorization: `stranger who cannot read the parent gets an empty
  page` fails `precondition: dave has no access to A` (expected false, true).
- Parent reference: `viewer who cannot read B gets no reference` fails
  `precondition: dave cannot read B` (expected false, true).
- Parent reference: `forward recipient of B with no path to A gets an
  unavailable reference` fails `precondition: dave has no path to A`
  (expected false, true).

These older T01/T02 tests explicitly use Dave, the **owner of descendant C**.
Under T09, published C makes Dave a canonical member and grants
contextAncestor access to both A and B. The preconditions are obsolete under
the already-implemented semantics. They fail identically with the original
view-based predicate and this rewrite. Fixing the fixture persona is outside
this session's edit scope; changing SQL to satisfy them would violate T09.
The child failure was also reproduced a second time before edits.

Additional rollback-only differential SQL on the disposable fixture compared
**345** source/viewer membership pairs against the live m0170 view and
**465** beacon/viewer pairs against separately named copies of the original
content/reasons functions: **zero membership, content, or reason-mask
mismatches**. The matrix includes all eight statuses, published/unpublished
sources, authors, steward-table rows, participant role/admission combinations,
blocked members, outsiders and null/blank/missing viewers. Live `pg_proc`
reports `provolatile = s` for both rewritten functions and the SQL alias.
Evidence: `/tmp/issue146-equivalence-final.log`,
`/tmp/issue146-test-comparison.json`, `/tmp/issue146-{before,after}-tests/`.

Infrastructure notes: the initial closure baseline setup hit the recorded
`RaceCondition` and teardown cascade; the serial rerun passed. The legacy
SQL parity test requires actual pgmer2 and cannot bootstrap over the perf
fixture's stub functions; it was run against its own disposable database
with `POSTGRES_DBNAME` bound, real pgmer2, and current migration functions.
Neither setup problem was treated as a functional assertion result.

Mandatory `check-custom-lints.sh packages/server` passed through the cleanup
wrapper: custom diagnostics **0**, baseline **0**, exit 0 (existing analyzer
info output remains). Its log is `/tmp/issue146-lints.log`.

---

## T08+T09 — Overseer: closing the escalation and committing

Astra's `codex` run hit its usage quota just after finishing the fix and the
equivalence audit, mid-way through re-running the "after" list-query
benchmark (its process exit showed `ERROR: You've hit your usage limit`, not
a functional failure). Per the skill's "unavailable escalation" handling I
did not retry it; I picked up verification directly myself rather than
spinning the Opus-high substitute, since the remaining work was mechanical
(re-run the full test/perf suite, review the diff, decide on the one
genuine gap Astra flagged as out of its scope).

**1. Independent review of Astra's `m0171.dart` rewrite.** Read the full
file. The `contextChild`/`contextAncestor` `WHEN` clauses in both
`beacon_can_read_content` and `beacon_access_reasons` now probe the specific
parent/ancestor `beacon` row directly (`member_beacon.id = b.parent_beacon_id`,
or via `beacon_ancestor a JOIN beacon member_beacon ON member_beacon.id =
a.beacon_id WHERE a.ancestor_id = b.id`) instead of going through the
`beacon_member` view's unrestricted 3-branch `UNION ALL`. The inline
eligibility condition — `member_beacon.status NOT IN (2, 3) AND
member_beacon.published_at IS NOT NULL AND (author-with-no-block-check OR
(steward-or-participant AND NOT block_hides(owner, viewer)))` — matches
`beacon_member`'s three branches exactly (confirmed by reading m0170.dart
side by side). Both functions changed from `LANGUAGE sql` to `LANGUAGE
plpgsql` (`BEGIN RETURN COALESCE((SELECT ...), fallback); END`), staying
`STABLE`; this is what let Postgres reuse the prepared query plan across the
~900 per-row invocations in a single Hasura list query instead of
re-planning the large CASE expression every time — the second, larger cost
component Astra's own measurements isolated (the direct-table rewrite alone
only got Inbox to 2837ms; adding PL/pgSQL plan reuse got it to 967ms, and
the final CASE-before-block ordering got `obligationBeacons` back under
budget too). `beacon_member` itself (m0170.dart) and the linked-detail alias
are untouched. Astra's own 345+465-pair differential SQL audit against the
live view and against copies of the original functions found zero
membership/content/reason-mask mismatches across every status, block, and
role combination — I did not re-run that audit myself, but re-ran the full
functional suite below as an independent check.

**2. A genuine gap Astra correctly flagged but was out of scope to fix.**
Astra's own re-run reproduced 3 failures that predate its session (present
on the *original*, unoptimized m0171 too — this is a consequence of T09's
widening itself, not of any SQL rewrite):
`beacon_children_authorization_pg_test.dart` › "stranger who cannot read the
parent gets an empty page", and
`beacon_parent_reference_authorization_pg_test.dart` › "viewer who cannot
read B gets no reference" and "forward recipient of B with no path to A
gets an unavailable reference". Root cause: these T01/T02 tests (already
committed in earlier units) use `daveId` as their "stranger" persona. Dave
owns beacon C — a descendant of both A and B — so once T09's contextAncestor
grant lands, dave is no longer a stranger to A or B; he's a legitimate
context observer of both. Worse, on inspection every other persona in the
6-user `BeaconHierarchyTopology` fixture (alice/bob/carol/dave/eve/frank)
also ends up connected to the A/B/C/D tree once the full fixture setup runs
(carol is admitted to C, eve owns D, frank has a help offer on A) — there is
no persona left in the shared fixture who is a genuine stranger to the whole
tree once T09 lands.

**Fix (overseer, direct — small, local, unambiguous):** added a freshly
seeded 7th user (`Uhierstranger`, via `pgTestPublicKey('stranger', 1)` —
note the namespace must map to a distinct 2-char tag from the existing
`'bhier'` users, an early attempt with `'bhierstr'` collided on
`user_public_key_key` because `pgTestPublicKey` only hashes the first two
characters of the namespace) who is never seeded into any admission,
authorship, forward, steward, or help-offer relationship, in both affected
test files. Replaced every use of `daveId` in the three broken assertions
with this new persona (`beacon_children_authorization_pg_test.dart`'s single
stranger test; `beacon_parent_reference_authorization_pg_test.dart`'s two
tests, via a shared local `seedStranger()` helper). Left every other use of
`daveId` in both files untouched (e.g. the deleted-tombstone visibility test
in T01, which doesn't depend on dave being a stranger). Re-ran both files
after the fix: all green (T01 4/4, T02 3/3).

**3. Final independent verification (overseer, all commands re-run
directly, each `-t pg` file its own invocation per the T00 flake note):**

| File | Result |
|---|---|
| `beacon_ancestor_pg_test.dart` | 4/4 (+ the backfill-predates-migration case) |
| `shared_context_visibility_pg_test.dart` | 9/9 (one setUpAll flake, clean retry) |
| `beacon_hierarchy_visibility_pg_test.dart` | 14/14 |
| `beacon_hierarchy_hasura_parity_test.dart` | 2/2 |
| `beacon_access_level_parity_pg_test.dart` | 4/4 (one setUpAll flake, clean retry) |
| `beacon_visibility_test.dart` (unit) | 32/32 |
| `beacon_access_sql_parity_test.dart` (regression) | 12/12 |
| `beacon_children_authorization_pg_test.dart` (T01 regression) | 4/4 after the stranger fix (one flake, clean retry) |
| `beacon_parent_reference_authorization_pg_test.dart` (T02 regression) | 3/3 after the stranger fix |
| `check-custom-lints.sh packages/server` | 0 vs baseline 0, OK |

**4. Final performance gate (overseer, re-ran the scratch benchmark after
the stranger-persona fix, since that fix only touched test files, not
`m0171.dart` — confirming the gate numbers are unaffected):**

| Metric | Before (≤0170) | After (final m0171) | Ratio | Gate |
|---|---:|---:|---:|---|
| predicate stranger@root | 0.358 ms | 0.297 ms | 0.83x | PASS |
| predicate ctx-member@root | 0.332 ms | 0.529 ms | 1.59x | PASS (well under 2ms cap) |
| predicate stranger@grandchild | 0.333 ms | 0.356 ms | 1.07x | PASS |
| gql InboxFetch | 827.8 ms | 889.3 ms | 1.07x | PASS |
| gql MyWorkInit | 847.9 ms | 512.3 ms | 0.60x | PASS (faster than baseline) |

All ratios are well inside the plan's 2x/2ms budget. The scratch benchmark
file (`test/zz_scratch_perf_146_pg_test.dart`) was throwaway per the plan's
own instruction and has been deleted; these numbers are the durable record.

**Escalation-sandwich summary:** routine Opus-low inner → correctly stopped
at the mandatory performance gate without committing → user chose to
escalate → Astra (codex, GPT-6) diagnosed the root cause independently with
EXPLAIN evidence, rewrote the two SQL functions to avoid `beacon_member`
view expansion and gain PL/pgSQL plan-cache reuse, proved behavior
equivalence with an 810-pair differential audit, then exhausted its usage
quota mid-verification → overseer completed verification directly, found
and fixed one additional pre-existing-but-newly-exposed test gap (T01/T02's
"stranger" persona), and confirmed the final numbers. No Opus-high
substitute was needed since Astra's own work was already complete and
independently verifiable.

**Commit:** `feat(server): hierarchy context grants observer access (issue #146)`,
body `issue-146 T08+T09`.

---

## T10 — Scout (read-only)

- **UNIT_BASE:** `2451f3c15fa0327cec4a19ae51a129decb2c957c` (= `HEAD` at scout time)
- **Task:** T10 — hierarchy endpoints use unified `beacon_can_read_content`; drop linked-detail SQL/Dart/Hasura

### Migration slot

| Check | Result |
|---|---|
| `m0172.dart` on disk | **Absent** — free for T10 |
| `m0173.dart` on disk | **Absent** — reserved for T11 (do not touch) |
| `_allMigrations` tail | `m0170`, `m0171` only |

### Live `beacon_hierarchy_repository.dart` linked-detail call sites (replace → `beacon_can_read_content`)

| Location | Current |
|---|---|
| `listChildren` L77 | `SELECT public.beacon_can_read_linked_detail($1, $2)` parent preflight |
| `listChildren` L112 | `public.beacon_can_read_linked_detail(b.id, $viewer)` per non-deleted child |
| `loadParentReference` L210 | `_predicate('beacon_can_read_linked_detail', parentId, viewerId)` (child gate already `beacon_can_read_content` @ L194–198) |

`loadCapabilities` (L37–59): still calls only `_loadAdmissionFacts` + `resolveCapabilities` — **no** `viewerCanReadParentContent` yet.

### Capabilities policy delta

`BeaconHierarchyCapabilityFacts` (`beacon_hierarchy_policy.dart` L51–61): add `required bool viewerCanReadParentContent`.

`resolveCapabilities` (L126–172): **reorder** — plan requires **draft** and **deleted** checks **before** the non-admitted branch. Today non-admitted is first (L129–134). New non-admitted return: `canListChildren: facts.viewerCanReadParentContent`, `canCreateChild: false`, `denialCode: notAdmitted`. Admitted path (L158–171) unchanged.

`beacon_hierarchy_policy_test.dart` L194–204: rename/extend **`non-admitted viewer cannot list or create`** → observer with `viewerCanReadParentContent: true` lists but cannot create.

### Linked-detail Dart deletion targets

| File | Remove |
|---|---|
| `beacon_visibility.dart` | `BeaconLinkedDetailVisibilityFacts`, `BeaconVisibility.canReadLinkedDetail` (L71–157) |
| `beacon_access_guard.dart` | `canReadLinkedDetail` |
| `beacon_access_repository.dart` | `canReadLinkedDetail` override |

`beacon_visibility_test.dart`: **no** `LinkedDetail` references (T09 covers content grants).

### Policy dead code (plan step 4)

| Symbol | `packages/server/lib` callers after linked-detail removal |
|---|---|
| `isAdmittedToImmediateParent` / `isAdmittedToImmediatePublishedChild` | **None** (only `beacon_visibility.dart` linked-detail path today) → **delete methods** + `BeaconImmediateParentLinkFacts` / `BeaconImmediateChildLinkFacts` if unused, and policy tests in group `A/B/C/D topology one-edge reads` (L77–190) |
| `resolveParentReference` / `BeaconParentReferenceFacts` | **None** in `lib/` (repo uses SQL since T02) — **not** named in T10 delete list; optional leave or delete with L231–262 tests only if worker wants zero dead policy |

### Client / schema

- `grep -rn can_read_linked_detail packages/client/lib --include='*.graphql' --include='*.dart' | grep -v _g/` → **empty** (no client selects field).
- `packages/client/lib/data/gql/schema.graphql` → **already has no** `can_read_linked_detail` (noop for step 4a schema edit; still run grep after codegen if touched).
- Client hierarchy UI: `canListChildren` / `canCreateChild` only in `beacon_hierarchy_cubit.dart`, `beacon_hierarchy_state.dart`, `beacon_child_requests_section.dart`, `beacon_hierarchy_repository.dart`, `beacon_hierarchy_capabilities.graphql` — **no surprises**; no client code changes expected.

### Hasura + SQL drop

- `hasura/metadata.json` L217–227: remove `can_read_linked_detail` computed_field; post-edit `grep -n can_read_linked_detail hasura/metadata.json` must be empty.
- `m0172.dart`: DROP `beacon_get_can_read_linked_detail(beacon, json)` and `beacon_can_read_linked_detail(text, text)`; register in `_migrations.dart` after `m0171`.
- History retained in `m0155`, `m0171` (comments/SQL); live DB drops in m0172.

### Server test files referencing `linked_detail` / `LinkedDetail` (all must update or drop)

**Production-adjacent / pg / api**

1. `test/data/repository/beacon_children_authorization_pg_test.dart` — precondition SQL fn name L130
2. `test/data/repository/beacon_parent_reference_authorization_pg_test.dart` — L190
3. `test/data/repository/beacon_hierarchy_visibility_pg_test.dart` — `access.canReadLinkedDetail` L197 (assert `canReadContent` only or drop redundant expect)
4. `test/data/repository/issue_145_stale_child_invite_pg_test.dart` — local helper + expectations L95–96, 180, 262, 284 → `canReadContent` on parent
5. `test/api/beacon_hierarchy_hasura_parity_test.dart` — metadata test L116–147: stop expecting `can_read_linked_detail` in computed_fields set
6. `test/api/beacon_hierarchy_graphql_contract_test.dart` — comment L291 only

**Unit / policy**

7. `test/domain/beacon_hierarchy_policy_test.dart` — capabilities test L194+; delete groups `A/B/C/D topology one-edge reads` (L77–190), `BeaconVisibility linked detail does not widen…` (L363–393); keep tombstone test L395+
8. `test/domain/beacon_lineage_visibility_test.dart` — test name mentions `canReadLinkedDetail` (L34); body likely fine — update name/comment only

**Support / mocks (regenerate after guard API change)**

9. `test/support/fake_beacon_access_guard.dart` — remove `linkedDetailAllowed` + method
10. `test/support/block_aware_beacon_access_guard.dart` — remove override
11. `test/domain/use_case/beacon_case_fork_media_test.dart` — `_AllowGuard.canReadLinkedDetail`
12. `test/domain/use_case/forward_band_case_mocks.mocks.dart` — **regen** via `dart run build_runner build -d` in `packages/server`

**Migrations (do not edit except new m0172)**

- `lib/data/database/migration/m0155.dart`, `m0170.dart`, `m0171.dart` — historical references only

### Implementer brief (Opus, low effort)

**One commit:** `refactor: hierarchy reads use the unified content predicate; drop linked-detail`

1. **Test-first:** `beacon_hierarchy_policy_test.dart` — observer `viewerCanReadParentContent: true`, not admitted → `canListChildren` true, `canCreateChild` false.
2. **Policy + repo:** `viewerCanReadParentContent` on facts; `resolveCapabilities` reorder; `loadCapabilities` calls `_predicate('beacon_can_read_content', parentBeaconId, viewerId)`.
3. **Repo SQL:** three `linked_detail` → `beacon_can_read_content` in `listChildren` + `loadParentReference`.
4. **Delete** linked-detail Dart API; strip test support/mocks; `build_runner -d` in server.
5. **`m0172` + metadata**; fix all 12 test paths above; pg tests use `beacon_can_read_content` in SQL preconditions where they used `beacon_can_read_linked_detail`.
6. **Delete** `isAdmittedToImmediateParent` / `isAdmittedToImmediatePublishedChild` (+ fact classes if orphaned) per plan step 4.
7. Locally: migrate then `./scripts/hasura_apply_metadata.sh`.

**TEST_CMD:**

```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test test/domain/beacon_hierarchy_policy_test.dart test/domain/beacon_visibility_test.dart
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 45m -- dart test -t pg test/data/repository/beacon_children_authorization_pg_test.dart test/data/repository/beacon_parent_reference_authorization_pg_test.dart test/data/repository/beacon_hierarchy_visibility_pg_test.dart test/api/beacon_hierarchy_hasura_parity_test.dart test/api/beacon_hierarchy_graphql_contract_test.dart test/data/repository/issue_145_stale_child_invite_pg_test.dart
../../scripts/run_with_test_cleanup.sh --timeout 10m -- ./scripts/check-custom-lints.sh packages/server
grep -rn 'linked_detail\|LinkedDetail' packages/server/lib packages/server/test hasura/metadata.json | grep -v m0155 | grep -v m0171 || true
```

- **Next:** T10 implementer (Opus low)

---

## T10 — inner (implementer, Composer 2.5 substitute) — done

- **UNIT_BASE:** `2451f3c15fa0327cec4a19ae51a129decb2c957c`
- **Substitute:** Opus 5 inner layer hit usage limit after partial TDD red on `beacon_hierarchy_policy_test.dart`; continued from that checkpoint.
- **Commit:** `ffc232a3f` — `refactor: hierarchy reads use the unified content predicate; drop linked-detail` (body `issue-146 T10`).

### Changes

- `BeaconHierarchyCapabilityFacts.viewerCanReadParentContent`; `resolveCapabilities` runs draft/deleted before non-admitted; observers list, cannot create.
- `loadCapabilities` + hierarchy SQL/parent-reference gates use `beacon_can_read_content` only.
- Removed `canReadLinkedDetail` / `BeaconLinkedDetailVisibilityFacts` / one-edge admission helpers from policy.
- `m0172` drops linked-detail SQL; Hasura `can_read_linked_detail` computed field removed.

### Tests (wrapped `dart test`)

| Suite | Result |
|---|---|
| `beacon_hierarchy_policy_test.dart` + `beacon_visibility_test.dart` | 45 passed |
| `beacon_children_authorization_pg_test.dart` | 4 passed |
| `beacon_parent_reference_authorization_pg_test.dart` | 3 passed |
| `beacon_hierarchy_visibility_pg_test.dart` | 14 passed |
| `beacon_hierarchy_hasura_parity_test.dart` | 2 passed |
| `beacon_hierarchy_graphql_contract_test.dart` | 12 passed (split capabilities: context observer vs inserted stranger) |
| `issue_145_stale_child_invite_pg_test.dart` | 2 passed |
| `check-custom-lints.sh packages/server` | OK |

### Notes

- Client `grep can_read_linked_detail` on `packages/client/lib` → empty.
- Post-T10 `grep linked_detail\|LinkedDetail` still hits `parentLinkedDetailAuthorized` on dead `resolveParentReference` facts (out of scope rename), `m0172` DROP strings, and parity negative assertion — not live linked-detail API.
- **Next:** T11 implementer

---

## T10 — verify (read-only overseer)

- **Range:** `2451f3c15fa0327cec4a19ae51a129decb2c957c..efac89367` (`ffc232a3f` impl, `efac89367` journal)
- **Worktree:** clean for T10 paths; pre-existing dirty files unchanged (`.serena/project.yml`, two client tests, untracked docs/keys per T00 list).

### Code review (spot-check)

| Check | Result |
|---|---|
| `resolveCapabilities` order | draft → deleted → non-admitted (`canListChildren: viewerCanReadParentContent`) → blocked → admitted path unchanged ✓ |
| `beacon_hierarchy_repository.dart` | All three SQL gates use `beacon_can_read_content`; `loadCapabilities` passes `viewerCanReadParentContent` from `_predicate` ✓ |
| Dart linked-detail API | Gone from `lib/` (`grep canReadLinkedDetail` / `isAdmittedToImmediate*` empty) ✓ |
| `m0172` | Two `DROP FUNCTION` statements only; `_migrations.dart` registers `m0172`; `m0155`/`m0170`/`m0171` byte-unchanged ✓ |
| `hasura/metadata.json` | Only removal of `can_read_linked_detail` computed_field block; `grep -n can_read_linked_detail` empty ✓ |
| Contract personas | **eve:** author of published child **D** under **A**, not in `_seedAdmissions` for A → T09 context-ancestor read on A, not admitted → list true / create false ✓. **Uhierstranger:** fresh `INSERT` user, no tree edges → `canListChildren` false ✓ (same rigor as T08+T09 stranger fix) |
| Commits | Impl commit message matches plan; journal-only second commit ✓ |

### Tests re-run (independent)

| Command | Result |
|---|---|
| `beacon_hierarchy_policy_test.dart` + `beacon_visibility_test.dart` | **45/45** passed |
| `beacon_children_authorization_pg_test.dart` `-t pg` | **4/4** passed |
| `beacon_parent_reference_authorization_pg_test.dart` `-t pg` | **3/3** passed |
| `beacon_hierarchy_visibility_pg_test.dart` `-t pg` | **14/14** passed |
| `beacon_hierarchy_hasura_parity_test.dart` `-t pg` | **2/2** passed |
| `beacon_hierarchy_graphql_contract_test.dart` `-t pg` | **12/12** passed |
| `issue_145_stale_child_invite_pg_test.dart` `-t pg` | **2/2** passed |
| `check-custom-lints.sh packages/server` | **0 vs baseline 0**, OK |

### Grep residual

`grep -rn 'linked_detail\|LinkedDetail' packages/server/lib packages/server/test hasura/metadata.json` → only `m0155`/`m0170`/`m0171` history, `m0172` DROP lines, dead `parentLinkedDetailAuthorized` + its unit tests, parity `isNot(contains('can_read_linked_detail'))`. No production linked-detail consumers.

- **Verdict:** **pass** — T10 acceptance met; ready for T11.

---

## T11 — Scout (read-only)

- **UNIT_BASE:** `56da48c2bea2896ec9f238ccb720d2d7082ddbe7` (= `HEAD` at scout time; matches overseer `UNIT_BASE`)
- **Task:** Bond SQL (`m0173`) + `PersonVisibilityRepositoryPort` widen + `ForwardCase` / `ForwardCandidatesCase` + `UserPublicRecord` / GQL field `shares_active_context` + pg/unit tests (S4-12, S4-13)
- **Migration slot:** `m0173.dart` **absent** on disk; `_allMigrations` ends at `m0172` — **next free = m0173** ✓
- **Scout brief:** see agent output in session (full SQL verbatim, STEPS, TEST_CMD, RISKS for Opus 5 implementer)
- **Live-code notes:**
  - `ForwardCase` recipient gate at **line 236–246** uses `mutuallyVisiblePeerIds`; already injects `PersonVisibilityRepositoryPort` — switch call only.
  - `ForwardCandidatesCase` has **no** `PersonVisibilityRepositoryPort`; constructor is `(ForwardCandidatesRepositoryPort, UserProfileBatchLookup)` — **DI + `build_runner` required**. **Bug:** `if (peers.isEmpty) return const []` at lines 34–36 must not run before bond merge (bond-only picker case).
  - `ForwardCandidatePeerRow` constructor confirmed: `peerId`, `forwardMr`, `reverseMr`, `viewerTrusts`, `trustsViewer` (all required).
  - `kForwardCandidatesWrapSql` stays trust-only (`person_are_mutually_visible`) — correct per D4; bond merge is Dart-only in the case.
  - Plan lists `forward_candidates_repository_port.dart` / `forward_candidates_repository.dart` in Files header but **no Dart edits** in task body — leave unchanged unless implementer discovers a gap.
- **Next (implementer):** Opus 5 low effort — follow brief; commit `feat(server): co-participant bond widens person visibility for forwarding`

---

## T11 — Verify (read-only)

- **UNIT_BASE:** `56da48c2bea2896ec9f238ccb720d2d7082ddbe7` → **commit:** `a3adbd47d` (`feat(server): co-participant bond widens person visibility for forwarding`, body `issue-146 T11`)
- **Scope:** `git show a3adbd47d --name-only` → **20 files**, all under `packages/server/`; **no** `packages/client/`; **no** diff on `m0170.dart` / `m0171.dart` vs `56da48c2..a3adbd47d`
- **SQL:** `m0173.dart` bodies match plan verbatim (`person_bond`, `person_bond_peers`, `person_shared_contexts`; status `IN (0, 5, 7, 8)`); registered as `m0173` after `m0172` in `_migrations.dart`
- **D4 / S4-13:** `person_bond_pg_test.dart` — bonded viewer+author on shared open request; unrelated beacon `is_discoverable: true`, `published_at`, status 0; `vote_user` cleared in `setUp`; asserts `person_are_mutually_visible` false, `beacon_can_read_content` false, `beacon_access_reasons & 32 = 0`; control that shared beacon stays readable ✓
- **Use cases:** `ForwardCase` recipient gate → `personVisiblePeerIds` only (plus unrelated one-line logger format in `_logForwardBandConversion`); `ForwardCandidatesCase` fetches bond after trust, merges bond-only rows, early return only when **both** lists empty; `sharesActiveContext` via `_withSharedContext` for all `bondPeerIds` ✓
- **§6.2 deferred:** `capability_projection_case.dart` unchanged; still `mutuallyVisiblePeerIds`; mock file regen only for new port methods
- **DI:** `di.config.dart` gitignored (`**.config.dart`); worktree has `PersonVisibilityRepositoryPort` wired into `ForwardCandidatesCase` (local `build_runner` expected)
- **Inner FINDINGS confirmed:** `beacon_member` author↔participant block drops helper membership → bond with other members ends (T06 semantics); first pg failure was test expectation, not SQL

### Tests re-run (independent)

| Command | Result |
|---|---|
| `person_bond_pg_test.dart` `-t pg` | **9/9** passed (1st run: all green then exit **255** kernel-copy flake; after `--sweep-only` retry: **9/9**, exit **0**) |
| 5 named unit files `--exclude-tags pg` | **76/76** passed |
| `person_visibility_repository_pg_test.dart` `-t pg` | **3/3** passed |
| `check-custom-lints.sh packages/server` | **0 vs baseline 0**, OK |

- **Verdict:** **pass** — T11 “Done when” satisfied; proceed **T12**.

---

## T11 — inner (Claude Opus 5)

- **UNIT_BASE:** `56da48c2bea2896ec9f238ccb720d2d7082ddbe7` → **commit `a3adbd47d`** `feat(server): co-participant bond widens person visibility for forwarding` (body `issue-146 T11`). Not pushed.
- **Done:** `m0173` (`person_bond`, `person_bond_peers`, `person_shared_contexts`, verbatim SQL) registered after `m0172`; `PersonVisibilityRepositoryPort` + impl gain `bondPeerIds` / `personVisiblePeerIds` (trust ∪ bond) / `sharedContexts`; `ForwardCase` recipient gate → `personVisiblePeerIds` (message unchanged); `ForwardCandidatesCase` injects the port, drops the pre-bond early return, appends bond-only zero-MR rows after the unchanged trust rows, flags every bonded peer `sharesActiveContext`; `UserPublicRecord.sharesActiveContext` (default false); nullable GQL `shares_active_context` + mapper. `build_runner` run (DI + mocks).
- **Untouched (D4):** `m0170`/`m0171`, `person_are_mutually_visible`, `person_visible_peers_symmetric`, `constellation_trust_edges`, `forward_candidates_sql.dart`, `CapabilityProjectionCase._canViewSubject`. No T12 query.
- **Red:** unit files failed to load (missing `personVisiblePeerIds` / 3rd ctor arg) before implementation.
- **Green:**
  - `person_bond_pg_test.dart -t pg` **9/9** (S4-12 lifetime/leave/block/symmetry/peers parity/shared contexts cap 20; S4-13 D4 proof: bonded viewer cannot read author's discoverable unrelated request, bit 32 = 0)
  - unit set (forward_candidates_case, forward_case, forward_case_auth, query_forward_candidates, gql_public_user_maps) **76/76**; plus forward_delivery_result, forward_band_case, capability_projection_case in a wider run **100/100**
  - `person_visibility_repository_pg_test.dart -t pg` **3/3**; `forward_reason_reconciliation_pg_test` + `beacon_hierarchy_visibility_pg_test` **23/23**
  - `check-custom-lints.sh packages/server` **0 vs baseline 0**
- **Findings:**
  - `beacon_member` drops a participant when a block exists between that participant and the request author, so an author↔helper block also ends the helper's bond with every other member of that request. The first pg run failed on my hard-coded expectation; I corrected the fixture expectation (SQL unchanged).
  - `UserPublicRecord` has no `copyWith`; the case rebuilds flagged records via a private `_withSharedContext`.
  - ForwardCase-path stubs/fakes renamed to `personVisiblePeerIds` in `forward_case_auth_test`, `forward_case_test`, `beacon_hierarchy_visibility_pg_support`, `forward_reason_reconciliation_pg_test`, `forward_delivery_result_test`; capability-projection stubs stay on `mutuallyVisiblePeerIds`.
  - This journal update is left uncommitted (single-commit brief; hash only known after commit).
- **Next:** T11 verify

---

## T12 — Scout (read-only)

- **UNIT_BASE:** `1267d2589ed17d440f0066e836bf6dc254ec13f5` (= `HEAD` at scout time; T11 journal commit on branch)
- **Task:** V2 root query `personSharedContexts` — `PersonContextCase` + `QueryPersonSharedContexts` + `gqlTypePersonSharedContext`; no SQL/repo changes (T11 `sharedContexts` port method is the data source)
- **Template:** `QueryBeaconHierarchy.beaconParentReference` (constructor optional port/case + `GetIt.I<>`, `InputFieldString` arg, `getCredentials(args).sub`, `GraphQLObjectField` on `all` getter) — but **separate file** per plan (`query_person_shared_contexts.dart`), list return type like `QueryMutualFriends.mutualFriends`
- **Contract test:** **not** `beacon_hierarchy_graphql_contract_test.dart` style (`@Tags(['pg'])`, real Postgres). Plan step 4 = schema exposure + resolver with **mocked** `PersonContextCase` → follow `user_block_graphql_test.dart` / `query_capability_projection_test.dart` (no `pg` tag, `--exclude-tags pg`)
- **Port signature (T11):** `Future<List<({String beaconId, String title})>> sharedContexts({required String viewerId, required String peerId})`
- **Resolver self-view:** return `[]` when `viewerId == userId` **before** calling case (repo also returns `[]` for self, but plan requires resolver guard)
- **Next:** T12 implementer (Opus 5 low) — full brief in scout session output

---

## T12 — Verify (read-only)

- **Range:** `1267d2589ed17d440f0066e836bf6dc254ec13f5..70b34aabd` (`feat(server): personSharedContexts query`, body `issue-146 T12`)
- **Commit scope:** 5 files only — `person_context_case.dart`, `query_person_shared_contexts.dart`, `_queries_all.dart`, `custom_types.dart`, `person_shared_contexts_graphql_contract_test.dart`; **no** `packages/client/`, migrations, Hasura, or T11 port/repo paths in diff
- **Resolver:** `viewerId == peerId` → `return const <Map<String, String>>[]` **before** `_personContextCase.sharedContexts` (`query_person_shared_contexts.dart` L27–31)
- **GraphQL:** `[PersonSharedContext!]!` via `GraphQLListType(gqlTypePersonSharedContext.nonNullable()).nonNullable()`; maps use `beaconId` / `title`
- **Case:** thin delegate to `PersonVisibilityRepositoryPort.sharedContexts` only
- **Contract test:** no `@Tags(['pg'])`; fake port + real case; self → empty + `port.calls` empty; peer → mapped list + `(viewerId: 'viewer', peerId: 'peer')`
- **custom_types.dart:** unrelated reflows on `gqlTypeConstellationAnchorProjection` / `gqlTypeBeaconHierarchyPage` are formatting-only (confirmed in `git show` diff)

### Tests re-run (independent)

| Command | Result |
|---|---|
| `dart run build_runner build -d` (server) | exit **0** |
| `dart test --exclude-tags pg test/api/person_shared_contexts_graphql_contract_test.dart` | **4/4** passed |
| `check-custom-lints.sh packages/server` | **0 vs baseline 0**, OK |

- **Verdict:** **pass** — T12 “Done when” satisfied; proceed **T13**.

---

## T12 — inner (Claude Opus 5)

- **UNIT_BASE:** `1267d2589` → **commit `70b34aabd`** `feat(server): personSharedContexts query` (body `issue-146 T12`). Not pushed.
- **Done:** `PersonContextCase` (`@Injectable(order: 2)`, wraps `PersonVisibilityRepositoryPort.sharedContexts`); `QueryPersonSharedContexts` (`[PersonSharedContext!]!`, `userId: String!`, self → `[]` without calling the case); `gqlTypePersonSharedContext` in `customTypes` after `gqlTypePersonFriendContext`; registered in `_queries_all.dart`. `build_runner` run (DI, gitignored).
- **Red:** new contract test failed to load (missing files).
- **Green:** `person_shared_contexts_graphql_contract_test.dart --exclude-tags pg` **4/4**; `check-custom-lints.sh packages/server` **0 vs baseline 0**.
- **Findings:** `PersonContextCase` is a `final class`, so the test can't subclass it; it builds a real case over a hand-written fake port (`implements` + `noSuchMethod`) that records calls. `dart format` also re-wrapped some existing lines in `custom_types.dart`; these are layout-only changes.
- **Next:** T12 verify

---

## T13 — Scout (read-only)

- **UNIT_BASE:** `3c59d6c5e10cdd4247a48abe7376cac4cfbeb97f` (= `HEAD` at scout time; T12 commit `70b34aabd` on branch)
- **Server contract (T11/T12, do not edit):** V2 `user.shares_active_context` (nullable bool); root `personSharedContexts(userId: String!): [PersonSharedContext!]!` with `{ beaconId, title }`; self → `[]`.
- **Client `schema.graphql` (hand-add until next Hasura fetch):** insert `personSharedContexts(userId: String!): [v2_PersonSharedContext!]!` on `query_root` next to `personFriendContextBatch` (~5087); add `type v2_PersonSharedContext { beaconId: String! title: String! }` near other `v2_` types (~7850); add `shares_active_context: Boolean` on `type v2_user` (currently ends at `user_presence` — no field yet). **Stitching:** server type `PersonSharedContext` → client `v2_PersonSharedContext` (single prefix; contrast `v2_PersonFriendContext` server name → `v2_v2_PersonFriendContext` in schema). Do **not** use `v2_v2_` for PersonSharedContext.
- **Direct V2 routing:** add `'PersonSharedContexts'` to `_tenturaDirectOperationNames` after `'PersonFriendContextBatch'` (~320); operation name must match `.graphql` `query PersonSharedContexts`.
- **Port/repo template:** `ForwardCandidateContextRepository` + port (`@LazySingleton(as: Port)`); plan asks `@Singleton(as: PersonSharedContextPort)` on `person_shared_context_repository.dart`. `MutualFriendsRepository` shows Ferry `request` + `dataOrThrow` shape but no port. Return type `List<({String beaconId, String title})>` from port method (name implementer choice, e.g. `fetchSharedContexts(String userId)`).
- **`ProfileViewCase.load`:** mirror subjectiveTags best-effort — `var sharedContexts = …`; `try { sharedContexts = await _port… } catch (_) {}`; extend typedef `ProfileViewSnapshot` + `ProfileViewState`/`ProfileViewCubit.fetch` emit path with `sharedContexts`.
- **`PersonActionPolicy`:** add optional `sharesActiveContext = false` to `from` → pass into `_baseFrom`. Compute `trustMutual = profile.isMutuallyVisible`; policy `isMutuallyVisible = trustMutual || sharesActiveContext`; `visibilityState = sharedContext` when `!trustMutual && sharesActiveContext`, else existing `_visibilityState(...)` (pass **trust** mutual flag, not augmented). Bond-only then hits `if (isMutuallyVisible)` branch (Send primary) — intentional per plan widening.
- **`profile_view_body.dart`:** today builds `PersonActionPolicy.from(profile, …)` without bond; must pass `sharesActiveContext: sharedContexts.isNotEmpty` and feed first title into `_ProfileVisibilitySection` for `sharedContext` switch case (two l10n lines). Eye icon uses `policy.isMutuallyVisible` (opens for bond).
- **Exhaustive switches:** adding `PersonVisibilityState.sharedContext` **breaks compile** in `profile_view_body.dart` and `graph_person_context_panel.dart` (`_directionalLines` switches). Graph panel must **not** pass `sharesActiveContext` (trust-only); add `sharedContext` case mapping to trust-only copy (e.g. same lines as `neither` or re-derive from profile trust fields) — optional `// issue-146: bond not shown here yet` comment only.
- **`user_public_model` path:** `packages/client/lib/data/gql/user_public_model.graphql` (not under `data/model/`). Profile main fetch uses Hasura `UserModel` on `user` — bond flag for forwarding comes via `UserPublicModel` on `forwardCandidates` only.
- **Tests (plan):** `ForwardCandidate.isReachable` bond-only; `ProfileViewCase` load + failing shared-context fetch → `[]`; widget test for shared-context visibility line — extend `profile_view_body_action_policy_test.dart` / `profile_view_case_test.dart`; add `person_action_policy_test.dart` bond rows; optional `direct_operation_routing_test.dart` for `PersonSharedContexts`.
- **Codegen / gates:** client `build_runner`, `flutter gen-l10n`, `check-user-facing-terminology.sh`, `check-custom-lints.sh packages/client`. **Version:** AGENTS.md requires client semver + `web/index.html` cache-buster for user-visible changes; plan T16 does release minor — recommend at least **patch** bump in T13 commit.
- **Next:** T13 implementer (Opus 5 low) — full brief in scout session output

---

## T13 — inner (Claude Opus 5)

- **UNIT_BASE:** `3c59d6c5e` → **commit `a3c2acd38`** `feat(client): show co-participant bond on profile and in forwarding` (body `issue-146 T13`). Not pushed. No version bump (T16 does it).
- **Done:** schema stitching (`v2_user.shares_active_context`, `personSharedContexts` root field, `v2_PersonSharedContext` with a single prefix, sorted between `v2_NotificationPreferences` and `v2_ReviewWindowStatus`); `PersonSharedContexts` operation + direct-V2 routing; `PersonSharedContextPort` (`typedef PersonSharedContext = ({String beaconId, String title})`, `fetchSharedContexts(userId)`); `PersonSharedContextRepository` (`@Singleton`, dev/prod) + test-env `PersonSharedContextRepositoryMock` (returns `[]`); `ProfileViewCase` gains a 6th positional port and fetches subjective tags + shared contexts in parallel, each best-effort → `ProfileViewSnapshot/State.sharedContexts`; `Profile.sharesActiveContext` via `UserPublicModel`; `ForwardCandidate.isReachable` ORs the bond; `PersonActionPolicy.from(sharesActiveContext:)` → `PersonVisibilityState.sharedContext` (trust-only mutual still feeds `_visibilityState`); profile body shows the two EN/RU lines from the first context's title.
- **Graph panel:** `sharedContext` shares the `neither` arm (unreachable there because the panel never passes the flag); it has the `issue-146` comment. Only two exhaustive switches existed (profile body, graph panel).
- **Tests:** new `test/support/fake_person_shared_context_port.dart`; 8 `ProfileViewCase(...)` test constructions updated; new `forward_candidate_reachability_test.dart`; bond cases in policy, case (fetch throws → `[]`, profile still loads), body widget (EN+RU lines, Send primary), routing tests.
- **Red/green:** the code was written before the tests (not strictly red-first). Green: the mandated 6-file run **96/96**; the broader profile_view/ + graph person-context run **155/155**; `check-custom-lints.sh packages/client` **30 vs baseline 30** OK; terminology ok; build_runner + gen-l10n ok.
- **Findings:** `dart format` re-wrapped some existing lines in touched files (graph panel, seen-helping strip test, action-policy test); these are layout-only changes. Format-only changes to untouched files were reverted. The profile body `BlocSelector` now selects the `(profile, sharedContexts)` record.
- **Next:** T13 verify

---

## T13 — Verify (read-only)

- **Range:** `3c59d6c5e10cdd4247a48abe7376cac4cfbeb97f..d7b358c58` (`a3c2acd38` feat + `d7b358c58` journal). **30** client files in feat commit; **no** `packages/server/`, **no** `pubspec.yaml` / `web/index.html`, **no** T14 banner file, **no** touch of pre-existing dirty tests (`home_tab_branch_routing_test`, `constellation_body_test`).
- **Schema:** `shares_active_context: Boolean` on `v2_user`; root `personSharedContexts(userId: String!): [v2_PersonSharedContext!]!` after `personFriendContextBatch`; `type v2_PersonSharedContext { beaconId title }` — matches server/T12 contract.
- **Policy:** `_baseFrom` uses `trustMutual = profile.isMutuallyVisible` for `_visibilityState`; augmented `isMutuallyVisible = trustMutual || sharesActiveContext`; `sharedContext` only when `!trustMutual && sharesActiveContext` — confirmed in diff.
- **Graph panel:** sole `PersonActionPolicy.from` omits `sharesActiveContext` (defaults false); `sharedContext` switch arm aliases `neither` copy + comment; no call site passes bond flag (grep).
- **L10n:** EN/RU strings match plan (`profileVisibilitySharedContext`, `profileVisibilitySharedContextNote`).
- **Test genuineness (no captured red run):** `forward_candidate_reachability_test` bond case would fail pre-T13 (`isReachable` was trust-only); policy bond-only case would fail (was `neither`/Trust); case load tests fail without port + try/catch; widget test fails without `sharedContext` UI + `sharesActiveContext` wiring (asserts exact l10n + Send, not `neither`).
- **Tests re-run (independent):**

| Command | Result |
|---|---|
| `dart run build_runner build -d` (client) | exit **0** |
| `flutter gen-l10n` | exit **0** |
| `check-user-facing-terminology.sh` | **ok** |
| flutter test (6 paths + `forward_candidate_reachability_test.dart`) | **96/96** passed |
| `check-custom-lints.sh packages/client` | **30 vs baseline 30**, OK |

- **Verdict:** **pass** — T13 “Done when” satisfied; proceed **T14**. **Advisory:** AGENTS.md expects client semver + web cache-buster for user-visible changes; deferred to T16 per inner — not a T13 plan blocker.
