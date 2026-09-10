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

## UNIT 01 — complete — 2026-09-10
COMMITS: (this entry's own commit, made immediately after)
TESTS: `cd packages/server && dart pub get --offline`; `dart run build_runner build -d`; `dart test -t pg -j 1 test/data/repository/attention_live_obligations_pg_test.dart` — 5 passed, 0 skipped; `./scripts/check-custom-lints.sh packages/server` — pass.
FILES: packages/server/lib/domain/port/attention_query_port.dart; packages/server/lib/data/repository/attention_repository.dart; packages/server/lib/api/controllers/graphql/query/query_attention.dart; packages/server/test/api/controllers/graphql/attention_graphql_test.dart; packages/server/test/domain/attention/legacy_canonical_compat_fixture_test.dart; packages/server/test/data/repository/attention_live_obligations_pg_test.dart; docs/plans/inbox-activity-ia-implementation-journal.md
FINDINGS: none
DECISIONS: extracted `_authorizedReceiptJoin` SQL fragment so `unreadForBeacons` and `liveObligationBeacons` share one authorization join path.
REMAINING: none. Proceed to UNIT 02.

## UNIT 02 — complete — 2026-09-10
COMMITS: 347a18d1a feat(client): fetch live obligation beacons
TESTS: `cd packages/client && flutter pub get --offline`; `cd packages/client && dart run build_runner build -d`; `cd packages/client && flutter test test/domain/attention/attention_live_obligations_test.dart` — 3 passed; `./scripts/check-custom-lints.sh packages/client` — pass.
FILES: packages/client/lib/data/gql/schema.graphql; packages/client/lib/features/attention/data/gql/attention_live_obligations.graphql; packages/client/lib/domain/attention/port/attention_repository_port.dart; packages/client/lib/data/repository/attention_repository.dart; packages/client/lib/data/service/remote_api_client/build_client.dart; packages/client/lib/domain/attention/attention_case.dart; packages/client/test/domain/attention/attention_case_test.dart; packages/client/test/domain/attention/attention_live_obligations_test.dart; packages/client/test/architecture/cross_surface_subscription_test.dart; packages/client/test/features/home/home_attention_cubit_test.dart; packages/client/test/features/home/constellation_nav_test.dart; packages/client/test/ui/widget/tab_attention_scope_test.dart; packages/client/test/features/inbox/inbox_expanded_chrome_test.dart; packages/client/test/features/inbox/inbox_receipts_fold_test.dart; packages/client/test/features/updates/updates_feed_cubit_test.dart; packages/client/test/features/updates/updates_102_my_work_attention_test.dart; packages/client/test/features/updates/cross_surface_coordination_accept_test.dart; docs/plans/inbox-activity-ia-implementation-journal.md
FINDINGS: unit owns list omits V2 direct-routing registration in `build_client.dart` (required alongside sibling `AttentionMarkers` per codegen.mdc).
DECISIONS: registered `AttentionLiveObligations` in `_tenturaDirectOperationNames` so the Ferry adapter reaches the V2 field.
REMAINING: none. Proceed to UNIT 03.
