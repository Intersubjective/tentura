# Desktop & Adaptive Readiness Report

Audit date: 2026-06-30. Scope: full `packages/client` — all `@RoutePage` screens, `lib/ui/**` shared widgets, beacon/room chat, design-system responsive primitives.

**Related:** prior fix log in [`responsive-design-audit.md`](responsive-design-audit.md) (2026-06-27).

**Overall verdict:** **Partial** — desktop-usable, not desktop-polished. Solid responsive infrastructure with inconsistent application. Primary failure mode: intentional full-bleed surfaces (room chat, graph canvas) plus inconsistent dialog width caps and no wide-screen multi-column lists.

---

## Executive summary

| Dimension | Assessment |
|-----------|------------|
| Foundation (`WindowClass`, tokens, `TenturaContentColumn`) | **Strong** |
| Home shell & navigation | **Ready** (rail at ≥600px, extended at ≥840px) |
| Standalone form/list routes | **Mostly ready** (~20+ use `TenturaContentColumn`) |
| Beacon room / chat | **Partial** — text bubbles capped; shell/composer/polls/media stretch |
| Feature dialogs | **Partial** — many raw `AlertDialog`s without `maxWidth` |
| Shared `ui/` dialogs | **Mostly ready** — share/seed/confirm capped; QR on desktop web gaps |
| Wide-screen lists | **Low** — single column to 720px; no `maxCrossAxisExtent` grids |

---

## Global strategy today

The app uses **opt-in width caps**, not a root-level constraint.

1. **`TenturaResponsiveScope`** (`design_system/tentura_responsive_scope.dart`) at app root updates token density and `contentMaxWidth` from `WindowClass`. It **does not** constrain layout width (avoids clipping `NavigationRail` and graph canvases).

2. **Per-route opt-in** — screens wrap bodies in `TenturaContentColumn` (`Align` + `ConstrainedBox(maxWidth: contentMaxWidth)`). Exceptions: graph canvases, room chat, maps, rating scatter, expanded Inbox master–detail.

3. **Navigation adaptation** — `NavigationBar` (compact) ↔ `NavigationRail` (≥600px); extended rail labels at ≥840px (`home_screen.dart`).

4. **Modal adaptation** — `showTenturaAdaptiveSheet`: bottom sheet on compact, centered capped dialog on regular+.

5. **Component-level reflow** — shared widgets use `LayoutBuilder` / `windowClass` for internal reflow without global caps.

**Product decision:** `responsive-design-audit.md` defers room chat as intentional full-bleed (like graph canvas). This report evaluates against desktop-web best practices regardless.

---

## Breakpoints & tokens (canonical)

| Constant | Value | Source |
|----------|------:|--------|
| Compact | `< 600px` | `tentura_window_class.dart` |
| Regular | `600–839px` | same |
| Expanded | `≥ 840px` | same |
| `contentMaxWidth` regular | **560** | `tentura_tokens.dart` |
| `contentMaxWidth` expanded | **720** | same |
| Dialog fallback | **560** | `tentura_confirm_dialog.dart`, share/seed/qr dialogs |
| Narrow modal targets | **480** | `connect_bottom_sheet.dart`, `my_work_empty_body.dart` |
| Overlay / empty-state cap | **360** | `mention_suggestions_overlay.dart`, `my_work_empty_body.dart` |
| Inbox master pane | **420–560** | `inbox_screen.dart` |
| Forward search sidebar | **320–420** (40% width) | `forward_search_overlay.dart` |
| Room text bubble caps | **520 / 640** | `room_message_tile.dart` |

**Not used:** `ResponsiveBuilder`, `breakpoint`, `largeScreen` third-party APIs. Grids use `SliverLayoutBuilder` + fixed cross-axis count (`beacon_icon_picker_screen.dart`), not `SliverGridDelegateWithMaxCrossAxisExtent`.

---

## Pattern inventory

| Pattern | ~Files | Notes |
|---------|-------:|-------|
| `TenturaContentColumn` | 20+ screens | Canonical fix for forms/lists |
| `windowClass` / `contentMaxWidth` | 29+ | Token-driven density |
| `LayoutBuilder` | 21 | Inbox, room tiles, forward overlay, graph body |
| `ConstrainedBox` / `maxWidth` | 20–32 | Dialogs, inbox split, HUD widgets |
| `showTenturaAdaptiveSheet` | ~45 | Sheet → dialog on regular+ |
| `TenturaFullBleed` | 3 screens | Graph routes (intentional) |
| `kIsWeb` | 19 | Capability branching, not layout class |
| `SliverGridDelegateWithMaxCrossAxisExtent` | **0** | — |

