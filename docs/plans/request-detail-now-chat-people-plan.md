# Request detail — NOW / CHAT / People surfaces

**Status:** draft, revision 2 (post adversarial review)
**Date:** 2026-09-07
**Scope:** `packages/client` request detail screen (`features/beacon_view`, `features/beacon_threads`), design system tab component, routing, l10n, tests, shipped docs.
**Skills applied:** `material-3-flutter`, `flutter-build-responsive-layout`, `clean-architecture` (UI layer only — no domain/data changes).
**Review:** rev 1 reviewed by codex `gpt-6-astra` (read-only, whole-tree). 13 findings, all verified against the code and folded in here. Disposition table in §12.

---

## 1. Goal

Replace the current three-tab request detail (**Discussion / People / Log**) with three surfaces:

| Surface | Role | Tab |
|---|---|---|
| **NOW** | Operational header, state, details, actions **+ child Request cards at the bottom** | primary, labeled, equal width |
| **ROOM** (user-facing label **Chat**) | The single Request conversation (General), inline | primary, labeled, equal width |
| **PEOPLE** | Existing People body, unchanged | secondary, fixed-width, **icon-only**, right end of the same row |

The tab row moves out of the scrolling sliver and sits **directly below the app bar**. **Log** leaves primary navigation and becomes an **Activity** entry in the app-bar overflow, opening a full-height adaptive sheet.

### What this is not

MR / admission / visibility semantics are untouched. No domain, data, GraphQL, or server change. `BeaconViewCubit`, `ThreadsCubit`, `RoomCubit`, `BeaconHierarchyCubit`, and `BeaconViewState` keep their current contracts; only the widget tree that consumes them is restructured.

---

## 2. Confirmed decisions

| # | Decision | Chosen |
|---|---|---|
| D1 | Expanded/desktop behaviour | **Keep the two-pane split.** When the split is active, the tab row shows **NOW + People** only; the conversation lives permanently in the right pane with its drag handle. |
| D2 | ROOM tab label | **"Chat"** / «Чат» — new l10n keys. `ROOM` stays the internal surface name in code, constants, and technical docs. |
| D3 | Activity / Log surface | **Full-height adaptive sheet** (`showTenturaAdaptiveSheet`), consistent with the pinned-facts and status sheets. No new route. |
| D4 | Browser Back on web (new, §4.6) | **Browser Back leaves the request; it does not step through surfaces.** Only app-bar / Android Back do surface → NOW. |
| D5 | Room lifetime (new, §4.5) | **Owned by the screen, not by a surface.** One `ThreadHostCubit` lease shared by the tab and the split pane. |

### 2.1 Flagged concern — "Chat" vs. the terminology alias

`.cursor/rules/terminology.mdc` (alwaysApply) and `CONTEXT.md` § Terminology both fix the user-facing name of the coordination workspace as **discussion** / «обсуждение». Every other shipped string uses it (`beaconRoomWaitingForApproval`, `threadGeneralTitle`, push copy, `docs/features/beacon_room.md`). Introducing **Chat** only for the tab label makes the product say two different things about the same surface.

The enforced check (`request_terminology_contract_test.dart`, `scripts/check-user-facing-terminology.sh`) bans only *beacon* and *room*, so **"Chat" passes the gate** — the inconsistency is editorial, not mechanical.

Proceeding as instructed. **U11** amends `terminology.mdc` + `CONTEXT.md` to sanction **Chat** as the short tab-label form of the workspace noun, so the rule and the UI agree. Renaming the *other* "discussion" copy to "chat" is a separate product decision and is **out of scope** here.

---

## 3. Target UX

### 3.1 Compact / regular (phone, tablet, narrow desktop pane)

```
┌────────────────────────────────────────────┐
│ ←   Request title            STATUS     ⋮  │  app bar (unchanged chrome)
├────────────────────────────────────────────┤
│      NOW      │      CHAT     │    👥      │  tab row, pinned, below app bar
├────────────────────────────────────────────┤
│                                            │
│  selected surface fills the rest           │
│                                            │
└────────────────────────────────────────────┘
```

**NOW** (scrolls as one `CustomScrollView`):

```
  ↑ parent-reference link / lineage link      (unchanged slivers)
  ├ BeaconOperationalHeaderCard               (STATUS / NOW / YOU / ACT)
  └ Child requests                            ← moved here from Discussion
      ┌──────────────────────────────────┐
      │ Active                        +  │
      │  ▸ child request card            │  taps push BeaconViewRoute(id:)
      │  ▸ child request card            │
      │ Finished                         │
      └──────────────────────────────────┘
```

**CHAT** — `ThreadDetail` (General) filling the surface: closed-request banner, message list, composer. The app-bar title swaps to `ThreadDetailGeneralTitle` (request title + involved-people face pile), matching the chrome shipped today on `ThreadDetailScreen`.

