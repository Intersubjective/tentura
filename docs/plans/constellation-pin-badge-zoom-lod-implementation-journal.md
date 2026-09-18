# Implementation journal — constellation pin badge zoom LOD

## Objective

Implement `docs/plans/constellation-pin-badge-zoom-lod-plan.md`: hide the
per-node "pin" badge on constellation graph nodes below a zoom/scale
threshold (full-field overview), show it once nodes are legible, reusing the
existing `ConstellationDetailLevel` / `cameraScale` LOD machinery already
used for labels. Status badge and avatar stay zoom-independent — only the
pin badge is gated.

## Repository state at start

- Repo: `/home/vader/MY_SRC/tentura`, branch `main`.
- Starting HEAD (`UNIT_BASE` for unit 1): `2385b496a9c30779f1b7e3cbd6713b5bf390a905`.
- Pre-existing uncommitted changes at start (**untouchable** — preserve exactly,
  do not stash/reset/commit as part of this work):
  - Modified: `.serena/project.yml`, `docs/known-issues.md`,
    `packages/client/integration_test/support/e2e_test_helpers.dart`,
    `packages/client/l10n/app_en.arb`, `packages/client/l10n/app_ru.arb`,
    `packages/client/lib/features/forward/ui/bloc/person_forward_cubit.dart`,
    `packages/client/lib/features/forward/ui/screen/person_forward_screen.dart`,
    `packages/client/lib/features/forward/ui/widget/forward_recipient_picker.dart`,
    `packages/client/pubspec.yaml`,
    `packages/client/test/features/forward/forward_recipient_picker_test.dart`,
    `packages/client/test/features/forward/person_forward_cubit_test.dart`,
    `packages/client/test/features/forward/person_forward_screen_test.dart`,
    `packages/client/test_driver/realtime_multiclient_web_test.dart`,
    `packages/client/web/index.html`.
  - Untracked: many `docs/plans/*.md` files (other in-flight plans),
    `CLAUDE.local.md`, `dart-defines`, `graph-ego-neighbors-layout-issue.md`,
    `key.fb`, `leo.key`, `out.key`, `product_testing_*`,
    `packages/image_cropper_for_web/build/`, and this plan's own two new files.
  - None of the above relate to constellation/pin-badge work. Do not modify,
    stage, or commit any of them as part of this unit.

## Tooling check

- `cursor-agent` 2026.09.15-d2fe57e, `composer-2.5` listed and current (not
  the fast variant). OK.
- `claude` CLI 2.1.274. Opus runner probed with trivial prompt: log `init`
  event reports `"model":"claude-opus-5"`. OK.
- `codex` CLI 0.154.0 installed. Not probed for Astra availability up front
  (escalation-only, scarce quota) — will resolve on first escalation need, if
  any.

## Unit checklist

| # | Unit | Tag | Status |
|---|------|-----|--------|
| 1 | Pin badge zoom-dependent visibility (resolve Option A vs B spike, then implement + test) | routine | verified |

Single unit — the plan's scope is one bounded, well-defined change (one
threshold check gating one widget), sized well within "one to four
commit-sized steps" for the inner layer.

## Acceptance criteria (from plan)

- Pin badge (`ConstellationMarkerBadge.pin`) is hidden when
  `cameraScale` is below the chosen threshold (recommend reusing
  `kConstellationNormalDetailScale` / `ConstellationDetailLevel.normal` vs
  `overview`), and shown at/above it.
- Status badge and avatar rendering are unaffected — always visible
  regardless of zoom.
- No flicker at the threshold boundary — reuse existing hysteresis
  (`nextConstellationDetailLevel`) rather than a raw scale comparison, unless
  the scout's investigation finds a reason not to.
- Whichever file actually renders/positions the pin badge (spike question in
  the plan: `_ConstellationMapNode` in `constellation_body.dart` vs.
  `ConstellationViewportOverlay`) is the one gated — not a duplicate/parallel
  gate in both places.

