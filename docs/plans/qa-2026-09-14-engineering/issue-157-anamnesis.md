# Issue #157 — Plan / What's next stale until refresh

**GitHub:** [Intersubjective/tentura#157](https://github.com/Intersubjective/tentura/issues/157)  
**Parent:** [#142](https://github.com/Intersubjective/tentura/issues/142)  
**Related:** [#73](https://github.com/Intersubjective/tentura/issues/73) (realtime without reload), [#104](https://github.com/Intersubjective/tentura/issues/104) (plan around current state), [#149](https://github.com/Intersubjective/tentura/issues/149) (header lifecycle live sync — fixed separately)

**Source:** 2026-09-14 product testing (Vadim 20:49)

## Symptom

On request detail **NOW** / **Plan** / **What's next**, the pinned plan line (`beacon_room_state.current_line`) does not change while the screen stays open. Another participant (or another control on the same request) can update the plan on the server; the viewer still sees the old text until **F5**.

Same trust class as #73: coordination state on NOW is not live.

## User-facing expectation

- Plan / What's next reflects the **current** `current_line` while the detail view is open.
- **Client A** edits plan; **Client B** sees the new text **without** reload.

## How Plan is derived (client)

| Layer | Path | Role |
|------|------|------|
| NOW primary text | [`beacon_hud_derivation.dart`](../../packages/client/lib/features/beacon_view/ui/util/beacon_hud_derivation.dart) | `beaconHudNowLine` / `beaconHudNowDisplay` prefer `state.beaconRoomCue?.currentLine` |
| State source | [`beacon_view_cubit.dart`](../../packages/client/lib/features/beacon_view/ui/bloc/beacon_view_cubit.dart) | `beaconRoomCue` from `fetchRoomStateIfAllowed` → `BeaconThreadsCase.fetchBeaconRoomState` |
| Local edit | [`beacon_now_surface.dart`](../../packages/client/lib/features/beacon_view/ui/widget/beacon_now_surface.dart) | `onSaved` → `refreshBeaconRoomCue(savedCurrentLine: …)` (same client only) |
| Server write | [`beacon_room_case.dart`](../../packages/server/lib/domain/use_case/beacon_room_case.dart) | `updateRoomNowLine` → `beacon_room_state` row + `coordinationChanged` attention (no coordination plan item) |

Plan text is **not** on the `Beacon` entity; it lives in **`beacon_room_state`**.

## Live-update paths (BeaconViewCubit)

| Signal | Handler | Refetches `beaconRoomCue`? | Notes |
|--------|---------|---------------------------|--------|
| Initial / gated full fetch | `_fetchBeaconByIdWithTimeline` | Yes | Parallel `fetchRoomStateIfAllowed` |
| `RepositoryEventUpdate` / `Invalidate` on `beaconChanges` | `_requestFullRefresh` → full fetch | Yes | **#149** added `Update` handling (header lifecycle) |
| `coordination_item` room invalidation | `_requestFullRefresh` (since #149) | Yes | Was targeted-only before #149; still refetched cue via `needRoomState` even then |
| `help_offer` / `forward` | `_requestFullRefreshFor` | Yes | Control path |
| `activity_event` room invalidation | `_runTargetedFetch` | **No** | Only `request_activity` slice |
| `room_message` room invalidation | `_runTargetedFetch` | **No** | Chat / activity only |
| Catch-up | `_requestFullRefresh` | Yes | Only after reconnect-style catch-up |

### #149 overlap (header vs plan)

**#149 does not overwrite Plan with stale header data.** Full refresh replaces `beaconRoomCue` from a fresh `fetchBeaconRoomState` alongside `beacon.status`. The regression tests in the issue #157 file show that `coordination_item` invalidation and `RepositoryEventUpdate` both converge **plan and** lifecycle when the repository returns updated room state.

**#149 is not a duplicate fix for #157.** It fixed **lifecycle header** convergence and broadened full refresh triggers; it did **not** add a realtime wire kind for `beacon_room_state` or teach targeted invalidations to refresh the NOW line.

## Root cause (system)

1. **Server:** `updateRoomNowLine` updates `beacon_room_state` and emits **`coordinationChanged`** attention / outbox ([`room_now_line_pg_test.dart`](../../packages/server/test/domain/use_case/room_now_line_pg_test.dart)); it does **not** create a published coordination plan item and there is **no** `beacon_room_state` entry in [`realtime-entity-contract.json`](../../docs/contracts/realtime-entity-contract.json). Remote viewers are unlikely to receive `coordination_item` or `beacon` entity changes for a plan-only edit.

2. **Client:** `BeaconRoomInvalidation.fromRealtimeChange` has **no** mapping for room-state rows. Even when the UI receives **`activity_event`** or **`room_message`** invalidations (timeline / chat), [`_fetchForEntityTypes`](../../packages/client/lib/features/beacon_view/ui/bloc/beacon_view_cubit.dart) does **not** call `_refreshBeaconRoomCue`.

Together: **Client B** can sit on an open detail view with no invalidation that refetches `current_line` → stale Plan until manual reload (or catch-up full refresh).

## Observed test run (2026-09-15)

**Command:**

```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 10m -- flutter test \
  test/features/beacon_view/issue_157_plan_live_sync_test.dart \
  --dart-define=ENV=test \
  --dart-define-from-file=env/test.env
```

**Result:** `+2 -2` (two regression pins green; two acceptance tests red).

| Test | Result | Meaning |
|------|--------|---------|
| `coordination_item invalidation refetches room cue for NOW plan (regression)` | Pass | Cubit + full refresh path OK when this signal arrives |
| `beacon RepositoryEventUpdate refetches room cue for NOW plan (regression)` | Pass | #149 `Update` path also refreshes plan data |
| `activityEvent room invalidation refreshes NOW plan without reload` | **Fail** | Targeted fetch leaves `currentLine` stale |
| `room_message invalidation refreshes NOW plan when chat updates plan text` | **Fail** | Same gap for chat-shaped signals |

## Expected behavior (fix acceptance)

- Open detail NOW shows live `current_line` for remote edits without F5.
- Contract option A: publish a realtime invalidation for `beacon_room_state` (or map `coordinationChanged` → `request_detail` refresh).
- Contract option B: extend `_fetchForEntityTypes` (or attention-driven invalidation) so production signals for plan edits call `_refreshBeaconRoomCue`.
- Keep regression pins green for `coordination_item` + `RepositoryEventUpdate` full-refresh convergence.

## Files touched (TDD only)

- `packages/client/test/features/beacon_view/issue_157_plan_live_sync_test.dart` (new)
- `packages/client/test/features/beacon_view/beacon_view_case_test_support.dart` (`FakeBeaconViewRoomRepository.fetchBeaconRoomState`)

No production code changes in this pass.
