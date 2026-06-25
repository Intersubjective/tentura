# Tentura design system (Flutter client)

Operational, minimal, record-list UI for `packages/client`. Not a social feed, marketplace, or default Material “chunky” chrome.

## Source of truth in code

| Area | Location |
|------|----------|
| Theme + `ThemeExtension` | [`tentura_theme.dart`](../packages/client/lib/design_system/tentura_theme.dart), [`tentura_tokens.dart`](../packages/client/lib/design_system/tentura_tokens.dart) |
| Text styles | [`tentura_text.dart`](../packages/client/lib/design_system/tentura_text.dart) |
| Window breakpoints | [`tentura_window_class.dart`](../packages/client/lib/design_system/tentura_window_class.dart), [`tentura_responsive_scope.dart`](../packages/client/lib/design_system/tentura_responsive_scope.dart) |
| Components | [`packages/client/lib/design_system/components/`](../packages/client/lib/design_system/components/) |
| Barrel export | [`tentura_design_system.dart`](../packages/client/lib/design_system/tentura_design_system.dart) |
| App wiring | [`packages/client/lib/app/app.dart`](../packages/client/lib/app/app.dart) uses `TenturaTheme.light()` / `dark()` + `TenturaResponsiveScope` |
| Adaptive shell | [`home_screen.dart`](../packages/client/lib/features/home/ui/screen/home_screen.dart) — bottom nav vs `NavigationRail` |
| Orientation policy | [`orientation_policy.dart`](../packages/client/lib/app/platform/orientation_policy.dart) (native vs web) |
| PWA manifest | [`packages/client/web/manifest.json`](../packages/client/web/manifest.json) |
| Theme compatibility | [`packages/client/lib/ui/theme.dart`](../packages/client/lib/ui/theme.dart) — `createAppTheme` for tests/previews |

Access tokens: `import 'package:tentura/design_system/tentura_design_system.dart';` then `context.tt` ([`TenturaThemeX`](../packages/client/lib/design_system/tentura_tokens.dart)).

## Type scale (semantic)

Primary font: **Inter** (bundled assets). Use `TenturaText.*` helpers and `ThemeData.textTheme` roles — **never** inline `fontSize:` in `features/**` or `ui/**` (enforced by `no_inline_font_size` where enabled).

| Role                          | TenturaText / TextTheme                                                | Size | Weight | Line height           |
| ----------------------------- | ---------------------------------------------------------------------- | ---- | ------ | --------------------- |
| Card / beacon title           | `titleMedium`                                                          | 18   | 700    | 1.22                  |
| Large title                   | `titleLarge`                                                           | 20   | 700    | 1.22                  |
| Section / small title         | `titleSmall`                                                           | 15   | 600    | 1.25                  |
| Body                          | `bodyMedium`                                                           | 15   | 400    | 1.40                  |
| Body large                    | `bodyLarge`                                                            | 16   | 400    | 1.40                  |
| Metadata / status / secondary | `bodySmall`                                                            | 13   | 500    | 1.35                  |
| Primary actions / buttons     | `labelLarge`                                                           | 15   | 700    | 1.20                  |
| Chips / secondary labels      | `labelMedium`                                                          | 13   | 600    | 1.20                  |
| Bottom nav labels             | `TenturaText.navLabel` (`NavigationBarTheme` in app theme)             | 12.5 | 600    | 1.20                  |
| Type / offer labels           | `TenturaText.typeLabel` (Inter; letter-spaced, not a second font)         | 13   | 700    | 1.35 (letterSpacing 0.3) |
| Tab labels                    | `TenturaText.tabLabel` (`TenturaUnderlineTabs`)                        | 13   | 600    | 1.20                  |
| Command emphasis              | `TenturaText.command`                                                  | 15   | 700    | 1.20                  |

`command`, `typeLabel`, `tabLabel`, and `navLabel` are **TenturaText** helpers only (not separate `TextTheme` slots). All other rows map to both `TenturaText.*` and `ThemeData.textTheme` via `TenturaTheme.baseTextTheme` in `tentura_theme.dart`.

For **tabular numerals** (timers, counts): `TenturaText.withTabular(style)`.

## Breakpoints & WindowClass

Width drives layout density, **not** font size:


| WindowClass | Width (logical px) | Behavior |
|-------------|-------------------|----------|
| `compact` | &lt; 600 | Phone; smallest density tokens |
| `regular` | 600 ≤ *w* &lt; 840 | Tablet / narrow desktop; medium tokens (same class at width 839.5, etc.) |
| `expanded` | ≥ 840 | Wide desktop; largest density tokens, `contentMaxWidth` cap |


`TenturaResponsiveScope` selects `TenturaTokens` preset per class. **TextTheme sizes stay identical** across classes; only padding, gaps, icon sizes, avatar sizes, button heights, app bar / bottom nav heights, and max content width change.

On **regular** and **expanded**, tab and standalone route bodies use [`TenturaContentColumn`](../packages/client/lib/design_system/tentura_responsive_scope.dart) to center content at `contentMaxWidth` **560** / **720** logical px respectively. **Compact** has no cap (`TenturaContentColumn` is a no-op). [`TenturaResponsiveScope`](../packages/client/lib/design_system/tentura_responsive_scope.dart) at the app root applies token density only — it does **not** cap layout width globally (avoids clipping the nav rail or graph canvas).

### Full-bleed routes

Some surfaces must use the **full viewport width**, not the centered column:

| Surface | Route / widget |
|---------|----------------|
| Graph canvas | [`graph_screen.dart`](../packages/client/lib/features/graph/ui/screen/graph_screen.dart), [`forwards_graph_screen.dart`](../packages/client/lib/features/graph/ui/screen/forwards_graph_screen.dart) |
| Beacon room (chat) | [`BeaconRoomSurface`](../packages/client/lib/features/beacon_view/ui/widget/beacon_room_surface.dart) — not wrapped when operational detail uses `TenturaContentColumn |

[`TenturaFullBleed`](../packages/client/lib/design_system/tentura_responsive_scope.dart) remains available for graph routes; it is currently a pass-through when the app root is already full width.

**Content-column routes (regular / expanded):** home tab bodies ([`home_screen.dart`](../packages/client/lib/features/home/ui/screen/home_screen.dart)), beacon operational detail, forward beacon picker ([`forward_beacon_screen.dart`](../packages/client/lib/features/forward/ui/screen/forward_beacon_screen.dart)), credentials ([`credentials_screen.dart`](../packages/client/lib/features/credentials/ui/screen/credentials_screen.dart)).

## Adaptive layout rules

Drive layout from **logical width** (or parent `constraints.maxWidth`), not device type or orientation.

| Do | Don’t |
|----|--------|
| `LayoutBuilder` + `windowClassForWidth(constraints.maxWidth)` | `OrientationBuilder`, `MediaQuery.orientationOf` for shell/layout |
| `context.windowClass` / `context.tt` for density | `isTablet` / `isPhone` / `Platform.is*` for layout branching |
| `Expanded` / `Flexible` / `CustomScrollView` for lists and rows | `ListView(shrinkWrap: true)` inside unbounded `Column` without `Expanded` |
| `ListView.builder` / `GridView.builder` for dynamic lists | Spread `...items.map(...)` into static `ListView` children |

When a widget sits inside a sliver or grid, prefer **`windowClassForWidth(constraints.crossAxisExtent)`** (or the relevant constraint axis), not viewport `MediaQuery` width — the parent may be narrower than the window.

### Home shell (main tabs)

[`HomeScreen`](../packages/client/lib/features/home/ui/screen/home_screen.dart) switches navigation chrome at the same **600** px breakpoint as `WindowClass.regular`:

| WindowClass | Navigation |
|-------------|------------|
| `compact` | Bottom [`NavigationBar`](https://api.flutter.dev/flutter/material/NavigationBar-class.html) |
| `regular` | [`NavigationRail`](https://api.flutter.dev/flutter/material/NavigationRail-class.html) (labels below icons) |
| `expanded` | `NavigationRail` with `extended: true` (labels beside icons) |

Implementation uses `AutoTabsRouter` (not `AutoTabsScaffold`) so one tab router drives both layouts. Tab reselect behavior and [`HomeBottomNavListener`](../packages/client/lib/features/home/ui/widget/home_bottom_nav_listener.dart) wrap nav in both modes. Tab content is wrapped in [`TenturaContentColumn`](../packages/client/lib/design_system/tentura_responsive_scope.dart) (no-op on `compact`).

### Expanded-window flows (≥ 600 px)

These flows keep a **single-pane / bottom-sheet** UX on compact and add a wider layout on regular/expanded:

| Flow | Compact | Regular / expanded |
|------|---------|-------------------|
| Forward recipient search | Single column + inline notes | Master–detail split ([`forward_search_overlay.dart`](../packages/client/lib/features/forward/ui/widget/forward_search_overlay.dart)) |
| Connect | `showModalBottomSheet` | Centered `Dialog` ([`connect_bottom_sheet.dart`](../packages/client/lib/features/connect/ui/widget/connect_bottom_sheet.dart)) |
| Beacon create images | `ReorderableListView` | 2- / 3-column grid ([`image_tab.dart`](../packages/client/lib/features/beacon_create/ui/widget/image_tab.dart)) |
| Beacon definition media | Fixed-height band | Taller band + max-width centering ([`beacon_definition_body.dart`](../packages/client/lib/features/beacon_view/ui/widget/beacon_definition_body.dart)) |
| Graph | Full bleed + pan/zoom | Optional side rail controls ([`graph_body.dart`](../packages/client/lib/features/graph/ui/widget/graph_body.dart)) |

## Orientation policy

Product goal: **phones stay portrait** when rotated; **tablets and desktop** may use landscape (matches adaptive shell and Android large-screen guidance).

Policy is **split by platform** — do not use `device_info_plus` or user-agent parsing for orientation on web.

### Native app (Android / iOS)

[`orientation_policy_native.dart`](../packages/client/lib/app/platform/orientation_policy_native.dart):

- Applied at startup in `App.runner()` and re-applied on [`didChangeMetrics`](../packages/client/lib/app/platform/lifecycle_handler_native.dart) (foldables / window resize).
- **Lock portrait** when logical **shortest side** &lt; **600** (`kPortraitLockMaxLogicalShortestSide`) — same threshold as `WindowClass.compact`, but uses **shortest side** so a phone held landscape (wide width, short height) stays locked.
- **Unlock all orientations** when shortest side ≥ 600 (tablets).
- **Desktop** (`linux` / `windows` / `macos` native): no lock.

**iOS plist backup:** iPhone [`UISupportedInterfaceOrientations`](../packages/client/ios/Runner/Info.plist) lists **portrait only**; iPad (`~ipad`) keeps all orientations.

**Android:** no `android:screenOrientation` on `MainActivity` — tablet rotation is controlled in Dart only.

Unit tests: [`test/app/orientation_policy_test.dart`](../packages/client/test/app/orientation_policy_test.dart).

### Web / PWA

[`orientation_policy_web.dart`](../packages/client/lib/app/platform/orientation_policy_web.dart) is a **no-op** — Flutter web does not reliably enforce orientation via `SystemChrome`.

| Surface | Mechanism |
|---------|-----------|
| **Installed PWA** (`display: standalone`) | [`manifest.json`](../packages/client/web/manifest.json) → `"orientation": "portrait-primary"` |
| **Mobile browser tab** (not installed) | Browser controls rotation; responsive layout must tolerate landscape |
| **Desktop web** | No orientation lock; `WindowClass` + rail layout apply |

After changing `manifest.json` orientation, users may need to **re-install** the PWA to pick up the new manifest.

## Hard floors

- **Metadata / secondary readable text:** minimum **13** logical px (`bodySmall`).
- **Body:** minimum **15** (`bodyMedium` / `body`).
- **Action labels:** minimum **15** (`labelLarge`).
- **Bottom nav labels:** **12.5** is the **only** allowed exception below 13.
- **Banned** in `packages/client/lib/features/**` and `packages/client/lib/ui/**`: literal font sizes **8, 10, 11, 12** (use semantic roles instead).

Do **not** scale the whole UI proportionally from screen width (no `fontSize: 14 * (width / 390)`).

**Compact width:** reflow actions (e.g. second row for tertiary) and use ellipsis on tabs — do **not** visually shrink tab or action text with `FittedBox` / proportional font hacks.

## Beacon detail — type hierarchy

On **Beacon view** (`features/beacon_view`), tabs are **Items**, **People**, **Log**. Keep a clear ladder:

| Element | Role |
|--------|------|
| App bar title ([`BeaconViewScreen`](../packages/client/lib/features/beacon_view/ui/screen/beacon_view_screen.dart)) | `titleLarge` (20 / 700) |
| Beacon title (header) | `titleMedium` (18 / 700) — pass `titleStyle` into [`BeaconCardHeaderRow`](../packages/client/lib/ui/widget/beacon_card_primitives.dart) from the detail screen only; **list cards** keep default `titleSmall`. |
| Operational header ([`BeaconOperationalHeaderCard`](../packages/client/lib/features/beacon_view/ui/widget/beacon_operational_header_card.dart)) — STATUS / NOW / YOU / ACT | STATUS & NOW: `TenturaText.status` (13); YOU segment: `bodySmall`; ACT buttons: `labelLarge` (15 / 700) |
| Items tab foldable section titles | `titleSmall` (15 / 600) |
| Items tab coordination **collapsed** summary (accent line under section title) | `TenturaText.status` (13 / 500) |
| Items tab coordination **expanded** diagnosis title | `TenturaText.typeLabel` (13 / 700) |
| Items tab prose (need excerpt, pinned facts, coordination copy) | `bodyMedium` (15 / 400) |
| Metadata (counts, timestamps) | `bodySmall` / `TenturaText.status` (13) |
| People tab display name | `titleSmall` — below beacon title, above body message |
| Log tab section headers | `titleSmall` — same weight as other section titles |
| Primary / secondary Material buttons (incl. [`CardTriageActionRow`](../packages/client/lib/ui/widget/card_triage_action_row.dart), beacon detail CTAs) | `labelLarge` (15 / 700) via `theme.textTheme.labelLarge` |

## Forward Beacon picker — type hierarchy

On **Forward Beacon** (`features/forward` — `ForwardBeaconPage`, `ForwardRecipientRow`, `ForwardScopeLinks`, `ForwardBottomComposer`), keep a compact list hierarchy; do not compete with `titleMedium` on every row.

| Element | Role |
|--------|------|
| Screen title (top bar) | `TenturaText.title` / `titleMedium` (18 / 700) — same as other modal-style titles |
| Subtitle (beacon title · lifecycle) | `bodySmall` muted |
| Context strip (author · context · dates) | `bodySmall` + `metadataAvatarSize` / token gaps from `context.tt` |
| Scope tabs (best / unseen / involved) | `TenturaText.tabLabel` (13) for label; `bodySmall` or tabular `bodySmall` for `/count`; **ellipsis** when tight — **no `FittedBox` scale-down** |
| Recipient display name | `titleSmall` (15 / 600), not `title` — use `SelfUserHighlight.nameStyle` with `TenturaText.titleSmall` as base |
| Presence + involvement line | `bodySmall` for presence; `TenturaStatusText` + `TenturaTone` for forward-path status (plain text, not chips) |
| Personalized note action (add/hide) | **Icon only** (`add_comment_outlined` / `expand_less`), **immediately left of** the row checkbox, with the same strings as **tooltip** when the row is selected |
| Per-recipient + shared note fields | Same tokenized `InputDecoration` (surface, border, `TenturaRadii.cardDense`, `TenturaText.body` for input) |
| Primary Forward CTA | `TenturaText.command` / `OutlinedButton` with height ≥ `context.tt.buttonHeight` |
| List row avatars + checkbox hit targets | Avatar size from `context.tt` (`avatarSize` = medium bucket); checkbox visual stays small but wrap in at least **44×44** logical px tap target |

## No global text scaler override

Do **not** wrap the app in `MediaQuery.copyWith(textScaler: TextScaler.noScaling)`. Let Flutter apply system / accessibility text scaling. Design dense cards so they remain usable at **text scale ~1.3** (wrap rows, allow soft wrap, reduce padding via tokens if needed — never shrink semantic type below floors).

## Principles

1. **Information first** — quiet surfaces; no ornamental gradients, heavy shadows, or badge clouds.
2. **Statuses = plain colored text** — semantic color on **`bodySmall`**-scale type (see [`TenturaText.status`](../packages/client/lib/design_system/tentura_text.dart)); no `Chip` / pill backgrounds for state on operational surfaces.
3. **Flat record cards** — white surface, 1px border, radius from tokens, padding/gap from `context.tt`, shadow minimal or off.
4. **Hairlines** — use [`TenturaHairlineDivider`](../packages/client/lib/design_system/components/tentura_hairline_divider.dart), not nested cards.
5. **Tabs** — underline row with 2px active indicator ([`TenturaUnderlineTabs`](../packages/client/lib/design_system/components/tentura_underline_tabs.dart)), not `SegmentedButton` on beacon detail. Labels stay at **13px** logical size; use **ellipsis** when width is tight, not scaled-down paint size. Vertical padding follows **`context.tt.rowGap`** (density), not a fixed px hack.
6. **Actions** — [`TenturaTextAction`](../packages/client/lib/design_system/components/tentura_text_action.dart) / [`TenturaCommandButton`](../packages/client/lib/design_system/components/tentura_command_button.dart); avoid filled buttons inside dense cards unless truly primary.
7. **Avatars** — unified [`TenturaAvatar`](../packages/client/lib/design_system/components/tentura_avatar.dart) with four buckets via `TenturaAvatarSize`: **big** (160, profile hero), **medium** (`avatarSize`, list rows / people tab), **small** (`metadataAvatarSize`, facepiles / coordination footer), **tiny** (`avatarTinySize`, inline log/timeline). Optional flags: `showAuthorStar` (beacon author), `isSelf` (viewer halo), `withRating` / `withContactBadge` (MeritRank; honored at big/medium/small only). Personal/identity surfaces default to plain avatars (`withRating: false`). Viewer identity is resolved only in [`SelfAwareAvatar`](../packages/client/lib/ui/widget/self_aware_profile_avatar.dart) (never in the DS widget). Facepiles use [`OverlappingPeopleAvatars`](../packages/client/lib/ui/widget/overlapping_people_avatars.dart) with `selfUserId` + `starredProfileId`.
8. **A11y** — min tap targets (e.g. button height from tokens); respect system text scaling.

## Token summary (light)


| Token                                                              | Role               |
| ------------------------------------------------------------------ | ------------------ |
| `bg`                                                               | `#F8FAFC` scaffold |
| `surface`                                                          | `#FFFFFF` cards    |
| `border` / `borderSubtle`                                          | hairlines          |
| `text` / `textMuted` / `textFaint`                                 | hierarchy          |
| `info` (sky) / `good` (emerald) / `warn` (amber) / `danger` (rose) | semantics          |


## Components (use these)

- `TenturaTechCard` / `TenturaTechCardStatic`
- `TenturaStatusText`, `TenturaMetaText`, `TenturaTypeLabel`
- `TenturaTextAction`, `TenturaCommandButton`
- `TenturaUnderlineTabs`, `TenturaAvatar`, `TenturaHairlineDivider`

## Do / don’t (operational areas)


| Do                                               | Don’t                                                                                                                      |
| ------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------- |
| `context.tt` + `TenturaText` / `theme.textTheme` | `Color(0x…)`, `Colors.*` (except e.g. `Colors.transparent` where needed) in `beacon_view`, `my_work`, `inbox` feature code |
| `TenturaTechCard` for record rows                | Ad-hoc `TextStyle(fontSize: …)` in those folders                                                                           |
| Plain text status                                | `Chip` / `SegmentedButton` in `beacon_view` `widget/` + `screen/`                                                          |
| `context.tt` gaps/padding (`rowGap`, `cardGap`, `tightGap`, …) + `tt.cardRadius` / `TenturaRadii.*` | `EdgeInsets.only(top: 6)` / `BorderRadius.circular(12)` and other raw-number insets/radii in **all** `features/**` and `ui/**` |


Custom lint: `no_operational_raw_color`, `no_operational_raw_text_style`, `no_operational_pill_widgets_in_beacon_view` in [`packages/tentura_lints`](../packages/tentura_lints); plus `no_inline_font_size`, `no_raw_edge_insets`, and `no_raw_border_radius` for `features/**` and `ui/**` (design-system files and the package `test/` tree are exempt). If a spacing/radius token is missing, add it to `tentura_spacing.dart` + `tentura_tokens.dart` (or `tentura_radii.dart`) first — e.g. `tightGap` (2px hairline nudge between stacked metadata lines). The `material-3-flutter` agent skill summarizes this workflow.

## Web viewport

`packages/client/web/index.html` must use `width=device-width, initial-scale=1.0`, `viewport-fit=cover`. Do **not** set `maximum-scale=1` or `user-scalable=no` (hurts accessibility and zoom).

**PWA:** `manifest.json` sets `"display": "standalone"` and `"orientation": "portrait-primary"` for installed mobile apps. See [Orientation policy](#orientation-policy) above.

If the design doc and code disagree, update the doc after confirming product intent.