## Verification commands (from AGENTS.md § Verify)

```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 45m -- \
  flutter test --dart-define=ENV=test --dart-define-from-file=env/test.env test/features/constellation/
./scripts/run_with_test_cleanup.sh --timeout 10m -- ./scripts/check-custom-lints.sh packages/client
```

Full-package `flutter test` is the plan-level closing gate (section 9), not
required per-unit given this is a single unit.

## Unresolved decisions / blockers

- None yet. The plan's own "open question" (Option A vs B) is scoped to the
  scout brief for unit 1, not a blocker for the overseer.

## Checkpoints

(appended by each worker layer as it runs)

### Scout (unit 1) — 2026-09-17

**Spike answer (definitive): Option A.** The map pin badge is rendered and
positioned only in `_ConstellationMapNode` inside `constellation_body.dart`.
`ConstellationViewportOverlay` does **not** paint pin (or status) badges; it
only uses `_nodeShowsBadge` to feed `badgeOverhang` into
`computeConstellationPresentationFrame` for label/chip collision layout.

Evidence:
- Pin widgets are constructed in `nodeBuilder` and passed as `pinBadge` to
  `_ConstellationMapNode` (`constellation_body.dart:719-749`).
- `_ConstellationMapNode.build` places `pinBadge` in a `PositionedDirectional`
  (`constellation_body.dart:933-938`). Status badge at `:927-932`.
- Overlay `build` returns a `Stack` of label plates and overflow chips only
  (`constellation_viewport_overlay.dart:386-392`) — no
  `ConstellationMarkerBadge` / pin marker keys in overlay tree.
- `_nodeShowsBadge` (`constellation_viewport_overlay.dart:102-121`) is layout-only;
  `badgeOverhang` assigned at `:251-258`, consumed by presentation frame
  (`constellation_presentation_frame.dart:140-145`).

**Plan contradictions vs live code:**
- Open question / Option B: overlay does **not** independently render badges;
  Option B visibility gate is wrong. Optional overlay tweak for pin-only
  `badgeOverhang` at overview is layout accuracy, not visibility (out of plan
  unless product wants tighter labels).
- Option A step 1 vs 2: prose says avoid per-node `ListenableBuilder` (mirror
  edge painter) but step 2 mandates per-node `ListenableBuilder` — edge painter
  uses one `repaint` listener for all edges; `nodeBuilder` does not rebuild on
  zoom, so per-node listen on `cameraRevision` (or a small child gate widget) is
  required for pin LOD unless GraphView API changes.
- Plan path `ui/utils/constellation_consts.dart` — actual file is
  `domain/constellation_consts.dart` (`kConstellationRenderPeerCap`).
- Journal untouchable list includes `pubspec.yaml` / `web/index.html` but
  AGENTS.md requires client version + cache-buster for user-visible changes —
  version bump is outside this unit’s editable paths unless overseer relaxes.

**Recommended approach:** Gate pin `PositionedDirectional` in
`_ConstellationMapNode` (or dedicated child widget) with
`ListenableBuilder(listenable: graphController.cameraRevision)`; track
`ConstellationDetailLevel` with `nextConstellationDetailLevel(scale, previous)`
(same hysteresis as overlay labels at `constellation_viewport_overlay.dart:155-156`);
show pin only when `detail == ConstellationDetailLevel.normal` and `pinBadge != null`.
Do **not** add a parallel visibility gate in overlay. Pass `GraphController` (or
revision + scale accessors) into `_ConstellationMapNode` from `nodeBuilder`.

**Tests:** Extend `constellation_viewport_overlay_test.dart` UI-14 group or add
`constellation_body_test.dart` widget cases: default reference pump (scale ~1.0)
pin present; after `zoomBy` until `cameraScale <
kConstellationOverviewDetailScale` pin absent; status marker still present on
pinned request with status; re-zoom to `>= kConstellationNormalDetailScale` pin
returns. Existing UI-14 placement tests should stay green at default zoom.

