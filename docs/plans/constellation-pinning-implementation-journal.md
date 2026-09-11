# Constellation pinning implementation journal

## Scope

- Objective: implement `docs/plans/constellation-pinning-plan.md` packets P01–P12.
- Repository: `/home/vader/MY_SRC/tentura`
- Branch: `feature/pin_constellation`
- Starting commit: `b61c44880e047bac66caafe045bae7eb9552dbb9`
- Started: 2026-09-11

## Worktree boundary at start

The following pre-existing untracked paths are outside this implementation and
must not be modified, staged, or committed:

```text
CLAUDE.local.md
dart-defines
docs/plans/algorithm-invariant-suites-plan.md
docs/plans/availability-request-receptiveness-architecture.md
docs/plans/availability-request-receptiveness-implementation-plan.md
docs/plans/availability-review-codex.md
docs/plans/availability-review-grok46.md
docs/plans/availability-review-kimik3.md
docs/plans/graph-navigation-implementation-guide.md
docs/plans/graph-navigation-rework-plan.md
docs/plans/issue-100-people-graph-person-context-implementation-plan.md
docs/plans/issue-110-forward-explicit-architecture.md
docs/plans/issue-110-forward-explicit-implementation-plan.md
docs/plans/issue-115-reply-to-message-implementation-journal.md
docs/plans/issue-115-reply-to-message-plan.md
docs/plans/issue-130-first-run-orientation-plan.md
docs/plans/mention-without-handle-plan.md
docs/plans/mention-without-handle-review-sol.md
docs/plans/nested-requests-architecture.md
docs/plans/nested-requests-cleanup-fk-manifest.json
docs/plans/nested-requests-implementation-plan.md
docs/plans/post-request-evaluation-detail-sheet-implementation-journal.md
docs/plans/post-request-evaluation-detail-sheet-plan.md
docs/plans/received-reviews-trust-changes-plan.md
docs/plans/request-threads-architecture.md
docs/plans/request-threads-implementation-plan.md
docs/plans/subjective-help-tag-evidence-architecture.md
docs/plans/subjective-help-tag-evidence-implementation-plan.md
graph-ego-neighbors-layout-issue.md
key.fb
out.key
product_testing_compact_buglist.md
product_testing_detailed_report.md
tg_style_research.md
```

## Ordered manifest

| Packet | Status | Dependency | Evidence / commit |
|---|---|---|---|
| P01 Contract fixtures and domain types | pending | — | — |
| P02 Migration and storage adapter | pending | P01 | — |
| P03 Server membership and complete snapshot | pending | P02 | — |
| P04 Authenticated V2 API | pending | P03 | — |
| P05 Client wire adapters and server echo policy | pending | P04 | — |
| P06 Pure composition, budgets and layout | pending | P05 | — |
| P07 Graph gesture adapter | pending | P06 | — |
| P08 Placement orchestration and live reconciliation | pending | P07 | — |
| P09 Map/Text controls, filters and status accessibility | pending | P08 | — |
| P10 End-to-end and failure acceptance | pending | P09 | — |
| P11 Full verification and release preparation | pending | P10 | — |
| P12 Product docs and coordinated activation | pending | P11 | — |

## Required process and verification discipline

- One fresh non-fast Composer 2.5 worker at a time.
- Heavy integration, browser, PostgreSQL, code generation, and full-suite work
  runs serially. Never start more than one such command at once.
- After every worker exit, the overseer records a process audit for task-owned
  or dangling Chrome, Dart, analyzer, Flutter, test-driver, and server
  processes before launching the next worker.
- Generated sources are regenerated only through their generators and are not
  hand-edited or committed.
- Every coherent implementation step is independently checked and committed
  with only its owned paths.

## Acceptance matrix

P01–P10 use their packet-specific checks from the plan. P11 requires serial
codegen, focused and full server/client/graph/lint/terminology checks, a unique
disposable PostgreSQL database for tagged PG tests, serial browser runners, and
versioned web artifact verification under one `WEB_BUILD_ID`. P12 records the
operational and product documentation only after those gates are accounted for.

## Checkpoints

### Initialization — 2026-09-11

- Status: accepted coordination setup.
- Verified: repository root, branch, starting SHA, pre-existing worktree list,
  and Cursor `composer-2.5` availability.
- Process baseline: long-running user/editor Chrome, Cursor, and Dart language
  servers exist; no task-owned worker has started. These must not be killed as
  cleanup.
- Decision: create the required journal before P01 so every fresh worker has
  shared state. Its initial setup is committed separately by the overseer.
