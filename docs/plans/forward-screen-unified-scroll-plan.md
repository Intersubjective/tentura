# Forward screen — unified scroll, invite bar relocation, note-button removal

Status: draft, awaiting review.

## 1. Problem

On the forward-recipient screen, `_ForwardRecipientPickerState.build()`
(`packages/client/lib/features/forward/ui/widget/forward_recipient_picker.dart:452-633`)
lays out a fixed, non-scrolling `Column` containing (in order): top bar,
`CompactBeaconContextStrip` (the author line), `ForwardBandStrip`
("recommended"/"new" sections), `ForwardScopeLinks` (the two-tab bar), an
`Expanded(ListView(...))` holding the lineage + "usual suspects" recipient
rows, and `ForwardBottomComposer` (shared note + invite + send).

Only the `ListView` inside the `Expanded` scrolls. On a small phone, once
`ForwardBandStrip` grows (a few "recommended" + "new" rows), it eats most of
the vertical space, the tab bar is squeezed against it, and the recipient
list is left with a tiny scrollable sliver — the user has to scroll the
*list* to see rows that are visually right below sections that don't move.

Three fixes requested:
1. Make the whole thing scroll as one region (sections + tabs + list).
2. Remove the "add shared note" button in `ForwardBottomComposer`'s collapsed
   state — the reminder sheet shown on Forward-press already covers this.
3. Move "invite new person" to a fixed slot below the author line, with
   hide-on-scroll-down / reveal-on-scroll-up behavior.

## 2. Design rationale (ui-ux-pro-max + flutter-build-responsive-layout)

- `scroll-behavior` (ux domain): "Avoid nested scroll regions that interfere
  with the main scroll experience" — this is exactly today's bug. The fix is
  one scroll owner for the whole content area, not two.
- `touch-target-size` / `touch-spacing`: the relocated invite affordance
  keeps its existing `TenturaInfoHintButton`-adjacent sizing (`tt.buttonHeight`,
  44pt+) and stays reachable without being cramped against the author strip.
- Codebase precedent for "sections above a pinned tab bar, one shared
  scroll": `BeaconOperationalScrollView`
  (`packages/client/lib/features/beacon_view/ui/widget/beacon_operational_scroll_view.dart:195-356`)
  already solves this exact shape for the beacon-view screen — a
  `CustomScrollView` with a `SliverToBoxAdapter` header, a
  `SliverPersistentHeader(pinned: true)` wrapping the tab bar via
  `BeaconPinnedSegmentBarDelegate`, then a `SliverToBoxAdapter` tab body, then
  a `SliverFillRemaining(hasScrollBody: false)` filler. This plan reuses that
  exact shape rather than inventing a new one.