> **Correction (review F7).** Rev 1 claimed the shipped General title already gives face-pile tap → People. It does not: `BeaconInvolvedPeopleFacePile` *does* expose an `onTap` parameter (`beacon_involved_people_face_pile.dart:16,23,61`), but `ThreadDetailGeneralTitle` never passes it and wraps the pile in `ExcludeSemantics` (`thread_detail.dart:188-205`). So the ItemCard affordance being deleted with `ThreadsList` (`onGeneralFacePileTap`) has **no** shipped equivalent. **U5 must add** an `onFacePileTap` parameter to `ThreadDetailGeneralTitle`, pass it through to the pile, and remove the `ExcludeSemantics` wrapper so the tap is reachable by assistive tech as well as pointer.

**PEOPLE** — `BeaconPeopleTabBody` verbatim, in its own scroll view.

### 3.2 Expanded with active split (D1)

```
┌──────────────────────────────────────────────────────────────┐
│ ←  Request title              │  General · 👥👥👥         ⋮  │
├───────────────────────────────┼──────────────────────────────┤
│     NOW      │      👥        │                              │
├───────────────────────────────┤     CHAT (persistent pane)   │
│ header / state / actions      │║                             │
│ child request cards           │║  ← drag handle              │
└───────────────────────────────┴──────────────────────────────┘
```

The tab row is scoped to the left (ops) pane so it aligns with the content it drives — the room pane is not a tab there. When the split is **not** active on an expanded window (admission blocked, or the route is hosted in a narrow parent pane), the three-tab row from §3.1 is used.

---

## 4. Architecture

### 4.1 Tab identity and split transitions

`features/beacon_view/ui/widget/beacon_view_constants.dart`

```dart
/// Logical surface ids for the request detail screen. Stable across window
/// classes — the visible tab set is a subset, never a re-index.
enum BeaconSurface { now, room, people }
```

Replaces `kBeaconTabThreads / kBeaconTabPeople / kBeaconTabLog / kBeaconTabCount / kBeaconTabIcons`. Selection is stored and compared as a `BeaconSurface`, never as a positional index, so hiding ROOM on the split cannot shift People's identity.

```dart
List<BeaconSurface> beaconVisibleSurfaces({required bool isSplit}) =>
    isSplit
        ? const [BeaconSurface.now, BeaconSurface.people]
        : const [BeaconSurface.now, BeaconSurface.room, BeaconSurface.people];
```

#### Split must be latched, not recomputed per build (review F6)

`beaconViewUsesExpandedThreadSplit` currently requires `threadsState.isSuccess && threads.isNotEmpty` (`beacon_view_screen.dart:341`). `ThreadsCubit.fetch()` defaults to `silent: false` and emits `StateIsLoading` first (`threads_cubit.dart:93-97`), and `_refreshThreadsTab()` calls the **non-silent** form — including from `onCoordinationSaved` (`beacon_view_screen.dart:676`). So *saving a coordination item on a desktop window transiently makes `isSplit` false*.

Under a naive "split changed → reselect surface" rule that would silently swap the user's surface and tear the chat down and back up, with no resize involved. Therefore:

```dart
/// Split is derived from durable inputs only. A refresh in flight is not a
/// reason to collapse a layout the user is already looking at.
bool isSplit = availableWidth >= minPaneWidth * 2 + handleWidth
    && windowClass == WindowClass.expanded
    && showBeaconContent
    && hadThreadRowsAtLeastOnce;   // latched, not `threadsState.isSuccess`
```

- `hadThreadRowsAtLeastOnce` latches on the first successful non-empty `ThreadsState` and resets only on beacon id change (the existing `didUpdateWidget` reset point).
- Surface reselection fires **only** on an actual `isSplit` edge:
  - non-split → split while ROOM selected → select `now` (the conversation is now the right pane, still visible).
  - split → non-split while the room pane was open → select `room`.
- Admission loss (`isRoomAdmissionBlocked` flipping true) does **not** reselect; the ROOM surface renders its placeholder in place. Admission is a body concern, never a navigation one.

This also replaces today's `scheduleWindowClassTransition` push/pop dance in both screens.

### 4.2 Design system — icon-only secondary tab

`design_system/components/tentura_underline_tabs.dart` gets one **additive** parameter; the two other call sites (`friends_screen`, `updates_screen`) are untouched.

```dart
/// Indices rendered at a fixed compact width, icon-only, outside the
/// equal-width distribution — for a secondary tab at the row's end.
final Set<int> compactIconTabs; // default: const {}
```

Layout changes inside `build` / `_buildTabCell`:

