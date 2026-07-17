# Telegram-Style Adaptive Layout — Port Plan for Tentura

> **Status: implemented in client chat layout.** This document reworks the
> Telegram Desktop horizontal-layout specification into Tentura's design-system
> vocabulary (`WindowClass`, `TenturaTokens`, `TenturaContentColumn`,
> `room_message_tile`) and lays out a concrete, ordered implementation plan.
>
> **Read first:** [`responsive-design-audit.md`](responsive-design-audit.md)
> (verified baseline) and
> [`desktop-adaptive-readiness-report.md`](desktop-adaptive-readiness-report.md)
> (gap list + priority order). This plan is the chat-layout half of that
> report's priority list, made precise against the Telegram reference.

---

## 1. Why Telegram's model maps cleanly onto ours

Telegram and Tentura already share the same two-level adaptive structure; they
just use different names. The port is mostly **adopting Telegram's constants and
its content-fit bubble math**, not rebuilding our primitives.

| Concept | Telegram | Tentura (today) |
|---|---|---|
| Window layout class | `OneColumn` / `Normal` / `ThreeColumn` via `computeColumnLayout()` | `WindowClass.compact` / `regular` / `expanded` (`tentura_window_class.dart`) |
| Width breakpoints | 640 / 932 (body width) | 600 / 840 (`MediaQuery` width) |
| Per-panel "wide" threshold | `adaptiveChatWideWidth = 880px` | **missing** — chat is full-bleed (`basic_chat_body.dart`) |
| Centered content column | `WideChatWidth() = 542px` | `TenturaContentColumn` + `contentMaxWidth` (560/720) — used on forms, **not** on chat |
| Bubble hard cap | `msgMaxWidth = 430px` | `readableCap` 520/640 + 75% fraction (`room_message_tile.dart`) |
| Bubble min | `msgMinWidth = 160px` | none explicit |
| Avatar gutter | `msgPhotoSkip = 40px` | ad-hoc per tile |
| Content-fit shrink | `countGeometry()` + `bubbleTextualWidth()` | `measureBubble()` + `shouldHugBubbleWidth()` (`room_message_bubble_measure.dart`) |
| Outgoing right-anchor | `contentLeft += availableWidth - contentWidth` | `isMine` row alignment in tile |

**Key insight:** Tentura's biggest divergence from Telegram is that the **chat
surface itself never enters a "wide" mode**. On desktop the message list +
composer span the entire viewport (the `responsive-design-audit.md` called this
intentional full-bleed; the readiness report flags it as the #1 desktop gap).
Telegram's `adaptiveChatWideWidth` behavior is exactly the fix: above a
threshold, stop widening the chat and instead **center a fixed-width column**.

---

## 2. Constant mapping (Telegram → Tentura tokens)

Telegram's pixel constants are tuned for a denser desktop client. We adopt the
*structure* but keep our existing token scale and snap to nearest token, per
[`design-system-migration-prefs`] (MD3 conformance > frozen pixels). Proposed
Tentura values:

| Telegram constant | Telegram px | Tentura token (proposed) | Tentura value |
|---|---:|---|---:|
| `adaptiveChatWideWidth` | 880 | `tt.chatWideWidth` (new) | **840** (reuse expanded breakpoint) |
| `WideChatWidth()` | 542 | `tt.chatColumnMaxWidth` (new) | **720** (reuse `contentMaxWidth` expanded) |
| `msgMaxWidth` (bubble cap) | 430 | keep `readableCap` | 520 (regular) / 640 (expanded) |
| `msgMinWidth` | 160 | `tt.bubbleMinWidth` (new) | **160** |
| `msgPhotoSkip` (avatar gutter) | 40 | `tt.avatarGutter` (new) | **40** |
| `msgMargin.left` (near side) | 16 | `tt.screenHPadding` | 16 / 20 / 24 |
| `msgMargin.right` (far side) | 56 | `tt.bubbleFarGutter` (new) | **56** |
| `maxMediaSize` | 430 | `tt.mediaMaxWidth` (new) | match bubble cap |
| `historyGroupSkip` (album gap) | 4 | `tt.albumGridGap` (new) | **4** |

> **Decision point (do not pre-decide):** whether the centered chat column max
> should be **720** (matches our existing expanded `contentMaxWidth`, visually
> consistent with forms) or a chat-specific **~640–680** (closer to Telegram's
> tighter 542 feel). Recommend 720 for token reuse; revisit after a visual pass.

---

## 3. Two-level adaptive model for Tentura chat

### Level 1 — Window/shell layout (already done)

`home_screen.dart` already does the column work: `NavigationBar` (compact) ↔
`NavigationRail` (≥600) ↔ extended rail (≥840), and Inbox master–detail on
expanded. **No change needed at this level** — this is Telegram's
`OneColumn/Normal/ThreeColumn` and we already have it.

### Level 2 — Chat-panel "wide" mode (the new work)

This is Telegram's `recountChatWidth()` → `ElementChatMode::Wide`. Introduce the
same decision inside the chat surface:

```
chatPanelWidth = constraints.maxWidth        // from a LayoutBuilder at the chat root

if chatPanelWidth >= tt.chatWideWidth (840):
    mode = Wide
    → constrain list + composer + FAB to a centered column of tt.chatColumnMaxWidth (720)
    → bubbles align left (incoming) / right (outgoing) *within that column*
else:
    mode = Default
    → list + composer span the panel (current behavior)
    → bubbles align/anchor against the panel edges, capped by readableCap
```

The crucial Telegram detail to replicate (`countGeometry()`): in **Wide mode the
per-row left/right alignment is computed against the centered column width, not
the panel width.** Today our bubble alignment uses `constraints.maxWidth` of the
full panel, so once we add a centered column the existing
`isMine`/`readableCap`/`measureBubble` logic continues to work **unchanged** — it
just receives a 720px constraint instead of a 1600px one. That is the whole
elegance of the port.

---

## 4. Content-fit bubble math — already aligned, minor gaps

Tentura's `measureBubble()` + `shouldHugBubbleWidth()` already implements
Telegram's "bubbles shrink to content, never stretch" rule (`countGeometry()` +
`bubbleTextualWidth()`). Gaps to close:

