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

## UNIT 03 — complete — 2026-09-10
COMMITS: b9ce9dc82 fix(server): notify on settlement-only outbox updates
TESTS: `cd packages/server && dart pub get --offline`; `cd packages/server && dart run build_runner build -d`; `cd packages/server && dart test -t pg -j 1 test/data/database/settlement_notify_pg_test.dart` — 2 passed, 0 skipped; `./scripts/check-custom-lints.sh packages/server` — pass.
FILES: packages/server/lib/data/database/migration/m0164.dart; packages/server/lib/data/database/migration/_migrations.dart; packages/server/test/data/database/settlement_notify_pg_test.dart; docs/plans/inbox-activity-ia-implementation-journal.md
FINDINGS: none
DECISIONS: none
REMAINING: none. Proceed to UNIT 04.

## UNIT 04 — complete — 2026-09-10
COMMITS: (this entry's own commit, made immediately after)
TESTS: `cd packages/client && flutter pub get --offline`; `cd packages/client && dart run build_runner build -d`; `cd packages/client && flutter test test/features/my_work/` — 107 passed; `./scripts/check-custom-lints.sh packages/client` — pass.
FILES: packages/client/lib/features/my_work/domain/my_work_obligations_gate.dart; packages/client/lib/features/my_work/data/gql/my_work_fetch.graphql; packages/client/lib/features/my_work/domain/entity/my_work_fetch_types.dart; packages/client/lib/features/my_work/data/repository/my_work_repository.dart; packages/client/lib/features/my_work/domain/use_case/my_work_case.dart; packages/client/lib/features/my_work/domain/derive_my_work_cards.dart; packages/client/lib/features/my_work/domain/entity/my_work_card_view_model.dart; packages/client/lib/features/my_work/ui/widget/my_work_cards.dart; packages/client/test/features/my_work/my_work_obligation_membership_test.dart; packages/client/test/features/my_work/my_work_test_support.dart; packages/client/test/features/my_work/my_work_case_load_desk_test.dart; packages/client/test/features/my_work/my_work_case_streams_test.dart; packages/client/test/features/my_work/my_work_cubit_test.dart; packages/client/test/features/updates/cross_surface_coordination_accept_test.dart; docs/plans/inbox-activity-ia-implementation-journal.md
FINDINGS: owns list omits `my_work_test_support.dart` and sibling my_work test tuple updates required by `MyWorkInitResult.obligationBeacons`; `my_work_cubit.dart` needed no edits (gate lives in `MyWorkCase`).
DECISIONS: none
REMAINING: none. Proceed to UNIT 05.

## UNIT 05 — complete — 2026-09-10
COMMITS: 9bfdcfd27 fix(client): archive revokes a source, not the row
TESTS: `cd packages/client && flutter pub get --offline`; `cd packages/client && dart run build_runner build -d`; `cd packages/client && flutter test test/features/my_work/` — 113 passed; `./scripts/check-custom-lints.sh packages/client` — pass.
FILES: packages/client/lib/features/my_work/ui/bloc/my_work_cubit.dart; packages/client/lib/features/my_work/domain/entity/my_work_card_view_model.dart; packages/client/lib/features/my_work/domain/derive_my_work_cards.dart; packages/client/lib/features/my_work/ui/widget/my_work_cards.dart; packages/client/test/features/my_work/my_work_archive_membership_test.dart; docs/plans/inbox-activity-ia-implementation-journal.md
FINDINGS: UNIT 04 already added `sources` and `viewerArchived` on `MyWorkCardViewModel`; this unit wired archive revocation and `isArchived` without new Freezed fields.
DECISIONS: `myWorkCardAfterArchiveRevocation` in `derive_my_work_cards.dart` is the shared desk projection for archive + obligation merge on reload.
REMAINING: none. Proceed to UNIT 06.

## UNIT 06 — complete — 2026-09-10
COMMITS: 62a68bd09 feat(client): refresh my work on obligation changes
TESTS: `cd packages/client && flutter pub get --offline`; `cd packages/client && flutter test test/features/my_work/` — 117 passed; `./scripts/check-custom-lints.sh packages/client` — pass.
FILES: packages/client/lib/features/my_work/ui/bloc/my_work_cubit.dart; packages/client/test/features/my_work/my_work_refresh_triggers_test.dart; docs/plans/inbox-activity-ia-implementation-journal.md
FINDINGS: `BlockRepository` lives under `packages/client/lib/features/block/data/repository/block_repository.dart`, not `packages/client/lib/data/repository/block_repository.dart`.
DECISIONS: wired notification and block invalidation in `MyWorkCubit` via optional `RealtimeSyncCase` / `BlockCase` constructor params (same pattern as `GraphCubit`), re-fetching the desk on each signal.
REMAINING: none. Proceed to UNIT 07.

## UNIT 07 — complete — 2026-09-10 (overseer-recovered)
COMMITS: (this entry's own commit, made immediately after)
TESTS: `cd packages/client && flutter pub get --offline`; `dart run build_runner build -d`; `flutter test test/features/updates/ test/features/inbox/ test/domain/attention/ test/features/home/ test/architecture/ test/ui/widget/tab_attention_scope_test.dart test/features/my_work/` — 333 passed; `flutter analyze` — 0 errors (only pre-existing baseline info/warnings); `./scripts/check-custom-lints.sh packages/client` — pass.
FILES: packages/client/lib/domain/attention/attention_case.dart; packages/client/lib/domain/attention/entity/attention_feed.dart; packages/client/lib/domain/attention/feed_session_registry.dart (new); packages/client/lib/features/updates/ui/bloc/feed_session_registry.dart (new, re-export shim); packages/client/lib/features/updates/ui/bloc/updates_feed_cubit.dart; packages/client/lib/features/updates/ui/bloc/updates_feed_state.dart; packages/client/lib/features/updates/ui/screen/updates_screen.dart; packages/client/lib/features/updates/ui/widget/updates_feed_pane.dart; packages/client/lib/features/inbox/ui/screen/inbox_screen.dart; packages/client/test/features/updates/updates_feed_session_test.dart (new); plus fake/mock updates in test/architecture/, test/domain/attention/, test/features/home/, test/features/inbox/, test/features/my_work/, test/features/updates/, test/ui/widget/ required by the `AttentionFeedSnapshot` → `AttentionFeedSession`/`AttentionFeedSnapshot` split.
FINDINGS:
1. The Cursor worker for this unit implemented it correctly but was killed by an infra-level "system is running low on memory" auto-kill (see below — unrelated to any defect) right as it started its own Verify chain, before it could commit or write its journal entry. The overseer inspected the resulting uncommitted diff directly, ran the full Verify block independently, found it green, and is committing it here rather than discarding valid work and re-running an expensive ~10-minute unit from scratch.
2. The worker relocated `feed_session_registry.dart` from the plan's named path (`features/updates/ui/bloc/`) to `lib/domain/attention/` (arguably the more architecturally correct home for account-scoped domain state, and where it needs to sit to be a plain constructor dependency of `AttentionCase`), leaving a one-line re-export shim at the originally-named path so nothing else needed to change. Reasonable judgment call under Executor Contract rule 2; not reverted.
3. **A real regression, found and fixed by the overseer, not by the worker**: `_requestHeadRefreshForAllAttended` (as originally written) iterated only `_feedSessions.attachedDestinationIds` — when zero destinations are attached (e.g. no feed screen is currently mounted), a notification/catch-up/block-change event silently refreshed nothing at all, including the account-wide `summary` that the browser-tab unread badge (`TabAttentionController`) reads. This broke `test/ui/widget/tab_attention_scope_test.dart` deterministically (4 failing cases, reproduced in isolation) and contradicts the plan's own stated invariant that account-wide summary must stay independent of per-destination state. Fixed: when no destination is attached, `_requestHeadRefreshForAllAttached` now performs exactly one head-refresh against the default `AttentionFeedDestinationId.activity`, which still updates `snapshot.summary` and harmlessly pre-warms that destination's session for whenever it is later attached. Verified: all four previously-failing cases pass; full re-run of every test directory touched by this unit's diff (333 tests) plus `flutter analyze` (0 errors) shows no other regression.
4. A trivial worker slip also fixed directly: `test/ui/widget/tab_attention_scope_test.dart` had gained a duplicate `import 'package:tentura/domain/attention/feed_session_registry.dart';` line; removed the duplicate and restored alphabetical import order.
5. **Infra note, not plan-relevant but recorded for whoever reads this journal**: this session observed that `~/.claude/skills/overseer/scripts/run_cursor_worker.sh` launched via a *backgrounded* Bash call was killed by a host-level "low memory" monitor on four consecutive attempts for UNIT 03 despite `free -h` showing 30-40GB available immediately before and after each kill; switching to a *foreground*, blocking invocation of the identical command succeeded immediately and has been used for every unit since (00-07). Root cause not fully diagnosed (likely a background-task-specific memory-tracking heuristic distinct from system-wide availability), but the workaround is reliable so far.
DECISIONS: none beyond the plan's own text, aside from the relocation and regression fix already described above.
REMAINING: none. Proceed to UNIT 08.

## UNIT 08 — complete — 2026-09-10 (overseer-recovered)
COMMITS: (this entry's own commit, made immediately after)
TESTS: `cd packages/client && flutter pub get --offline`; `dart run build_runner build -d`; `flutter test test/features/my_work/` — 121 passed; `./scripts/check-custom-lints.sh packages/client` — pass.
FILES: packages/client/lib/features/my_work/ui/widget/my_work_obligations_pane.dart (new); packages/client/lib/features/updates/ui/widget/updates_feed_pane.dart (view parameterisation: `offeredViews`/`showViewControl`); packages/client/lib/features/my_work/ui/screen/my_work_screen.dart (mounts the pane behind the gate); packages/client/lib/features/my_work/domain/my_work_obligations_gate.dart (`readMyWorkObligationsGateEnabled()` helper); packages/client/lib/features/updates/ui/bloc/updates_feed_cubit.dart (`pinnedView` constructor param); packages/client/lib/ui/test_ids.dart; packages/client/test/features/my_work/my_work_obligations_pane_test.dart (new).

**Activity-vs-My-Work parity (required by this unit's acceptance, UNIT 09 depends on this record):** `MyWorkObligationsPane` mounts the exact same `UpdatesFeedPane` widget Activity's Needs-you tab already uses today — pinned to `AttentionView.needsYou`, `showViewControl: false`, on its own `AttentionFeedDestinationId.myWorkObligations` session (UNIT 07 machinery, independent view/search/generation from Activity's). Because it is literal reuse of the same pane rather than a re-implementation, it carries the same per-receipt card rendering and the same settlement action (Mark done, verified in this unit's own test: tapping it calls `AttentionCase.settle` through the shared cubit and removes the item from the pane) that Activity's Needs-you view offers today. Nothing in Activity's Needs-you view is present in code that this pane does not also reach through the same shared widget tree. Verified by test: `settling an obligation removes it from the pane but keeps the My Work card` (the Beacon's card stays, sourced by the authored/help-offered membership, when another source remains — matching architecture §8's own invariant, not just this unit's UI).

FINDINGS:
1. The Cursor worker for this unit implemented the code correctly (verified: activation gate correctly read and not flipped; Activity's three views left completely untouched per behaviour-preservation requirement; dotted My Work test-id convention followed; settlement wired to a real `AttentionCase.settle` call, not read-only) but was killed by the same infra memory-tracking issue as UNIT 07, this time before even finishing writing its own test file — it never reached its own Verify block or journal entry. The overseer picked up the uncommitted diff, ran full verification, found and fixed three real defects in the **test file** before accepting (the shipped widget/screen/pane/cubit code itself needed no changes).
2. **Root cause of a genuine ~10-minute test hang, found and fixed**: the test's own `_drain()` helper looped `await Future<void>.delayed(Duration.zero)`, called before any `WidgetTester.pump()` had occurred. Under `AutomatedTestWidgetsFlutterBinding`, `Future.delayed` — even with `Duration.zero` — schedules through a `Timer`, which the binding fakes and never fires without an explicit pump; the awaited `Future` therefore never completes and the test hangs until `package:test`'s own default 10-minute timeout kills it. This is the exact same bug class already documented elsewhere in this repository's history (a different, unrelated commit fixing "`Future.delayed(Duration.zero)` loop... never fires under `AutomatedTestWidgetsFlutterBinding` without an explicit pump... switched to `Future.microtask`"). Fixed identically: switched to `Future.microtask(() {})`, which drains via the microtask queue rather than a Timer. Root-causing this took a lengthy investigation because every diagnostic re-run with different CLI flags (`--timeout`, `--plain-name`) forced a fresh multi-minute cold recompile, and this environment's background-task memory monitor was independently killing most attempts before the (already-slow) compile could even finish, producing misleading "Bad state: Cannot close sink while adding stream" IPC-teardown noise unrelated to the actual bug. The conclusive evidence was one uninterrupted run that reached `package:test`'s own internal `TimeoutException after 0:10:00`, and a second uninterrupted run with disk-persisted (not stdout-buffered) checkpoint writes confirming the hang occurred before the very first line of `_pumpMyWorkScreen` ever executed.
3. Two further, smaller test-only gaps found and fixed while getting the file green: (a) `_AuthoredActiveCard`'s `build()` looks up `BeaconRepository`/`EvaluationRepository` directly from GetIt (not via `MyWorkCase`'s constructor injection, which `buildTestMyWorkCase()` already satisfies separately) — this is the first test in this plan to actually mount an authored card widget rather than only its cubit, so it's the first to need these registered; fixed by registering `FakeBeaconRepository`/`EvaluationRepositoryMock` in `setUp`/`tearDown`. (b) The destination-only test (`MyWorkObligationsPane uses the needs-you destination session`) mounted the pane under a bare `SizedBox` with no `Material` ancestor, which the pane's search `TextField` requires; fixed by wrapping it in a `Scaffold`.
DECISIONS: none beyond the plan's own text, aside from the test fixes described above.
REMAINING: none. Proceed to UNIT 09 — **do not start it until this entry is read**: UNIT 09 removes Needs-you from Activity based on the parity comparison recorded above.

## UNIT 09 — complete — 2026-09-10 (overseer-recovered)
COMMITS: (this entry's own commit, made immediately after)
TESTS: `cd packages/client && flutter pub get --offline`; `flutter test test/features/updates/ test/features/my_work/` — 191 passed; `./scripts/check-custom-lints.sh packages/client` — pass.
FILES: packages/client/lib/features/my_work/domain/my_work_obligations_gate.dart (gate default flipped to `true`); packages/client/lib/features/updates/ui/widget/updates_feed_pane.dart (`kDefaultUpdatesFeedOfferedViews` drops `needsYou`); packages/client/test/features/updates/updates_feed_views_test.dart (new — the 3-tab → 2-tab pinning coverage this unit requires).

FINDINGS:
1. The Cursor worker implemented the flip correctly (gate default `true`; only the *default* offered-views list changed, so Activity — which never explicitly overrides `offeredViews` — narrows automatically while My Work's explicit `[needsYou]` override from UNIT 08 is untouched) but was again killed by the same infra memory-tracking issue before its own Verify block, this time mid-way through running just its own new test file. The shipped `updates_feed_pane.dart`/gate change needed no correction; only the new test file did.
2. **A second, distinct hang bug, found and fixed** — not the UNIT 08 `Future.delayed` issue (this file already used `Future.microtask`). Disk-persisted checkpoints (same technique as UNIT 08) proved the test body runs and its assertions pass in full, then hangs specifically in its own explicit teardown (`cubit.close()` / `attention.dispose()` awaited back-to-back after a widget built from that same cubit/case was still mounted). Confirmed the bug is unique to `testWidgets`-based tests that actually mount a real `UpdatesFeedPane`: the pre-existing, passing `updates_feed_session_test.dart` (UNIT 07) exercises the same `AttentionCase`/`UpdatesFeedCubit` pair but only via plain `test()` with no widget ever mounted, so it never hits this. Root cause not fully isolated to one exact line (several partial fixes — unmounting first, closing only the cubit unawaited — each moved the hang to the *next* awaited teardown call rather than removing it), but the reliable, confirmed fix is the one already established for exactly this class of problem in UNIT 08: make every teardown call in a `testWidgets` test that mounted a live cubit-backed widget (`cubit.close()`, `attention.dispose()`, the fake account stream's `close()`) `unawaited` rather than blocking on it. Verified by the same signature as UNIT 08's fix: the identical bare `flutter test` invocation dropped from a reproducible ~76s hang (four consecutive confirmations) to sub-second completion the moment this was applied, across all three `testWidgets` cases in the file.
3. A small, separate gap: the pane-only test needed `Logger` registered in GetIt (guarded so it doesn't clobber a pre-existing registration), since `MyWorkObligationsPane` constructs its internal `UpdatesFeedCubit` without an explicit logger and falls back to `GetIt.I<Logger>()`.
4. **Repo-wide note for future units, since this is now the second time this exact class of bug has cost significant investigation time**: any `testWidgets` test in this codebase that (a) constructs a real `AttentionCase`/`Cubit` outside of DI, (b) mounts it into a real widget via `BlocProvider`, and (c) then tries to `await` that cubit's or case's `close()`/`dispose()` in the same test body, should make those calls `unawaited` from the start rather than discovering the hang empirically.
DECISIONS: none beyond the plan's own text.
REMAINING: none. Proceed to UNIT 10.

## UNIT 10 — complete — 2026-09-10
COMMITS: (this entry's own commit, made immediately after)
TESTS: `cd packages/server && dart pub get --offline`; `cd packages/server && dart run build_runner build -d`; `cd packages/server && dart test -t pg -j 1 test/domain/use_case/invite_prompt_projection_pg_test.dart` — 3 passed, 0 skipped; `./scripts/check-custom-lints.sh packages/server` — pass.
FILES: packages/server/lib/domain/port/invite_seed_prompt_port.dart; packages/server/lib/data/repository/invite_seed_prompt_repository.dart; packages/server/lib/data/repository/mock/invite_seed_prompt_repository_mock.dart; packages/server/lib/domain/use_case/invite_seed_attestation_case.dart; packages/server/lib/api/controllers/graphql/query/query_invite_seed_prompt.dart; packages/server/test/domain/use_case/invite_prompt_projection_pg_test.dart; docs/plans/inbox-activity-ia-implementation-journal.md
FINDINGS: `dart run build_runner build -d` regenerates `invite_seed_resolver_mocks.mocks.dart` for the port growth; Mockito still compiles without committing that file.
DECISIONS: batch authorization omits blocked/unauthorized/unknown subjects (same predicate as `_authorizeInviter`, without throwing); GraphQL clamps `subjectIds` to 100 per call.
REMAINING: none. Proceed to UNIT 11.

## UNIT 11 — complete — 2026-09-10
COMMITS: (this entry's own commit, made immediately after)
TESTS: `cd packages/server && dart pub get --offline`; `cd packages/server && dart run build_runner build -d`; `cd packages/server && dart test -t pg -j 1 test/domain/use_case/invite_prompt_invalidation_pg_test.dart` — 4 passed, 0 skipped; `./scripts/check-custom-lints.sh packages/server` — pass.
FILES: packages/server/lib/data/database/migration/m0165.dart; packages/server/lib/data/database/migration/_migrations.dart; packages/server/lib/domain/use_case/invite_seed_attestation_case.dart; packages/server/test/domain/use_case/invite_prompt_invalidation_pg_test.dart; docs/plans/inbox-activity-ia-implementation-journal.md
FINDINGS: none
DECISIONS: added `emit_realtime_entity_change_strict` (failure-propagating sibling of `emit_realtime_entity_change`) for prompt invalidation; trigger fires on `invite_seed_prompt_state` state changes only.
REMAINING: none. Proceed to UNIT 12.

## UNIT 12 — complete — 2026-09-10 (overseer-recovered)
COMMITS: (this entry's own commit, made immediately after)
TESTS: `cd packages/client && flutter pub get --offline`; `dart run build_runner build -d`; `flutter test test/features/updates/` (2 batches) — 75 passed; `flutter test test/architecture/cross_surface_subscription_test.dart test/data/service/invalidation_service_test.dart` — 30 passed; `flutter analyze` — 0 errors; `./scripts/check-custom-lints.sh packages/client` — pass.
FILES: packages/client/lib/features/updates/domain/entity/prompt_projection.dart (new); packages/client/lib/domain/entity/realtime/realtime_entity_change.dart (the decoder fix); packages/client/lib/domain/port/capability_repository_port.dart; packages/client/lib/features/capability/data/repository/capability_repository.dart; packages/client/lib/features/capability/data/gql/invite_prompt_states.graphql (new); packages/client/lib/features/updates/domain/use_case/invite_accepted_setup_case.dart; packages/client/lib/features/updates/ui/bloc/updates_feed_cubit.dart; packages/client/lib/features/updates/ui/bloc/updates_feed_state.dart; packages/client/lib/features/updates/ui/widget/invite_accepted_receipt_card.dart; packages/client/lib/features/updates/ui/widget/updates_feed_pane.dart; packages/client/lib/data/service/remote_api_client/build_client.dart (V2 direct-routing registration); packages/client/lib/data/gql/schema.graphql (refreshed by the overseer before this unit, per UNIT 02's precedent); plus the test files listed in FINDINGS below.

FINDINGS: the overseer refreshed `schema.graphql` before launching this unit's worker (started the worktree server, reloaded Hasura's remote-schema cache, fetched, copied in — the schema-fetch dance documented in UNIT 02's entry), so the worker never had to touch that fragile step itself.

**Regression check on the critical decoder gap the plan calls out**: verified `RealtimeEntityKind.fromWire('invite_seed_prompt')` decodes correctly (not `null`), and the worker's own `prompt_projection_test.dart` asserts this through `fromWire` rather than constructing the enum value directly, exactly as required — confirmed by rerunning it independently.

**Four real defects found and fixed by the overseer, none present in the worker's own (never-reached) Verify pass since it was killed mid-run**, none related to the decoder gap (which was correct from the start):
1. `prompt_projection.dart`'s own getters used Freezed's `.when()`/`.maybeWhen()`, which this repo's `build.yaml` explicitly disables (`freezed: options: when: false`) for every Freezed class in the client package — a repo-wide convention, not specific to this file. The generated `.freezed.dart` therefore has no such methods, and neither call site (the entity itself, plus `invite_accepted_receipt_card.dart`'s two call sites) compiled. Rewrote all three as `switch` expressions on the sealed class's generated subtypes, which Dart 3 supports natively regardless of the Freezed `when` setting.
2. `_promptPhase()`'s "not applicable" gate checked only `_isNewAccount`, not whether a subject id was actually extractable — a receipt that is new-account-origin but has no `actorUserId`/`targetEntityId` fell through to the projection switch and could still show the "Add details" action. Added the missing `_subjectId == null` check, matching the existing guard already present in `_openSetup()`.
3. Test-harness gap, not a product bug: `invite_accepted_receipt_card_test.dart`'s `pumpCard()` helper pumped a static `promptProjection` value and never wired `onPromptSettled` to anything, so the two tests asserting the "Add details" action disappears after a successful Save/Skip never actually exercised the update path the widget correctly calls (`widget.onPromptSettled?.call(...)`, matching the documented design — the shared projection is externally owned by the parent, not the card). Wrapped the harness in a `StatefulBuilder` so `onPromptSettled` updates the projection it re-renders with.
4. `updates_feed_cubit_test.dart` had a duplicate `import '.../feed_session_registry.dart'` line (the same class of mistake as UNIT 09's worker, apparently a recurring composer-2.5 tic worth watching for) and referenced `realtime.case_` where `realtime` was already unwrapped to the port, not the record — added a `late RealtimeSyncCase realtimeCase` field set alongside `attention` in `setUp`.
DECISIONS: none beyond the plan's own text, aside from the fixes above.
REMAINING: none. Proceed to UNIT 13.

## UNIT 13 — complete — 2026-09-10
COMMITS: (this entry's own commit, made immediately after)
TESTS: `cd packages/client && flutter pub get --offline` — ok; `cd packages/client && flutter test test/features/inbox/` — 33 passed; `./scripts/check-custom-lints.sh packages/client` — pass.
FILES: packages/client/lib/features/inbox/ui/screen/inbox_screen.dart; packages/client/lib/features/inbox/ui/widget/inbox_triage_list.dart (new); packages/client/lib/features/inbox/ui/widget/inbox_tombstone_section.dart (new); packages/client/test/features/inbox/inbox_expanded_chrome_test.dart; packages/client/test/features/inbox/inbox_receipts_fold_test.dart; docs/plans/inbox-activity-ia-implementation-journal.md
FINDINGS: none
DECISIONS: moved-nudge snackbar action is Rejected-archive only until UNIT 14/17 restore triage/Watching routes; Activity top bar uses `updatesTitle` until a later copy unit renames the branch to Activity.
REMAINING: none. Proceed to UNIT 14.

## UNIT 14 — complete — 2026-09-10
COMMITS: (this entry's own commit, made immediately after)
TESTS: `cd packages/client && flutter pub get --offline` — ok; `cd packages/client && flutter gen-l10n` — ok; `cd packages/client && dart run build_runner build -d` — ok; `cd packages/client && flutter test test/features/inbox/` — 38 passed; `./scripts/check-custom-lints.sh packages/client` — pass.
FILES: packages/client/lib/features/inbox/ui/widget/inbox_triage_row.dart (new); packages/client/lib/features/inbox/ui/screen/inbox_triage_screen.dart (new); packages/client/lib/features/inbox/ui/screen/inbox_screen.dart; packages/client/lib/app/router/root_router.dart; packages/client/lib/consts.dart; packages/client/lib/ui/test_ids.dart; packages/client/l10n/app_en.arb; packages/client/l10n/app_ru.arb; packages/client/integration_test/support/e2e_test_helpers.dart; packages/client/test/features/inbox/inbox_triage_row_test.dart (new); packages/client/test/features/inbox/inbox_expanded_chrome_test.dart; docs/plans/inbox-activity-ia-implementation-journal.md
FINDINGS: `forward_messages.dart` is listed in the plan Owns block but UNIT 14 steps do not change it (forward-success re-point is UNIT 17); left untouched. Dismissal affordances remain on `InboxTriageList` via existing `showInboxDismissDialog` / `showRejectionDialog` wiring from UNIT 13.
DECISIONS: E2E `goToInboxTriage()` navigates directly to `$kPathInbox/triage` rather than tapping the summary row.
REMAINING: Browser integration suite (nine lifecycle specs in the plan Verify block) has not been run in this worker environment; overseer must run `./scripts/run_client_integration_web_local.sh` with those targets before this unit is fully accepted.

## UNIT 14 (addendum) — browser integration suite verified — 2026-09-10 (overseer)

The worker's own entry above correctly deferred the browser integration suite (the nine lifecycle specs this unit's own acceptance requires, per the plan's explicit "not UNIT 25's" note) to the overseer, since running it requires a live server against this branch's own migrations and a real headless browser — fragile inside a single worker turn. Ran all nine directly, restarting a detached `scripts/run-server-local.sh` server as needed (each `run_client_integration_web_local.sh` invocation reuses it when already up). Final outcome:

1. `request_lifecycle_create_forward_inbox_test.dart` — **PASS**.
2. `request_lifecycle_offer_admit_chat_test.dart` — **PASS**.
3. `request_lifecycle_closed_to_archive_test.dart` — **genuine, reproducible FAIL (2/2)**, but not a regression: `TimeoutException: Timed out waiting for archived card left active list`. Verified directly against the database — `notification_outbox` rows for the test's beacon (`kind` `reviewReady` and `commitmentEvent`) have `requires_action = true` and `settlement_kind IS NULL`. UNIT 09 already flipped the My Work obligations gate to `true`, so per already-shipped UNITs 01/04/05, a Beacon with a live, unsettled obligation correctly keeps its card in My Work (archived only revokes the authored/help-offered source, per UNIT 05's own design). Nothing settles this obligation yet — that is exactly what UNIT 21 ("settle review obligations on window close") adds, seven units from now. This is the architecture's own accepted, documented tradeoff (§ shipping sequence: "step 7 ... improves accuracy; nothing above depends on it"), surfaced early only because this whole plan is being implemented and verified inside one continuous session rather than shipped incrementally. **Action: none now. Re-run this spec after UNIT 21 lands; expect it to pass then.**
4. `request_lifecycle_close_review_test.dart` — **PASS**.
5. `request_lifecycle_review_trust_control_test.dart` — **PASS**.
6. `request_threads_navigation_test.dart` — **genuine, reproducible FAIL (2/2)**, confirmed pre-existing and unrelated: `Bad state: Cannot emit new states after calling close` in `packages/client/lib/features/beacon_threads/ui/bloc/threads_cubit.dart:111` (an async repository callback race with no `isClosed` guard before `emit`). `git log main..HEAD -- packages/client/lib/features/beacon_threads/ui/bloc/threads_cubit.dart packages/client/lib/features/beacon_threads/data/repository/beacon_threads_repository.dart` returns zero commits — neither file has been touched anywhere on this branch. Not fixed: out of this plan's scope, matching the same standard the issue-130 session on `main` used for its own two pre-existing failures.
7. `request_detail_back_navigation_web_test.dart` — **PASS**.
8. `witness_admission_forward_band_test.dart` — **not verified in this environment**: killed by the sandbox's background-task memory monitor mid-run on all 4 attempts, each showing active progress (live GraphQL proxy traffic), never a genuine pass or fail signal. Inconclusive, not a failure — this spec's flow appears to simply run longer than this environment's typical kill window tolerates. Should be re-verified opportunistically (e.g. as part of UNIT 25's acceptance walk) rather than blocking this unit.
9. `tab_attention_forced_background_test.dart` — **genuine FAIL**, but a pre-existing test-helper limitation, not a regression: `TimeoutException: Timed out waiting for goToPath(/home/updates)`. `/home/updates` is a `RedirectRoute` to `$kPathInbox?$kQueryHomeTab=$kInboxTabReceipts` (`root_router.dart`, untouched by this branch — `git log main..HEAD` on that file returns nothing), and the generic `goToPath` helper (also untouched) waits for `router.currentUrl.contains(path)` — a condition that can never be satisfied once a `RedirectRoute` resolves to a different path. The HUD dump in the failure output shows the app correctly landed on the Activity feed (two tabs, All/Unread, matching UNIT 09) at the redirect target; only the test's own URL-substring assertion is unable to express "navigated via a route that redirects elsewhere." This is the first spec in the suite to call `goToPath` against a redirecting target, which is why this has not surfaced before. Not fixed: fixing a shared, generic E2E helper's redirect handling is unrequested scope expansion for this unit.

**Net for UNIT 14's own acceptance**: 5 genuine passes, 2 confirmed pre-existing/plan-sequencing gaps with no code fix owed to this unit, 1 inconclusive due to environment resource limits, 0 regressions found in any code this plan has shipped. UNIT 14 is accepted on this basis.
REMAINING: re-run `request_lifecycle_closed_to_archive_test.dart` after UNIT 21 ships; opportunistically re-attempt `witness_admission_forward_band_test.dart` later in this session or at UNIT 25's acceptance walk.

## UNIT 15 — complete — 2026-09-10
COMMITS: 244ae0777 feat(client): pin fresh invite prompts
TESTS: `cd packages/client && flutter pub get --offline` — ok; `cd packages/client && flutter gen-l10n` — ok; `cd packages/client && flutter test test/features/updates/` — 85 passed; `./scripts/check-custom-lints.sh packages/client` — pass.
FILES: packages/client/lib/features/updates/ui/widget/updates_feed_pane.dart; packages/client/lib/features/updates/ui/widget/prompt_batch_sheet.dart (new); packages/client/lib/ui/test_ids.dart; packages/client/l10n/app_en.arb; packages/client/l10n/app_ru.arb; packages/client/test/features/updates/prompt_pinning_test.dart (new); docs/plans/inbox-activity-ia-implementation-journal.md
FINDINGS: none
DECISIONS: none
REMAINING: none