- compact-icon indices render in `SizedBox(width: tt.tabCompactWidth)`; the rest keep `Expanded` and therefore stay **equal width among themselves** (NOW and CHAT).
- `_labelsFit` computes the flexible slot as `(maxWidth - fixedTotal) / flexCount` instead of `maxWidth / n`.
- a compact-icon cell forces `iconOnly` regardless of the global `showLabels` decision; it already gets `Tooltip(message: label)` + `Semantics(label: label, button: true, selected: selected)` → **accessible label "People"** and normal selected-state behaviour come for free from the existing `_TabCell`.
- badges in a compact-icon cell render as an **overlay on the icon** (top-right), not as a trailing chip: primary (`tt.danger`, unanswered offers) wins; the secondary (`tt.warn`, needs-coordination) shows only when there is no primary. Deliberate information trade for the narrow cell — both counts remain fully enumerated inside the People body.
- the attention pulse (`attentionIndex` / `attentionActive`) is unchanged and works on the icon-only cell because it paints via the existing `Positioned.fill` layer.

**New token:** `tentura_tokens.dart` + `tentura_spacing.dart` gain `tabCompactWidth` — `56` compact, `64` regular/expanded.

**Minimum tap target — width is not the constraint (review F11).** The cell's current *height* is `2 × rowGap + iconSize + 6 + 2` = `2×8 + 20 + 6 + 2` = **44 dp** on compact (`tentura_underline_tabs.dart:290-330`, `TenturaSpacing.row`), and nothing enforces a floor. Widening the cell does not fix that. `_TabCell` therefore gains a `ConstrainedBox(minHeight: kMinInteractiveDimension)` around its `InkWell`, applied to **all** cells (labeled ones benefit equally). T1 asserts the measured hit rectangle, not the declared width.

Icons: `Icons.bolt_outlined` (NOW), `Icons.forum_outlined` (CHAT — the current Discussion icon), `Icons.people_outline` (PEOPLE, icon-only).

### 4.3 Tab row placement

The row is the **first child of the content column below the app bar**, not `TenturaTopBar.bottom`.

Rationale: `bottom:` spans the full app-bar width, which is wrong for the split (§3.2) where the row must align to the ops pane only; and it would need a second, divergent code path. As a plain `Column` child the row is pinned all the same, respects `TenturaContentColumn` width capping, and reuses the hairline the current sliver delegate already draws.

```dart
// non-split
TenturaContentColumn(
  child: Column(children: [BeaconSurfaceTabs(...), Expanded(child: surface)]),
)

// split
Row(children: [
  Expanded(child: TenturaContentColumn(
    child: Column(children: [BeaconSurfaceTabs(...), Expanded(child: nowOrPeople)]),
  )),
  TenturaVerticalResizeHandle(...),
  SizedBox(width: paneWidth, child: roomPane),
])
```

`SliverPersistentHeader` + `BeaconPinnedSegmentBarDelegate` are **deleted** — the row is no longer a sliver, so the fixed-48px `minExtent == maxExtent` workaround for web `NestedScrollView` geometry goes away with it.

### 4.4 Widget decomposition

`beacon_operational_scroll_view.dart` (462 lines, currently header + tab bar + all three bodies) splits into:

| New file | Contents |
|---|---|
| `ui/widget/beacon_surface_tabs.dart` | `BeaconSurfaceTabs` — wraps `TenturaUnderlineTabs`, maps `BeaconSurface` ↔ index, owns labels/icons/badges/test-ids/attention |
| `ui/widget/beacon_now_surface.dart` | `BeaconNowSurface` — `CustomScrollView`: parent-reference sliver, lineage sliver, `BeaconOperationalHeaderCard`, then `BeaconChildRequestsSection` + `_HierarchyBootstrap` **moved in from `ThreadsList`** |
| `ui/widget/beacon_room_surface.dart` | `BeaconRoomSurface` — admission placeholder, `ClosedRequestBanner`, `ThreadDetail(thread: general)` |
| `ui/widget/beacon_people_surface.dart` | thin scroll wrapper around the **unchanged** `BeaconPeopleTabBody` (keeps today's People-specific padding) |
| `ui/widget/beacon_room_lease.dart` | `BeaconRoomLease` — the room lifetime owner described in §4.5 |
| `ui/widget/beacon_activity_sheet.dart` | `showBeaconActivitySheet` (§4.7) |

`beacon_operational_scroll_view.dart` is deleted. All `_setTab` fan-out callbacks it currently threads (`onSwitchToPeopleTab`, `onOpenPeopleTab`, `onOpenItemsTab`, `onActivatePeopleAttention`, `onFocusCoordinationItem`) are re-pointed at `BeaconSurface` values; none of their behaviours change.

### 4.5 Room lifetime — a lease, not a surface side effect (review F1)

Rev 1 put `ensureGeneral` on surface entry and `clear()` on surface exit. Reading `ThreadHostCubit` makes that unsafe:

- `select()` and `clear()` both queue onto a shared `_switchTail` and guard on `selectionGeneration` (`thread_host_cubit.dart:55-101`).
- `ensureGeneral()` **returns immediately** when `state.openThreadId == generalId && _roomCubit != null` (`thread_host_cubit.dart:46-52`). Right after a `clear()` is queued but before its tail runs, both conditions still hold — so a fast CHAT → NOW → CHAT tab sequence returns early from `ensureGeneral` and then lets the queued `clear` close the room out from under the freshly-selected surface.
- `RoomCubit.close()` persists seen state, so that race is not cosmetic: it can write a watermark for a surface the user is still on, and leave CHAT showing an empty host.

**Design.** A single `BeaconRoomLease` owned by `BeaconViewScreen` (above both the tab body and the split pane) holds the room while **any** presentation needs it:

```dart
// refcount, not on/off
void acquire(Object holder);   // CHAT surface mounted, or split pane mounted
void release(Object holder);   // holder unmounted
// ensureGeneral() only when the count goes 0 → 1
// clear()        only when the count goes 1 → 0, and only after a
//                microtask settle, so tab-flip churn does not close the room
```

- the split ⇄ tab handover is a *reparent*, never a teardown: during the transition both holders are briefly registered, so the count never reaches 0.
- `release` schedules the drop through `Future.microtask`; a re-`acquire` before it runs cancels it. This is the fix for the fast-tab-flip race above.
- `ensureGeneral`'s early-return guard is additionally tightened to also require `!state.switching`, so a queued clear can no longer be mistaken for a live room.
- **read/seen semantics are therefore unchanged** — the room persists its watermark exactly once, when the last holder actually goes away, as today when the chat route pops.
- chat scroll position is not preserved across tab switches. Same as today.

When `state.isRoomAdmissionBlocked`, the ROOM tab **stays visible** and its body shows the existing `beaconRoomNoAdmission` / `beaconRoomWaitingForApproval` copy. Hiding the tab would leak admission state into navigation chrome; showing the message is what the Discussion tab does today.

### 4.6 Back / navigation state

`ThreadDetailRoute` is retired as a *pushed* surface. `ThreadDetailScreen` and its `_AdmissionPlaceholder` / `_LegacyThreadUnavailable` states fold into `BeaconRoomSurface`.

- `/beacon/view/:id/thread/:threadId` stays registered as a **redirect** to the operational route (precedence rules in §6.1).
- a legacy (non-`general`) thread id still renders the `beaconLegacyThreadUnavailable` message, now inside the ROOM surface.

#### App / Android Back

`PopScope` on the operational screen: Back on CHAT or PEOPLE selects NOW; Back on NOW leaves the request via the existing `_leaveBeaconView` fallback chain.

#### Browser Back — D4, explicit (review F2)

`PopScope` does not govern web history. Browser navigation enters `AutoRouterDelegate.setNewRoutePath()` and reconciles the page stack by removing pages **without** calling `maybePop()` (`routing_controller.dart:1313-1344`), so a `PopScope` handler is simply not consulted. And because tab changes use `replacePath`, there is no NOW history entry to go back *to*.

**Decision D4: browser Back leaves the request.** Surfaces are not history entries. This is deliberate — the alternative (pushing a history entry per tab tap) makes Back-out-of-request take three presses and is worse. T7 asserts this explicitly with real `history.back()` / `history.forward()` on the web target, not app-bar taps, and asserts that Back after a tab switch still reaches My Desk in one press (the `beacon_view_screen.dart:930` sentinel bug).

#### `?message=` canonicalizer (review F3)

Rev 1 said the guards were kept "verbatim". They cannot be: today they hand off to a route push, and the only staleness check after the await is `mounted` (`beacon_view_host_screen.dart:120-160`). Once the target is an in-place surface selection, that is not enough.

- resolution is tagged with a monotonic **intent generation**; the result is applied only if the generation is still current after each `await`. A slow resolve for message A can no longer override a newer message B, nor re-open CHAT after the user has navigated to another surface.
- `_resolvedForMessageId` is set **on success only**, so a failed resolve is retryable instead of permanently suppressed.
- the scroll target is handed to `roomCubit.prepareThreadScroll` only once the lease reports the room ready, not at resolve time.

### 4.7 Activity sheet (review F8)

`BeaconActivityList` is a plain `Column` (`activity_list.dart:116-136`) with no scrolling of its own; today its scroll comes from the enclosing `CustomScrollView` and its liveness from the enclosing `BlocBuilder<BeaconViewCubit>` (`beacon_operational_scroll_view.dart:123-160`). A sheet must supply both:

- `showBeaconActivitySheet` hosts the list inside a bounded scrollable (`ConstrainedBox` + `SingleChildScrollView`) so long histories scroll instead of overflowing;
- it takes the `BeaconViewCubit` explicitly and wraps the body in its own `BlocBuilder` (the sheet is pushed on a different `Navigator`, so it does not inherit the page's providers) — events and participant changes arriving while the sheet is open still update it.

`beaconViewAppBarOverflow(...)` gains `onActivityLog`; `BeaconOverflowMenu` gains a matching entry (`Icons.history_outlined`, `l10n.labelBeaconTabLog`) after `request_status`. Log-row taps close the sheet, then apply the **existing** focus behaviour from `_onTapCoordinationLogEvent` — ask/promise/blocker → ROOM at General; plan → ROOM scrolled to `sourceMessageId` + `coordinationItemId`; participant → PEOPLE with `focusUserId` flash.

`inRoomSurface: true` / `roomCubit:` on the overflow builder are currently a dead path (both call sites pass `false` / `null`), so create-poll / update-plan / create-promise are unreachable from the request detail overflow today. That is a **pre-existing** gap; this plan does not change it (follow-up, §11).

### 4.8 Other `ThreadDetailRoute` constructors (review F4)

Two files outside the ones rev 1 listed build and inspect the route, and both break at compile time when the pushed route goes away:

| File | Current | Change |
|---|---|---|
| `features/beacon_threads/ui/coordination_room_navigation.dart:55,57` | builds `ThreadDetailRoute(threadId: item.id)`; branches on `router.currentChild?.name == ThreadDetailRoute.name`; also selects through `ThreadHostCubit` from `ThreadsCubit` rows | replace the route hop with host-owned General selection + `prepareThreadScroll` anchor; replace the `currentChild` probe with "is ROOM currently presented" (tab selected **or** split pane mounted) |
| `features/beacon_threads/ui/widget/room_message_tile.dart:68,69` | same pattern for an in-message coordination link | same |

Both are message/coordination **anchor navigation**, not surface navigation — after this change they never leave the request.

---

## 5. Work units

Reordered from rev 1 so that each unit really does leave the tree compiling (review F12): a deletion never precedes the removal of its last caller.

| # | Unit | Files | Done when |
|---|---|---|---|
| **U1** | Design-system tab support | `tentura_underline_tabs.dart`, `tentura_tokens.dart`, `tentura_spacing.dart` | `compactIconTabs`, `tabCompactWidth`, `kMinInteractiveDimension` floor land; existing callers and all 9 tests in `tentura_underline_tabs_test.dart` unchanged and green |
| **U2** | Surface identity | `beacon_view_constants.dart` | `BeaconSurface` + `beaconVisibleSurfaces` added **alongside** the old constants; nothing deleted yet |
| **U3** | Room lease | new `beacon_room_lease.dart`, `thread_host_cubit.dart` | refcounted acquire/release, microtask-deferred clear, tightened `ensureGeneral` guard; T4 green |
| **U4** | Surface widgets | new `beacon_now_surface.dart`, `beacon_room_surface.dart`, `beacon_people_surface.dart`, `beacon_surface_tabs.dart` | all four build and are unit-testable; **not yet wired** into the screen |
| **U5** | Face-pile affordance | `thread_detail.dart` | `ThreadDetailGeneralTitle.onFacePileTap` added, `ExcludeSemantics` removed, pile `onTap` wired |
| **U6** | Screen recomposition | `beacon_view_screen.dart` | tab row below app bar; latched split (§4.1); `PopScope`; ROOM hidden iff split. **Now** `beacon_operational_scroll_view.dart`, `threads_list.dart`, `item_card.dart` lose their last callers and are deleted, and `labelBeaconTabDiscussion` loses its last reader |
| **U7** | l10n | `l10n/app_en.arb`, `l10n/app_ru.arb`, `flutter gen-l10n` | `labelBeaconTabNow` + `labelBeaconTabChat` added, `labelBeaconTabDiscussion` removed; terminology + key-parity tests green |
| **U8** | Activity sheet + overflow | new `beacon_activity_sheet.dart`, `beacon_view_app_bar_overflow.dart`, `beacon_overflow_menu.dart` | bounded scroll + own `BlocBuilder`; all four Log-row focus behaviours preserved |
| **U9** | Anchor navigation | `coordination_room_navigation.dart`, `room_message_tile.dart` | §4.8 table satisfied |
| **U10** | Routing + deep links | `root_router.dart`, `browse_deep_link.dart`, `beacon_view_host_screen.dart`, `consts.dart` + **`dart run build_runner build -d`** | §6 table and §6.1 precedence hold; `root_router.gr.dart` regenerated so the folded-away screen's generated imports disappear |
| **U11** | Docs, rules, version | see §9 + `packages/client/pubspec.yaml`, `packages/client/web/index.html` | `check-doc-drift.sh` clean; **client semver bump + web cache-buster** per `.cursor/rules/versioning.mdc` |
| **U12** | Tests | see §8 | Green |

`dart run build_runner build -d` is required after U10 (generated router) and after any DI change — rev 1 listed only `gen-l10n` (review F12).

---

## 6. Routing / deep-link contract

`kQueryBeaconViewTab` wire values are **not renamed** — `threads` keeps pointing at the conversation, so server-issued attention receipts (`destination_map.dart`) need no migration.

| URL | Result |
|---|---|
| `/beacon/view/:id` | NOW |
| `?tab=now` | NOW (new value) |
| `?tab=threads` | ROOM (split: room pane focused, NOW selected) |
| `?tab=threads&thread=general` | ROOM |
| `?tab=threads&message=<id>` | ROOM, scrolled to the message |
| `?tab=people` | PEOPLE |
| `?tab=people&people_tab_attention=1` | PEOPLE + attention pulse (unchanged) |
| `?tab=log` | NOW + Activity sheet opened post-frame (**legacy compat**) |
| unknown / absent `tab` | NOW |
| `/beacon/view/:id/thread/general` | redirect → `?tab=threads&thread=general` |
| `/beacon/view/:id/thread/<legacy>` | redirect → ROOM showing `beaconLegacyThreadUnavailable` |
| `?message=<id>` without `thread=` | canonicalized in-place to ROOM + scroll (§4.6) |

> **Correction (review F10).** Rev 1 wrote the attention parameter as `peopleAttention`. The shipped key is **`people_tab_attention`** (`consts.dart:101`). T8 asserts the literal wire key; no alias is introduced.

### 6.1 Redirect precedence (review F5)

"Redirect-only" was underspecified, and the two entry paths differ: cold deep links explicitly construct a thread child (`browse_deep_link.dart:45-80`), while warm notification navigation goes through path matching, where AutoRoute preserves incoming query parameters **over** redirect defaults. So `/thread/general?tab=people&thread=legacy` is genuinely ambiguous today.

One normalization function, used by **both** paths, with fixed precedence:

1. **path** `thread/:threadId` wins over query `thread=`;
2. a resolved thread id implies `tab=threads`, overriding any incoming `tab=`;
3. a non-`general` thread id resolves to ROOM + `beaconLegacyThreadUnavailable`, **even when** `message=` is present (the message cannot be shown in a thread that no longer exists);
4. `entry=` / `is_deep_link=` provenance parameters are always preserved;
5. anything left unrecognized falls through to NOW.

T8 covers conflicting path/query thread ids, preserved provenance, and a `message=` target that resolves to a legacy thread.

**Test ids** (`ui/test_ids.dart`): `beaconTabThreads` → `beaconTabRoom` (`'beacon.tab.room'`), add `beaconTabNow` (`'beacon.tab.now'`), keep `beaconTabPeople`, drop `beaconTabLog`, add `beaconOverflowActivity`.

---

## 7. l10n

| Key | en | ru | Action |
|---|---|---|---|
| `labelBeaconTabNow` | `Now` | `Сейчас` | add |
| `labelBeaconTabChat` | `Chat` | `Чат` | add |
| `labelBeaconTabPeople` | `People` | `Люди` | keep — now also the icon-only tooltip + a11y label |
| `labelBeaconTabLog` | `Log` | `Журнал` | keep — overflow item + sheet title |
| `labelBeaconTabDiscussion` | `Discussion` | `Обсуждение` | **remove** in U6/U7, after its last reader goes |

Both locales must stay key-identical (`request_terminology_contract_test.dart` asserts it). Regenerate with `cd packages/client && flutter gen-l10n`.

---

## 8. Tests

### Update

| Test | Change |
|---|---|
| `beacon_tab_reselect_folds_test.dart` | `BeaconSurface` + new widget names; reselect-remounts-folds must still hold for NOW and PEOPLE |
| `beacon_operational_scroll_view_pinned_facts_test.dart` | retarget to `BeaconNowSurface`; drops `tabIndex: kBeaconTabLog` |
| `request_threads_adaptive_test.dart` (~35 KB, 6 groups) | biggest edit. compact/regular groups assert an inline ROOM surface instead of a pushed route; `resize transitions` assert surface reselection; `Log adaptive` drives the sheet; `unread adaptive` asserts the badge on CHAT. Also mocks `currentChild` as `ThreadDetailRoute.name` (line 98) — retarget with §4.8 |
| `beacon_view_room_split_contract_test.dart` | keep both pure functions; add the latched-split rule (§4.1) and the visible-tab-set rule |
| **`promise_composer_live_wiring_test.dart:185`** | *missed in rev 1 (F9).* Hosts `ThreadsList` to reach the composer CTA — rehost on `BeaconNowSurface`. Adjudicate its CTA expectation on its own merits; do not silently rewrite it to match new behaviour |
| **`thread_detail_test.dart:253,332`** | *missed in rev 1 (F9).* Drives `ThreadDetailScreen` directly — port to `BeaconRoomSurface`, **keeping** the delayed-close coverage, which is exactly the §4.5 race |
| **`request_thread_routing_test.dart:59,84,100`** | *missed in rev 1 (F9).* Swaps `ThreadDetailRoute.page` — rework against the redirect + §6.1 precedence |
| **`nested_beacon_navigation_test.dart:59,84,99`** | *missed in rev 1 (F9).* Same `ThreadDetailRoute.page` pattern; asserts retained legacy thread pages |
| `threads_list_test.dart`, `item_card_golden_test.dart` (+4 goldens) | delete with their widgets in U6 |
| `beacon_hierarchy_view_test.dart` | host in `BeaconNowSurface` |
| `integration_test/request_threads_navigation_test.dart`, `support/e2e_test_helpers.dart` | new test ids; no `ThreadDetailRoute` push to await |
| `destination_map_test.dart` | assertions unchanged (wire values preserved) — proves the no-migration claim |

### Add

- **T1** `beacon_surface_tabs_test.dart` — NOW and CHAT equal width; PEOPLE fixed width, icon-only, at every window class; `Semantics(label: 'People', button: true, selected: …)` + tooltip; underline paints on the icon-only cell; **measured hit rectangle ≥ 48×48 dp** (§4.2).
- **T2** `tentura_underline_tabs_test.dart` (extend) — `compactIconTabs` leaves the two existing callers' layout unchanged; `_labelsFit` accounts for the fixed slot; badge overlay precedence.
- **T3** `beacon_surface_selection_test.dart` — split ⇄ non-split reselection both directions; **and that a non-silent `ThreadsCubit.fetch()` (e.g. `onCoordinationSaved`) while PEOPLE is selected on an expanded window changes neither the split nor the surface** (§4.1).
- **T4** `beacon_room_lease_test.dart` — refcount reparenting across split ⇄ tab never reaches 0; fast CHAT → NOW → CHAT does not close the room; watermark persisted exactly once, on last release; `ensureGeneral` does not early-return over a queued clear.
- **T5** `beacon_now_surface_test.dart` — child cards render below the header card and push `BeaconViewRoute(id:)`.
- **T6** `beacon_activity_sheet_test.dart` — long history scrolls inside the sheet; an event arriving while the sheet is open updates it; all four Log-row focus behaviours survive the close.
- **T7** back navigation — app/Android Back: CHAT/PEOPLE → NOW, NOW → leaves. **Web leg**: real `history.back()`/`forward()` honour D4, and Back after a tab switch reaches My Desk in one press.
- **T8** deep-link table (§6) + precedence rules (§6.1) as a parametrized routing test, including the literal `people_tab_attention` key.
- **T9** `?message=` canonicalizer — out-of-order resolution (slow A must not override newer B), failed resolve is retryable, message targeting an already-mounted General surface scrolls without remount.
- **T10** face-pile tap → PEOPLE by pointer **and** by semantic activation (§3.1).

### Gates

```bash
cd packages/client && flutter gen-l10n
cd packages/client && dart run build_runner build -d      # after U10
cd packages/client && flutter analyze --no-fatal-warnings --no-fatal-infos
bash scripts/check-custom-lints.sh          # client baseline: 115 — must not grow
cd packages/client && flutter test
bash scripts/check-user-facing-terminology.sh
bash scripts/check-doc-drift.sh
cd packages/client && dart run tool/verify_web_version_consistency.dart
./scripts/run_client_integration_web_local.sh    # T7 web leg + navigation e2e
```

Design-system lints that will bite this diff: `no_raw_edge_insets`, `no_raw_border_radius`, `no_inline_font_size`, `no_operational_raw_color`, `no_operational_raw_text_style`, `no_operational_pill_widgets_in_beacon_view`. Hence the `tabCompactWidth` token rather than an inline `56`.

---

## 9. Docs, rules, version

| File | Edit |
|---|---|
| `docs/Tentura_current_status_quo.md` | L125 `Discussion / People / Log` → `NOW / Chat / People`; L127 discussion paragraph; L204 summary line |
| `docs/features/beacon_room.md` | L40–46 tab table; L104–105 adaptive table (split keeps NOW+People); L108 URL contract (§6); L112 unread badge now on CHAT; L86 "from the parent's Discussion surface" → NOW |
| `docs/client-ui-inventory.md` | L5 note, L57–58, L294–312 tree, L368 multi-pane row, L395 width-adaptive shells |
| `docs/plans/request-threads-architecture.md` | surface names + the retired pushed thread route |
| `.cursor/rules/terminology.mdc` | sanction **Chat** as the tab-label form (§2.1) |
| `CONTEXT.md` | matching glossary line |
| `docs/tentura-design-system.md` | `compactIconTabs`, `tabCompactWidth`, the new min-interactive-height floor |
| `packages/client/pubspec.yaml` + `packages/client/web/index.html` | **mandatory** client semver bump (minor — user-visible navigation change) and matching `flutter_bootstrap.js?v=` cache-buster (`.cursor/rules/versioning.mdc:19-25`) |

`kDefaultMinClientVersion` in `packages/server/lib/env.dart` does **not** move: this is a client-only UI change with no wire-format break.

---

## 10. Risks

| Risk | Mitigation |
|---|---|
| Room closed under a live surface by a queued `clear` | Refcounted lease + microtask-deferred release (§4.5); T4 |
| Split collapsing on an ordinary threads refresh | Latched `hadThreadRowsAtLeastOnce` (§4.1); T3 |
| Web Back semantics differ from app Back | D4 stated, not discovered; T7 runs real `history.back()` on the web target |
| `request_threads_adaptive_test.dart` rewrite masks a real regression | Rewrite group-by-group against §6; keep the pure split predicates so the contract test still guards them |
| Redirect query precedence surprises | One normalization function shared by cold and warm paths (§6.1); T8 |
| Two badges do not fit an icon-only People tab | Documented precedence (§4.2); both counts remain visible in the People body |
| Deleting `ItemCard` removes the face-pile → People affordance | Explicitly rebuilt in U5, with semantics (§3.1) |

---

## 11. Out of scope

MR / admission / visibility semantics · server, GraphQL, migrations · renaming the rest of the "discussion" copy to "chat" · wiring the live `roomCubit` into the overflow to un-deaden create-poll / update-plan (§4.7) · child-request creation flow · People body internals.

---

## 12. Review record — rev 1 → rev 2

Reviewer: codex `gpt-6-astra`, high reasoning, read-only sandbox, whole-tree access. Every finding was re-verified against the code before acceptance.

| # | Severity | Finding | Disposition |
|---|---|---|---|
| F1 | major | `ensureGeneral`/`clear` on surface entry/exit races; `ensureGeneral` early-returns over a queued `clear`, which then closes the room and persists seen state | **Accepted** — §4.5 rewritten as a refcounted lease; T4 |
| F2 | major | `PopScope` does not govern browser history; `replacePath` leaves no NOW entry | **Accepted** — D4 + §4.6 now decide the behaviour instead of flagging it; T7 web leg |
| F3 | major | Canonicalizer guards cannot be "verbatim": only `mounted` is checked after await; failed resolve is permanently suppressed | **Accepted** — intent generation + success-only memo (§4.6); T9 |
| F4 | major | `coordination_room_navigation.dart` and `room_message_tile.dart` also construct `ThreadDetailRoute` | **Accepted** — verified at both call sites; new §4.8 + U9 |
| F5 | major | "Redirect-only" underspecified; AutoRoute prefers incoming query over redirect defaults | **Accepted** — §6.1 precedence policy; T8 |
| F6 | major | Split predicate keys off `threadsState.isSuccess`, which a non-silent `fetch()` clears — surfaces would swap on a coordination save | **Accepted** — latched split (§4.1); T3 |
| F7 | major | §3.1 wrongly claimed a shipped face-pile → People tap | **Accepted with corrected evidence.** The reviewer said `BeaconInvolvedPeopleFacePile` exposes no callback; it *does* (`:16,23,61`) — `ThreadDetailGeneralTitle` simply never passes it and wraps it in `ExcludeSemantics`. Fix is smaller than proposed: U5, T10 |
| F8 | major | `BeaconActivityList` is a bare `Column`; sheet must supply scrolling and its own cubit subscription | **Accepted** — §4.7; T6 |
| F9 | major | Four test consumers missed: `promise_composer_live_wiring_test`, `thread_detail_test`, `request_thread_routing_test`, `nested_beacon_navigation_test` | **Accepted** — all four verified and added to §8 |
| F10 | minor | Attention query key is `people_tab_attention`, not `peopleAttention` | **Accepted** — §6 corrected |
| F11 | minor | 56/64 dp width does not give a 48 dp target; cell height is 44 dp with no floor | **Accepted** — min-height in the design system, measured in T1 |
| F12 | minor | Unit order breaks the "compiles after each unit" promise; `build_runner` omitted | **Accepted** — §5 reordered, `build_runner` added to U10 and the gates |
| F13 | minor | Mandatory client version bump + web cache-buster omitted | **Accepted** — U11 + §9 |
