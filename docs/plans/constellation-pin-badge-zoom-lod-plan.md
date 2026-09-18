# Constellation pin badge: zoom-dependent visibility (LOD)

## Problem

The per-node "pin" badge on constellation graph nodes (`ConstellationMarkerBadge.pin`,
`packages/client/lib/features/constellation/ui/widget/constellation_request_status_marker.dart:191-211`)
is always rendered regardless of zoom level. As pinning becomes common (eventually on the
majority of nodes), a full-field zoomed-out overview turns into a field of identical badges —
visual noise with no information value at that zoom, since individual nodes aren't legible
anyway at overview scale.

This plan hides the pin badge below a zoom/scale threshold and shows it once nodes are large
enough to be read individually, reusing the zoom-detail infrastructure the constellation view
already has for labels.

Related: color/shell de-emphasis of the pin badge (muted color, unshelled icon) is a separate,
already-agreed follow-up and is not part of this plan — this plan only adds the zoom gate.

## What already exists (no new plumbing needed)

- `ConstellationCubit.graphController` (`force_directed_graphview` `GraphController`) exposes
  `cameraScale` (getter) and `cameraRevision` (a `Listenable` bumped on every pan/zoom). This is
  already the source of truth used elsewhere for zoom-reactive rendering:
  - `ConstellationEdgePainter` reads `cameraScale` via a closure, repainted on `cameraRevision`
    (`constellation_body.dart:702`, `:951-965`).
  - `ConstellationViewportOverlay` reads `controller.cameraScale` inside a
    `ListenableBuilder(listenable: Listenable.merge([controller, controller.cameraRevision]))`
    (`constellation_viewport_overlay.dart:141,155-156`).
- An LOD pattern for exactly this kind of decision already exists for labels:
  `constellation_presentation_frame.dart:7-40` —
  `enum ConstellationDetailLevel { normal, overview }`,
  `kConstellationNormalDetailScale = 0.85`, `kConstellationOverviewDetailScale = 0.70`,
  `nextConstellationDetailLevel(cameraScale, previous)` (hysteresis band, avoids flicker at the
  boundary), and `constellationLabelCandidateForDetail(...)` for per-node candidacy.
- `nodeBuilder` (`constellation_body.dart:705-781`) itself does **not** currently rebuild on
  zoom — nodes are positioned by the `GraphView` viewport, and `nodeBuilder` only reruns on
  structural state changes (selection, anchors, node set changing). Zoom-reactive rendering is
  achieved by other widgets independently listening to `cameraRevision`, not by rebuilding nodes.
- Scale: `kConstellationRenderPeerCap = 120` (`constellation_consts.dart:4`), label cap
  `_kMaxLabelsTotal = 150` (`constellation_density.dart:6`). Up to ~120-150 nodes on screen —
  the existing pattern computes visibility for all of them in one `ListenableBuilder` pass per
  camera revision, not via per-node individual listeners. Follow that pattern; don't attach 120+
  listeners.

## Open question to resolve first (spike, ~30 min)

Two agents' findings disagree slightly on where the pin badge is actually positioned:
- `constellation_body.dart:907-939` (`_ConstellationMapNode`) positions pin/status badges via
  `PositionedDirectional` directly over `GraphNodeWidget`, inside `nodeBuilder`'s output.
- `constellation_viewport_overlay.dart:102-121,251-258` already has `badgeOverhang`/
  `_nodeShowsBadge`-shaped per-node-per-camera-revision computation.

Before writing code, confirm by reading both files together: is the pin badge rendered once (in
`_ConstellationMapNode`), or is there a second overlay-layer rendering/positioning pass for
badges (e.g. for a summary/legend use)? This determines which of the two implementation options
below applies. If badges are rendered only in `_ConstellationMapNode`, use Option A. If
`ConstellationViewportOverlay` is a second, independent render of badge visibility, use Option B
(and check they don't end up disagreeing about whether a badge is showing).

## Implementation options

### Option A — gate inside `_ConstellationMapNode` (likely correct, do this unless the spike says otherwise)

Wrap just the pin badge's `PositionedDirectional` (not the whole node — status badge and avatar
stay zoom-independent) in a small listener on `cubit.graphController.cameraRevision`, mirroring
`ConstellationEdgePainter`'s closure pattern rather than introducing a new `ListenableBuilder`
per node:

1. Add a scale threshold. Reuse `kConstellationNormalDetailScale` (0.85) if pin legibility should
   track the same normal/overview boundary as labels, or add a dedicated
   `kConstellationPinBadgeVisibleScale` constant next to it in
   `constellation_presentation_frame.dart` if pin visibility should kick in at a different zoom
   than labels (recommend starting with the same constant — one threshold is easier to reason
   about, and pins are a similar-or-lower information density than labels, so they shouldn't
   need to appear earlier).
2. In `_ConstellationMapNode`, instead of unconditionally including the pin
   `PositionedDirectional`, wrap it (or just its `child`) in
   `ListenableBuilder(listenable: cubit.graphController.cameraRevision, builder: ...)` and inside,
   check `cubit.graphController.cameraScale >= threshold` before returning the badge vs.
   `SizedBox.shrink()`.
3. Apply the same hysteresis approach as `nextConstellationDetailLevel` if the raw threshold
   flickers during small pan/zoom jitter at the boundary — likely reuse that function directly
   rather than reimplementing hysteresis, by tracking `ConstellationDetailLevel` and showing the
   pin only at `normal` (not `overview`).
4. Keep the status badge and avatar unconditional — only the pin badge is gated, per the
   problem statement (pin is the one that will cover "majority of nodes").

### Option B — gate inside `ConstellationViewportOverlay` (only if the spike shows badges render there)

If badge visibility is actually decided in the overlay's existing per-camera-revision pass, add
the same `cameraScale >= threshold` / `ConstellationDetailLevel` check next to the existing
`_nodeShowsBadge`-equivalent logic there instead of touching `constellation_body.dart` at all —
this is the cheaper path since the per-node, per-revision computation loop already exists and
runs once for all ~120-150 nodes rather than needing new per-node listeners.

## Testing

- Extend `packages/client/test/features/constellation/constellation_body_test.dart` (or
  `constellation_viewport_overlay_test.dart`, depending on which option applies) with cases at
  camera scale above/below/at the threshold, asserting the pin badge widget is present/absent
  (search existing file for `pinBadge`/`PinMarker` references as the hook point).
  `constellation_viewport_overlay_test.dart` already has pin/marker-related assertions per prior
  research — check whether it needs updating regardless of which option is chosen, since it may
  assert current always-visible pin behavior.
- Add/extend a case in `constellation_presentation_frame_test.dart` only if a new threshold
  constant or hysteresis path is added there.
- No new golden/pixel tests needed unless the design-system skill review flags one; this is a
  visibility toggle, not a new visual, so existing pin-badge appearance goldens (if any) stay
  valid — they just gain a "hidden below threshold" case.

## Explicitly out of scope

- Pin badge color/icon-outline de-emphasis (agreed separately, not blocked by this plan).
- Status badge zoom gating — status is meant to stay legible/attention-worthy at any zoom.
- Any change to `kConstellationRenderPeerCap` / label budget logic.
