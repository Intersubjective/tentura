# Constellation UI remediation — implementation journal

Objective: implement `docs/plans/constellation-ui-remediation-plan.md` (rev 2), units R00–R08, remediating UI-01..UI-14.

Plan source: `docs/plans/constellation-ui-remediation-plan.md` (untracked in git; pre-existing, do not commit or edit it).

Orchestration: Claude (overseer) drives one fresh Cursor `composer-2.5` worker per unit, reviews every result, and records the manager verdict here.

## Start state (2026-09-14)

- Repository: `/home/vader/MY_SRC/tentura`, branch `main`.
- Starting HEAD: `2a3ddc333` feat(client): add tongue-in-cheek RPG capability category.
- Client version at start: `7.8.0` (the plan's 7.6.x numbers are stale; R08 reads the version at implementation time).
- Pre-existing uncommitted changes (NOT owned by this plan; never stage, revert, or rewrite):
  - `M packages/client/test/app/router/home_tab_branch_routing_test.dart` (adds a constellation→profile routing test)
  - `M packages/client/test/features/constellation/constellation_body_test.dart` (adds a profile-navigation test and makes `_pumpBody` return a `FakeUiEffectPort`)
  - many untracked files (`docs/plans/*.md`, `CLAUDE.local.md`, `dart-defines`, `key.fb`, `out.key`, product testing reports, ...). Never stage them.
- A separate interactive `codex` session may be running in this repository. Stage files **by explicit path only**; never `git add -A` / `git add .` / `git commit -a`.

## Manager decisions

- **D-M1 (constellation_body_test.dart is off-limits).** It carries pre-existing uncommitted edits from other work. Plan steps that say "move `_pumpBody` from `constellation_body_test.dart`" or "widget test in `constellation_body_test.dart`" are redirected: the shared helper lives in the new fixture file (duplicated, not moved), and new tests go into new test files. Do not modify `constellation_body_test.dart` until the owner commits those edits.
- **D-M2 (§6.1.1 compact Field nav label).** Default kept: no change to `home_screen.dart` / `home_bottom_navigation_bar.dart`.
- **D-M3 (§6.1.2 per-author density).** Formula unchanged; owner note only.
- **D-M4 (R03 split).** Plan unit R03 is too large for one reliable Cursor turn (9 steps: new pure-geometry module, tap resolver, overlay widget wiring, badge redesign, footprint-metric plumbing, plus its own large test suite). Split into **R03a** (pure-Dart `constellation_presentation_frame.dart` + tap resolver + overflow-chip sizing helper + tokens — plan R03 steps 1-4, unit-tested in isolation, no widget-tree wiring) and **R03b** (wire the overlay into `constellation_body.dart`, remove `_MapOverflowOverlay`, redesign pin/status badges as top-corner badges, plumb footprint metrics to the cubit — plan R03 steps 5-9, plus the full plan-R03 widget test suite). R04 now depends on R03b instead of R03.
- **D-M5 (R04 split).** Plan unit R04 (6 steps: drawn-only layout set, footprint types threaded through two record-typed construction sites plus `ConstellationSceneLayoutAlgorithm`'s `==`/`hashCode`, obstacle-aware automatic placement, satellite/ego-fan geometry, attachment-crossing preference, a diagnostics helper, plus a large domain test suite) is split the same way. **R04a** (this unit's target on launch): steps 1-3 (`constellationDrawnSatellites` UI-11 fix, `ConstellationFootprint`/`ConstellationFootprintMetrics` plumbing into `ConstellationPlacedLayoutInput` and `ConstellationSceneLayoutAlgorithm`, obstacle-aware `_chooseAutomaticPosition` with the author-exemption removed) plus step 6's small `constellationFootprintOverlaps` diagnostic (needed by R04b's tests). **R04b**: steps 4-5 (ego-fan direction via largest-angular-gap bisector, satellite radius/chord from footprints, attachment-crossing candidate preference) plus the full plan-R04 test suite (A3 person-position guard, pins-exact, ego-direction cases, crossing-preference case, and running/updating the existing `constellation_p06_composition_layout_test.dart`/`tentura_layout_algorithms_test.dart`/`constellation_scene_layout_test.dart`/density tests). R05/R06/R07 continue to depend only on R02/R03b as already recorded; R08 depends on R04b (not R04a alone).
- **D-M6 (worker test/lint parallelism guard).** After R03b's launch was killed 8 times in a row by an external low-memory guard (recorded in "Open decisions / blockers" below, now resolved), the shared worker prompt (`common.txt` in the overseer scratchpad) was updated to forbid `-j`/`--concurrency` flags on `flutter test`/`dart analyze`, require confirming via `ps` that only one heavy test/analyze process runs at a time, and require checking `MemAvailable` before stepping up test scope (single file → directory → whole package). Applies to every unit from R04a onward.

