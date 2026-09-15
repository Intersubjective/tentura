# Issue #168 — Duplicate overflow menus in request header (split layout)

**GitHub:** [Intersubjective/tentura#168](https://github.com/Intersubjective/tentura/issues/168)  
**Parent:** [#142](https://github.com/Intersubjective/tentura/issues/142)  
**Related:** [#104](https://github.com/Intersubjective/tentura/issues/104)

**Source:** 2026-09-14 product testing (participant note 30)

## Symptom

On **request detail** at **expanded** width, when the **secondary pane** (discussion / General thread) is open beside the **NOW** surface (fact / management column), the top chrome shows **two identical ⋮ overflow controls** in one header row. Users cannot tell which menu applies to which pane; dangerous actions are behind an ambiguous control.

User-facing noun: **Request** (internal `Beacon`). Secondary pane is the **discussion** workspace (internal thread / room split).

## User-facing expectation

- **One** overflow menu per header chrome, scoped to that pane, **or** a single combined menu with clear grouping / pane labels.
- Acceptance: with the fact/management column and discussion pane both visible, only **one** ⋮ per header region, or each ⋮ is labeled by pane.

## Product path

| Step | Surface | Implementation |
|------|---------|----------------|
| Expanded width | Split NOW + discussion | [`BeaconViewScreen`](../../packages/client/lib/features/beacon_view/ui/screen/beacon_view_screen.dart) — `_computeIsSplit` + `TenturaTopBar` `row` |
| Compact width | Single AppBar `actions` | Same file — `actions: [beaconViewAppBarOverflow(...)]` when `!isSplit` |
| Split header row | Left + right panes | `row` `LayoutBuilder` builds a `Row`: left `managementOverflow`, right `_splitThreadPaneAppBar(..., overflow: roomOverflow)` |
| Overflow widget | ⋮ + menu | [`beaconViewAppBarOverflow`](../../packages/client/lib/features/beacon_view/ui/widget/beacon_view_app_bar_overflow.dart) → [`BeaconOverflowMenu`](../../packages/client/lib/features/beacon/ui/widget/beacon_overflow_menu.dart) (`Icons.more_vert`) |

## Root cause (engineering)

**Split mode intentionally clears `TenturaTopBar.actions` (`isSplit ? null`) but mounts two independent `beaconViewAppBarOverflow` widgets in the custom `row`:**

1. **`managementOverflow`** — `inRoomSurface: false` on the left (NOW / request management chrome).
2. **`roomOverflow`** — `inRoomSurface: true` passed into `_splitThreadPaneAppBar` on the right (discussion pane).

Both call sites gate on `showBeaconContent` and each returns a full `BeaconOverflowMenu` with the same ⋮ icon. There is no pane label, no shared menu, and no deduplication. Compact layout only renders one overflow (AppBar `actions`); the duplicate appears **only in split**, matching QA.

`beaconViewAppBarOverflow` already varies **menu entries** via `inRoomSurface` (`showBeaconManagementOverflow`, room create/update actions), but the **chrome control is duplicated**.

## Fix direction (not implemented in TDD pass)

Pick one product-consistent approach:

- **Single overflow in split:** one `beaconViewAppBarOverflow` (or merged menu) for the combined header, with grouped sections for NOW vs discussion actions; **or**
- **Pane-scoped chrome:** keep two menus only if each ⋮ is visually and semantically distinct (label, tooltip, or position policy documented in design system); **or**
- **Right-pane-only overflow in split:** drop `managementOverflow` from the left split row and relocate management actions (higher risk — verify author flows).

Minimal engineering fix aligned with acceptance “one ⋮”: render **one** overflow in split `row` and merge/dispatch actions by pane inside `beaconViewAppBarOverflow` / `BeaconOverflowMenu`.

## Failing test (TDD — expected red)

**File:** `packages/client/test/features/beacon_view/issue_168_duplicate_overflow_menus_test.dart`  
**Test:** `issue #168 expanded split shows one header overflow menu`

**Command:**

```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 10m -- flutter test \
  --dart-define=ENV=test \
  --dart-define-from-file=env/test.env \
  test/features/beacon_view/issue_168_duplicate_overflow_menus_test.dart
```

**Assertions:** After split layout settles (`TenturaVerticalResizeHandle` + `ThreadDetail`), `find.byIcon(Icons.more_vert)` is `findsOneWidget`.

## Files touched (TDD only)

- `packages/client/test/features/beacon_view/issue_168_duplicate_overflow_menus_test.dart` — failing acceptance
- `docs/plans/qa-2026-09-14-engineering/issue-168-anamnesis.md` — this note

**Observed (2026-09-15):** `+0 -1` — `find.byIcon(Icons.more_vert)` finds **2** widgets in expanded split (expected `findsOneWidget`).

**No production code changes** in this pass.