- **Simplification (per user feedback):** rather than building custom
  hide-on-scroll-down/reveal-on-scroll-up behavior (`ScrollController`
  listener + `ScrollDirection` tracking + `AnimatedSlide`/`AnimatedOpacity` +
  reduced-motion handling), place the invite bar as the **first sliver**
  inside the same `CustomScrollView` used for everything else. It then
  scrolls away with the top sections using ordinary scroll physics — zero
  new state, zero animation code, zero reduced-motion special-casing (there's
  nothing being animated to reduce). No `SliverAppBar`/`NestedScrollView`
  precedent exists anywhere in the client today (`grep` for `SliverAppBar`,
  `floating:`, `ScrollDirection.` returns zero hits), so this also avoids
  introducing a first instance of that machinery for a single bar.
  Trade-off worth naming: this reappears only once the user scrolls **all
  the way back to the top** of the content, not on *any* upward scroll from
  wherever they are (unlike a true sticky reveal-on-scroll-up bar, e.g.
  Gmail's compose FAB). Given "invite a new person" is a secondary, low
  frequency action here, that trade-off seems acceptable — flagged in §7 in
  case that reachability difference matters.

## 3. Current widget inventory (for reference)

| Piece | File | Notes |
|---|---|---|
| Screen body / scroll owner | `forward_recipient_picker.dart:452-633` | `Stack` → `AbsorbPointer` → fixed `Column` |
| "Recommended"/"New" sections | `forward_band_strip.dart` (`ForwardBandStrip`) | Plain `Column`, no scroll of its own |
| Two-tab bar | `forward_scope_links.dart` (`ForwardScopeLinks`) | Hand-rolled underline tabs bound to `ForwardFilter`, not `TabBar`/`TabController` |
| Recipient list ("usual suspects") | `_buildRecipientList()` in `forward_recipient_picker.dart:659-781` | Feeds the current `ListView`'s children |
| Bottom bar (note + invite + send) | `forward_bottom_composer.dart` (`ForwardBottomComposer`) | Collapsed "add shared note" row: lines 89-127; invite button: lines 129-146 |
| Reminder popup | `_UncoveredRecipientsSheet` in `forward_recipient_picker.dart:842-961`, triggered by `_handleForwardPressed`/`_showUncoveredRecipientsSheet` (132-197) | Own `TextEditingController`, independent of the composer's note state |
| Invite flow | `_inviteNewPerson()` in `forward_recipient_picker.dart:328-365` | Unchanged — only its trigger widget moves |
| Invite gating | `lib/features/forward/domain/invite_new_person_enabled.dart` | `inviteNewPersonEnabled(beaconId, allowsForward, isLive)` — no dependency on `activeFilter` |
| State | `forward_state.dart` (`ForwardState`) | `activeFilter` (enum, the "tab"), `band`, `lineageSuggestions`, `skippedPersonalNoteIds`. No scroll-position or tab-index state today. |
| Reusable pinned-header delegate (precedent) | `beacon_operational_scroll_view.dart:364-398` (`BeaconPinnedSegmentBarDelegate`) | Fixed 48px extent, `Material` + elevation-on-overlap. Feature-local, not in `design_system/`. |
| Design-system tabs (unused by `ForwardScopeLinks` today) | `design_system/components/tentura_underline_tabs.dart` (`TenturaUnderlineTabs`) | Not part of this plan's scope — flagged as a pre-existing reuse gap, not something to fix here |

## 4. Target structure

```
Stack                                            (unchanged)
 └─ AbsorbPointer
     └─ Column (stretch)
         ├─ TenturaTopBar + divider                       (unchanged, if !embedded)
         ├─ CompactBeaconContextStrip                      (unchanged, if !embedded)  ← "author line"
         ├─ Expanded
         │   └─ CustomScrollView                            ← single scroll owner (NEW)
         │       slivers:
         │         SliverToBoxAdapter: ForwardInviteBar (NEW)  ← scrolls away with the rest
         │         [SliverToBoxAdapter: ForwardBandStrip]     (if showBandBlock)
         │         SliverPersistentHeader(pinned: true,
         │           delegate: _ForwardPinnedTabBarDelegate(  ← wraps ForwardScopeLinks
         │             child: ForwardScopeLinks(...)))
         │         [SliverToBoxAdapter: lineage section]     (if lineage.isNotEmpty — this order
         │                                                     matches today: lineage renders inside
         │                                                     the list, i.e. below the tab bar, not
         │                                                     above the band strip)
         │         SliverList.list: recipient rows   (or SliverFillRemaining+Center for empty state)
         │         SliverFillRemaining(hasScrollBody: false)   (bottom breathing room, matches beacon_view precedent)
         └─ ForwardBottomComposer                            (unchanged position; note+send only, invite removed)
```

`ForwardInviteBar` is the first sliver in the `CustomScrollView` — below the
fixed author strip when scrolled to top, scrolled away like any other
content once the user scrolls down. No separate `ScrollController` or
animation is needed for it.

## 5. Implementation units

### Unit A — Convert the scroll area to `CustomScrollView`

File: `forward_recipient_picker.dart`.

1. Add a `ScrollController _scrollController` to `_ForwardRecipientPickerState`
   (disposed alongside the existing controllers).
2. Replace the `Expanded(child: listIsEmpty ? Center(...) : ListView(...))`
   block (lines 565-598) with `Expanded(child: CustomScrollView(controller: _scrollController, slivers: [...]))`.
3. Move `ForwardBandStrip` (currently a direct `Column` child at line
   537-559) into a `SliverToBoxAdapter` inside that `CustomScrollView`'s
   `slivers`, still gated by the existing `showBandBlock` bool.
4. Move `ForwardScopeLinks` (line 560-564) into a
   `SliverPersistentHeader(pinned: true, delegate: _ForwardPinnedTabBarDelegate(child: ForwardScopeLinks(...)))`.
   `_ForwardPinnedTabBarDelegate` is a small local class in this file (or a
   new `forward_pinned_tab_bar_delegate.dart` in the same `ui/widget/`
   folder), copying `BeaconPinnedSegmentBarDelegate`'s outer mechanics
   (`Material` wrapper, `elevation: overlapsContent ? 0.5 : 0`) but **not**
   its literal `_barHeight = 48` constant. Reviewer finding: `48` was tuned
   for `TenturaUnderlineTabs` (small fixed ~6px internal gap,
   `tentura_underline_tabs.dart:321`), not for `ForwardScopeLinks`, whose
   `scopeTab()` cells (`forward_scope_links.dart:38-90`) use
   `ConstrainedBox(minHeight: tt.buttonHeight)` around `2×tt.rowGap` padding
   + a text line + `tt.iconTextGap` + a 2px underline — a naturally taller,
   window-class-scaling (44/46/48) shape whose content height can *equal or
   exceed* a flat 48 at the `expanded` breakpoint with zero headroom left
   for larger system text scale. Fix: derive `minExtent`/`maxExtent` from
   `context.tt.buttonHeight` at build time plus a small fixed safety margin
   (e.g. `tt.buttonHeight + 4`) — NOT `buttonHeight + 2×rowGap +
   iconTextGap + 2` stacked additively, which double-counts (the padding/
   gap/underline are already what the `ConstrainedBox(minHeight:
   tt.buttonHeight)` content is clamped to, per the reviewer's finding that
   natural content height is already "bound to ≈tt.buttonHeight"). This
   scales with window class instead of a disconnected literal; verify the
   exact margin empirically in-browser at the `expanded` breakpoint with a
   larger system text-scale setting during manual QA (§6), and adjust the
   margin if any clipping is observed. Note: `BeaconPinnedSegmentBarDelegate`'s own comment
   about avoiding "invalid SliverGeometry ... under NestedScrollView"
   (`beacon_operational_scroll_view.dart:362-363`) doesn't apply here or
   there — a repo-wide grep confirms `NestedScrollView` isn't used
   anywhere; don't carry that comment over uncritically. Keep this delegate
   feature-local (don't import the beacon-view file cross-feature); if a
   third screen needs this shape later, that's the trigger to extract a
   shared, properly-measured `design_system/components/` delegate — not
   before.
5. Split `_buildRecipientList()` (lines 659-781): the **lineage** portion
   (670-715) becomes its own `SliverToBoxAdapter` (small, bounded section —
   fine as one box), gated by `lineage.isNotEmpty` — same condition as
   today. The **visible recipients** portion (717-778) — potentially the
   long list — becomes `SliverList.list(children: [...])` rather than
   `SliverToBoxAdapter(child: Column(...))`. Reviewer finding: today's
   `ListView(children: [...])` (`forward_recipient_picker.dart:583-597`) is
   backed by an implicit `SliverList`, so while row *widgets* are built
   eagerly by `_buildRecipientList()` either way, the sliver-level
   `RenderObject`s are still laid out/disposed lazily by viewport under
   `SliverList`. Collapsing this into a single `SliverToBoxAdapter` would be
   a real (if modest for typical list sizes) regression versus current
   behavior. `SliverList.list(children: rows)` keeps the same eager-widget
   construction the plan already accepts while preserving today's
   render-level laziness.
6. Empty state (`listIsEmpty`, lines 566-582): replace with
   `SliverFillRemaining(hasScrollBody: false, child: Center(...))` in place
   of the trailing filler sliver, so an empty tab doesn't look broken.
7. Trailing `SliverFillRemaining(hasScrollBody: false, child: SizedBox.shrink())`
   after the recipient sliver, matching `beacon_operational_scroll_view.dart:350-353`,
   so short lists don't leave the pinned tab bar awkwardly stuck mid-screen.
8. Tab-switch scroll reset: when `cubit.setFilter` changes `activeFilter`,
   jump `_scrollController` back to 0 (e.g. in the filter-changed path or via
   a `BlocListener` on `activeFilter`) so switching tabs doesn't leave the
   user scrolled into the previous tab's now-different content. Reviewer
   correction: this is **not** just a defensive/consistency copy of existing
   behavior — today's plain `ListView` (`forward_recipient_picker.dart:583`)
   has no `Key`, so when `activeFilter` changes but `listIsEmpty` stays
   `false` on both tabs (a common case), `Widget.canUpdate` (same
   `runtimeType`, same `null` key) preserves the same `Element`/
   `ScrollPosition` today — i.e. the scroll offset does *not* reliably reset
   today either. The explicit `jumpTo(0)` this plan adds is a genuine,
   necessary fix, not a behavior-preserving formality.

No `TabBarView`/`PageStorageKey`/`AutomaticKeepAliveClientMixin` needed:
`ForwardScopeLinks` isn't a real `TabBar` and only one filter's rows are ever
built at a time (mirrors `BeaconOperationalScrollView`'s `tabBody` swap, not
`friends_screen.dart`'s independent-per-tab `TabBarView`). Introducing a real
`TabController` here would be new scope beyond this fix.

### Unit B — Remove the "add shared note" button

File: `forward_bottom_composer.dart`.

1. Delete the `else` branch (lines 89-127: the `Material`/`Row`/`InkWell`
   "add shared note" affordance). Keep the `if (noteExpanded) ...` branch
   (52-88) untouched — it still renders when `noteExpanded` is true, which
   now only happens via the existing `BlocListener` auto-expand in
   `forward_recipient_picker.dart:395-407` (lineage-suggested note present)
   or if some other future caller sets it. Its `expand_less` suffix icon
   (`onToggleNoteExpanded`, line 79-84) remains the only way to collapse it
   again.
2. `TenturaInfoHintButton(fullText: l10n.forwardReasonAheadHint, ...)`
   (lines 120-124) was only shown inside the branch being deleted, gated on
   `selectedIds.isEmpty`. Relocate it rather than silently drop the
   affordance: place it as a small leading/trailing icon next to the Send
   button row (120-124 → new home near line 148-195), same gating
   (`selectedIds.isEmpty`). This is a UX decision worth confirming with the
   user before implementing — flagged in §7.
3. `onToggleNoteExpanded` stays a required param (still used by the
   suffix-icon collapse action); no signature change needed.
4. Confirmed one-way consequence (not a bug, but worth stating explicitly):
   once a user manually collapses an auto-expanded note (taps `expand_less`,
   `forward_bottom_composer.dart:78-84`), there is no way to reopen it in
   the composer except by re-triggering the lineage-suggestion condition —
   proactively adding a shared note with no lineage suggestion present is
   now only reachable via the independent `_UncoveredRecipientsSheet` at
   send time (own separate controller, `forward_recipient_picker.dart:861`,
   though its text still lands in `cubit.state.note`). This matches the
   request's intent (the reminder sheet is meant to be sufficient) — flagging
   so it's a conscious tradeoff, not a surprise found later.

### Unit C — Extract and relocate "invite new person"

Files: `forward_bottom_composer.dart`, `forward_recipient_picker.dart`, new
file `forward_invite_bar.dart` (same `ui/widget/` folder).

1. Remove the invite `Semantics`/`TextButton.icon` block (lines 129-146) and
   the `onInvite` parameter from `ForwardBottomComposer` — the composer no
   longer knows about inviting.
2. New `ForwardInviteBar` widget: a slim row reusing the same visual
   treatment (`Icons.person_add_alt_1_outlined` + `l10n.forwardInviteNewPerson`,
   `tt.textMuted` command-style text, `tt.buttonHeight` min height for the
   44pt touch target), keeping `Semantics(identifier: TestIds.forwardInviteNewPerson, button: true)`
   and the same `Key` so existing test/integration lookups by test id keep
   working.
3. Place `ForwardInviteBar` as the **first sliver** in the new
   `CustomScrollView` from Unit A (`SliverToBoxAdapter(child: ForwardInviteBar(...))`,
   ahead of the lineage/band-strip slivers). No `ScrollController` listener,
   no animation — it scrolls with the content, per §2's simplification. Gate
   it the same way the button was gated before
   (`inviteNewPersonEnabled(beaconId:, allowsForward:, isLive:)`), but
   **not** by `activeFilter` — today it only appeared implicitly on
   non-"already involved" tabs because the whole composer was hidden there;
   at the top of the screen, showing it on both tabs is the more sensible
   behavior and matches "move to the top" as stated. Call this out as an
   intentional behavior change in the PR description.
4. `embedded` mode: `ForwardRecipientPicker` is also used inside the
   beacon-create tab with `embedded: true`, which omits the top bar and
   `CompactBeaconContextStrip` entirely (no "author line" to sit below). No
   special-casing needed here either — `ForwardInviteBar` is still just the
   first sliver in the same `CustomScrollView`, it simply has no fixed strip
   above it in that mode. Same gating logic applies unchanged since
   `inviteNewPersonEnabled` doesn't reference `embedded`.

## 6. Testing

- `test/features/forward/forward_recipient_picker_test.dart`: existing tests
  use `find.text(...)`/`find.byTooltip(...)` which don't care whether the
  ancestor is a `Column`/`ListView` or `CustomScrollView`/slivers — should
  keep passing unmodified. Add new coverage:
  - Scrolling the outer view scrolls both the band-strip/lineage content and
    the recipient rows together (drag near the bottom, assert a row that was
    off-screen becomes visible, plus assert the band-strip title is now
    scrolled off — i.e., they move as one).
  - Tab-switch resets scroll position.
  - "Add shared note" button (`l10n.forwardAddSharedNoteCommand` text) is
    gone from `ForwardBottomComposer`.
  - Invite button (`TestIds.forwardInviteNewPerson`) is found above the
    band-strip/lineage/tab-bar content (e.g. assert its `dy` offset is less
    than the tab bar's) and is present regardless of `activeFilter`.
  - Invite bar scrolls away together with the top sections on a downward
    drag (assert it's no longer hit-testable/visible after scrolling), and
    scrolling back to the top brings it back into view.
- `test/features/forward/ui/widget/forward_band_strip_test.dart`: shouldn't
  need changes (tests the strip in isolation), but re-run since it may be
  pumped directly inside a `Scaffold`/`SliverToBoxAdapter` context now if any
  test wraps it in a scroll view — check after Unit A lands.
- `test/golden/typography_overhaul_test.dart:187-208`,
  `testWidgets('forward composer collapsed with ahead hint', ...)`: pumps
  `ForwardBottomComposer(noteExpanded: false, selectedIds: {})` specifically
  to golden-test the exact collapsed-row + `TenturaInfoHintButton` UI Unit B
  deletes. This test's entire subject goes away — it needs a rewrite/retarget
  (e.g. to the relocated info-hint button per §7 decision 1), not just image
  regeneration. The sibling test at line 162 (`'forward composer'`,
  `noteExpanded: true`) is unaffected since Unit B only touches the `else`
  branch.
- `integration_test/support/e2e_test_helpers.dart`: grepped — nothing there
  currently references `TestIds.forwardInviteNewPerson` (only its
  definition in `test_ids.dart` and its use inside
  `forward_bottom_composer.dart`), so there's no existing e2e call site to
  fix; this is a forward-looking check in case a future e2e test taps it,
  not a currently-broken one.
- Manual QA per `local-debug` skill: run the client, open a forward screen
  with enough band-strip rows to overflow a small-phone viewport (resize
  browser or use device emulation ~360×740), confirm one continuous scroll,
  confirm the invite bar scrolls away with the top sections and reappears on
  scrolling back to the top, confirm the reminder sheet still appears when
  forwarding without personal notes.

## 7. Open decisions to confirm before/while implementing

1. **Info-hint button relocation** (Unit B.2): where exactly should
   `forwardReasonAheadHint`'s `TenturaInfoHintButton` land once its original
   row is deleted? Proposed: inline next to the Send button, `selectedIds.isEmpty`-gated as before.
2. **Invite bar reachability trade-off** (§2, Unit C.3): scroll-away means
   the invite bar only reappears once the user scrolls all the way back to
   the top, not on any upward scroll from wherever they are. Confirming this
   is an acceptable trade for the simpler implementation, given inviting a
   new person is a secondary action here.
3. **Invite bar visibility across tabs** (Unit C.3): confirming the
   intentional change — invite is now visible on both "Not yet seen" and
   "Already involved" tabs, whereas today it's implicitly hidden on
   "Already involved" (composer isn't rendered there at all).

## 8. Out of scope

- Migrating `ForwardScopeLinks` to the shared `TenturaUnderlineTabs`
  component (pre-existing reuse gap, unrelated to this scroll fix).
- Any change to `ForwardBandStrip`'s internal content/ordering (recommended
  vs. exploration split) — only its scroll ownership changes.
- Any change to the reminder-sheet (`_UncoveredRecipientsSheet`) content or
  trigger condition — it already does the job the removed button's absence
  relies on.
