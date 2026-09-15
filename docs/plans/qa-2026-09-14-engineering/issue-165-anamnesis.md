# Issue #165 — Parent Active child list stale after child create

**GitHub:** [Intersubjective/tentura#165](https://github.com/Intersubjective/tentura/issues/165)  
**Parent:** [#142](https://github.com/Intersubjective/tentura/issues/142)  
**Related:** [#73](https://github.com/Intersubjective/tentura/issues/73) (realtime without reload), [#149](https://github.com/Intersubjective/tentura/issues/149) (header lifecycle live sync — fixed), [#157](https://github.com/Intersubjective/tentura/issues/157) (NOW plan / `current_line` live sync — fixed separately)

**Source:** 2026-09-14 product testing (participant note 10)

## Symptom

After **creating a child request from the parent**, the parent detail screen **does not auto-refresh**. The new child is missing from the parent **NOW** tab **Active** child list until a manual reload (F5). Authors may believe creation failed.

## User-facing expectation

- Publish (or complete) child creation from the parent context.
- Return to or keep the parent detail open on **NOW**.
- **Active** nested-request cards include the new child **without** F5.

## How the Active list is rendered (client)

| Layer | Path | Role |
|------|------|------|
| NOW surface | [`beacon_now_surface.dart`](../../packages/client/lib/features/beacon_view/ui/widget/beacon_now_surface.dart) | `_HierarchyBootstrap` calls `BeaconHierarchyCubit.load()` once after first frame |
| State | [`beacon_hierarchy_cubit.dart`](../../packages/client/lib/features/beacon_threads/ui/bloc/beacon_hierarchy_cubit.dart) | `active` / `finished` / `deleted` slices from `fetchChildren` |
| Data | [`beacon_hierarchy_case.dart`](../../packages/client/lib/domain/use_case/beacon_hierarchy_case.dart) | `fetchChildren`, `publishChildDraft`, `saveChildDraft` / `createChild` |
| Create flow | [`beacon_create_cubit.dart`](../../packages/client/lib/features/beacon_create/ui/bloc/beacon_create_cubit.dart) | Child mode: `saveChildDraft` → `publishChildDraft`; **no** hierarchy cubit refresh |

Child cards are **not** part of `BeaconViewCubit`; they are a **sibling** `BeaconHierarchyCubit` scoped to the parent beacon id on [`beacon_view_host_screen.dart`](../../packages/client/lib/features/beacon_view/ui/screen/beacon_view_host_screen.dart).

## Live-update paths (BeaconHierarchyCubit)

| Signal | Handler | Refetches Active children? |
|--------|---------|---------------------------|
| Initial `load()` | `_runLoad` → `_loadGroup(active, reset: true)` | Yes (once at bootstrap) |
| `RealtimeEntityKind.beaconHierarchy` for **this** parent id | `_onHierarchyChanged` → `_runSilentRefresh` | Yes |
| Catch-up | `_catchUpsSub` → `_scheduleSilentRefresh` | Yes |
| `publishChildDraft` / successful child publish in create flow | — | **No** |
| `BeaconViewCubit` invalidations (#149 / #157) | — | **No** (different cubit) |

`BeaconHierarchyCase.hierarchyChangesFor` listens only to **`beaconHierarchy`** aggregate hints on the **parent** beacon id ([`realtime_sync_case.dart`](../../packages/client/lib/domain/use_case/realtime_sync_case.dart)).

## Server invalidation (producer)

| Event | `entity_changes` kind | Aggregate id | Notes |
|-------|----------------------|--------------|--------|
| **Published** child linked to parent | `beacon_hierarchy` | **Parent** beacon id | Covered by PG test `child publication notifies parent hierarchy recipients with actor echo` in [`beacon_hierarchy_realtime_pg_test.dart`](../../packages/server/test/data/repository/beacon_hierarchy_realtime_pg_test.dart) |
| Draft-only child row (unpublished) | *(none)* | — | `draft child save emits no beacon_hierarchy hint` in same file |

Server producer behavior for **published** children is **not** the same gap class as #157 (missing wire). The product bug is still explained on the client when the **parent hierarchy projection is not refreshed** after the authoring actor finishes publish—either because no hint is processed in time, or because there is **no local refresh** on the success path.

## #149 / #157 overlap

- **#149** — `BeaconViewCubit` header / lifecycle status via `beaconChanges` and broader full refresh; does **not** update `BeaconHierarchyCubit.active`.
- **#157** — `BeaconViewCubit.beaconRoomCue` / NOW plan line; does **not** update nested child list.

**Status vs #149/#157:** **not already-fixed** — those issues addressed **header** and **plan line** on `BeaconViewCubit`, not parent **Active children** on `BeaconHierarchyCubit`.

## Root cause (system)

1. **Client:** Parent NOW loads hierarchy **once** (`_HierarchyBootstrap`). Subsequent updates depend on **`beacon_hierarchy`** realtime hints (or catch-up). **`publishChildDraft`** and the create cubit success path do **not** call `BeaconHierarchyCubit.load()` / `refreshGroup` and do **not** emit a **local** `RealtimeEntityChange` for the parent aggregate.

2. **Client:** The authoring user can complete publish while the parent detail route stays mounted; without a processed hint or explicit refresh, `state.active.items` remains the pre-create snapshot → matches “missing until F5”.

3. **Server:** Published children **do** emit `beacon_hierarchy` for the parent (PG contract). Remaining risk is **delivery / timing** on the open tab, not absence of the event type. Draft-only creates correctly omit hints and **should not** appear in Active until publish.

## Observed test run (2026-09-15)

**Command:**

```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 10m -- flutter test \
  test/features/beacon_view/issue_165_parent_active_children_live_sync_test.dart \
  --dart-define=ENV=test \
  --dart-define-from-file=env/test.env
```

**Result:** `+1 -1` (regression pin green; acceptance red).

| Test | Result | Meaning |
|------|--------|---------|
| `matching beacon_hierarchy hint refreshes Active children (regression)` | Pass | Cubit silent refresh works when hint arrives |
| `publishChildDraft on parent leaves Active list stale without reload` | **Fail** | After publish + server-side listing would include child, cubit still empty without hint |

## Expected behavior (fix acceptance)

- After successful child **publish** from parent context, parent **Active** list includes the new child without F5.
- Fix options (product/engineering choice): local invalidation or `BeaconHierarchyCubit` refresh on publish success; optimistic insert; and/or ensure authoring actor always receives processed `beacon_hierarchy` hint for parent id on the open session.

## Files touched (TDD only)

- `packages/client/test/features/beacon_view/issue_165_parent_active_children_live_sync_test.dart` — failing acceptance + regression pin
- `docs/plans/qa-2026-09-14-engineering/issue-165-anamnesis.md` — this note

**No production code changes** in this pass.