### Screens with zero responsive-pattern matches (4)

| Screen | Reason |
|--------|--------|
| `accept_invite_screen.dart` | Spinner shell only |
| `profile_screen.dart` | Home tab — inherits shell cap |
| `beacon_room_screen.dart` | Redirect stub |
| `beacon_legacy_path_screen.dart` | Redirect stub |

---

## Navigation structure

| Layer | Path | Role |
|-------|------|------|
| App root | `app/app.dart` | `TenturaResponsiveScope` (tokens only) |
| Router | `app/router/root_router.dart` | `RouteType.adaptive()` |
| Home shell | `features/home/ui/screen/home_screen.dart` | Tabs + rail/bar; `TenturaContentColumn` on tab bodies (except expanded Inbox) |
| Stack routes | `features/**` | Each screen opts into column cap individually |
| Drawers | — | None |

| Context | Pattern | Trigger |
|---------|---------|---------|
| Main tabs | `NavigationRail` vs `NavigationBar` | `windowClass != compact` |
| Extended rail | `NavigationRail(extended: true)` | `WindowClass.expanded` |
| Inbox | Master–detail split | `WindowClass.expanded` |
| Forward search | List + detail split | `windowClass != compact` |
| Graph | Side controls panel | `windowClass != compact` |

---

## Screen readiness matrix

### Ready

| Screen / area | Path / notes |
|---------------|--------------|
| Home shell | `home_screen.dart` |
| Inbox (+ rejected archive) | `inbox_screen.dart` — strongest adaptive pattern |
| My Work | `my_work_screen.dart` |
| Auth (login, register, recover) | `features/auth/**` |
| Intro | `intro_screen.dart` |
| Settings, notifications | `settings_screen.dart`, `notification_*` |
| Profile view / edit | `profile_view_screen.dart`, `profile_edit_screen.dart` |
| Credentials | `credentials_screen.dart` |
| Beacon list / create / icon picker | `beacon_screen.dart`, `beacon_create/**`, `beacon_icon_picker_screen.dart` |
| Forward beacon | `forward_beacon_screen.dart`, `forward_search_overlay.dart` |
| Trust / forwards / invite genealogy graphs | `TenturaFullBleed` — intentional |
| Rating scatter | Full viewport by design |
| Complaint, review contributions | `TenturaContentColumn` |
| Connect sheet | `showTenturaAdaptiveSheet(maxWidth: 480)` |
| Geo location picker | Fullscreen map — correct |

### Partial

| Screen / area | Issue | Severity |
|---------------|-------|----------|
| Friends | No local `TenturaContentColumn`; relies on home shell | Medium |
| Profile (Me tab) | Same as Friends | Medium |
| Beacon view (operational) | Room surface full-bleed; operational tabs capped | Medium |
| Beacon view (room mode) | No column cap vs operational tabs | Medium |
| Rating (list mode) | Single column; fixed header flex | Low |
| Accept invite | Spinner shell; invitation dialog uncapped | Medium |
| Feature dialogs (~15+) | Raw `AlertDialog` without `maxWidth` | Medium |
| QR scan (desktop web) | Fullscreen camera vs native paste UI | Medium |

### Not ready

| Screen / area | Issue | Severity |
|---------------|-------|----------|
| Item discussion | Embeds `BeaconRoomBody` full width — no column cap | **High** |
| Room poll cards | Stretch with parent bubble on ultrawide | **High** |

---

## Beacon / room chat (detailed)

**Overall:** **Partial** — mobile/compact strong; desktop stretched except text bubbles.

### Good patterns

- Text bubble width capping — `room_message_tile.dart` + `room_message_trailing_meta_layout.dart` + `room_message_bubble_measure.dart` (75% fraction, 520/640px caps, hug-width for short messages).
- WindowClass-aware media height — `room_attachment_widgets.dart` (180/220/280px).
- Adaptive sheets — `showTenturaAdaptiveSheet` for poll, promote, edit, fact actions.
- Mention overlay — 360px cap + `LayoutBuilder` (`mention_suggestions_overlay.dart`).
- Composer compact behavior — attach hidden when typing on compact.
- Safe areas — composer `SafeArea`; sheet keyboard insets.
- Touch targets — lifecycle footer `minHeight: 44`.
- Centered chrome — date pills, system timeline bars, jump FAB in stack.

