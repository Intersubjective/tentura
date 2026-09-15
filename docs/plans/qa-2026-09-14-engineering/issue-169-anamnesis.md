# Issue #169 — Discussion header and messages cropped at viewport

**GitHub:** [Intersubjective/tentura#169](https://github.com/Intersubjective/tentura/issues/169)  
**Parent:** [#142](https://github.com/Intersubjective/tentura/issues/142)  
**Related:** [#138](https://github.com/Intersubjective/tentura/issues/138) (overlay scrollbar; can compound unreadable chat edges)

**Source:** 2026-09-14 product testing (participant note 25)

## Symptom

On **request detail** at **expanded** width with the **discussion** pane open beside **NOW**, content is **cropped** at the session viewport. The top chrome can show a **message snippet** (e.g. «Не факт!») where the **request / discussion title** should read, and **message text / images** clip at pane or viewport edges.

User-facing nouns: **Request**, **discussion** (internal `Beacon`, thread / room split).

## User-facing expectation

- Discussion layout must not clip the header or message bubbles inside the visible viewport.
- Acceptance: screenshot viewport shows **full** message text and images without cutoff; header shows the proper request/discussion title, not ad‑hoc message body.

## Product path

| Step | Surface | Implementation |
|------|---------|------------------|
| Expanded split | NOW + discussion | [`BeaconViewScreen`](../../packages/client/lib/features/beacon_view/ui/screen/beacon_view_screen.dart) — `_computeIsSplit`, `_buildExpandedSplitBody`, `TenturaTopBar` custom `row` |
| Discussion pane | General thread body | [`BeaconRoomSurface`](../../packages/client/lib/features/beacon_view/ui/widget/beacon_room_surface.dart) → [`ThreadDetail`](../../packages/client/lib/features/beacon_threads/ui/widget/thread_detail.dart) → [`BeaconRoomBody`](../../packages/client/lib/features/beacon_threads/ui/widget/beacon_room_body.dart) / [`BasicChatBody`](../../packages/client/lib/ui/widget/basic_chat_body.dart) |
| Split header (right) | Discussion title + ⋮ | `_splitThreadPaneAppBar` → [`ThreadDetailGeneralTitle`](../../packages/client/lib/features/beacon_threads/ui/widget/thread_detail.dart) |
| Pane width | Resize + clamp | `beaconViewRoomSplitPaneWidth` / `_roomPaneWidthOverride` |
| Shell | Home rail inset | `_BeaconViewHomeRail` wraps **body only**; `appBar` spans full scaffold width |

## Root cause (engineering)

**Split geometry is computed twice from different horizontal budgets:**

1. **App bar custom `row`** (`beacon_view_screen.dart`, `LayoutBuilder` inside `TenturaTopBar.of(..., row: ...)`) calls `beaconViewRoomSplitPaneWidth` with `constraints.maxWidth` from the **full-width** app bar title area (scaffold width minus horizontal padding).
2. **Discussion body** (`_buildExpandedSplitBody`) uses another `LayoutBuilder` inside `_BeaconViewHomeRail`’s `Expanded` child, where `constraints.maxWidth` is **reduced by the persistent `NavigationRail`** (expanded window).

The same helper therefore yields a **wider** `threadPaneWidth` for the header’s right `SizedBox` than for the `BeaconRoomSurface` column. Header chrome and the discussion pane **do not share left edge or width**, so content appears misaligned and **clips** at the viewport/pane boundary. In QA, a short message line («Не факт!») near the seam can read like a broken **title** even when the beacon has a real title.

**Contributing factor:** [`ThreadDetailGeneralTitle`](../../packages/client/lib/features/beacon_threads/ui/widget/thread_detail.dart) is a **two-row** app-bar title inside [`TenturaTopBar`](../../packages/client/lib/design_system/components/tentura_top_bar.dart)’s fixed `toolbarHeight` `SizedBox`; vertical overflow is clipped by the app bar, which worsens header readability in the narrow split column.

## Fix direction (not implemented in TDD pass)

- **Single width source:** compute split pane width once from the **body** `LayoutBuilder` (post-rail) and pass it to the app bar `row` (e.g. `InheritedWidget`, cubit field, or lift split `Row` so header and body share one `LayoutBuilder`).
- **Alternatively:** move discussion header chrome into the right pane (same as compact tab) so title and messages share one column constraints.
- **Header layout:** allow two-line discussion titles (taller split toolbar or single-line + overflow policy) without clipping.
- Re-verify with long text and image attachments after width sync; cross-check [#138](https://github.com/Intersubjective/tentura/issues/138) scrollbar overlay on the same surfaces.

## Failing test (TDD — expected red)

**File:** `packages/client/test/features/beacon_view/issue_169_discussion_cropped_test.dart`  
**Test:** `issue #169 discussion header and messages fit the visible pane`

**Command:**

```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 10m -- flutter test \
  --dart-define=ENV=test \
  --dart-define-from-file=env/test.env \
  test/features/beacon_view/issue_169_discussion_cropped_test.dart
```

**Assertions:**

- Discussion app bar uses the formal request title; message snippet «Не факт!» is not in the app bar.
- `ThreadDetailGeneralTitle` horizontal bounds match `ThreadDetail` (same left + width).
- Discussion header fits within app bar height.
- Seeded message text rects lie fully inside `BasicChatBody` bounds.

## Files touched (TDD only)

- `packages/client/test/features/beacon_view/issue_169_discussion_cropped_test.dart` — failing acceptance
- `docs/plans/qa-2026-09-14-engineering/issue-169-anamnesis.md` — this note

**Observed (2026-09-15):** `+0 -1` — `ThreadDetailGeneralTitle` `left` ≈ **742** vs `ThreadDetail` `left` ≈ **854** (~112px delta, matches home `NavigationRail` inset).

**No production code changes** in this pass.