1. **Min-width floor (`msgMinWidth = 160`)** — Telegram never lets a bubble go
   below 160px. We have no floor, so single-emoji / one-word bubbles can render
   awkwardly narrow. Add `tt.bubbleMinWidth` and clamp `measureBubble()` result
   to `max(result, bubbleMinWidth + cardPaddingH)`.

2. **Media/poll enforce-width (`enforceBubbleWidth`)** — Telegram photos drive
   the bubble to exactly the media width. Today `shouldHug` is **false** for
   media/poll, so the bubble takes the full row (readiness report: poll/media
   "Not ready / High"). Port Telegram's rule: for media/poll, bubble width =
   `min(media.naturalWidth, mediaMaxWidth)`, still centered/anchored in the
   column. This fixes the #2 priority item (poll/media caps).

3. **"Nice to read" line cap** — Telegram binary-searches the narrowest width
   that keeps text within `kMaxNiceToReadLines`. We have `measureTightTextWidth`
   which already hugs; the line-count refinement is **optional polish**, defer.

---

## 5. Avatar gutter & alignment (group-chat parity)

Telegram reserves a fixed 40px avatar column (`msgPhotoSkip`) on the incoming
side; outgoing messages leave a 56px far-side gap. Tentura rooms are
group-style, so adopt:

- Incoming row left edge = `screenHPadding + avatarGutter` (avatar sits in the
  gutter strip).
- Outgoing bubbles right-anchored with `bubbleFarGutter (56)` from the column's
  right edge.
