# Journal — issue-112-timezone-display-and-wire-fix-plan

**Plan:** [`issue-112-timezone-display-and-wire-fix-plan.md`](issue-112-timezone-display-and-wire-fix-plan.md)
**Objective:** Fix the naive-datetime wire bug (beacon `startAt`/`endAt` lose
their timezone between client and server) and the UTC-leak display bugs
identified in issue #112's audit, without adding author-timezone storage or
new UI (explicit scope decision, plan §0.4).

**Repository:** `/home/vader/MY_SRC/tentura`
**Branch:** `main`
**Starting HEAD:** `fbd55c6c` ("docs(plan): add block-hang-and-preview-fix plan and close out journal")

**Pre-existing worktree changes at plan start (not owned by this plan — never
revert, never overwrite):**

```
 M CONTEXT.md
 M docs/README.md
 M docs/archive/journals/commitment-truth-rework-journal.md
 M docs/archive/plans/commitment-truth-rework-plan.md
 M docs/audits/room-coordination-audit.md
 M packages/client/web/index.html
 M packages/server/lib/data/database/table/beacon_commitment_events.dart
 M packages/server/lib/env.dart
?? dart-defines
?? docs/plans/graph-navigation-implementation-guide.md
?? docs/plans/graph-navigation-rework-plan.md
?? graph-ego-neighbors-layout-issue.md
?? key.fb
?? out.key
?? product_testing_compact_buglist.md
?? product_testing_detailed_report.md
```

None of these overlap with files this plan's units touch.

## Ordered work manifest

| # | Unit | Files | Status |
|---|------|-------|--------|
| 1 | P1 — client wire-format fix (`scheduleDateTimeToIso`, `.toUtc()`) | `packages/client/lib/features/beacon/data/repository/beacon_repository.dart` + new test | complete |
| 2 | P2 — server defensive UTC normalization (`InputFieldDatetime`) | `packages/server/lib/api/controllers/graphql/input/_input_types.dart` + new test | complete |
| 3 | P3 — `dateFormatYMD`/`timeFormatHm` always `.toLocal()` | `packages/client/lib/ui/utils/ui_utils.dart` + new test | complete |
| 4 | P4 — format `review.closesAt` instead of raw ISO | `packages/client/lib/features/evaluation/ui/widget/review_window_banner_host.dart` + extended test | complete |
| 5 | P5 — multi-timezone regression matrix | new `timezone_conversion_matrix_test.dart` + `run_timezone_matrix.sh` | pending |
| 6 | P6 — full regression pass (manager-run, not a worker unit) | n/a | pending |

Units are sequential (no parallelism) per the overseer contract, in plan
order P1→P5. P6 is closure/verification performed by the manager (this
session), not delegated to a fresh Cursor worker, since its "work" is running
existing verification commands and cross-checking acceptance criteria rather
than producing new code.

## Acceptance / verification commands (plan §2, §5 per-phase)

```bash
cd packages/client && flutter analyze
cd packages/client && flutter test
cd packages/client && bash test/ui/utils/run_timezone_matrix.sh   # after P5
cd packages/server && dart analyze
cd packages/server && dart test
```

## Unresolved decisions / blockers

None at start. Scope explicitly excludes author-timezone storage and
dual-label UI (user decision, plan §0.4) — do not expand into that.

## Checkpoints

### 2026-08-07 — P1 complete

**Changed:** Added top-level `scheduleDateTimeToIso` helper in
`beacon_repository.dart` (`@visibleForTesting`, `package:meta/meta.dart`);
replaced all six `startAt`/`endAt` wire writes in `create()`, `updateDraft()`,
and `update()` to use it. New unit test
`beacon_repository_schedule_serialization_test.dart`.

**Commit:** `b6d63f7f` — fix(client): send UTC ISO strings for beacon schedule dates (P1)

**Tests:**
- `cd packages/client && flutter test test/features/beacon/data/repository/beacon_repository_schedule_serialization_test.dart` — pass (3 tests)
- `cd packages/client && flutter analyze` — exit 1, 763 pre-existing info-level issues; no errors in changed files (only pre-existing `annotate_overrides` info on `beacon_repository.dart`)
- `./scripts/check-custom-lints.sh packages/client` — OK (baseline 111)

**Deviations from plan:** None — live code matched plan line numbers and method names; all six occurrences replaced via `replace_all` on the paired `startAt`/`endAt` lines in three methods.

### 2026-08-07 — P2 complete

**Changed:** Replaced `InputFieldDatetime.fromArgs`/`fromArgsNonNullable` in
`_input_types.dart` to route all parsed values through `_parseAsUtc` /
`_forceUtc`, ensuring `isUtc == true` and treating offset-less ISO strings as
UTC digits. New unit test
`packages/server/test/api/controllers/graphql/input/input_field_datetime_test.dart`
(created new `input/` subdirectory under `test/api/controllers/graphql/`, as
planned — sibling `mappers/` already existed).

**Commit:** `4c8d144d` — fix(server): force UTC parsing for InputFieldDatetime (P2)

**Tests:**
- `cd packages/server && dart analyze lib/api/controllers/graphql/input/_input_types.dart` — pass (no issues)
- `cd packages/server && dart test test/api/controllers/graphql/input/input_field_datetime_test.dart` — pass (4 tests)

**Deviations from plan:** None — live code matched plan; helpers placed as private instance methods on `InputFieldDatetime` (plan's indentation implied class scope; import path `package:tentura_server/api/controllers/graphql/input/_input_types.dart` matches sibling tests).

### 2026-08-07 — P3 complete

**Changed:** Added `.toLocal()` inside `dateFormatYMD`/`timeFormatHm` in
`ui_utils.dart` with doc comment per plan. New unit test
`ui_utils_datetime_test.dart`. No other source files changed — verified via
`grep` across `packages/client/lib`: three call sites without pre-conversion
(`beacon_tile.dart`, `inbox_item_tile.dart`, `beacon_hud_metadata_composer.dart`)
and four with redundant-but-idempotent `.toLocal()` (`help_offer_tile.dart`,
`updates_receipt_card.dart`, `coordination_log_row_chrome.dart`; plan also
listed `schedule_date_format.dart` and `relative_time.dart` which use their own
`DateFormat` paths, not these helpers).

**Commit:** `e867a5b7` — fix(client): render dateFormatYMD/timeFormatHm in viewer-local time (P3)

**Tests:**
- `cd packages/client && flutter test test/ui/utils/ui_utils_datetime_test.dart` — pass (2 tests)
- `cd packages/client && flutter analyze` — exit 0, 763 pre-existing info-level issues; no new errors in changed files

**Deviations from plan:** None — live callers matched plan's grep inventory; transitive fix claim confirmed.

### 2026-08-07 — P4 complete

**Changed:** Added `_formatClosesAt` helper in `review_window_banner_host.dart`
(parse → `.toLocal()` → `DateFormat.yMMMd(locale)`), matching
`review_contributions_screen.dart:285-297`; computed `closesAtLabel` once in
`build` and used it in both viewer and author banner branches. Extended
`review_window_banner_host_test.dart` with assertion that raw ISO is not shown
and localized date is.

**Commit:** (pending)

**Tests:**
- `cd packages/client && flutter test test/features/evaluation/review_window_banner_host_test.dart` — pass (7 tests)
- `cd packages/client && flutter analyze` — exit 0, 763 pre-existing info-level issues; no new errors in changed files

**Deviations from plan:** None — live code matched plan line numbers and pattern.