### Stretching issues (systematic list)

| Widget | Path | Issue | Severity |
|--------|------|-------|----------|
| Chat shell | `ui/widget/basic_chat_body.dart` | List + composer span full viewport; no `ConstrainedBox` | **High** |
| Composer | `basic_chat_body.dart` (`BeaconRoomComposer`) | `Expanded` TextField full width | **High** |
| Room body | `beacon_room/ui/widget/beacon_room_body.dart` | Delegates to full-bleed `BasicChatBody` | **High** |
| Room surface | `beacon_view/ui/widget/beacon_room_surface.dart` | Pass-through, no wrapper | Medium |
| Beacon view (room branch) | `beacon_view_screen.dart` | Operational tabs use `TenturaContentColumn`; room does not | Medium |
| Item discussion | `coordination_item/.../item_discussion_screen.dart` | Header, banner, chat all unconstrained | Medium |
| Message tile (poll/media) | `room_message_tile.dart` | `shouldHugBubbleWidth` false for media/poll → full row width | **High** |
| Poll card | `room_poll_card.dart` | Card stretches with bubble | **High** |
| Inline image album | `room_attachment_widgets.dart` | `width: double.infinity` | Medium |
| Pinned-now strip | `beacon_room_body.dart` (`_PinnedNowRow`) | Full-width card | Medium |
| Message actions | `beacon_room_body.dart` | Raw `showModalBottomSheet` on desktop | Medium |
| Unread divider | `room_unread_divider.dart` | Long divider lines on wide screens | Low |
| Reaction senders sheet | `reaction_senders_sheet.dart` | `DraggableScrollableSheet` in dialog on desktop | Low |

### Ready (room-adjacent)

`room_message_text_body.dart`, `room_date_separator.dart`, `mention_suggestions_overlay.dart`, `fact_actions_sheet.dart`, promote/edit sheets, `beacon_view_room_app_bar_button.dart`, `coordination_room_navigation.dart`.

---

## Shared UI (`lib/ui/**`)

### Dialogs

| Dialog | Status | Notes |
|--------|--------|-------|
| `share_code_dialog.dart` | Ready | `maxWidth: tt.contentMaxWidth ?? 560` |
| `show_seed_dialog.dart` | Ready | Same pattern |
| `qr_scan_dialog.dart` | Partial | Native desktop: capped paste UI; **web: fullscreen camera** |
| `tentura_confirm_dialog.dart` | Ready | App-wide benefit |
| `show_anchored_popup_menu.dart` | Partial | No max-width on long menu labels |

### Responsive-aware widgets (ready)

`screen_load_error_panel.dart`, `card_triage_action_row.dart`, `beacon_hud_metadata_table.dart`, `beacon_compact_metadata_strip.dart`, `beacon_card_primitives.dart`, `accordion_expansion.dart`, `hud_labeled_multiline.dart`, `hud_multiline_body.dart`, `beacon_pinned_facts_strip.dart`, `qr_code.dart`, `beacon_gallery_viewer.dart` (intentional fullscreen).

### Stretch-to-parent (partial — depend on screen wrapper)

`beacon_image_gallery.dart`, `beacon_image.dart`, `coordination_item_card_chrome.dart`, `coordination_log_row_chrome.dart`, `beacon_identity_tile.dart`, `beacon_requirements_bar.dart`, `basic_chat_body.dart`, `inbox_style_app_bar.dart` (hardcoded 48px vs token 60px on regular+).

### Web / platform gaps

- Desktop browser is `kIsWeb` with `isDesktopPlatform => false` — QR and geo use web paths, not native desktop paths.
- No `kIsWeb && windowClass != compact` branch for paste-first QR on wide web viewports.

---

## Anti-patterns & literal width divergence

### `width: double.infinity` on content surfaces

| File | Context |
|------|---------|
| `beacon_operational_scroll_view.dart` | Tab bands inside capped beacon shell |
| `beacon_people_tab_body.dart` | People tab action row |
| `beacon_create/.../info_tab.dart` | Publish CTAs |
| `my_work_cards.dart` | Card chrome |
| `forward_scope_links.dart` | Link row |
| `room_attachment_widgets.dart` | Attachment preview (full-bleed chat) |

