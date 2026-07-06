# Responsive Design Audit

> **Status (verified 2026-06-30): essentially complete.** Every screen/dialog fix
> and every "deferred"/backlog item from the original 2026-06-27 snapshot has
> since landed in committed code (`git diff HEAD` for `packages/client` is clean —
> nothing is staged or pending). This file now serves two purposes: a **verified
> baseline** of what is already done, and a small **residual backlog** of the
> only gaps that remain. An autonomous agent should implement *only* the
> "Residual backlog" section below; the rest is reference.

Scope: all `@RoutePage` screens and shared `lib/ui/` dialogs/widgets in
`packages/client`.

**Window classes:** compact &lt;600, regular 600–839, expanded ≥840
(`context.windowClass` / `context.tt`).

**Primary pattern (already applied across the app):** standalone form/list bodies
are wrapped in `TenturaContentColumn`, which centers and caps width at
`contentMaxWidth` (**560px** regular / **720px** expanded;
`tentura_tokens.dart:192,212`). Compact is left full-width
(`contentMaxWidth == null`). Full-bleed surfaces (graph canvas, room chat,
scatter plot, map picker) are intentionally unconstrained via `TenturaFullBleed`.

**Canonical references:** `tentura_responsive_scope.dart` (the `TenturaContentColumn`
definition), `tentura_tokens.dart` (`contentMaxWidth`), `credentials_screen.dart`,
`forward_beacon_screen.dart`.

---

## Residual backlog (the only unimplemented work)

### Task R1 — Cap the room message-action sheet on expanded windows

**File:** `packages/client/lib/features/beacon_room/ui/widget/beacon_room_body.dart`
(the `showModalBottomSheet<void>` call, currently at line ~332).

**Why it's an exception:** this is the one bottom sheet that deliberately bypasses
`showTenturaAdaptiveSheet` because it requires `useRootNavigator: true` to work
around a Flutter Web back-button/`PopScope` interaction (see the long comment at
the call site — do **not** route it through the adaptive wrapper). Because it
bypasses the wrapper, it also misses the wrapper's automatic
`maxWidth: contentMaxWidth` cap, so the message-action menu stretches edge-to-edge
on tablet/desktop.

**Current state:** the `builder:` returns
`SafeArea(child: SingleChildScrollView(child: Column(...)))` with **no** width
constraint. The inner content also uses legacy const paddings
(`kPaddingH`, `kPaddingSmallT`, `kSpacingSmall`) rather than `tt` tokens.

**Change:** inside the `builder`, wrap the returned `SafeArea` so it is centered
and width-capped, reusing the same token the adaptive wrapper uses. Keep compact
unchanged (`contentMaxWidth` is null on compact → fall back to unbounded):

```dart
builder: (ctx) {
  final theme = Theme.of(ctx);
  final tt = ctx.tt;
  return Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: tt.contentMaxWidth ?? double.infinity,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          // ...existing Column unchanged...
        ),
      ),
    ),
  );
}
```

(Optional, same edit: swap the legacy `kPaddingH` / `kSpacingSmall` literals for
`tt` tokens — `tt.screenHPadding`, `tt.rowGap`/`tt.iconTextGap` — to match the
rest of the migrated UI. Token names: see `tentura_tokens.dart`.)

**Acceptance criteria:**
- On a ≥840px window the action sheet content is centered and no wider than
  720px; on a 600–839px window no wider than 560px.
- On a compact (&lt;600) window the sheet is visually unchanged.
- The room remains exitable after the sheet is dismissed on Web (the
  `useRootNavigator: true` behavior must be preserved — do not remove it).
- `flutter analyze` on `packages/client` reports no new diagnostics.

**Verify:**
```bash
cd packages/client && flutter analyze lib/features/beacon_room
```
Then drive the room → long-press/secondary-tap a message → open the action sheet
at compact vs. expanded widths (see the Playwright/Obscura e2e harness; window
resizing exercises `windowClass`).

---

## Verified baseline (already done — reference only)

The following were confirmed present in committed code on 2026-06-30. Do **not**
re-implement; this is here so the agent recognizes completed work and the design
intent behind the exceptions.

### Standalone screens wrapped in `TenturaContentColumn`

