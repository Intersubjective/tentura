# Issue #149 — Request app-bar status stale until refresh

**GitHub:** [Intersubjective/tentura#149](https://github.com/Intersubjective/tentura/issues/149)  
**Parent:** [#142](https://github.com/Intersubjective/tentura/issues/142)  
**Related:** [#73](https://github.com/Intersubjective/tentura/issues/73) (realtime transport), [#102](https://github.com/Intersubjective/tentura/issues/102) (cross-surface consistency)  
**Source:** 2026-09-14 product testing (Vadim 20:34)

## Symptom

On an **open request detail** screen, the **app-bar / header lifecycle status** (offers, in progress, waiting for author, review, closed, etc.) does not change after the server has already moved on. Only a **full browser reload (F5)** shows the new phase.

Same failure class as #73: users cannot tell whether an action succeeded but the UI has not caught up.

## User-facing expectation

- Header status tracks **live** request state while the screen stays open.
- Lifecycle transitions from **another client** or **the author’s own actions** update the header **without** reload.
- Covers the full lifecycle band called out in the issue: offers → in progress → waiting for author → review → closed.

## How header status is derived (client)

| Layer | Path | Role |
|------|------|------|
| App bar subtitle | [`beacon_view_screen.dart`](../../packages/client/lib/features/beacon_view/ui/screen/beacon_view_screen.dart) | `beaconViewStatusSlots(l10n, state)` → `BeaconViewAppBarTitle` |
| Phase computation | [`beacon_anchor_status.dart`](../../packages/client/lib/features/beacon_view/ui/widget/beacon_anchor_status.dart) | `deriveBeaconCoordinationPhase(beaconPhaseInputFromViewState(state))` |
| State source | [`beacon_view_cubit.dart`](../../packages/client/lib/features/beacon_view/ui/bloc/beacon_view_cubit.dart) | `state.beacon.status` + room/help-offer enrichment |

The header is **not** a separate store; it mirrors `BeaconViewCubit` snapshot. Stale header ⇒ cubit did not refetch or apply an updated `Beacon` entity.

## Root cause (client)

`BeaconViewCubit` only converges lifecycle on a **full** `_fetchBeaconByIdWithTimeline` pass. That pass runs for:

- Initial load
- `RepositoryEventInvalidate<Beacon>` on `beaconChanges` (WS `beacon` kind → [`BeaconRepository`](../../packages/client/lib/features/beacon/data/repository/beacon_repository.dart))
- `help_offer` / `forward` streams (`_requestFullRefreshFor`)
- Catch-up recovery

It does **not** run when:

1. **`RepositoryEventUpdate<Beacon>`** — [`refreshAndNotify`](../../packages/client/lib/features/beacon/data/repository/beacon_repository.dart) after mutations emits **Update**, not Invalidate. [`MyWorkCubit`](../../packages/client/lib/features/my_work/ui/bloc/my_work_cubit.dart) handles Update; **`BeaconViewCubit` ignores Update** (only listens for Invalidate). Any open detail view misses in-process beacon refreshes that desk/list surfaces already applied.

2. **Targeted room invalidation** — [`_onRoomInvalidation`](../../packages/client/lib/features/beacon_view/ui/bloc/beacon_view_cubit.dart) → [`_fetchForEntityTypes`](../../packages/client/lib/features/beacon_view/ui/bloc/beacon_view_cubit.dart) refreshes messages, participants, help offers, room cue, fact cards **but never `fetchBeaconById`**. The realtime contract declares `coordination_item` impacts including **`request_detail`** ([`realtime-entity-contract.json`](../../docs/contracts/realtime-entity-contract.json)); that path is a common fan-out when coordination changes without a separate `beacon` invalidate reaching the client.

**Contrast (working path):** `help_offer` invalidation triggers `_requestFullRefreshFor` → full fetch; the control test in the issue file passes.

## Relevant code

| Area | Path | Notes |
|------|------|--------|
| Cubit subscriptions | `beacon_view_cubit.dart` | Invalidate-only on `beaconChanges`; room targeted fetch |
| Full vs targeted fetch | same | `_runFetchWithGate` vs `_fetchForEntityTypes` |
| App bar binding | `beacon_view_screen.dart` | `buildWhen` includes `p.beacon != c.beacon` (OK once cubit updates) |
| Desk parity | `my_work_cubit.dart` | Handles `RepositoryEventUpdate` |
| Existing invalidation test | `beacon_view_initial_load_test.dart` | Title change via **Invalidate** only |

## Observed test run (2026-09-15)

`+1 -2` on the issue #149 file (control `help_offer` path green; two regression tests red). Log: `/tmp/issue-149-test.log`.

## Failing tests (TDD — expected red)

**File:** `packages/client/test/features/beacon_view/issue_149_header_status_live_sync_test.dart`

| Test | Expected failure |
|------|------------------|
| `beacon RepositoryEventUpdate refreshes lifecycle for app-bar slots` | `beacon.status` stays `open` after `emitUpdate(enoughHelp)`; slots still “Looking for helpers” |
| `coordination_item room invalidation refetches beacon lifecycle for header` | No extra `fetchBeaconById`; status stays `open` after server would be `closed` |
| `help_offer invalidation keeps header lifecycle in sync (control)` | **Passes** — documents working full-refresh path |

**Command (from `packages/client`):**

```bash
../../scripts/run_with_test_cleanup.sh --timeout 10m -- flutter test \
  test/features/beacon_view/issue_149_header_status_live_sync_test.dart \
  --dart-define=ENV=test \
  --dart-define-from-file=env/test.env
```

## Expected behavior (fix acceptance)

- Open request detail: when `BeaconRepository` emits **Update** or **Invalidate** for the open id, cubit refetches (or applies update) so `state.beacon.status` and `beaconViewStatusSlots` match server.
- `coordination_item` (and any `request_detail` impact that changes lifecycle) triggers **beacon entity** convergence, not only room cue / activity slices.
- Re-run issue #149 test file green; keep control test to guard `help_offer` full refresh.

## Recommended fix (for implementer)

1. Align `BeaconViewCubit` `beaconChanges` handler with `MyWorkCubit`: on `RepositoryEventUpdate<Beacon>` for `state.beacon.id`, call `_requestFullRefreshFor` or merge `event.value` when complete.
2. In `_fetchForEntityTypes`, when invalidation types imply lifecycle (`coordinationItem`, possibly `participant` / `activityEvent`), include `fetchBeaconById` in the targeted batch **or** escalate to `_requestFullRefreshFor`.
3. Verify WS producer always emits `beacon` on `beacon.state` changes; client fix should still handle contract `request_detail` paths that arrive without beacon kind.

## Out of scope for this TDD pass

- Production code changes, commits, or pushes.
- `constellation_body_test.dart`, `home_tab_branch_routing_test.dart`, generated `*.g.dart`.
