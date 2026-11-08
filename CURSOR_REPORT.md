# #938 QA-FAIL fix round (branch `feat/938-arranging-mode`)

## Summary

Addresses QA FAIL on 7.61.9: Field tab re-enter, browser/system back, hold-hint vs camera, top arranging toolbar (2026-11-07 owner decision), camera Arrange visibility, overflow semantics.

## Commits (4)

1. `fix(client): exit arranging when leaving or re-entering Field tab`
2. `fix(client): browser back exits arranging while staying on Field`
3. `fix(client): move field hold hint clear of camera controls`
4. `fix(client): top arranging toolbar and camera overflow chrome`

## Tests

```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 15m -- \
  flutter test --dart-define=ENV=test --dart-define-from-file=env/test.env \
  test/features/constellation/constellation_arranging_qa938_fix_test.dart \
  test/features/constellation/constellation_field_arranging_gating_test.dart \
  test/features/constellation/constellation_arranging_toolbar_drag_clamp_test.dart \
  test/features/constellation/constellation_tag_hull_drag_test.dart \
  test/features/constellation/constellation_screen_layout_test.dart
scripts/run_tests.sh client-gates
```

Real-path: `wire field load then enterArranging via selection cubit` in `constellation_arranging_qa938_fix_test.dart`.

## Coverage map (QA items)

| QA item | Fix | Test |
|--------|-----|------|
| 1 Tab leave/re-enter resets arranging | `onEnter` + `onLeave` on `HomeTabTransitionListener` | `re-entering the Field tab exits Arranging` |
| 2 Browser/system back exits arranging on Field | `PopScope`, `BackButtonListener`, web `pushState` sentinel | gating + layout tests; web sentinel in `field_arranging_browser_back_web.dart` |
| 3 Hold-hint OK not under camera | Hint `Positioned` on map stack with camera right inset | `hold-hint OK clears the camera column at 375 RU` |
| 4 Top toolbar, no bottom card | Overlay toolbar in top chrome; bottom clamp removed | `Arranging toolbar sits in top chrome…`, drag_clamp test |
| Camera Arrange hidden while arranging | `constellation_camera_controls.dart` | `camera Arrange hides while already Arranging` |
| ⋯ not announced as Arrange | `constellationArrangingMoreActions` l10n | `⋯ overflow uses non-Arranging semantics` |

## Sibling notes

- Tag hull drag: stabilized chrome in harness after bottom hint move.
- Sector multi-select: `open()` uses `beginSector` directly (selection bar embedded in top toolbar when arranging).
- Tag row stays visible when not arranging to avoid map geometry regressions; toolbar overlays visibility bar while arranging.

Refs #938 (no close keyword).
