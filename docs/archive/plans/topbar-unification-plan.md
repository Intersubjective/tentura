---
status: done
kind: plan
---
# Top App Bar Unification — Mobile + Wide Adaptive Desktop

> **Execution note:** Before writing any code, read `.claude/skills/material-3-flutter/SKILL.md` and `docs/tentura-design-system.md` — all styling must go through the design system.

## Context

The Flutter client (`packages/client`) shows a top app bar on almost every screen, but there are **four unrelated implementations** that visibly disagree, especially on wide/desktop layouts (audit: `docs/client-ui-inventory.md`, "Top App Bar Audit"):

| Family | Height | Tone | Used by |
|---|---|---|---|
| `InboxStyleAppBar` / `SliverInboxStyleAppBar` (`lib/ui/widget/inbox_style_app_bar.dart`) | **hard-coded 48** | primary fill | MyWork, Friends, Profile tabs |
| Raw `AppBar` with `tt.appBarHeight` | **56/60** (token) | primary fill | Inbox tab |
| Raw `AppBar` / `SliverAppBar`, per-screen ad-hoc colors | 56 (`kToolbarHeight`) or theme default | surface (or `surfaceContainer` in InboxRejected) | BeaconView, ProfileView, Settings, Rating, ~20 more |
| `ForwardTopBar` (`lib/features/forward/ui/widget/forward_top_bar.dart`) | intrinsic Row, not an `AppBar` | surface | ForwardBeaconScreen |

On desktop the mismatch compounds: MyWork/Friends/Profile wrap their whole `Scaffold` in `TenturaContentColumn`, so their 48dp primary bars render as narrow centered "islands", while Inbox on expanded runs a 60dp primary bar across the full pane. Switching tabs makes the header jump in height, width, and content position. There is **no `appBarTheme` in `TenturaTheme`** (`lib/design_system/tentura_theme.dart`), so every screen re-specifies colors.

**Decisions made with the user:**
1. **Full-pane bar surface, content-aligned bar internals** (see model below).
2. **Height = `tt.appBarHeight`** (56 compact / 60 regular+). The hard-coded 48 and `kToolbarHeight` go away. Home-tab bars get slightly taller — acceptable (project rule: snap to token, MD3 conformance > frozen pixels).
3. **Full sweep**: all screens including `ForwardTopBar` and simple form screens migrate. Immersive overlays (galleries, map, QR) are the only raw-`AppBar` exceptions.

Tone policy (unchanged, now made official): **primary-filled bar on the 4 home-tab roots; surface bar on every pushed/standalone screen**. Immersive galleries keep their black bars.

---

## The alignment model (M3 grounding — read before coding)

Material 3 large-screen guidance: the top app bar belongs to its **pane** and its *background* spans the pane, but its *content* must sit on the same keylines/margins as the pane's body content. Stretching a title to the far-left and actions to the far-right of a 1400px pane (with a dead gap between) is an M3 anti-pattern; so is shrinking the whole bar into a centered island. References: M3 top app bar spec, M3 canonical layouts (list-detail / supporting pane), Flutter "Adaptive and responsive design" + "Large screen devices" docs.

Concretely for Tentura, the bar has **three alignment modes**:

1. **`content`** (default): the bar's content block — `[leading] [title] [actions]` row — occupies exactly the horizontal bounds of the body's content column (`tt.screenHPadding` edge padding + `TenturaContentColumn` centering at `tt.contentMaxWidth`). The screen title's left edge lines up with the body column's left edge; the last action aligns to the column's right edge. On **compact**, `contentMaxWidth` is null, so this degrades to a normal full-width bar with `screenHPadding` margins — phones are effectively unchanged.
2. **`fullWidth`**: content block spans the pane minus `tt.screenHPadding` margins. For full-bleed bodies (graph canvases, rating scatter) where there is no content column to align to.
3. **`custom` (multi-pane)**: for split-pane bodies (Inbox expanded master/detail, BeaconView expanded split), the screen composes the bar content as a Row whose segments reuse the **same pane-geometry helper as the body**, so bar segments sit exactly over their panes (title/tabs over the master/left pane, pane-specific actions over the detail/right pane). This generalizes to any future N-column layout: one shared geometry function per screen, consumed by both body and bar.

