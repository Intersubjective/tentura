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
| 5 | P5 — multi-timezone regression matrix | new `timezone_conversion_matrix_test.dart` + `run_timezone_matrix.sh` | complete |
| 6 | P6 — full regression pass (manager-run, not a worker unit) | n/a | complete |

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

**Commit:** `1dc6c449` — fix(client): format review window closesAt for display (P4)

**Tests:**
- `cd packages/client && flutter test test/features/evaluation/review_window_banner_host_test.dart` — pass (7 tests)
- `cd packages/client && flutter analyze` — exit 0, 763 pre-existing info-level issues; no new errors in changed files

**Deviations from plan:** None — live code matched plan line numbers and pattern.

### 2026-08-07 — P5 complete

**Changed:** New `timezone_conversion_matrix_test.dart` exercising
`dateFormatYMD`/`timeFormatHm`, `formatScheduleDate`,
`coordinationLogTimestampLabel`, and `compactRelativeTimeAgo` with self-
referential `.toLocal()` assertions on boundary UTC instants. New
`run_timezone_matrix.sh` runs the test under `TZ=UTC`,
`TZ=Europe/Amsterdam`, and `TZ=Pacific/Kiritimati`.

**Commit:** `7218fa91` — test(client): add multi-timezone formatter regression matrix (P5)

**Tests:**
- `cd packages/client && flutter analyze` — exit 0, 763 pre-existing info-level issues; no new errors in changed files
- `cd packages/client && bash test/ui/utils/run_timezone_matrix.sh` — pass (12 tests: 4 per TZ × 3 zones)

**Deviations from plan:** Added `import 'package:flutter/material.dart';` for
`Locale` in the test file (plan omitted it; `relative_time_test.dart` uses the
same import). All three planned TZ values (`UTC`, `Europe/Amsterdam`,
`Pacific/Kiritimati`) were available in this environment — no fallback to
`Asia/Tokyo` / `America/New_York`. Live `formatScheduleDate` and
`coordinationLogTimestampLabel` signatures matched the plan; import path for
`coordinationLogTimestampLabel` confirmed as
`package:tentura/ui/widget/coordination_log_row_chrome.dart`.

### 2026-08-07 — P6 complete (manager-run, plan closed)

All five implementation units (P1-P5) reviewed by the manager against their
committed diffs (each matched the plan's prescribed code with zero
unexplained deviation) and independently re-run (not just trusting worker
self-reports):

- `beacon_repository_schedule_serialization_test.dart` — 3/3 pass.
- `input_field_datetime_test.dart` — 4/4 pass (both standalone and confirmed
  present under the standard `test/**/*_test.dart` discovery used by the
  full-suite run below; the compact reporter doesn't echo per-test names in
  a 1271-test batch, which is a reporter-verbosity artifact, not evidence of
  omission).
- `ui_utils_datetime_test.dart` — 2/2 pass.
- `review_window_banner_host_test.dart` — 7/7 pass (full file, including
  pre-existing cases).
- `timezone_conversion_matrix_test.dart` — additionally sanity-checked for
  real regression value, not tautology: temporarily reverted P3's two
  `.toLocal()` calls in `ui_utils.dart` and re-ran under `TZ=Europe/Amsterdam`
  — the matrix failed exactly as expected (`dateFormatYMD` produced
  `6/20/2026` instead of the correct `6/21/2026`), then the revert was
  discarded (`git checkout --`) confirming zero diff versus the accepted P3
  commit.

Full regression (plan §2 + §5):

- `cd packages/client && flutter analyze` — 763 issues, all pre-existing
  (identical count to every per-phase run above); no new issues in any file
  this plan touched.
- `cd packages/client && flutter test` — **1704 passed, 14 skipped
  (pre-existing skips), 0 failed.**
- `cd packages/client && bash test/ui/utils/run_timezone_matrix.sh` — all
  three `TZ=` runs pass.
- `cd packages/server && dart analyze` — 2177 issues, all pre-existing
  (targeted `dart analyze lib/api/controllers/graphql/input/_input_types.dart`
  in P2 already confirmed "No issues found!" for the one file this plan
  changed on the server).
- `cd packages/server && dart test -x pg` — **1271 passed, 0 failed.**

Acceptance criteria cross-check against plan §0/§6:

- P1: `scheduleDateTimeToIso` always emits a `Z`-suffixed string; all three
  beacon mutation methods (create/update/updateDraft) use it for both
  `startAt`/`endAt`. Confirmed in diff.
- P2: `InputFieldDatetime.fromArgs`/`fromArgsNonNullable` always return
  `isUtc == true`; offset-less input treated as UTC digits, not server-local.
  Confirmed in diff + test.
- P3: `dateFormatYMD`/`timeFormatHm` convert to local before formatting;
  `beacon_tile.dart`, `inbox_item_tile.dart`,
  `beacon_hud_metadata_composer.dart` needed no source change (confirmed: no
  diff touched them).
- P4: `review_window_banner_host.dart` shows a formatted local date, never
  the raw ISO string. Confirmed in diff + test.
- P5: TZ matrix passes under UTC + Amsterdam (DST-observing) + Kiritimati
  (UTC+14, date-line). Confirmed, and confirmed non-tautological (see above).
- No changes touched `info_tab.dart`, `beacon_create_cubit.dart`,
  `timestamptz_serializer.dart`, or any Drift table definition — confirmed
  via `git diff fbd55c6c..HEAD --stat` (only the six files this plan's units
  own, plus this journal and the plan doc itself, changed).
- No author-timezone storage, timezone/time picker, or dual-label UI was
  added — scope boundary from plan §0.4/§1 held throughout all five units.

**All pre-existing uncommitted worktree changes from journal start (`CONTEXT.md`,
`docs/README.md`, the two `docs/archive/*` files, `docs/audits/room-coordination-audit.md`,
`packages/client/web/index.html`,
`packages/server/lib/data/database/table/beacon_commitment_events.dart`,
`packages/server/lib/env.dart`, and all listed untracked files) remain
untouched** — verified via `git status --short` showing the identical set at
plan close as at plan start.

**Plan status: complete.** All 6 units accepted; no remaining work. Deferred
by explicit user decision (plan §0.4, §6): author-timezone storage, "your
time vs. original" dual-label UI, and the accepted ±1-day date-only-deadline
consequence for distant-timezone viewers — not defects, a documented scope
boundary.