- Consecutive messages from the same sender: hide the avatar but **keep the
  gutter** (Telegram's attached-message behavior), and use small/large corner
  rounding accordingly (§6).

Audit `room_message_tile.dart` rows (lines ~340–470, ~994–1064) to route these
through the new tokens instead of `tt.screenHPadding` directly on both sides.

---

## 6. Bubble corner rounding (Telegram parity — optional, low priority)

Telegram's `countMessageRounding()` gives large corners by default, small corner
where a message is attached to the previous from the same sender, and a tail on
the last message of a run. Tentura currently uses uniform rounding. This is a
**polish item** — list it but gate behind the structural work above. If adopted,
mirror the four-corner `BubbleRounding` logic keyed on
"attached-to-previous / attached-to-next / has-inline-keyboard".

---

## 7. Implementation plan (ordered)

Each step is independently shippable and analyzer-clean.

### Step 1 — Add chat-layout tokens
`design_system/tentura_tokens.dart`: add `chatWideWidth`, `chatColumnMaxWidth`,
`bubbleMinWidth`, `avatarGutter`, `bubbleFarGutter`, `mediaMaxWidth`,
`albumGridGap` to `TenturaTokens` (+ `copyWith`/`lerp`/all three class
factories). Values per §2. No behavior change yet.

### Step 2 — Centered chat column (the headline fix)
`ui/widget/basic_chat_body.dart`: wrap the list + composer (+ jump FAB) in a
`LayoutBuilder`; when `maxWidth >= chatWideWidth`, center a
`ConstrainedBox(maxWidth: chatColumnMaxWidth)`. Below threshold, unchanged.
This resolves readiness-report priority **#1** and implicitly improves every
bubble because rows now measure against 720px.
Apply the same wrapper to the two other chat hosts:
`item_discussion_screen.dart` and the room branch of `beacon_view_screen.dart`
(`beacon_room_surface.dart` pass-through) — priority **#3**.

### Step 3 — Media / poll bubble caps (`enforceBubbleWidth`)
`room_message_tile.dart` + `room_poll_card.dart` + `room_attachment_widgets.dart`:
make `shouldHug` cap media/poll to `min(natural, mediaMaxWidth)` instead of full
row; replace `width: double.infinity` on albums with the gutter-aware column
width. Resolves priority **#2**.

### Step 4 — Bubble min-width floor
`room_message_bubble_measure.dart`: clamp `measureBubble()` to `bubbleMinWidth`.
Small, isolated, well-covered by existing measure unit tests.

### Step 5 — Avatar gutter & far-gutter alignment
`room_message_tile.dart`: route incoming/outgoing horizontal anchors through
`avatarGutter` / `bubbleFarGutter` tokens (§5). Keep gutter on attached
messages.

### Step 6 (optional polish) — Corner rounding + album grid gap + nice-to-read
Mirror `countMessageRounding()`; tokenize album `historyGroupSkip`. Defer unless
time allows.

---

## 8. Acceptance criteria

- **Compact (<600):** chat visually unchanged from today (column max is null /
  not applied; full-bleed retained).
- **Regular (600–839):** chat still spans panel; bubbles capped at readableCap
  520; media capped at `mediaMaxWidth`.
- **Expanded / wide (≥840):** list + composer + FAB centered in a ≤720px column;
  outgoing right-anchored, incoming left-anchored with avatar gutter; no element
  spans edge-to-edge; poll/media cards no longer stretch.
- No bubble narrower than `bubbleMinWidth (160)`.
- `flutter analyze` on `packages/client` clean; `room_message_bubble_measure`
  unit tests pass and gain min-width + media-cap cases.
- Existing full-bleed surfaces (graph, maps, scatter) untouched.

## 9. Verification

```bash
cd packages/client && flutter analyze lib/features/beacon_room lib/ui/widget
cd packages/client && flutter test test/.../room_message_bubble_measure_test.dart
```
Then drive the room via the Playwright/Obscura e2e harness
([`local-e2e-playwright-obscura`]) at three viewport widths (≈480 / 720 / 1400),
checking: column centering kicks in at 840, outgoing/incoming anchoring, poll +
image-album caps, single-word bubble min-width.

---

## 10. Explicitly out of scope

- Window-shell column layout (Level 1) — already complete, no change.
- A third/info column (Telegram `ThreeColumn`) — Tentura has no chat-info
  side panel; not in scope.
- Round video / sticker / GIF sizing constants — Tentura has no such media
  types; ignore those Telegram constants.
- Pixel-identical match to Telegram — we snap to existing tokens
  ([`design-system-migration-prefs`]).

---

### Source references

- Telegram spec: provided derivation from `window_session_controller.cpp`,
  `chat.style`, `history_view_message.cpp`, `history_widget.cpp`.
- Tentura: `tentura_window_class.dart`, `tentura_tokens.dart`
  (`contentMaxWidth` 560/720), `room_message_tile.dart` (readableCap 520/640,
  `kRoomMessageBubbleMaxWidthFraction`), `room_message_bubble_measure.dart`
  (`measureBubble`), `basic_chat_body.dart` (full-bleed chat shell),
  `tentura_responsive_scope.dart` (`TenturaContentColumn`).