**Icon keyline compensation (subtle, do not skip):** an `IconButton`'s tap box has ~11-12dp of internal padding around the glyph. If the leftmost/rightmost element of the content block is an icon button and you pad the row by `screenHPadding`, the *glyph* lands ~12dp deeper than body text — visibly misaligned. The primitive therefore compensates edge padding for icon-led/icon-trailed rows:

```dart
double _iconEdgeCompensation(TenturaTokens tt) => (tt.buttonHeight - tt.iconSize) / 2;
// left inset  = leadingIsIcon  ? screenHPadding - comp : screenHPadding
// right inset = trailingIsIcon ? screenHPadding - comp : screenHPadding
// clamp both to >= 0
```

On compact this yields ~4-5dp for icon-led bars — matching both the current look and M3's 4dp icon-container edge margin. Text-led bars (tab roots) get the full `screenHPadding`, putting the title text exactly on the body column keyline.

---

## Phase 1 — Design-system primitive

### 1a. New file `lib/design_system/components/tentura_top_bar.dart`

```dart
enum TenturaTopBarTone { primary, surface }
enum TenturaTopBarAlignment { content, fullWidth }

class TenturaTopBar extends StatelessWidget implements PreferredSizeWidget {
  factory TenturaTopBar.of(
    BuildContext context, {
    required Widget title,
    TenturaTopBarTone tone = TenturaTopBarTone.surface,
    TenturaTopBarAlignment alignment = TenturaTopBarAlignment.content,
    Widget? leading,
    List<Widget>? actions,
    PreferredSizeWidget? bottom,   // e.g. a TabBar; gets the same alignment wrapper
    Widget? progress,              // 4dp loading strip; full pane width; space ALWAYS reserved when non-null
    bool centerTitle = false,
    bool? leadingIsIcon,           // default: leading != null
    bool? trailingIsIcon,          // default: actions?.isNotEmpty ?? false
    Widget? row,                   // ESCAPE HATCH for multi-pane: fully custom content row;
                                   // when set, leading/title/actions/centerTitle must be null/unused
    Key? key,
  })
  // captures tt.appBarHeight, tt.screenHPadding, tt.iconTextGap, and the icon
  // compensation into final fields, then calls the private const constructor.
}
```

Build output — an `AppBar` used only as the *chrome shell* (background, status-bar inset, system overlay style):

```dart
AppBar(
  backgroundColor: tone == primary ? scheme.primary : scheme.surface,
  foregroundColor: tone == primary ? scheme.onPrimary : scheme.onSurface,
  iconTheme: IconThemeData(color: fg),
  surfaceTintColor: Colors.transparent,
  elevation: 0,
  scrolledUnderElevation: 0,
  toolbarHeight: toolbarHeight,          // captured tt.appBarHeight
  automaticallyImplyLeading: false,
  leading: null,                          // ALWAYS — content lives in the title slot
  titleSpacing: 0,
  title: _alignedRow(...),
  bottom: /* PreferredSize wrapping Column [ _aligned(bottom)?, progress? ] */,
)
```

`_alignedRow` = the alignment wrapper (per the model above: `TenturaContentColumn`-style centering via `Align` + `ConstrainedBox(maxWidth: contentMaxWidth)` when alignment == content, plus the compensated edge `Padding`) around either the caller's `row` (escape hatch) or:

```dart
NavigationToolbar(
  middleSpacing: iconTextGap,            // captured tt.iconTextGap
  centerMiddle: centerTitle,
  leading: leading,
  middle: title,
  trailing: actions == null ? null : Row(mainAxisSize: MainAxisSize.min, children: actions),
)
```

`NavigationToolbar` is the exact layout primitive `AppBar` uses internally — it gives correct true-centering for `centerTitle` and proper middle overflow, so do not hand-roll the three-slot row.

Also add:

```dart
/// Loading strip with tone-correct colors. MUST match the bar's [tone].
static Widget loadingBar(BuildContext context, bool isLoading,
    {TenturaTopBarTone tone = TenturaTopBarTone.surface}) { ... }
```

