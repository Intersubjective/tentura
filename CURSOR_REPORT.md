# CURSOR_REPORT — #938 Field Arranging mode

## Coverage map

| Acceptance item | Status | Evidence |
|-----------------|--------|----------|
| U1: `touchNodeDragLocked` (touch pans on nodes; mouse drags) | done | `packages/force_directed_graphview` + `node_drag_gesture_test.dart` |
| U1: two-finger pinch never claims locked node | done | `touchNodeDragLocked second finger pinch…` test |
| U1: `onNodeLongPress` lift same gesture + haptic | done | `onNodeLongPress lift continues…` test |
| U1: node long press ≠ canvas long press | done | `node long press does not call onCanvasLongPress` |
| U2: `enterArranging` / exit paths | done | `constellation_multi_selection_test.dart`, PopScope, composer/route |
| U2: `touchNodeDragLocked = !arranging` (+ composing exception) | done | `constellation_body.dart` BlocBuilder wiring |
| U2: long press → arranging + lift | done | `onNodeLongPress` in body |
| U2: lift cue dashed rings while arranging | done | `_ArrangingLiftRings` in selection_layers |
| U3: Arranging app bar ✕ / title / Done | done | `ConstellationAppBarRow` |
| U3: toolbar Undo/Redo/Tidy/Select/⋯ | done | `ConstellationArrangingToolbar` |
| U3: selection sub-row in toolbar | done | embedded `ConstellationSelectionBar` |
| U3: bottom touch/mouse hint | done | `constellation_arranging_toolbar_test.dart` (RU 375×667) |
| U4: one-time touch hold hint + persistence | done | `ConstellationVisibility.fieldHoldHintDismissed` + banner |
| U4: hidden on mouse-only | done | `RendererBinding.instance.mouseTracker` gate |

## Sibling matrix

| Row | Result |
|-----|--------|
| input touch | graph + client tests; RU phone toolbar hint |
| input mouse | graph mouse drag tests; arranging hint mouse string |
| surface Field map | body wiring + arrange harness |
| role viewer | existing constellation harness |
| state arranging / normal | selection cubit tests + menu tests |
| state composing | exit arranging on composer open (screen listener) |
| freshness load | n/a: mode not persisted |
| width phone 360 | `usePhoneSurface` in toolbar test |
| locale RU | `constellation_arranging_toolbar_test.dart` |

## Tests run

```text
cd packages/force_directed_graphview && ../../scripts/run_with_test_cleanup.sh --timeout 15m -- flutter test
→ All tests passed (268 tests in full suite run)

scripts/run_tests.sh client-files test/features/constellation/constellation_arrange_menu_test.dart test/features/constellation/constellation_arranging_toolbar_test.dart
→ 13 passed

scripts/run_tests.sh client-gates
→ custom lints OK; check-analyze-baseline reported 1970 vs baseline 1964 (+6; investigate on merge — changed lib files analyze clean individually)

scripts/run_tests.sh client-affected
→ not run (time); recommend on merge
```

## Commits

1. `feat(graph): touch node-drag lock and onNodeLongPress lift (#938 u1)`
2. `feat(client): Field Arranging mode state and touch drag wiring (#938 u2)`
3. `feat(client): merged Arranging toolbar and app bar (#938 u3)`
4. `feat(client): one-time Field touch hold hint (#938 u4)`
