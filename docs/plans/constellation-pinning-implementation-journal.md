# Constellation pinning — implementation journal

## Execution record

- Objective: implement `docs/plans/constellation-pinning-plan.md` (P01–P12).
- Branch and starting commit: `feature/pin_constellation` at `2457dc95c466da2568c930abd2cbbc6bcb85ff4b` (`fix(test): restore constellation PG trust after cascade deletes`).
- Plan baseline: migrations through `m0166`; the plan specifies the next free migration as `m0167.dart` only if it remains free when P02 begins.
- Orchestration: fresh sequential `composer-2.5` Cursor workers. Integration/browser/database suites run one at a time to protect RAM. The overseer inspects development processes after each worker result.

## Pre-existing worktree paths — preserve unchanged

`CLAUDE.local.md`, `dart-defines`, `docs/plans/algorithm-invariant-suites-plan.md`, `docs/plans/availability-request-receptiveness-architecture.md`, `docs/plans/availability-request-receptiveness-implementation-plan.md`, `docs/plans/availability-review-codex.md`, `docs/plans/availability-review-grok46.md`, `docs/plans/availability-review-kimik3.md`, `docs/plans/graph-navigation-implementation-guide.md`, `docs/plans/graph-navigation-rework-plan.md`, `docs/plans/issue-100-people-graph-person-context-implementation-plan.md`, `docs/plans/issue-110-forward-explicit-architecture.md`, `docs/plans/issue-110-forward-explicit-implementation-plan.md`, `docs/plans/issue-115-reply-to-message-implementation-journal.md`, `docs/plans/issue-115-reply-to-message-plan.md`, `docs/plans/issue-130-first-run-orientation-plan.md`, `docs/plans/mention-without-handle-plan.md`, `docs/plans/mention-without-handle-review-sol.md`, `docs/plans/nested-requests-architecture.md`, `docs/plans/nested-requests-cleanup-fk-manifest.json`, `docs/plans/nested-requests-implementation-plan.md`, `docs/plans/post-request-evaluation-detail-sheet-implementation-journal.md`, `docs/plans/post-request-evaluation-detail-sheet-plan.md`, `docs/plans/received-reviews-trust-changes-plan.md`, `docs/plans/request-threads-architecture.md`, `docs/plans/request-threads-implementation-plan.md`, `docs/plans/subjective-help-tag-evidence-architecture.md`, `docs/plans/subjective-help-tag-evidence-implementation-plan.md`, `graph-ego-neighbors-layout-issue.md`, `key.fb`, `out.key`, `product_testing_compact_buglist.md`, `product_testing_detailed_report.md`, `tg_style_research.md`.

## Ordered packet manifest

| Packet | Status | Evidence / commits |
|---|---|---|
| P01 Contract fixtures and domain types | pending | — |
| P02 Migration and storage adapter | pending | — |
| P03 Server membership and complete snapshot | pending | — |
| P04 Authenticated V2 API | pending | — |
| P05 Client wire adapters and server echo policy | pending | — |
| P06 Pure composition, budgets and layout | pending | — |
| P07 Graph gesture adapter | pending | — |
| P08 Placement orchestration and live reconciliation | pending | — |
| P09 Map/Text controls, filters and status accessibility | pending | — |
| P10 End-to-end and failure acceptance | pending | — |
| P11 Full verification and release preparation | pending | — |
| P12 Product docs and coordinated activation | pending | — |

## Manager checkpoint — 2026-09-12

The plan and relevant repository rules were read. `cursor-agent models` confirms the required non-fast `composer-2.5` model. Initial process inspection found active user-owned Cursor, Chrome, Dart MCP, Docker, and PostgreSQL processes, with no task-owned worker or test process. Do not terminate pre-existing processes. P01 may start.