### Row + Expanded without max constraint

| File | Notes |
|------|-------|
| `basic_chat_body.dart` + `beacon_room_body.dart` | Chat list + composer — intentional full-bleed per prior audit |
| `inbox_screen.dart` | Split-pane — intentional; detail pane can still stretch very wide |
| `beacon_card_primitives.dart` | HUD rows — partial `LayoutBuilder` mitigation |

### Non-token width literals

`connect_bottom_sheet.dart` (480), `my_work_empty_body.dart` (360/480), `mention_suggestions_overlay.dart` (360), `beacon_compact_metadata_strip.dart` (360/160), `friends_screen.dart` (320 fallback), `forward_search_overlay.dart` (320–420), `inbox_screen.dart` (420–560), `qr_scan_dialog.dart` (600/800/1200 height breakpoints).

---

## Feature trees with no responsive patterns

| Feature | Path | Notes |
|---------|------|-------|
| Invitation | `features/invitation/` | Dialogs only; no width-class logic |
| Geo | `features/geo/` | Fullscreen map — correct |
| Capability | `features/capability/` | Embedded chips; no layout adaptation |

---

## Priority fix order

| Priority | Item | Action |
|----------|------|--------|
| **1 — High** | Chat column shell | `Center` → `ConstrainedBox(maxWidth: 720–840)` around list + composer + FAB in `basic_chat_body.dart` |
| **2 — High** | Poll/media caps | Apply bubble readable caps in `room_message_tile.dart` / `room_poll_card.dart` / inline albums |
| **3 — Medium** | Item discussion + beacon room surface | Same chat column; wrap `ItemDiscussionScreen` and room branch of `beacon_view_screen.dart` |
| **4 — Medium** | Feature dialogs | Route through `TenturaConfirmDialog` or add `maxWidth: tt.contentMaxWidth` |
| **5 — Medium** | Friends / Profile tabs | Local `TenturaContentColumn` for standalone reuse |
| **6 — Medium** | Message actions sheet | Migrate to `showTenturaAdaptiveSheet` in `beacon_room_body.dart` |
| **7 — Medium** | QR on desktop web | Branch on `windowClass != compact` for paste UI in `qr_scan_dialog.dart` |
| **8 — Low** | Wide-screen grids | `SliverGridDelegateWithMaxCrossAxisExtent` or icon-picker pattern on My Work / Friends / beacon list |
| **9 — Low** | Popup menus, app bar height, padding token migration | `show_anchored_popup_menu.dart`, `inbox_style_app_bar.dart`, evaluation sheets |

---

## Comparison with prior audit (2026-06-27)

| Metric | Prior | This report |
|--------|------:|------------:|
| `@RoutePage` screens | 30 | 31 |
| Screens/widgets fixed with `TenturaContentColumn` | 24 | 20+ maintained |
| Deferred groups documented | 12 | Room/chat, dialogs, HUD, invitation — still open |
| Primary new finding | Systematic missing column on pushed routes | **Chat stack** is largest remaining desktop gap; infrastructure is complete |

---

## Recommended standard for new work

1. Use `WindowClass` only — compact `<600`, regular `600–839`, expanded `≥840`. Do not introduce parallel breakpoint APIs.
2. Standalone form/list routes: wrap body in `TenturaContentColumn` → 560/720 via tokens.
3. Dialogs/sheets on regular+: `showTenturaAdaptiveSheet` with `maxWidth: tt.contentMaxWidth ?? 560`; use 480 only for narrow flows.
4. Full-bleed exceptions: graph, maps, scatter — document explicitly; cap bubbles/overlays locally.
5. Grids: follow `beacon_icon_picker_screen.dart` — `SliverLayoutBuilder` + `windowClassForWidth` + fixed cross-axis count.
6. Base layout decisions on `LayoutBuilder` / `constraints.maxWidth`, not `MediaQuery.orientation` or hardware type.

---

## Audit sources

Consolidated from four parallel codebase audits (2026-06-30):

- Feature screens (`features/**`, excluding beacon room deep-dive)
- Beacon / room chat (`beacon_room`, `basic_chat_body`, item discussion)
- Pattern inventory (grep + `responsive-design-audit.md`)
- UI shell (`lib/ui/**`, design system, navigation context)
