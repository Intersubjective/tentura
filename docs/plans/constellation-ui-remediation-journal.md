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

## Unit checklist

| Unit | Depends on | Status | Commits | Manager verdict |
|---|---|---|---|---|
| R00 fixture + baseline | — | done | c690eca44, 47e9bf065 | accepted — smoke test independently re-run (pass), `git diff --check` clean, no leaked test processes |
| R01 label budget (ships alone) | R00 | in progress | | |
| R02 graph package seams | R01 landed | pending | | |
| R03 screen-space labels/chips/badges | R02 | pending | | |
| R04 collision-aware Request placement | R03 | pending | | |
| R05 edge legibility | R02 | pending | | |
| R06 targeting + semantics | R02, R03 | pending | | |
| R07 camera recovery + app bar | R02, R03 | pending | | |
| R08 integrate, verify, release | R00–R07 | pending | | |

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

- None blocking at start.

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
