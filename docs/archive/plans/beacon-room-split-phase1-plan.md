# Phase 1 — Beacon | Room Split (expanded only)

Plan date: 2026-06-30. Scope: `beacon_view_screen.dart` only. Goal: at
`WindowClass.expanded`, render the **operational view and room chat side by side**
in one `Row` instead of swapping full screens. Compact and regular behavior is
**frozen** — no router changes, no shell changes.

**Related:** [`desktop-adaptive-readiness-report.md`](desktop-adaptive-readiness-report.md),
[`room-coordination-audit.md`](room-coordination-audit.md),
[`telegram-adaptive-layout-port-plan.md`](telegram-adaptive-layout-port-plan.md).
Precedent pattern: inbox in-screen master–detail (`inbox_screen.dart`
`_InboxExpandedBody`).

This is **Phase 1 of 3** from the adaptive-layout brief. It deliberately does
**not** persist the `NavigationRail` over the beacon (that is Phase 2, router/shell
work, intentionally deferred — see brief). Phase 1 ships standalone value with the
blast radius contained to a single file.

> **Dependency update (2026-06-30): the Telegram adaptive-layout port has
> landed.** Several things this plan originally treated as "separate / out of
> scope" are now in committed code and change how Phase 1 should be built:
>
> - **`TenturaChatColumn`** (`design_system/tentura_responsive_scope.dart`) now
>   centers any chat surface to **`tt.chatColumnMaxWidth` (720)** once the surface
>   reaches **`tt.chatWideWidth` (840)** wide; below 840 it is a **no-op** and the
>   surface stays full width.
> - It is already applied at all three chat hosts, including
>   **`beacon_room_surface.dart`** — i.e. `BeaconRoomSurface` (the exact widget
>   this plan embeds in the room pane) **already self-caps**.
> - New tokens exist: `chatColumnMaxWidth` (720), `chatWideWidth` (840),
>   `bubbleMinWidth` (160), `avatarGutter` (40), `bubbleFarGutter` (56),
>   `mediaMaxWidth` (520/640), `albumGridGap` (4). Poll/media bubble caps and the
>   bubble min-width floor also landed.
>
> Net effect: Phase 1 no longer needs to *introduce* a chat width cap, and the
> "room pane stretches on ultrawide" risk now has a built-in backstop. See the
> updated **Layout**, **Risk register**, and **Out of scope** sections below.

---

## Core constraint: hard-fork by `WindowClass`

`beacon_view_screen.dart` carries a fragile room-lifecycle state machine
(`_showRoomSurface`, `_roomEnteredViaPush`, `_userDismissedRoomSurface`,
`_roomExitInProgress`, `_pendingRoomExit`, `_didApplyFetchResolution`) with
push/replace/back juggling, `PopScope(canPop: !_showRoomSurface)`, and deep-link
URL reconciliation in `didUpdateWidget`.

**Non-negotiable:** the compact/regular code path must remain byte-for-byte
behaviorally identical. The split is an **additive expanded-only branch**, not a
unification of the two modes. Phones are always compact; **tablets in landscape and
foldables hit `expanded`**, so this branch is real mobile surface — test on tablet.

Decision point: introduce a single derived flag near the top of `build`:

```dart
final isSplit = context.windowClass == WindowClass.expanded
    && showBeaconContent
    && state.canNavigateBeaconRoom;
```

Gate at **expanded (≥840)**, matching the inbox split — not 600. Rail-less today,
but operational column (~360) + room chat (~360) does not breathe at regular width.

---

## Behavioral model in split mode

| Concept | Compact/regular (unchanged) | Expanded split (new) |
|---------|-----------------------------|----------------------|
| Operational vs room | Mutually exclusive; `_showRoomSurface` swaps body | Both mounted in a `Row` |
| Room cubit lifecycle | Created on enter, closed on exit (mark-seen flush) | **Permanently mounted** while beacon open |
| `_enterRoomSurface` | Push `?tab=room` / open surface | No-op for visibility; only `prepareThreadScroll` to focus the already-visible pane |
| `_exitRoomSurface` | Back / strip URL / release cubit | No room "exit"; back leaves the beacon |
| `PopScope.canPop` | `!_showRoomSurface` | `true` (room is not a poppable layer) |
| App bar back button | `BackButton(onPressed: _exitRoomSurface)` when in room | Always `AutoLeadingWithFallback` (leave beacon) |
| App bar title status | room status line when `_showRoomSurface` | operational status line (room is co-visible, not focused) |
| `?tab=room` deep link | Opens room surface | **Focus/scroll** room pane; do not toggle a "mode" |
| Chat icon in app bar / CTA | shows; opens room | hidden or repurposed to "scroll room pane to bottom/focus" |

Key consequence to call out in review: in split mode the room is **never closed**
until the whole beacon route is popped, so **mark-seen / unread-anchor side effects
fire on a different cadence** (continuous, not on exit). That is acceptable and
expanded-only, but must be explicit in the PR description and tests.

---

## Layout

In the `else`/room branch of the body builder (around `beacon_view_screen.dart:652`),
replace the swap with a split when `isSplit`:

```
Row(
  crossAxisAlignment: stretch,
  children: [
    Expanded(                       // operational — reuse existing TenturaContentColumn body
      flex: ...,
      child: operationalBody,
    ),
    const TenturaVerticalHairline(), // same divider used by home rail split
    SizedBox(                       // room pane — explicit cap governs below 840
      width: roomPaneWidth,         // clamp(tt.chatColumnMaxWidth, 360, 560)
      child: BlocProvider.value(value: _roomCubit!, child: BeaconRoomSurface(...)),
                                    // BeaconRoomSurface's TenturaChatColumn no-ops
                                    // here (pane < chatWideWidth); SizedBox wins
    ),
  ],
)
```

