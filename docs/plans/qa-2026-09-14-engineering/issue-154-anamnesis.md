# Issue #154 — Back from completed child request drops to global list

**GitHub:** [Intersubjective/tentura#154](https://github.com/Intersubjective/tentura/issues/154)  
**Parent:** [#142](https://github.com/Intersubjective/tentura/issues/142)  
**Related:** [#141](https://github.com/Intersubjective/tentura/issues/141) (constellation / graph-walk back — different defect)

**Source:** 2026-09-14 product testing (Vadim 20:37)

## Symptom

From a **completed or closed child request** detail screen, the app bar **Back** control lands on the **My Work / Activity root list**, not on the **parent request** the user opened before drilling into the child. Nested navigation context is lost; the user must find the parent again manually.

Distinct from **#141**, which concerns graph-walk back inside constellation — not parent/child request stack back.

## User-facing expectation

- Open **parent request** → open **child request** (nested card) → mark child **complete/closed** → **Back** → **parent request** detail.
- Terminal lifecycle must **not** special-case back into the global list when the child was opened from a parent.

## Product path (nested open + back)

| Step | Surface | Implementation |
|------|---------|----------------|
| Open child from parent NOW | Active nested card | [`BeaconChildRequestCard`](../../packages/client/lib/features/beacon_threads/ui/widget/beacon_child_request_card.dart) → `context.router.push(BeaconViewRoute(id: …))` |
| Lineage on child NOW | Parent link (no title fetch) | [`BeaconLineageParentLink`](../../packages/client/lib/features/beacon/ui/widget/beacon_lineage_parent_link.dart) via [`beacon_now_surface.dart`](../../packages/client/lib/features/beacon_view/ui/widget/beacon_now_surface.dart) (`lineageParentBeaconId`) |
| App bar back | Compact detail chrome | [`AutoLeadingWithFallback`](../../packages/client/lib/ui/widget/auto_leading_with_fallback.dart) → [`_leaveBeaconView`](../../packages/client/lib/features/beacon_view/ui/screen/beacon_view_screen.dart) |
| Leave fallback | When stack cannot pop | `_leaveBeaconView` → `router.root.replacePath(kPathMyWork)` (default tab branch) |

## Back decision tree (as implemented)

| Condition | Action |
|-----------|--------|
| `context.router.canPop()` | `maybePop()` |
| `router.parent<StackRouter>()?.canPop()` | `parent.maybePop()` |
| Else | `router.root.replacePath` → `kPathInbox` / `kPathUpdates` / `kPathNetwork` / **`kPathMyWork`** from active home tab |

**Not consulted:** `Beacon.lineageParentBeaconId` on the mounted child detail (only used for forward tap target on NOW, not for back).

## Route / history context

| Topic | Notes |
|-------|--------|
| Browse detail stack | [`BeaconViewRoute`](../../packages/client/lib/app/router/root_router.dart) on root stack; nested parent→child is **`push`**, not replace |
| Tab-branch `replacePath` hazard | [`_syncExpandedThreadQuery`](../../packages/client/lib/features/beacon_view/ui/screen/beacon_view_screen.dart) comment (~L370): replacing through tab branch can turn `beacon/view/:id` into an unmatched relative path → AutoRoute falls back to **My Work** while keeping query params |
| Chrome / history drift | [`HomeShellChromeListenable`](../../packages/client/lib/features/home/ui/widget/home_shell_chrome_listenable.dart): query or child updates can pop UI without updating `urlState`, so in-app back and stack `canPop` can disagree with browser history |

## Root cause (engineering)

When the child detail’s stack reports **`canPop == false`** (and parent router also cannot pop) after complete/close — e.g. browse stack / URL drift or a single-frame detail without a poppable parent — **`_leaveBeaconView` unconditionally replaces to the home tab root (`kPathMyWork` by default)**. It never routes to **`lineageParentBeaconId`**, even though the child entity still carries the parent id and the NOW surface already exposes a forward link to that parent.

## Observed test run (2026-09-15)

**Command:**

```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 10m -- flutter test \
  test/features/beacon_view/issue_154_back_from_completed_child_test.dart \
  --dart-define=ENV=test \
  --dart-define-from-file=env/test.env
```

**Result:** `+0 -1` (acceptance red; bug reproduced).

| Test | Result | Observation |
|------|--------|---------------|
| `back returns to lineage parent instead of My Work list` | **Fail** | After back on closed child with `lineageParentBeaconId`, `router.root.replacePath` receives **`/home/work`** (`kPathMyWork`), not parent beacon path |

## Expected behavior (fix acceptance)

- Back from a **closed/completed child** opened from a parent returns to **parent request detail** (`/beacon/view/<parentId>` or equivalent `BeaconViewRoute` pop/push), **not** My Work / Activity root.
- Same when `canPop` is false but lineage parent id is present on loaded beacon state.

## Fix direction (not implemented in TDD pass)

- In `_leaveBeaconView` (or shared browse-back helper): before `replacePath(kPathMyWork)`, if mounted [`BeaconViewCubit`](../../packages/client/lib/features/beacon_view/ui/bloc/beacon_view_cubit.dart) state has non-empty **`lineageParentBeaconId`**, **`push` or `replacePath`** to that parent beacon on the **root** browse stack (preserve home tab below), or **`maybePop` until** parent id matches — product choice, but must not drop to global list.
- Optionally align **`AutoLeadingWithFallback`** fallback with the same helper (already delegates to `_leaveBeaconView` today).
- Re-verify after fix with real nested **`RootRouter`** push (see [`nested_beacon_navigation_test.dart`](../../packages/client/test/app/router/nested_beacon_navigation_test.dart)) plus widget acceptance in `issue_154_back_from_completed_child_test.dart`.

## Files touched (TDD only)

- `packages/client/test/features/beacon_view/issue_154_back_from_completed_child_test.dart` — failing acceptance
- `docs/plans/qa-2026-09-14-engineering/issue-154-anamnesis.md` — this note

**No production code changes** in this pass.