## Unit checklist

| Unit | Depends on | Status | Commits | Manager verdict |
|---|---|---|---|---|
| R00 fixture + baseline | — | done | c690eca44, 47e9bf065 | accepted — smoke test independently re-run (pass), `git diff --check` clean, no leaked test processes |
| R01 label budget (ships alone) | R00 | done | 4dcca824a, 9843bb9d1 | accepted — independently re-ran full `test/features/constellation` (265 pass), `test/features/graph test/features/home` (pass), `check-custom-lints.sh packages/client` (30/30, no drift); diff reviewed, matches UI-09/UI-10 fix design; `_MapOverflowOverlay` `ListenableBuilder` addition is a reasonable documented deviation, superseded by R03 |
| R02 graph package seams | R01 landed | done | baea36507, b03f9e598, d9dadf575, bcf3d20f1, 6b6b25c6b | accepted — independently re-ran the 5 targeted package tests, full package suite (112 pass), `dart analyze` (0 errors, pre-existing INFO-only), and `test/features/graph` on client (217 pass, compatibility gate); diff reviewed — camera-revision listener rebind/dispose is correct, tap-hit-tester shares one drag-pass snapshot for body+tap as required, RepaintingEdgePainter generalization is minimal and correct; zero client files touched |
| R03a presentation-frame + tap-resolver (split of R03, part 1) | R02 | done | da8ab8215, 379dc4f1f, 038d26e0b, 7c13b1b1f, 94fda7db9, c377ac3cb | accepted — independently re-ran the 12 new unit tests, full `test/features/constellation` (277 pass), `check-custom-lints.sh` (30/30, no drift); algorithm diff matches plan §3.3/§3.4 step-for-step (cull/decorated-body/chip-then-label ordering, forced-label rule, tap-resolver 3-phase order); tap resolver cleanly split into its own file, chip-size helper matches formula exactly |
| R03b wire overlay + badges + R03 tests (split of R03, part 2) | R03a | done | 185d5af80, c1e8b9ad8, 24a9abe90, cc16577de, 2a0dff449, 09fea0d8e, c4addd3af, 9838597fd | accepted — independently re-ran the 9 new UI-03/UI-13/UI-14 tests, full `test/features/constellation` (286 pass), `test/features/graph` (217 pass), terminology + lint gates clean (30/30, no drift); diff reviewed — `_MapOverflowOverlay` fully removed, `labelBuilder: null`, badges use `PositionedDirectional` with no `bottom:` offset anywhere, `nodeTapHitTester` stale-frame guard matches §3.4, unknown-status suppresses the status badge; `updateFootprintMetrics` deliberately stores-only (no reconcile) with the follow-up flagged for R04 |
| R04a drawn-only set + footprints + obstacles (split of R04, part 1) | R03b | done | (see final entry) | pending review |
| R04b satellite geometry + crossing preference + R04 tests (split of R04, part 2) | R04a | pending | | |
| R05 edge legibility | R02 | pending | | |
| R06 targeting + semantics | R02, R03b | pending | | |
| R07 camera recovery + app bar | R02, R03b | pending | | |
| R08 integrate, verify, release | R00–R07 (R04→R04a+R04b, R03→R03a+R03b) | pending | | |