**STATUS:** complete (spike resolved; implementation path clear).

### Inner (unit 1) — 2026-09-17

- Red: new group `Constellation pin badge zoom LOD` in
  `constellation_body_test.dart` (reference fixture, `req-in-2` pinned + has
  status). Against UNIT_BASE: +10 −1 (pin still found below overview scale).
- Green: `_ConstellationMapNode` is now a StatefulWidget holding
  `GraphController`; listens to `cameraRevision`, tracks
  `ConstellationDetailLevel` via `nextConstellationDetailLevel`, `setState`
  only on level change; pin `PositionedDirectional` emitted iff
  `pinBadge != null && detail == normal`. Status badge unchanged.
- Deviation from brief: no `ListenableBuilder` around the pin —
  `PositionedDirectional` must be a direct `Stack` child (ParentData), so a
  wrapper would throw. State listener gives the same behavior with fewer
  rebuilds.
- Test + impl committed together (8fd36aa22) to avoid a red commit; follow-up
  7529a71e5 removed a redundant nested `if` (analyzer warning).
- Verify: body test +11 green; `test/features/constellation/` +334 green;
  check-custom-lints packages/client OK (30/30 baseline).
- Not done (untouchable): pubspec version bump / index.html cache-buster.
- STATUS: complete.

### Verify (unit 1) — 2026-09-17

- Re-ran TEST_CMD: `constellation_body_test.dart` +11; `check-custom-lints.sh
  packages/client` total 30 (baseline 30); `test/features/constellation/` +334.
- Commits on `UNIT_BASE..HEAD`: exactly `8fd36aa22` (feat + tests),
  `7529a71e5` (refactor nested condition). Diff touches only
  `constellation_body.dart` and `constellation_body_test.dart`; no untouchable
  paths; `constellation_viewport_overlay.dart` unchanged.
- Implementation: `_ConstellationMapNode` StatefulWidget,
  `cameraRevision` listener, `nextConstellationDetailLevel`, pin iff
  `detail == normal`; status `PositionedDirectional` unconditional.
- Red-before-green not preserved as separate commit (combined in 8fd36aa22) —
  acceptable; current tree green.
- **STATUS:** pass (version/cache-buster deferred per unit untouchable list).

### Independent review — Astra (codex, gpt-6-astra) — 2026-09-17

Read-only review requested by the user after unit 1 verify passed. Result:
**STATUS: fail**, `RECOMMENDATION: fix before ship`.

**Finding 1 — BLOCKING, confirmed by overseer via direct source read (not
just trusting Astra's claim):** `_ConstellationMapNodeState` at
`constellation_body.dart:927-930` seeds its own `_detail` per instance:
```dart
late ConstellationDetailLevel _detail = nextConstellationDetailLevel(
  widget.graphController.cameraScale, ConstellationDetailLevel.normal,
);
```
Every node tracks zoom hysteresis independently, each seeded from `normal`
on creation. Inside the hysteresis band (`cameraScale` in
`[kConstellationOverviewDetailScale, kConstellationNormalDetailScale)` =
`[0.70, 0.85)`), `nextConstellationDetailLevel` returns whatever `previous`
was passed in — so a node's *history* (was it last `normal` or `overview`
before entering the band) determines its current detail level, not the
global camera state alone. A node created while sitting in-band (e.g. a
locally-filtered-out pinned request being restored, or any node whose
`Key` causes it to be recreated by the `GraphView`) always seeds at
`normal` regardless of what every other on-screen node currently shows,
producing inconsistent pin visibility across nodes at the identical camera
scale. Reproducible via source reasoning; not runtime-confirmed with a
screenshot.

**Finding 2 — known, not new:** pubspec.yaml/web/index.html version bump +
cache-buster still not done. Already flagged and deliberately deferred in
unit 1 (those files carry unrelated pre-existing uncommitted edits). Astra
is right this is required by repo convention before a real ship, but it is
a scope call already on record, not a fresh defect — **not** part of this
remediation unit; a separate decision for the user before release.

