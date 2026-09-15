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
| pending | **T01** beaconChildren auth |
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
