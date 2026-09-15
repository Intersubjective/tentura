# Issue #167 — Child-requests section text clipped on the left

**GitHub:** [Intersubjective/tentura#167](https://github.com/Intersubjective/tentura/issues/167)  
**Parent:** [#142](https://github.com/Intersubjective/tentura/issues/142)  
**Related:** [#138](https://github.com/Intersubjective/tentura/issues/138) (overlay scrollbar), [#139](https://github.com/Intersubjective/tentura/issues/139) (settings copy indent)

**Source:** 2026-09-14 product testing (participant note 9)

## Symptom

On the request **NOW** surface, the **child requests** block shows Russian copy **«Дочерние запросы»** (`beaconChildRequestsTitle`) and **«Дочерних запросов пока нет»** (`beaconChildRequestsEmpty`) **flush against the left viewport edge**, so the first glyphs look **cut off** compared with the padded operational header above.

User-facing noun: **Request** (internal `Beacon`).

## User-facing expectation

- Section title and empty-state strings are fully readable at the default session viewport.
- Horizontal alignment matches other NOW content (same inset as the operational header card).

## Product path

| Step | Surface | Implementation |
|------|---------|------------------|
| NOW tab body | Request detail | [`BeaconNowSurface`](../../packages/client/lib/features/beacon_view/ui/widget/beacon_now_surface.dart) → `CustomScrollView` slivers |
| Operational header | Padded block | [`BeaconOperationalHeaderCard`](../../packages/client/lib/features/beacon_view/ui/widget/beacon_operational_header_card.dart) — `Padding` with `tt.screenHPadding` |
| Child requests block | Unpadded sliver | Same file: `SliverToBoxAdapter(child: BeaconChildRequestsSection(...))` — **no** `SliverPadding` / horizontal inset |
| Section UI | Title, create, empty copy | [`BeaconChildRequestsSection`](../../packages/client/lib/features/beacon_threads/ui/widget/beacon_child_requests_section.dart) — `Column` only; no horizontal `Padding` |

**Contrast:** [`BeaconPeopleSurface`](../../packages/client/lib/features/beacon_view/ui/widget/beacon_people_surface.dart) wraps its body in `SliverPadding` with `tt.screenHPadding` on left and right.

## Root cause (engineering)

**Horizontal padding is applied to the operational header but not to the child-requests sliver.** `BeaconChildRequestsSection` is dropped directly into `CustomScrollView` without the `screenHPadding` inset used elsewhere on NOW/People surfaces. Copy lays out at **x = 0** relative to the scroll viewport while the header content is inset by `context.tt.screenHPadding`, producing the reported left-edge clipping / misalignment (worse on ru strings and on viewports where overlay chrome or subpixel rounding eats the edge).

No negative `Transform` or explicit `Clip` was found on this path; the defect is **missing layout inset**, not a separate clip widget.

## Fix direction (not implemented in TDD pass)

- Mirror **People** or **header** padding: wrap `BeaconChildRequestsSection` in `SliverPadding` with `EdgeInsets.symmetric(horizontal: tt.screenHPadding)` inside `BeaconNowSurface`, **or** add equivalent horizontal padding on the section root using `context.tt` tokens (`no_raw_edge_insets`).
- Re-check ru locale on a compact viewport after fix; align title row with `BeaconOperationalHeaderCard` content.

## Failing test (TDD — expected red)

**File:** `packages/client/test/features/beacon_threads/issue_167_child_requests_left_clip_test.dart`  
**Test:** `issue #167 ru child-requests title and empty copy are inset in NOW viewport`

**Command:**

```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 10m -- flutter test \
  --dart-define=ENV=test \
  --dart-define-from-file=env/test.env \
  test/features/beacon_threads/issue_167_child_requests_left_clip_test.dart
```

**Assertions:** Child-requests title and empty copy must sit at least `screenHPadding` inside the `CustomScrollView` viewport and align with the operational header’s first text (within 1px).

**Observed (2026-09-15):** `+0 -1` — `beaconChildRequestsTitle` left inset in scroll viewport is **0.0** vs required **20.0** (`screenHPadding` on compact viewport).

## Files touched (TDD only)

- `packages/client/test/features/beacon_threads/issue_167_child_requests_left_clip_test.dart` — failing acceptance
- `docs/plans/qa-2026-09-14-engineering/issue-167-anamnesis.md` — this note

**No production code changes** in this pass.