- Operational body = the **existing** `TenturaContentColumn(...BeaconOperationalScrollView...)`
  block, lifted into a helper so both the swap path and split path call it.
- Room pane = the **existing** `BeaconRoomSurface` + `RoomCubit` `BlocProvider.value`
  + the `unreadCount` `BlocListener`, also lifted into a helper.
- **The room pane still needs its own `width` cap**, but the reasoning has
  changed now that `TenturaChatColumn` has landed: `BeaconRoomSurface` already
  wraps its body in `TenturaChatColumn`, **but that only centers once the pane is
  ≥ `tt.chatWideWidth` (840)**. In split mode the pane is deliberately
  **narrower than 840** (operational + room must both breathe at ≥840 total), so
  the embedded `TenturaChatColumn` is a **no-op inside the pane** and the chat
  fills the pane. Therefore the explicit `SizedBox`/`ConstrainedBox` width here is
  what governs the pane, exactly as before — set it with **tokens, not literals**.
  Recommended pane width: `clamp(tt.chatColumnMaxWidth, 360, 560)` (the 720 chat
  column is the natural cap; clamp keeps the operational column usable). The two
  caps compose cleanly: pane width wins below 840, `TenturaChatColumn` is the
  backstop above 840 — no double-centering, since they never both apply.

Resize handling (desktop web + foldables): when the window crosses 840 with the
room visible, the build simply re-evaluates `isSplit`. Going **expanded → compact**
must land on the operational view with the room machine back in its
mutual-exclusion state (i.e. `_showRoomSurface == false`, no live push). Add an
explicit reconciliation in `didChangeDependencies`/`didUpdateWidget` so a shrink
does not strand `_showRoomSurface == true` with no swap UI.

---

## Refactor steps

1. **Extract `_buildOperationalBody(...)`** from the current `else` branch
   (`beacon_view_screen.dart:669-695`) — no behavior change, pure lift.
2. **Extract `_buildRoomPane(...)`** from the `_showRoomSurface` branch
   (`:652-668`) — pure lift, keeps the `RoomCubit` provider + unread listener.
3. **Add `isSplit` derivation** in `build`.
4. **Add the `Row` split branch** that calls both helpers; keep the legacy swap for
   non-split.
5. **Fork the room cubit lifecycle**: in split mode, ensure the embedded cubit is
   created on first build (reuse `_ensureEmbeddedRoomCubit`) and **not** released on
   any "exit" path; only `dispose` releases it.
6. **Fork app bar + `PopScope`**: when `isSplit`, force `canPop: true`, drop the
   room `BackButton`, use operational status line, hide/repurpose the room app-bar
   button.
7. **Fork deep links**: when `isSplit` and route says `tab=room`, call
   `prepareThreadScroll` on the visible pane instead of `_applyRoomSurfaceState`.
   Still **strip `?tab=room` from the URL** on entry so a later shrink to compact
   does not auto-open the swap surface unexpectedly (or keep it and let
   reconciliation handle it — pick one and test both directions).
8. **Add resize reconciliation** for expanded→compact (step in Layout above).

Steps 1–2 should be a separate no-op commit (easy to review and to prove compact
is untouched).

---

## Risk register

| Risk | Severity | Mitigation |
|------|----------|------------|
| Editing the 800-line state machine regresses compact back-gesture / room enter-exit | High | Steps 1–2 are pure lifts; all new logic behind `isSplit`; **never touch the `!isSplit` branch** |
| Tablets (landscape/foldable) silently enter split and break mobile QA | High | Treat tablet `expanded` as a first-class test target, not "desktop" |
| Mark-seen cadence change (room always mounted) | Medium | Document in PR; add test asserting unread clears continuously in split |
| Resize across 840 strands `_showRoomSurface` | Medium | Explicit reconciliation; test grow→shrink→grow |
| Room pane stretches on ultrawide | Low | Local pane width cap via tokens governs below 840; `TenturaChatColumn` in `BeaconRoomSurface` is the backstop above 840. Severity dropped from Medium now that the chat-column cap has landed |
| `?tab=room` deep link semantics drift between modes | Medium | Single source of truth: `isSplit ? focusPane : openSurface`; test both |

---

## Test matrix

- **Compact (phone):** open beacon → tap chat → room swaps in → back → operational;
  system back gesture; `?tab=room` deep link; `/beacon/room/:id` legacy redirect.
  **Must be identical to pre-change.**
- **Regular (600–839):** same as compact (split is expanded-gated).
- **Expanded (tablet landscape / desktop ≥840):** operational + room co-visible;
  `?tab=room` focuses room pane; app-bar back leaves beacon (no intermediate room
  exit); room pane width capped; unread clears while pane visible.
- **Resize:** grow compact→expanded with room open (swap → split); shrink
  expanded→compact (split → operational, room machine reset); foldable fold/unfold.
- **Access denied:** `canNavigateBeaconRoom == false` at expanded → no room pane,
  operational full width, existing banner path intact.

---

## Out of scope (Phase 2/3)

- Persisting `NavigationRail` over the beacon (router nesting / `AppShell`).
- Friends/profile column caps.

### Already landed (no longer Phase 1 concerns)

The Telegram adaptive-layout port shipped these, so they are **done**, not
deferred — do not re-implement:

- Global chat-column cap (`TenturaChatColumn` applied in `basic_chat_body.dart`,
  `beacon_room_surface.dart`, `item_discussion_screen.dart`).
- Poll/media bubble caps and the bubble min-width floor.
- Item-discussion chat surface is already wrapped (`item_discussion_screen.dart`).

Phase 1 now only adds the **side-by-side split** on top of these; it consumes
the new tokens/widget rather than introducing any width-capping of its own.