primary tone → `LinearPiActive.builder(context, isLoading, color: onPrimary.withValues(alpha: .85), backgroundColor: onPrimary.withValues(alpha: .15))` (pattern copied from `friends_screen.dart:202-208`); surface tone → plain `LinearPiActive.builder(context, isLoading)`.

**Subtle caveats — read carefully:**

- **`preferredSize` has no `BuildContext`.** That is why the factory `.of(context, …)` captures token values into final fields at construction. `preferredSize = toolbarHeight + (bottom?.preferredSize.height ?? 0) + (progress != null ? LinearPiActive.height : 0)`. Do **not** hardcode 56/60 and do not touch `MediaQuery` in the getter. On window resize the screen rebuilds and constructs a fresh bar — no extra listening needed.
- **Everything lives in the `title` slot** so it can be aligned as one block; `AppBar.leading`/`actions` slots are never used (they pin to pane edges, which is exactly what we're removing). Consequence: `AppBar` wraps its title slot in a `DefaultTextStyle` of `titleLarge` — bare `Text` widgets in former `actions` would inherit it. `TextButton`/`IconButton`/`PopupMenuButton` carry their own styles (fine); if a migrated bar has a bare `Text` action, wrap it in an explicit `TenturaText.*` style.
- **`automaticallyImplyLeading: false` always.** Tab roots must never grow a back arrow (comment in `inbox_screen.dart:174-175`: nested routes otherwise reserve leading width). Pushed screens must pass `leading:` **explicitly** (Phase 3 recipe).
- **Progress strip is always 4dp when the slot is used** — `LinearPiActive.builder` returns `SizedBox(height: 4)` when idle (`lib/ui/widget/linear_pi_active.dart`), so the bar height never jumps when loading starts. Progress spans the full pane (it is chrome, not content); `bottom` (TabBars) gets the alignment wrapper (tabs are content).
- The alignment wrapper uses plain `Padding`, while bodies use `SafeArea(minimum: EdgeInsets.symmetric(horizontal: tt.screenHPadding))`. These coincide everywhere except landscape-notch edge insets (AppBar already applies horizontal safe insets to its title slot) — accepted, do not add a second SafeArea.
- `Colors.transparent` and the `withValues(alpha:)` tints are fine here: design-system files are exempt from the raw-color lints.
- Export from the barrel `lib/design_system/tentura_design_system.dart` (follow `tentura_underline_tabs.dart`).

### 1b. New file `lib/design_system/components/tentura_primary_tab_bar.dart`

Extract the **on-primary TabBar styling** duplicated in `inbox_screen.dart:495-513` (`_InboxTabStrip`) and `friends_screen.dart:149-178`:

`TenturaPrimaryTabBar` (`implements PreferredSizeWidget`): params `tabs`, `controller`, `isScrollable = true`, `labelPadding`. Style: `labelColor: onPrimary`, `unselectedLabelColor: onPrimary.withValues(alpha: .72)`, `indicatorColor: onPrimary`, `indicatorSize: TabBarIndicatorSize.label`, `tabAlignment: TabAlignment.start`, `automaticIndicatorColorAdjustment: false`, labels `labelLarge` w600/w500. **Divergence to resolve:** inbox uses `dividerColor: scheme.primary`, friends uses `primary.withValues(alpha: 0)` — unify to `Colors.transparent` (identical rendering on a primary bar). Keep `labelPadding` per call site (`tt.rowGap` inbox, `tt.tightGap` friends) via the param.

### 1c. `appBarTheme` in `TenturaTheme` (`lib/design_system/tentura_theme.dart`)

Add to both light and dark: `backgroundColor: surface, foregroundColor: onSurface, surfaceTintColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0, centerTitle: false`. This normalizes the few raw `AppBar`s that intentionally remain (immersive overlays override their colors anyway).

**Caveat:** do **not** put `toolbarHeight`/`titleSpacing` into `AppBarTheme` — they are window-class dependent and `ThemeData` is static (`TenturaResponsiveScope` only swaps the `TenturaTokens` extension). Height lives exclusively in `TenturaTopBar`.

### 1d. Golden/widget tests (required by the design-system skill)

`test/design_system/tentura_top_bar_golden_test.dart`, pattern of `test/features/inbox/inbox_item_tile_golden_test.dart`:
- both tones × {plain title, leading+title+actions, with TabBar bottom, with progress} at compact and expanded widths;
- **an alignment golden**: bar above a body column (`SafeArea(minimum: screenHPadding)` + `TenturaContentColumn` with a bordered box) at 1280px — the title's left edge must sit on the column's left border, last action's glyph on the right border.

---

## Phase 2 — Home tabs (the visible fix)

Target for all four tabs: `Scaffold(appBar: TenturaTopBar.of(context, tone: primary, …))` — bar surface spans the pane, bar content and body share the content column.

**Structural rule:** `TenturaContentColumn` wraps the Scaffold **body content only** — never the `Scaffold` itself. (It is a no-op on compact: `contentMaxWidth` null, see `tentura_responsive_scope.dart:44-56` — phones unaffected by these moves.)

### 2a. MyWork — `lib/features/my_work/ui/screen/my_work_screen.dart`

- Currently **double-wrapped**: outer `TenturaContentColumn` at line 53 around the whole Scaffold *and* an inner one at line 84. **Remove the outer (line 53), keep the inner.**
- Replace `InboxStyleAppBar(...)` (line 64) with `TenturaTopBar.of(context, tone: primary, title: <same Row of filter menu + sort>, actions: <same>)`. Default `content` alignment — filter menu now aligns with the list column. No loading strip today; don't add one.

### 2b. Inbox — `lib/features/inbox/ui/screen/inbox_screen.dart`

- **Delete the outer conditional wrap at lines 220-226** (`windowClass == expanded ? screen : TenturaContentColumn(screen)`) — return `screen` unconditionally. The inner `TenturaContentColumn(child: body)` at line 211 already caps the list on non-expanded; `_InboxExpandedBody` stays.
- Extract the master-pane width calc from `_InboxExpandedBody` (lines 251-253) into a shared helper, e.g. `double inboxMasterPaneWidth(double maxWidth, TenturaTokens tt) => (tt.contentMaxWidth ?? maxWidth / 2).clamp(420.0, 560.0).toDouble();` — used by **both** the body and the bar row.
- Replace the raw `AppBar` (line 164):
  - **Non-expanded:** `TenturaTopBar.of(context, tone: primary, title: <same Row: _InboxTabStrip + _InboxSortButton>, actions: <notifications + overflow>)` — default `content` alignment.
  - **Expanded (multi-pane):** same call but with the `row:` escape hatch: `LayoutBuilder → Row[ SizedBox(width: inboxMasterPaneWidth(...), child: Row[tabs strip, sort]), Expanded(Align(right: Row[notifications, overflow])) ]`, wrapped in the same horizontal padding the body pane row gets — tabs sit exactly over the master list, notifications/overflow over the detail pane's right edge. (Choose per `context.windowClass == WindowClass.expanded`, mirroring the body's `useExpandedPane` flag — use the *same* flag variable.)
  - Old `surfaceTintColor: scheme.primary` → primitive's `Colors.transparent`: visually identical at elevation 0, intentional. Height already `tt.appBarHeight` — unchanged.
