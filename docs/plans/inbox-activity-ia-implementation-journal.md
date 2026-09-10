# Inbox → Activity: implementation journal

Plan: [`inbox-activity-ia-implementation-plan.md`](inbox-activity-ia-implementation-plan.md) (revision 8).
Architecture: [`inbox-activity-ia-architecture.md`](inbox-activity-ia-architecture.md) (revision 8, ADOPT WITH CHANGES).

Overseer: Claude Sonnet 5, invoked via `/overseer implement the plan autonomously`.
Workers: Cursor CLI, `composer-2.5`, one fresh session per unit, `--yolo --sandbox disabled --trust --print`.

## UNIT 00 — Journal and baseline — complete — 2026-09-10

**Repository.** Worktree at `/tmp/claude-1000/-home-vader-MY-SRC-tentura/b5adc5bd-496a-4a81-8ad2-09d6ce6d2c36/activity-docs`,
branch `feat/inbox-activity-ia`, baseline HEAD `f563c3c98` ("docs(plans): fold the
fifth unit review (plan rev 8)"). Base branch `main` at `54dd780cf`. Working tree
was clean at baseline — no pre-existing modified or untracked files in this
worktree to distinguish from later units' own changes.

**Plan revisions.** Implementation plan revision 8 (1933 lines), architecture
revision 8 (401 lines, ADOPT WITH CHANGES after 7 adversarial passes on the
architecture plus 5 further passes on the split-out implementation plan — see
plan header and prior review history; not re-litigated here).

**Toolchain.**
- `flutter --version`: Flutter 3.47.0 (channel stable), Dart 3.13.0, DevTools 2.60.0.
- `dart --version`: Dart SDK 3.13.0 (stable).

**Postgres preflight.** A disposable-database Postgres integration harness
already exists (`test/support/beacon_hierarchy_fixture.dart`,
`BeaconHierarchyDisposablePgTarget.fromEnvironment()`), targeting the
already-running local Postgres container (`postgres:5432` via
`vbulavintsev/postgres-tentura:v0.8.0`, defaults `127.0.0.1:5432`, overridable
via `POSTGRES_HOST`/`POSTGRES_PORT`/`POSTGRES_PASSWORD` per
`packages/server/README.md:15-16`). No separate bring-up step was needed; the
container was already up.

Generated code in this worktree was stale (this worktree had never run
`build_runner` — the doc-only commits never touched generated output). Ran
`cd packages/server && dart run build_runner build -d` (37s, 2560 outputs) to
get a compiling baseline before the PG run. Also required `dart pub get
--offline` first — the sandboxed shell has no outbound network to pub.dev by
default, and plain `dart pub get`/`dart test` hang and fail on that, **not**
on anything related to this plan; `--offline` resolves against the existing
`.dart_tool/pub` cache and succeeds. **Every subsequent Verify block in this
plan must use this same workaround if a bare `pub get` is invoked implicitly**
— recorded here once rather than in every unit.

Ran the required non-trivial PG suite:

```
cd packages/server && dart test -t pg -j 1 test/data/repository/attention_repository_pg_test.dart
```

Result: **17 tests passed, 0 skipped** (not the silent-skip false green the
plan warns about at `attention_repository_pg_test.dart:28-33`). This proves
Postgres is reachable and the `-t pg` tag actually executes for the rest of
this plan's units.

COMMITS: (this entry's own commit, made immediately after)
TESTS: `dart test -t pg -j 1 test/data/repository/attention_repository_pg_test.dart` — 17 passed, 0 skipped, 0 failed.
FILES: `docs/plans/inbox-activity-ia-implementation-journal.md` (new)
FINDINGS: worktree generated code was stale (never built in this worktree); sandboxed shell needs `dart pub get --offline` before any `dart test`/`dart run build_runner` invocation, else it hangs/fails on a network fetch unrelated to this plan.
DECISIONS: none beyond the plan's own text.
REMAINING: none. Proceed to UNIT 01.