## Verification commands (plan §5.3, run serially)

```bash
# repository root
git diff --check
bash scripts/check-user-facing-terminology.sh
# packages/force_directed_graphview
flutter test test/controller_test.dart test/node_drag_gesture_test.dart test/scene_rendering_test.dart test/scene_layout_protocol_test.dart test/scene_controller_layout_lifecycle_test.dart
flutter test
dart analyze --format machine
# packages/client
flutter gen-l10n        # only if ARB files changed
flutter test test/features/constellation test/architecture/constellation_domain_graph_boundary_test.dart
flutter test test/features/graph test/features/home/constellation_nav_test.dart test/design_system
# repository root
./scripts/check-custom-lints.sh packages/client
# packages/client
flutter test
# repository root (browser, memory-sensitive, one at a time)
./scripts/run_client_integration_web_local.sh integration_test/constellation_readability_test.dart
./scripts/run_client_integration_web_local.sh integration_test/constellation_pinning_test.dart
```

## Open decisions / blockers

- **R03b launch blocked (2026-09-14 ~20:24-20:35).** Six consecutive attempts to launch the R03b Cursor worker were killed by an external "system is running low on memory" guard, even though `/proc/meminfo`/`free -h` showed ~30GB `MemAvailable` and load <1.0 immediately after every kill (raw `MemFree` hovered at 6-7GB with 24GB reclaimable cache each time — possibly the guard thresholds on raw free rather than available memory, unconfirmed). One attempt (of six) ran long enough to make real progress before also being killed. No leaked cursor-agent processes and no corrupted git state resulted. A small, safe, additive partial edit from the killed attempt is left uncommitted in `constellation_anchor_composition.dart` (adds `expandedExtraCountByAuthor` field with a default — matches plan R03 step 5's first move) and is intentionally kept for the next attempt to build on rather than discarded. Filed as harness feedback (SendFeedback). Next step: retry R03b once conditions look stable, or ask the owner if other memory-heavy applications should be closed first.

## Entries

<!-- Workers append entries below, newest last. Format: `### <unit> — <worker|manager> — <checkpoint|final|verdict>` -->

### R00 — worker — checkpoint

- Implemented `fixtures/constellation_reference_fixture.dart` and smoke test per plan §4 R00; duplicated `_pumpBody` / stub patterns (D-M1: did not touch `constellation_body_test.dart` or `constellation_density_widget_test.dart`).
- Optional pinning: `constellationReferenceField(anchors: …)` sets `ConstellationAnchorProjection` (same shape as `constellation_anchor_interaction_test.dart` `_field`). R03 can pass e.g. `ConstellationAnchorTarget.beacon('req-in-2')` and `ConstellationAnchorTarget.person('am')`.
- Deviation: plan prose “move helper / keep old tests calling shared helper” overridden by D-M1 — no imports refactored in existing tests.

### R00 — worker — final

**Status:** complete

**Commits:** `c690eca44` test(client): add Constellation reference fixture for UI remediation

**Changed files:**
- `packages/client/test/features/constellation/fixtures/constellation_reference_fixture.dart` (new)
- `packages/client/test/features/constellation/constellation_reference_fixture_smoke_test.dart` (new)
- `docs/plans/constellation-ui-remediation-journal.md`

**Tests:**
- `cd packages/client && flutter test test/features/constellation/constellation_reference_fixture_smoke_test.dart` — pass
- `cd packages/client && flutter test test/features/constellation` — 256 passed
- `./scripts/check-custom-lints.sh packages/client` — pass (no baseline drift)

**Baseline record (375×547, `locale: ru`, `textScale: 1.0`, reference field default `egoRequestCount: 6`):**

| Metric | Plan expectation | Measured (HEAD with UI-09 unfixed) |
|---|---|---|
| Label budget `textScaleFactor` passed to cubit | 14.0 (UI-09 bug) | **14.0** — from `MediaQuery.textScalerOf(context).scale(14)` in `constellation_body._syncLabelBudget` |
| Derived `constellationLabelBudget` at that scale | (1, 2) per R01 table | **(perPerson: 1, total: 2)** |
| `overflowHiddenCountByAuthor` after first load | `{ego: 3}` | **`{ego: 3}`** |
| After `toggleSatelliteOverflow('in')` ×2 (body still pumped) | ego → 5 (UI-10) | **`{ego: 5, in: 2, sm: 1}`** — ego 5 matches UI-10 proof; `in`/`sm` counts reflect expanded satellite overflow state |
| `BottomLabelBuilder.labelSize` | — | **`Size(100, 20)`** (`constellation_body.dart`) |
| Overflow chip vs `req-ego-*` body rects | — | Chip `Rect.fromLTRB(107.5, 341.5, 242.5, 385.5)`; only **req-ego-1** has a body in the tree (`Rect.fromLTRB(229.9, 290.4, 265.9, 326.4)`); **no intersection**. req-ego-2..6 not in widget tree (label budget hides them). |
| `pumpAndSettle` on smoke/baseline pump | — | **Completed** (no perpetual-animation timeout in temp capture) |
| Browser screenshot (plan step 4) | optional R00 | **skipped** (manager R08) |

**Decisions:** `kRefEgo.displayName` = `Vadim` per plan; tier-1 edges one direction `ego → peer` matching existing widget tests; long titles for `req-ego-4`..`6` are synthetic mixed-script strings (plan did not spell exact copy).

**Remaining:** R01+ units per checklist.

### R01 — worker — checkpoint

- Implemented post-frame `_scheduleLabelBudgetSync` (ratio from `TenturaText.labelSmall` / 13), outer `LayoutBuilder` on all `BlocBuilder` branches, cubit `_currentLabelBudget` / `_appliedLabelBudget`, recompose on budget change with placement deferral.
- Deviation: plan did not mention `_MapOverflowOverlay` needing `ListenableBuilder` on `graphController` — without it, overflow chips did not appear after async layout once budget sync moved off the build path (`constellation_text_view_test` caught this).
- D-M1: widget text-scale tests in `constellation_label_budget_widget_test.dart`; `constellation_body_test.dart` untouched.
- `constellation_text_view_test._pumpBody`: extra `pump()` for post-frame budget callback.

### R01 — worker — final

**Status:** complete

**Commits:** `4dcca824a` fix(client): recompose constellation label budget on viewport and text scale

**Changed files:**
- `packages/client/lib/features/constellation/ui/widget/constellation_body.dart`
- `packages/client/lib/features/constellation/ui/bloc/constellation_cubit.dart`
- `packages/client/lib/features/constellation/domain/constellation_density.dart`
- `packages/client/test/features/constellation/constellation_density_test.dart`
- `packages/client/test/features/constellation/constellation_label_budget_context_test.dart` (new)
- `packages/client/test/features/constellation/constellation_label_budget_widget_test.dart` (new)
- `packages/client/test/features/constellation/constellation_tab_reselect_test.dart`
- `packages/client/test/features/constellation/constellation_text_view_test.dart`
- `packages/client/test/features/constellation/fixtures/constellation_reference_fixture.dart`
- `docs/plans/constellation-ui-remediation-journal.md`

**Tests:**
- `cd packages/client && flutter test test/features/constellation/constellation_density_test.dart test/features/constellation/constellation_label_budget_context_test.dart test/features/constellation/constellation_label_budget_widget_test.dart test/features/constellation/constellation_tab_reselect_test.dart` — pass
- `cd packages/client && flutter test test/features/constellation` — 265 passed
- `cd packages/client && flutter test test/features/graph test/features/home` — pass
- `./scripts/check-custom-lints.sh packages/client` — pass

**Decisions:** Formula table verified unchanged (375×547 @1.0 → (1,28), etc.). No client version bump per unit instructions.

**Remaining:** Manager commit hash + verdict; R02+.

### R02 — worker — checkpoint

- Implemented camera `cameraRevision` / `cameraScale` / `viewportSize`, viewport-aware `fitToRect` / `jumpToPosition`, `NodeTapHitTester`, and `RepaintingEdgePainter` in `packages/force_directed_graphview` only.
- Deviation: `fitToRect` uses `rawScale.clamp(min(minBound, maxBound), max(minBound, maxBound))` so an explicit `maxScale` below the InteractiveViewer boundary floor does not throw (plan prose used bare `clamp` which fails when `maxScale < _boundaryMinScale()`).
- Reverted unintended `analysis_options.yaml` exclude block auto-added by `flutter test` (not part of R02).

### R02 — worker — final

**Status:** complete

**Commits:** `baea36507` feat(graph): expose camera revision, scale, and viewport-aware fit/jump; `b03f9e598` feat(graph): add opt-in node tap hit tester seam; `d9dadf575` feat(graph): add RepaintingEdgePainter interface; `bcf3d20f1` docs(plan): R02 graph package seams journal

**Changed files:**
- `packages/force_directed_graphview/lib/src/controller.dart`
- `packages/force_directed_graphview/lib/src/configuration.dart`
- `packages/force_directed_graphview/lib/src/graph_view.dart`
- `packages/force_directed_graphview/lib/src/widget/node_drag_gesture.dart`
- `packages/force_directed_graphview/lib/src/edge_painter/edge_painter.dart`
- `packages/force_directed_graphview/lib/src/widget/edges_view.dart`
- `packages/force_directed_graphview/test/controller_test.dart`
- `packages/force_directed_graphview/test/node_drag_gesture_test.dart`
- `packages/force_directed_graphview/test/scene_rendering_test.dart`
- `docs/plans/constellation-ui-remediation-journal.md`

**Tests:**
- `cd packages/force_directed_graphview && flutter test test/controller_test.dart test/node_drag_gesture_test.dart test/scene_rendering_test.dart test/scene_layout_protocol_test.dart test/scene_controller_layout_lifecycle_test.dart` — pass (55 tests)
- `cd packages/force_directed_graphview && flutter test` — pass (112 tests)
- `cd packages/force_directed_graphview && dart analyze --format machine` — exit 2 (pre-existing warnings/info only; no new errors in owned files)
- `cd packages/client && flutter test test/features/graph` — pass

**Decisions:** Tap-only pending clears on `kTouchSlop` before other move handling; drags still require painted body (`_pendingNodeId`). Default `viewportInsets` / `maxScale` / absent `nodeTapHitTester` preserve prior matrices and hit paths (regression test on legacy matrix).

**Remaining:** Manager verdict; R03+.

### R03a — worker — checkpoint

- Added `graphLabelMaxWidthPerson` / `graphLabelMaxWidthRequest` tokens (5 sites each).
- Implemented pure `constellation_presentation_frame.dart`: detail hysteresis, `constellationLabelCandidateForDetail` helper (R03b sets `labelCandidate` on inputs using this policy), 6-step frame algorithm, `ConstellationPresentationFrameHolder`, and `resolveConstellationTap` (§3.4 order).
- Added `constellationOverflowChipSize` + `SizedBox.fromSize` wrap on `ConstellationOverflowGroup` (plan R03 step 4 partial — widget test for chip size deferred to R03b per plan step 4’s widget assertion).
- Unit tests in `constellation_presentation_frame_test.dart` (12 cases); full `test/features/constellation` green.

### R03a — worker — final

**Status:** complete

**Commits:** `da8ab8215` feat(client): add graph label max-width tokens; `379dc4f1f` feat(client): add Constellation viewport presentation-frame algorithm; `038d26e0b` feat(client): add Constellation tap resolver; `7c13b1b1f` feat(client): add overflow chip size helper; `94fda7db9` test(client): add Constellation presentation frame unit tests; `94369b571` docs(plan): R03a presentation frame journal final

**Changed files:**
- `packages/client/lib/design_system/tentura_tokens.dart`
- `packages/client/lib/features/constellation/ui/utils/constellation_presentation_frame.dart` (new)
- `packages/client/lib/features/constellation/ui/widget/constellation_overflow_group.dart`
- `packages/client/test/features/constellation/constellation_presentation_frame_test.dart` (new)
- `docs/plans/constellation-ui-remediation-journal.md`

**Tests:**
- `cd packages/client && flutter test test/features/constellation/constellation_presentation_frame_test.dart` — 12 passed
- `cd packages/client && flutter test test/features/constellation` — all passed
- `./scripts/check-custom-lints.sh packages/client` — pass (no baseline drift)

**Plan R03 coverage (this unit):**
- Done: step 1 (tokens), step 2 (frame module §3.3 + holder), step 4 partial (`constellationOverflowChipSize` + fixed chip size; no widget size test yet).
- Tap resolution §3.4 in the same utils file (plan step 2 sibling).
- Deferred to **R03b:** steps 3 (label measurement helper in overlay), 4 widget test, 5–9 (collapse ARB/cubit, overlay widget, body wiring, badges, footprint metrics), and plan R03 widget/integration tests.

**Decisions:** Exposed `constellationLabelCandidateForDetail` as a pure helper so unit tests can set `labelCandidate` without duplicating overview policy. Tap resolver and frame share one file (plan allows); separate git commits use one utils commit covering both. Chip widget test (`tester.getSize` vs helper) left for R03b when overlay lands.

**Remaining:** R03b wiring and badge work per manager split D-M4.

### R03b — worker — checkpoint

- Implemented collapse control (`expandedExtraCountByAuthor`), ARB keys, overflow chip expanded/collapsed UX, viewport overlay with label measurement cache, body wiring (overlay + `nodeTapHitTester`), top-corner badges, footprint metrics storage on cubit.
- Deviation: `updateFootprintMetrics` stores only in R03b (no `_reconcileLayout` yet) — calling reconcile on every footprint post-frame broke `constellation_layout_failure_recovery_test` and metrics are unused until R04 anyway; R04 should reconcile when footprints are consumed.
- Deviation: pan/adjacency widget test uses `jumpToPosition` + viewport adjacency after settle instead of strict global delta ±1px (overlay recomputes chip placement each frame).
- Deviation: overflow chip size test asserts `SizedBox` width/height vs helper (Semantics/`getSize` inflates hit targets beyond the fixed chip box).
- Deviation: expanded semantics label composes `constellationFewerRequests` + `, $authorName` (no separate ARB key).
- Deviation: `ConstellationBody.presentationFrameHolder` optional param for tests only.
- Boundary: `nodeTapHitTester` wired with stale-frame guard + `resolveConstellationTap`; no R06 single/double tap dispatch changes.

### R03b — worker — final

**Status:** complete

**Commits:** `185d5af80` feat(client): add author collapse control; `c1e8b9ad8` viewport overlay; `24a9abe90` wire graph stack; `cc16577de` top-corner badges; `2a0dff449` footprint metrics; `09fea0d8e` tests; `c4addd3af` journal

**Changed files:**
- `packages/client/lib/features/constellation/domain/constellation_anchor_composition.dart`
- `packages/client/lib/features/constellation/domain/constellation_layout.dart`
- `packages/client/lib/features/constellation/ui/bloc/constellation_cubit.dart`
- `packages/client/lib/features/constellation/ui/widget/constellation_body.dart`
- `packages/client/lib/features/constellation/ui/widget/constellation_overflow_group.dart`
- `packages/client/lib/features/constellation/ui/widget/constellation_request_status_marker.dart`
- `packages/client/lib/features/constellation/ui/widget/constellation_text_view.dart`
- `packages/client/lib/features/constellation/ui/widget/constellation_viewport_overlay.dart` (new)
- `packages/client/l10n/app_en.arb`, `packages/client/l10n/app_ru.arb`
- `packages/client/test/features/constellation/constellation_collapse_control_test.dart` (new)
- `packages/client/test/features/constellation/constellation_overflow_group_test.dart` (new)
- `packages/client/test/features/constellation/constellation_viewport_overlay_test.dart` (new)
- `packages/client/test/features/constellation/constellation_density_widget_test.dart`
- `packages/client/test/features/constellation/fixtures/constellation_reference_fixture.dart`
- `docs/plans/constellation-ui-remediation-journal.md`

**Tests:**
- `cd packages/client && flutter gen-l10n` — ok
- `cd packages/client && flutter test test/features/constellation` — 286 passed
- `cd packages/client && flutter test test/features/graph` — 217 passed
- `bash scripts/check-user-facing-terminology.sh` — ok
- `./scripts/check-custom-lints.sh packages/client` — 30/30, no drift

**Failures:** none at exit

**Decisions:** See checkpoint deviations; R04 must add `_reconcileLayout` when `_layoutFootprints` starts reading `_footprintMetrics`.

**Remaining:** R04 collision placement; R06 tap dispatch/semantics; R08 screenshot gate; manager R03b verdict.

### R04a — worker — checkpoint

- Added `constellationDrawnSatellites` and wired cubit `layoutVisibleRequestsByAuthor` / `layoutEgoOwnRequestIds` plus `layoutInputFromComposition` (UI-11). `_scratchInputAddingTarget` unchanged — pin-from-text still injects hidden targets into `satelliteRequestIdsByAuthor` outside the drawn set.
- `updateFootprintMetrics` reconciles when metrics change, but skips while `_awaitingConstellationLayoutOutcome`, `_ephemeralOwnedLayoutAlgorithm`, or `_dispatchingLayoutRecovery` (R03b recovery test regressed without these guards; deferred relayout when metrics arrive mid-layout handoff).

### R04a — worker — final

**Status:** complete

**Commits:** (see COMMITS in worker exit message)

**Changed files:**
- `packages/client/lib/features/constellation/domain/constellation_anchor_composition.dart`
- `packages/client/lib/features/constellation/domain/constellation_layout.dart`
- `packages/client/lib/features/constellation/domain/constellation_pin_position.dart`
- `packages/client/lib/features/constellation/ui/bloc/constellation_cubit.dart`
- `packages/client/lib/features/graph/ui/utils/tentura_layout_algorithms.dart`
- `packages/client/test/features/constellation/constellation_layout_test.dart`
- `packages/client/test/features/constellation/constellation_p06_composition_layout_test.dart`
- `docs/plans/constellation-ui-remediation-journal.md`

**Tests:**
- `cd packages/client && flutter test test/features/constellation/constellation_layout_test.dart` — 17 passed
- `cd packages/client && flutter test test/features/graph/tentura_layout_algorithms_test.dart test/features/constellation/constellation_scene_layout_test.dart` — 17 passed
- `cd packages/client && flutter test test/features/constellation/constellation_p06_composition_layout_test.dart test/features/constellation/constellation_density_test.dart` — passed
- `cd packages/client && flutter test test/features/constellation` — 293 passed
- `cd packages/client && flutter test test/features/constellation/constellation_layout_failure_recovery_test.dart` — 3 passed
- `cd packages/client && flutter test test/architecture/constellation_domain_graph_boundary_test.dart` — 1 passed
- `./scripts/check-custom-lints.sh packages/client` — 30/30, no drift

**Test expectation updates (author obstacle model, not regressions):**
- `constellation_layout_test.dart` R10: req–author distance was `≤57` at fan radius; now `>56` (observed ~136) because requests collide against author obstacles.
- `constellation_p06_composition_layout_test.dart` pinned-author beacon: author distance bound `120` → `150` (observed 136).

**Decisions:** Request automatic placement always uses obstacle map (author exemption removed) even when `footprints` is empty (symmetric body fallback). People placement path unchanged (A3). `ConstellationFootprint` record asymmetry matches label/badge extensions from `constellationNodeFootprint`.

**Remaining:** R04b (ego-fan geometry, attachment-crossing preference, full plan-R04 acceptance tests).