`auth_login`, `auth_register`, `recover`, `intro`, `settings`,
`notification_settings`, `notification_center`, `profile_view`, `profile_edit`,
`rating` (list mode only), `beacon`, `beacon_create`, `inbox` (compact path),
`inbox_rejected`, `my_work`, `review_contributions`, `complaint`, `credentials`.

### Shared dialogs/widgets width-capped via `tt.contentMaxWidth`

`share_code_dialog`, `show_seed_dialog`, `qr_scan_dialog` (desktop paste path),
`tentura_confirm_dialog`, `qr_code`, `screen_load_error_panel`.
Bottom sheets centralize the cap in `tentura_adaptive_sheet.dart`
(`maxWidth ?? tt.contentMaxWidth ?? size.width`), used at 22 call sites including
`evaluation_detail_sheet`.

### Previously-"deferred" items that have since landed

| Item | Where it landed |
|------|-----------------|
| Inbox split-pane master–detail on expanded | `inbox_screen.dart` — `_InboxExpandedBody` / `_InboxExpandedPreview`, gated on `windowClass == expanded` |
| Room message bubble width policy | `room_message_tile.dart` — `kRoomMessageBubbleMaxWidthFraction`, per-window-class `readableCap`; `room_message_bubble_measure.dart` |
| Empty-state padding tokenization | inbox/evaluation empty states use `tt.screenHPadding` (no `EdgeInsets.all(24)` remaining) |
| Evaluation detail sheet padding tokens | `evaluation_detail_sheet.dart` uses `tt.screenHPadding`/`tt.rowGap`/`tt.sectionGap` |
| Home per-tab content cap | `home_screen.dart:99–101` (`TenturaContentColumn` for non-expanded tab content) |
| Context drop-down / forwards-graph touch targets | `context_drop_down.dart`, `forwards_graph_screen.dart` |

### Intentionally full-bleed (`TenturaFullBleed` / unconstrained by design)

`graph_screen`, `forwards_graph_screen`, `invite_genealogy_screen` (graph body),
`rating_scatter_view` (scatter plot), `beacon_room`/`item_discussion` (chat
surfaces), `choose_location_dialog` (fullscreen map), home shell rail layout.

---

## Route inventory correction

The 2026-06-27 snapshot listed 30 routes. The set has since changed (still 30
total):

- **Added:** `invite_genealogy` (commit c6cfacee — full-bleed graph body, no cap
  needed).
- **Removed from the route set:** `beacon_icon_picker` is no longer a
  `@RoutePage`.

Current `@RoutePage` screens (`grep -rl "@RoutePage" --include=*.dart features`):
`home`, `intro`, `auth_login`, `auth_register`, `recover`, `settings`,
`notification_settings`, `notification_center`, `profile`, `friends`, `inbox`,
`inbox_rejected`, `my_work`, `beacon`, `beacon_create`, `beacon_view`,
`beacon_legacy_path`, `beacon_room`, `forward_beacon`, `item_discussion`, `graph`,
`forwards_graph`, `rating`, `profile_view`, `profile_edit`, `credentials`,
`complaint`, `review_contributions`, `accept_invite`, `invite_genealogy`.

---

## How to re-verify this audit

If a future change is suspected to regress responsive layout, re-run the checks
that produced this report:

```bash
# 1. No standalone screen silently lost its width cap.
cd packages/client/lib
grep -rl "@RoutePage" --include=*.dart features        # current route set
# Each non-full-bleed route should reference one of:
#   TenturaContentColumn | contentMaxWidth | windowClass | LayoutBuilder | TenturaFullBleed

# 2. No bottom sheet bypasses the adaptive wrapper except the documented room one.
grep -rn "showModalBottomSheet" --include=*.dart . | grep -v tentura_adaptive_sheet

# 3. Tokens, not literals, for spacing in migrated UI.
grep -rn "EdgeInsets.all(24)\|EdgeInsets.all(16)" --include=*.dart features

# 4. Analyzer clean.
cd packages/client && flutter analyze
```

A fresh, comprehensive responsive gap-audit of the *current* tree (as opposed to
checking the items above) is a separate task — the surface has grown since
2026-06-27 and a new sweep would re-walk every route at compact/regular/expanded.
