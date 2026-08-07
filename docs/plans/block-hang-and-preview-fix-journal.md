# Implementation journal — block-hang-and-preview-fix-plan

**Objective:** fix GitHub issue #111 (blocking hang / unscoped invalidation /
missing confirmation / capped-preview gap). Plan source:
[`block-hang-and-preview-fix-plan.md`](block-hang-and-preview-fix-plan.md).

**Repository:** `/home/vader/MY_SRC/tentura`, branch `main`, starting HEAD
`cacf4a9c88d888de84ba7047c9abc8b2c3050ef0`.

**Pre-existing worktree changes at plan start (not owned by this plan — do not
touch, revert, or commit them):**

```
 M CONTEXT.md
 M docs/README.md
 M docs/archive/journals/commitment-truth-rework-journal.md
 M docs/archive/plans/commitment-truth-rework-plan.md
 M docs/audits/room-coordination-audit.md
 M packages/client/web/index.html          (benign cache-busting version bump)
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

(`docs/plans/block-hang-and-preview-fix-plan.md` and this journal are new,
untracked, and owned by this plan.)

## Unit checklist

| Unit | Description | Status |
|---|---|---|
| P1 | Wire up GraphQL transport timeout (`build_client.dart`) | complete |
| P2 | Scope block-visibility graph-cache invalidation (`graph_cubit.dart`) | complete |
| P3 | Block confirmation snackbar + live profile refresh | complete |
| P4 | Surface capped cascade count in block preview | pending |
| P5 | Manager-run full regression pass (not a worker unit) | pending |

Dependencies: P1–P4 touch disjoint files and have no code dependency on each
other, but run sequentially per the operating contract (one worker at a
time). P5 runs only after P1–P4 are all accepted.

## Verification commands (from plan §2)

```bash
cd packages/client && flutter analyze
cd packages/client && flutter test
```

Plus each unit's own targeted test path (see plan).

## Decisions / blockers

- None yet.

## Checkpoint — P1 complete (2026-08-07)

**Changes:**
- Added `_TimeoutLink` as the first link in `build_client.dart`, wrapping all
  downstream transport with `params.requestTimeout` except
  `BeaconAddImage`, `BeaconStageImage`, and `BeaconSetMedia`.
- Timeout errors route through `mapRemoteFailure` → `ConnectionUplinkException`.
- Optional `httpClient` parameter on `buildClient()` for test injection.
- New `build_client_test.dart` with hanging `MockClient` coverage.

**Verification:**
- `cd packages/client && flutter test test/data/service/remote_api_client/` — pass (6 tests)
- `cd packages/client && flutter analyze` — 766 pre-existing infos, no new errors in changed files

**Commit:** `666af9fd` — fix(client): cap GraphQL link chain with requestTimeout (P1)

## Checkpoint — P2 complete (2026-08-07)

**Changes:**
- `_onBlockVisibilityChanged` now uses the `event` parameter and returns early
  when `event.id` is neither in `_nodes` nor the ego node — unrelated block
  events no longer wipe the graph cache or trigger a refetch.
- Extended `block_cache_invalidation_test.dart`: existing case now blocks the
  ego id (`Ume`) to assert refetch still happens for relevant events; new case
  blocks `U-unrelated` and asserts `fetch()` is not called again.

**Verification:**
- `cd packages/client && flutter analyze` — pass (760 pre-existing infos, no new errors)
- `cd packages/client && flutter test test/features/block/block_cache_invalidation_test.dart` — pass (2 tests)
- `cd packages/client && flutter test test/features/graph/` — pass (132 tests)

**Commit:** `fde73c8b` — fix(client): scope graph cache invalidation on block events (P2)

## Checkpoint — P3.1 complete (2026-08-07)

**Changes:**
- After a successful block, `BlockUserSheetBody` shows a confirmation snackbar
  (`blockConfirmedMessage` / `blockManageAction` l10n keys) before popping the
  sheet; the Manage action calls `GetIt.I<RootRouter>().push(BlockedUsersRoute)`
  (matches deferred-navigation pattern used elsewhere in the app).
- Extended `block_user_sheet_test.dart`: `FakeBlockCase.block()` implementation,
  snackbar + manage-action navigation tests (`_RecordingRootRouter` via GetIt).
- Client patch bump `5.6.47` → `5.6.48`.

**Verification:**
- `cd packages/client && flutter test test/features/block/ui/sheet/block_user_sheet_test.dart` — pass (7 tests)

**Commit:** `215387ef` — feat(client): show block confirmation snackbar with manage link (P3.1)

## Checkpoint — P3.2 complete (2026-08-07)

**Changes:**
- `ProfileViewCubit` subscribes to `_blockCase.changes` filtered to the open
  profile id and debounces a silent refetch (same `_scheduleSilentFetch` path as
  projection changes).
- Removed unscoped `_blockCase.changes` from `ProfileViewCase.projectionChanges`
  and dropped the unused `BlockCase` constructor dependency (scoped invalidation
  now lives in the cubit only).
- Extended `profile_view_cubit_test.dart`: same-id block event refetches; different-id
  does not.

**Verification:**
- `cd packages/client && flutter test test/features/block/ test/features/profile_view/` — pass (36 tests)
- `cd packages/client && flutter analyze` — 774 pre-existing infos, no new errors

**Commit:** `0a72eba1` — fix(client): refresh open profile on scoped block changes (P3.2)

## Final entry — P3 worker exit (2026-08-07)

P3 (P3.1 + P3.2) complete. P4 (capped cascade preview copy) and P5 (manager
regression pass) remain for subsequent workers.