**Finding 3 — non-blocking:** the widget test only asserts the two extremes
(`< 0.70` hidden, `>= 0.85` shown) so a naive `>= 0.85` raw-threshold
implementation (no real hysteresis) would also pass it. Worth strengthening
alongside the fix below, in the same unit, since fixing finding 1 needs
in-band assertions anyway.

**Finding 4 — non-blocking, docs only:** the inner worker's stated reason
for not using `ListenableBuilder` ("wrapping `PositionedDirectional` would
throw") is technically wrong per Astra — an intervening stateful widget
introduces no render object, so a `ListenableBuilder` there would have been
fine. The actual landed code doesn't have this problem; only the journal's
stated justification is inaccurate. No code action needed.

## Remediation unit — shared zoom-detail state

**Defect (from Astra finding 1):** per-node local hysteresis state
(`_ConstellationMapNodeState._detail`) causes inconsistent pin visibility
across nodes at the same camera scale, when a node is destroyed/recreated
while the camera sits inside the 0.70-0.85 hysteresis band.

**Fix direction:** hoist `ConstellationDetailLevel` tracking to a single
owner with one `cameraRevision` listener, so every node reads the same
current value instead of computing its own history. `_ConstellationBodyState`
(`constellation_body.dart:69`, already a `StatefulWidget` wrapping the
`GraphView`/`nodeBuilder`) is the natural single owner — mirrors the
existing single-`_detail`-field pattern `ConstellationViewportOverlay`
already uses for labels (`constellation_viewport_overlay.dart:57,155-156`),
just at the level that actually needs sharing across all nodes.
`_ConstellationMapNode` should stop owning its own hysteresis; it should
receive the current `ConstellationDetailLevel` (or a `ValueListenable`
sourced from the single owner) and simply rebuild when that shared value
changes, exactly like the status badge/avatar rebuild when `nodeBuilder`
reruns.

UNIT_BASE for this remediation: `7529a71e5b0a6ec4cf5ccd624c12e846d83ed370`
(unit 1's final commit).

(worker checkpoints appended below)

### Scout (remediation — shared zoom-detail state) — 2026-09-17

**Defect mechanism (live code, matches journal):** `_ConstellationMapNodeState`
(`constellation_body.dart:927-964`) owns per-instance `_detail`, initialized with
`previous: ConstellationDetailLevel.normal` and updated only via that instance's
`cameraRevision` listener. `nextConstellationDetailLevel` (`constellation_presentation_frame.dart:12-22`)
returns `previous` inside `[0.70, 0.85)`. A recreated node therefore seeds as
`normal` at ~0.77 while siblings that survived the zoom-out remain `overview` →
pin shown on one node, hidden on others. **Contrast:** `ConstellationViewportOverlay`
(`constellation_viewport_overlay.dart:57,156`) is one long-lived state object — same
pattern is safe there, unsafe on per-graph-node widgets.

**Why nodeBuilder-only param is insufficient without a body listener:** `NodesView`
in `force_directed_graphview` rebuilds node children from `nodeBuilder` when the
`GraphController` notifies or when an ancestor `setState`s — not on
`cameraRevision` alone (`zoomBy` mutates `TransformationController`, not controller
listeners). Unit 1's per-node `cameraRevision` listener was required for zoom
updates; remediation must move that to **one** listener on `_ConstellationBodyState`
that `setState`s when shared `_detail` changes, then pass the current level into
`nodeBuilder` / `_ConstellationMapNode`. Drop per-node listeners and
`graphController` from `_ConstellationMapNode` (can be `StatelessWidget` again).

**Overlay/body detail duplication:** After fix, overlay label `_detail` and body
pin `_detail` remain separate fields but both driven by the same
`nextConstellationDetailLevel` + `cameraRevision` — acceptable; unifying is out of
scope.

**Regression test design:** Reuse `_pinnedReferenceAnchors()` from
`constellation_viewport_overlay_test.dart` (person `am` + beacon `req-in-2`) via
`loadReferenceCubit(field: constellationReferenceField(anchors: …))` and existing
`pumpConstellationBody` / `zoomUntil` helpers in `constellation_body_test.dart`.
Sequence: (1) zoom below `kConstellationOverviewDetailScale`; (2) zoom back into band
e.g. `0.70 <= scale < 0.85` without reaching `kConstellationNormalDetailScale`
(iterative `zoomBy` + `pump`, assert band); (3) assert **both** pins hidden; (4)
hide `req-in-2` with `setFilterIncludeUnspecified(false)` +
`setFilterCapabilitySlugs({'tools'})` (request has no needs — matches
`constellation_density_widget_test.dart` filter pattern), `pump`; (5)
`await cubit.clearFilters()` + `pumpAndSettle` to recreate that node's widget; (6)
assert `req-in-2` pin still hidden and control pin on `am` still hidden. **Fails on
UNIT_BASE** (recreated node shows pin); passes after hoist.

**Journal vs live code:** No contradictions on defect or line refs; unit 1 scout
note that `nodeBuilder` does not rebuild on zoom still holds and informs the body
`setState` requirement.

**STATUS:** complete

### Inner (remediation — shared zoom-detail state) — 2026-09-17

- Step 1 red test `node recreated inside the hysteresis band keeps shared detail`
  (pins on `req-in-2` + person `am`; zoom <0.70, back into [0.70,0.85) via
  `zoomBy(1.02)`; filter `req-in-2` out with includeUnspecified=false +
  slugs {'tools'} (`am` survives), `clearFilters`). On UNIT_BASE: +10 -1, the
  recreated `req-in-2` shows its pin, `am` stays hidden. Commit `1f47c65e5`.
- Step 2: `_ConstellationBodyState` owns `_detail` + one `cameraRevision`
  listener (cubit via `context.read` in `initState`; body has no `cubit`
  field), `setState` only on level change; `_ConstellationMapNode` is now
  stateless with a `detail` param, and its `graphController` param is gone.
  Body test +12 green; `dart analyze` shows the same 17 issues as the base
  (none new). Commit `213b0b71a`.
- Step 3: check-custom-lints packages/client OK (30/30 baseline).
- Step 4: test/features/constellation/ +335 all passed.
- Regression was introduced by unit 1 (per-node hysteresis); nothing
  pre-existing found. Overlay label `_detail` still separate (out of scope).

**STATUS:** complete

### Verify (remediation — shared zoom-detail state) — 2026-09-17

- Re-ran TEST_CMD: `constellation_body_test.dart` **12 passed**; `check-custom-lints.sh
  packages/client` **total 30 (baseline 30) OK**; `test/features/constellation/`
  **335 passed**.
- Range `7529a71e5..HEAD`: commits `1f47c65e5`, `213b0b71a`, `ac8fb191c`; files
  only `constellation_body.dart`, `constellation_body_test.dart`, this journal.
  No `constellation_viewport_overlay.dart`, `force_directed_graphview`, pubspec,
  or `web/index.html` in range. No deleted/skipped tests; pin LOD group +1 test,
  refactored `inRequestNode` → `inNode` helper only.
- Regression test uses real cubit filter API (`setFilterIncludeUnspecified(false)`
  + `setFilterCapabilitySlugs({'tools'})`) to remove `req-in-2` from graph
  (`graphNode` absent), `clearFilters` restores node while `inBand(scale)` still
  true; asserts both pins hidden — would fail UNIT_BASE per-node seeding.
- `_ConstellationMapNode` is `StatelessWidget` with `detail` param only; no
  `graphController`/listener/history. `_ConstellationBodyState` single `_detail`
  + one `cameraRevision` listener.
- Unit-1 pin LOD test still covers default visible pin, overview hidden, status
  at overview, re-zoom pin returns; avatar unchanged (child `GraphNodeWidget` not
  gated).
- **STATUS:** pass