- Convert `_InboxTabStrip`'s hand-styled `TabBar` to `TenturaPrimaryTabBar` (keep its `BlocSelector`/needs-count logic).

### 2c. Friends — `lib/features/friends/ui/screen/friends_screen.dart`

- Remove the outer `TenturaContentColumn` (line 139); wrap the body content below the bar instead (match MyWork: `SafeArea(minimum: horizontal screenHPadding) → TenturaContentColumn → TabBarView…`).
- Replace `InboxStyleAppBar` (line 144) with `TenturaTopBar.of(context, tone: primary, ...)`:
  - `title:` the existing `BlocSelector` now returning `TenturaPrimaryTabBar` (tabs align to the list column left edge; actions to its right edge).
  - `actions:` unchanged.
  - The `bottom: PreferredSize(...)` loader (lines 193-209) becomes the **`progress:` slot**: keep the `BlocSelector<InvitationCubit, InvitationState, bool>`, its builder returns `TenturaTopBar.loadingBar(context, isLoading, tone: primary)`.

### 2d. Profile — de-sliver

A *pinned* small `SliverAppBar` with no flexible space behaves exactly like a fixed `Scaffold.appBar`, so convert:

- `lib/features/profile/ui/widget/profile_app_bar.dart`: turn `ProfileAppBar` into a builder function `PreferredSizeWidget buildProfileAppBar(BuildContext context, {required Profile profile})` returning `TenturaTopBar.of(context, tone: primary, title: <existing avatar+name Row>, actions: <existing>, key: Key('ProfileAppBar:${profile.id}'))`. (A wrapping `StatelessWidget` can't implement `PreferredSizeWidget` without a context-free height — same constraint as 1a.)
- `lib/features/profile/ui/screen/profile_screen.dart`: remove the outer `TenturaContentColumn` (line 17); restructure to `Scaffold(appBar: buildProfileAppBar(...), body: SafeArea(min horizontal screenHPadding) → TenturaContentColumn → RefreshIndicator.adaptive → CustomScrollView(slivers: [<the two SliverPaddings only>]))`. Keep the `BlocSelector` outermost so both bar and body see `profile`. The avatar+name block now aligns with the profile body column.
- Delete `SliverInboxStyleAppBar` (verify no other users: `rg -n "SliverInboxStyleAppBar" lib test`).

**Caveat:** pull-to-refresh must still work on mobile after the bar leaves the scroll view — test it.

---

## Phase 3 — Detail / standalone screens (mechanical recipe)

For each file below, replace `appBar: AppBar(...)` with `appBar: TenturaTopBar.of(context, tone: TenturaTopBarTone.surface, ...)`:

1. **Leading:** if the old bar had an explicit `leading`, keep it verbatim. If it had **no explicit leading but showed a back arrow** (Flutter's implicit leading), you MUST add `leading: const AutoLeadingButton()`, because the primitive disables implication. Screens using `AutoLeadingWithFallback` keep that exact widget and fallback path (web deep-link refresh).
2. **Loading `bottom`:** the recurring `bottom: PreferredSize(... LinearPiActive.builder ...)` pattern becomes `progress: <same BlocSelector, builder returns TenturaTopBar.loadingBar(context, isLoading)>`.
3. **TabBar `bottom`** (BeaconCreate): pass through as `bottom:` — it gets the content-alignment wrapper so tabs align with the form column.
4. Drop per-screen `backgroundColor/surfaceTintColor/elevation/scrolledUnderElevation/foregroundColor/iconTheme/toolbarHeight/titleTextStyle/titleSpacing` — the primitive owns them. Any other old property (e.g. `leadingWidth`) → check whether it still matters under the new title-slot layout (usually it doesn't; `NavigationToolbar` sizes leading intrinsically).
5. Keep `centerTitle: true` where present (auth screens, BeaconCreate) — pass it through.
6. Alignment: default `content` unless the row below says `fullWidth`.

| File | Notes / caveats |
|---|---|
| `features/beacon_view/ui/screen/beacon_view_screen.dart:1072` | **Highest-risk.** Preserve the `leading:` logic and its long comment verbatim (plain `BackButton` fall-through → `PopScope` → `_exitRoomSurface`; wiring `onPressed` directly hung compact — do NOT "simplify"). Non-split: default `content` alignment (operational body is already `TenturaContentColumn`-capped — line 847). **Split mode (`isSplit`):** use the `row:` escape hatch mirroring `_buildExpandedSplitBody` (lines 895-914): `LayoutBuilder → Row[ Expanded(<content-aligned block: leading + BeaconViewAppBarTitle>), SizedBox(width: beaconViewRoomSplitPaneWidth(tt, availableWidth: constraints.maxWidth), child: Align(right: overflow)) ]` — reuse the **existing** `beaconViewRoomSplitPaneWidth` helper so title sits over the operational pane and the overflow over the room pane. Room toggle button already hidden in split (line 1105-1113 condition). Drop the `titleTextStyle` override (M3 default is `titleLarge`). Legacy room surface at regular width: `content` alignment is a slight mismatch vs the full-width chat — accepted, note in code comment. |
| `features/profile_view/ui/widget/profile_view_app_bar.dart` + `.../screen/profile_view_screen.dart` | De-sliver like 2d but **surface tone**: `Scaffold(appBar: buildProfileViewAppBar(context), body: TenturaContentColumn(RefreshIndicator(CustomScrollView(...))))`. Put Bloc-awareness *inside* the slots: `title:` = `BlocBuilder` → `ProfileAppBarTitle`; `progress:` = `BlocSelector` on `isLoading` → `loadingBar`. The `PopupMenuButton.itemBuilder` runs lazily on open — read `context.read<ProfileViewCubit>().state` **inside** `itemBuilder` instead of a captured `state`. Drop the trailing `Padding(right: kSpacingSmall)` action — edge alignment is now the primitive's job. |
| `features/inbox/ui/screen/inbox_rejected_screen.dart:44` | Currently `surfaceContainer` background — unify to surface tone (intentional small visual change). |
| `features/rating/ui/screen/rating_screen.dart:134` | Use **`fullWidth` alignment in both modes** (scatter is full-bleed; keeping one alignment avoids the bar content jumping when toggling list/scatter). Its `bottom:` currently reserves a full `tt.appBarHeight` of mostly-empty space (lines 180-196) — replace with the `progress:` slot (`loadingBar(context, state.isLoading && state.items.isNotEmpty)`). Removes the odd blank strip; verify both views (body now starts right under the bar). |
| `features/beacon_create/ui/screen/beacon_create_screen.dart:80` | Keep `centerTitle: true`, `TabBar` bottom, `leading: const AutoLeadingButton()`. Already `tt.appBarHeight`. The save/draft `TextButton` actions keep their own padding — drop the `screenHPadding` padding around them (edge alignment is the primitive's job; set `trailingIsIcon: false` since the edge action is a text button). |
| `features/beacon/ui/screen/beacon_screen.dart:96`, `involved_beacon_screen.dart:73` | Recipe as-is. |
| `features/coordination_item/ui/screen/item_discussion_screen.dart:92, 208, 249` | **Three** bars incl. the bare hydration-fallback at 249 — migrate all three so height/alignment don't jump during hydration. |
| `features/evaluation/ui/screen/review_contributions_screen.dart:85` | Recipe as-is. |
| `features/graph/ui/screen/graph_screen.dart:44`, `forwards_graph_screen.dart:63` | `fullWidth` alignment (full-bleed canvas). If a bar turns out to be transparent-over-canvas, leave it raw and add to the lint allowlist instead. |
| `features/invite_genealogy/ui/screen/invite_genealogy_screen.dart:51` | Recipe as-is. |
| `features/notification_center/ui/screen/notification_center_screen.dart:32`, `notification_settings_screen.dart:31` | Recipe as-is (:31 is a one-liner `AppBar(title:)` — implicit leading, add `AutoLeadingButton`). |
| `features/settings/ui/screen/settings_screen.dart:52`, `debug_settings_screen.dart:32`, `credentials_screen.dart:79` | Recipe as-is. |
| `features/profile_edit/ui/screen/profile_edit_screen.dart:67` | Save action stays in `actions:`. |
| `features/complaint/ui/screen/complaint_screen.dart:111` | Recipe as-is. |
| `features/auth/ui/screen/auth_login_screen.dart:31`, `auth_register_screen.dart:107`, `recover_screen.dart:141` | Keep centered titles (`centerTitle: true`). Login has **no leading on purpose** (unauthenticated root). |
| `features/beacon_create/ui/screen/beacon_icon_picker_screen.dart:226` | Fullscreen dialog: keep close/clear/done actions; surface tone. |

**Explicitly left raw (immersive/overlay exceptions):** `ui/widget/beacon_gallery_viewer.dart` (2 bars), `ui/widget/tentura_fullscreen_image_viewer.dart` (2), `features/beacon_room/ui/widget/room_attachment_widgets.dart:344`, `features/geo/ui/dialog/choose_location_dialog.dart:150` (transparent over map), `ui/dialog/qr_scan_dialog.dart:44`. They override colors explicitly, so the new `appBarTheme` doesn't affect them.

---

## Phase 4 — ForwardBeaconScreen

Replace `ForwardTopBar` (`features/forward/ui/screen/forward_beacon_screen.dart:341`) with the primitive:

- The bar currently sits **inside a body `Column`** under `AbsorbPointer(absorbing: actionLoading)` — that must keep covering the bar. Keep the bar in the Column (an `AppBar` renders fine outside `Scaffold.appBar`; `preferredSize` is only consulted by `Scaffold`) and just swap `ForwardTopBar` → `TenturaTopBar.of(context, tone: surface, ...)`. Keep the `TenturaHairlineDivider` below it.
- Mapping: `leading:` = the close `IconButton` with the existing `canPop ? maybePop : navigate(closeFallbackRoute)` logic **copied verbatim** (web-refresh fallback matters); `title:` = the existing two-line title/subtitle `Column`; `actions:` = search / filter `IconButton`s. `content` alignment — the bar aligns with the recipient list column.
- Keep the `forwardBeaconSubtitle(...)` helper (move it beside the screen), then delete the `ForwardTopBar` class.
- **Caveat:** `forward_search_overlay.dart` may position itself relative to the old bar's intrinsic height in the Stack — check for hardcoded offsets and retest opening/closing search.

---

## Phase 5 — Lint guard + cleanup

1. Delete `lib/ui/widget/inbox_style_app_bar.dart` once `rg -n "InboxStyleAppBar" lib test` is empty.
2. New lint `use_tentura_top_bar` in `packages/tentura_lints`: flag `AppBar(`/`SliverAppBar(` constructor calls under `features/**` and `ui/**`, allowlisting the immersive/overlay files above (+ graph screens if left raw). Follow an existing rule (e.g. `no_raw_edge_insets`) incl. rule tests. **Caveat (project-known):** custom rules don't fire under CLI `flutter analyze` here — verify via `cd packages/tentura_lints && dart test` (the CI gate).
3. Docs: add a "Top app bar" section to `docs/tentura-design-system.md` (tones, height token, alignment model + icon keyline compensation, progress slot, leading rules, multi-pane `row:` pattern, exceptions); refresh the "Top App Bar Audit" in `docs/client-ui-inventory.md`.

---

## Verification

1. `cd packages/client && flutter analyze --no-fatal-warnings --no-fatal-infos` — no new violations.
2. `cd packages/client && flutter test` — expect golden diffs from height/alignment changes; regenerate **only** the ones whose PNG diff is the expected change (`flutter test --update-goldens <path>`), eyeball each; investigate anything else.
3. `cd packages/tentura_lints && dart test` (Phase 5 lint).
4. **Run the app and resize** (web: `flutter run -d chrome`, or the Playwright/Obscura runbook):
   - ~1280px: all 4 home tabs — same bar height (60), same primary fill spanning the pane; **title/filter/tabs left edge flush with the body column's left edge; last action flush with its right edge** (screenshot and overlay a vertical guide if unsure). No jump between tabs.
   - Inbox expanded: tab strip sits exactly over the master list; notifications/overflow over the detail pane edge.
   - BeaconView expanded split: title over the operational pane; overflow over the room pane.
   - ~700px (regular): bars 60 tall, content aligned to the 560 column.
   - ~390px (compact): bars 56, full width, title inset ≈ `screenHPadding`, icon-led bars' back glyph ≈ 4-5dp box edge (compensation working); bottom nav still hides on pushed details (unchanged shell logic).
   - Push BeaconView from MyWork; back from room surface (compact) and browser back on web — exercises the preserved `PopScope` wiring.
   - Profile + ProfileView: pull-to-refresh, overflow menus.
   - Forward screen: close button, search overlay open/close.
5. Loading strips: refresh Friends/Settings — 4dp strip animates full-pane width, bar height doesn't jump.
