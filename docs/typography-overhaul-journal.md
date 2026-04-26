# Typography & Responsive Overhaul — Journal

**Status:** Archived 2026-04 — kept in-repo as the permanent record of decisions and audit (see **Journal lifecycle** below).

## Locked decisions

- **Font:** Inter only, **bundled as local assets**. Drop Roboto, drop google_fonts package, drop all mono usage. For numerals/timers use `FontFeature.tabularFigures()` on Inter.
- **Web on desktop:** real desktop layout. Remove the 360dp phone frame. Use `WindowClass` (compact/regular/expanded), cap content width per class.
- **Mono:** dropped entirely.
- **Hard floors:** metadata text >= 13, body >= 15, action labels >= 15, navLabel >= 12.5 (only exception). Sizes 8 / 10 / 11 / 12 are banned in `lib/features/**` and `lib/ui/**`.
- **No global text scaler override.** `TextScaler.noScaling` and any `MediaQuery.copyWith(textScaler: …)` is forbidden in `app/app.dart`.
- **No proportional UI scaling.** Banned: `flutter_screenutil`, `.sp/.w/.h`, `MediaQuery.sizeOf(...).width / N`, global `Transform.scale`. (Per-Canvas painting in `rating_scatter_view.dart` is a documented exception.)
- **Density adapts via padding/icon/avatar/button-height tokens, not via text shrinkage.**

## Token map (current -> new)

- TenturaText.title    14/600/Roboto       -> 18/700/Inter, height 1.22
- TenturaText.body     13/400/Roboto       -> 15/400/Inter, height 1.40
- TenturaText.bodySmall (NEW)                  13/500/Inter, height 1.35
- TenturaText.status   10/600/RobotoMono   -> 13/500/Inter, height 1.35
- TenturaText.command  12/600/RobotoMono   -> 15/700/Inter, height 1.20
- TenturaText.typeLabel 11/700/RobotoMono  -> 13/700/Inter, letterSpacing 0.3
- TenturaText.tabLabel 12/600/RobotoMono   -> 13/600/Inter, height 1.20
- TenturaText.navLabel (NEW)                  12.5/600/Inter, height 1.20
- TextTheme.titleLarge   22/600    -> 20/700, height 1.22
- TextTheme.titleMedium  18/600    -> 18/700, height 1.22
- TextTheme.titleSmall   14/600    -> 15/600, height 1.25
- TextTheme.headlineLarge 22       -> 22/700, height 1.22
- TextTheme.headlineMedium 16/500  -> 20/600, height 1.25
- TextTheme.headlineSmall 12/500   -> 18/600, height 1.30
- TextTheme.bodyLarge    16/400    -> 16/400, height 1.40
- TextTheme.bodyMedium   14/400    -> 15/400, height 1.40
- TextTheme.bodySmall    13/400    -> 13/500, height 1.35
- TextTheme.labelLarge   12/600    -> 15/700, height 1.20
- TextTheme.labelMedium  (unset)   -> 13/600, height 1.20
- TextTheme.labelSmall   11/400    -> 13/500, height 1.35
- TextTheme.displayLarge (add)     -> 32/700, height 1.20
- TextTheme.displayMedium 45       -> 28/700, height 1.20
- TextTheme.displaySmall (add)     -> 24/700, height 1.22

## Per-target audit log

### Screens & feature widgets

- [x] features/auth/ui/screen/auth_login_screen.dart — audited; no inline fontSize
- [x] features/auth/ui/screen/auth_register_screen.dart — audited; no inline fontSize
- [x] features/intro/ui/screen/intro_screen.dart — audited; no inline fontSize
- [x] features/settings/ui/screen/settings_screen.dart — audited; no inline fontSize
- [x] features/profile/ui/screen/profile_screen.dart — audited; no inline fontSize
- [x] features/profile/ui/widget/profile_app_bar.dart — audited; no inline fontSize
- [x] features/profile/ui/widget/profile_body.dart — audited; no inline fontSize
- [x] features/profile_view/ui/screen/profile_view_screen.dart — audited; no inline fontSize
- [x] features/profile_view/ui/widget/profile_view_app_bar.dart — audited; no inline fontSize
- [x] features/profile_view/ui/widget/profile_view_body.dart — audited; no inline fontSize
- [x] features/profile_view/ui/widget/mutual_friends_sheet.dart — audited; no inline fontSize
- [x] features/profile_view/ui/widget/mutual_friends_button.dart — audited; no inline fontSize
- [x] features/profile_edit/ui/screen/profile_edit_screen.dart — audited; no inline fontSize
- [x] features/friends/ui/screen/friends_screen.dart — verified; `MediaQuery.height*0.5` sheet only
- [x] features/chat/ui/screen/chat_screen.dart — verified
- [x] features/chat/ui/widget/chat_peer_list_tile.dart — verified
- [x] features/chat/ui/widget/peer_presence_subtitle.dart — verified
- [x] features/chat/ui/widget/chat_list.dart — verified
- [x] features/chat/ui/widget/chat_tile_mine.dart — verified; **keeps** `maxWidth: width * 0.75` (intrinsic bubble layout)
- [x] features/chat/ui/widget/chat_tile_sender.dart — verified; same `0.75` width factor
- [x] features/chat/ui/widget/chat_message_actions.dart — verified
- [x] features/chat/ui/widget/chat_separator.dart — verified
- [x] features/home/ui/screen/home_screen.dart — `TenturaText.navLabel` + `context.tt.bottomNavHeight`
- [x] features/home/ui/widget/inbox_navbar_item.dart — verified
- [x] features/home/ui/widget/my_work_navbar_item.dart — verified
- [x] features/home/ui/widget/friends_navbar_item.dart — verified
- [x] features/home/ui/widget/profile_navbar_item.dart — verified
- [x] features/home/ui/widget/new_stuff_dot.dart — verified
- [x] features/home/ui/widget/new_stuff_reason_l10n.dart — verified
- [x] features/home/ui/widget/home_bottom_nav_listener.dart — verified
- [x] features/inbox/ui/screen/inbox_screen.dart — verified
- [x] features/inbox/ui/screen/inbox_rejected_screen.dart — verified
- [x] features/inbox/ui/widget/inbox_item_tile.dart — verified
- [x] features/inbox/ui/widget/inbox_card_meta_chips.dart — verified
- [x] features/inbox/ui/widget/inbox_card_forwards_fold.dart — Phase 3 bodySmall deadline
- [x] features/inbox/ui/widget/inbox_card_action_row.dart — verified
- [x] features/inbox/ui/widget/inbox_forward_provenance_panel.dart — Phase 3 +24px avatars
- [x] features/inbox/ui/widget/inbox_tombstone_card.dart — verified
- [x] features/inbox/ui/widget/rejection_dialog.dart — verified
- [x] features/my_work/ui/screen/my_work_screen.dart — verified
- [x] features/my_work/ui/widget/my_work_cards.dart — verified
- [x] features/my_work/ui/widget/compact_forwarder_avatars.dart — Phase 3 labelMedium badge
- [x] features/my_work/ui/widget/my_work_status_line.dart — verified
- [x] features/my_work/ui/widget/my_work_card_status_strip.dart — verified
- [x] features/beacon/ui/screen/beacon_screen.dart — verified
- [x] features/beacon/ui/widget/beacon_info.dart — verified
- [x] features/beacon/ui/widget/beacon_tile.dart — verified
- [x] features/beacon/ui/widget/beacon_overflow_menu.dart — verified
- [x] features/beacon/ui/widget/beacon_tile_control.dart — verified
- [x] features/beacon/ui/widget/beacon_mine_control.dart — verified
- [x] features/beacon/ui/widget/coordination_ui.dart — verified
- [x] features/beacon_create/ui/screen/beacon_create_screen.dart — verified
- [x] features/beacon_create/ui/screen/beacon_icon_picker_screen.dart — verified
- [x] features/beacon_create/ui/widget/beacon_color_selector.dart — verified
- [x] features/beacon_create/ui/widget/info_tab.dart — verified
- [x] features/beacon_create/ui/widget/image_tab.dart — Phase 3 labelMedium index badge
- [x] features/beacon_create/ui/widget/polling_tab.dart — verified
- [x] features/beacon_view/ui/screen/beacon_view_screen.dart — verified
- [x] features/beacon_view/ui/screen/beacon_forwards_screen.dart — verified
- [x] features/beacon_view/ui/widget/beacon_operational_collapsible_header.dart — verified
- [x] features/beacon_view/ui/widget/beacon_primary_cta_bar.dart — verified
- [x] features/beacon_view/ui/widget/beacon_mine_control.dart — verified
- [x] features/beacon_view/ui/widget/activity_list.dart — verified
- [x] features/beacon_view/ui/widget/unified_forward_row.dart — verified
- [x] features/beacon_view/ui/widget/self_aware_plain_mini_avatar.dart — verified
- [x] features/beacon_view/ui/widget/plain_mini_avatar.dart — verified
- [x] features/beacon_view/ui/widget/coordination_response_bottom_sheet.dart — verified
- [x] features/beacon_view/ui/widget/overview/beacon_overview_tab.dart — Phase 3 TextTheme cleanup
- [x] features/beacon_view/ui/widget/commitments_summary_card.dart — verified
- [x] features/beacon_view/ui/widget/commitment_tile.dart — bodySmall migration (Phase 1)
- [x] features/forward/ui/screen/forward_beacon_screen.dart — bodySmall migration
- [x] features/forward/ui/widget/forward_top_bar.dart — verified
- [x] features/forward/ui/widget/forward_bottom_composer.dart — verified
- [x] features/forward/ui/widget/forward_recipient_row.dart — verified
- [x] features/forward/ui/widget/forward_scope_links.dart — verified
- [x] features/forward/ui/widget/forward_search_overlay.dart — Phase 3 body style
- [x] features/forward/ui/widget/per_recipient_note_input.dart — verified
- [x] features/forward/ui/widget/compact_beacon_context_strip.dart — verified
- [x] features/evaluation/ui/screen/review_contributions_screen.dart — verified
- [x] features/evaluation/ui/widget/evaluation_detail_sheet.dart — verified
- [x] features/evaluation/ui/widget/evaluation_summary_card.dart — verified
- [x] features/evaluation/ui/widget/review_banner.dart — verified
- [x] features/evaluation/ui/widget/beacon_evaluation_hooks.dart — verified
- [x] features/evaluation/ui/widget/beacon_review_countdown_row.dart — verified
- [x] features/rating/ui/screen/rating_screen.dart — verified
- [x] features/rating/ui/widget/rating_list_tile.dart — verified
- [x] features/rating/ui/widget/rating_scatter_view.dart — CustomPainter `fontSize: 18` exception
- [x] features/graph/ui/screen/graph_screen.dart — verified
- [x] features/graph/ui/screen/forwards_graph_screen.dart — verified
- [x] features/graph/ui/widget/graph_node_widget.dart — verified
- [x] features/graph/ui/widget/graph_body.dart — verified
- [x] features/complaint/ui/screen/complaint_screen.dart — verified
- [x] features/favorites/ui/screen/favorites_screen.dart — verified
- [x] features/updates/ui/screen/updates_screen.dart — verified
- [x] features/connect/ui/widget/connect_bottom_sheet.dart — verified
- [x] features/comment/ui/widget/comment_tile.dart — verified
- [x] features/context/ui/widget/context_drop_down.dart — verified (color-only TextStyle)
- [x] features/like/ui/widget/like_control.dart — verified
- [x] features/opinion/ui/widget/opinion_tile.dart — verified
- [x] features/opinion/ui/widget/opinion_list.dart — verified
- [x] features/polling/ui/widget/polling_question_input.dart — verified
- [x] features/polling/ui/widget/polling_variant_input.dart — verified
- [x] features/polling/ui/widget/poll_button.dart — verified
- [x] features/geo/ui/widget/place_name_text.dart — verified
- [x] features/auth/ui/widget/account_list_tile.dart — verified
- [x] features/settings/ui/widget/theme_switch_button.dart — verified
- [x] features/dev/ui/widget/colors_drawer.dart — Phase 3 titleSmall DefaultTextStyle

### Shared `packages/client/lib/ui/`

- [x] ui/widget/beacon_card_primitives.dart — Phase 2 metadata tokens
- [x] ui/widget/beacon_card_author_subline.dart — verified
- [x] ui/widget/self_user_highlight.dart — verified
- [x] ui/widget/linear_pi_active.dart — verified
- [x] ui/widget/card_triage_action_row.dart — verified
- [x] ui/widget/beacon_image_gallery.dart — verified
- [x] ui/widget/beacon_photo_count.dart — verified
- [x] ui/widget/inbox_style_app_bar.dart — verified
- [x] ui/widget/qr_code.dart — height breakpoints (replaced ScreenSize)
- [x] ui/widget/self_aware_profile_avatar.dart — verified
- [x] ui/widget/share_code_icon_button.dart — verified
- [x] ui/widget/beacon_image.dart — verified
- [x] ui/widget/show_more_text.dart — verified (inherits textTheme)
- [x] ui/widget/collapsible_section.dart — verified
- [x] ui/widget/rating_indicator.dart — verified
- [x] ui/widget/bottom_text_input.dart — verified
- [x] ui/widget/beacon_gallery_viewer.dart — verified
- [x] ui/widget/profile_app_bar_title.dart — verified
- [x] ui/widget/avatar_rated.dart — verified (`fontSize: size.height/2` proportional to avatar)
- [x] ui/widget/author_info.dart — verified
- [x] ui/widget/side_outline_cta_button.dart — verified
- [x] ui/widget/tentura_icons.dart — verified
- [x] ui/widget/beacon_identity_tile.dart — verified
- [x] ui/dialog/qr_scan_dialog.dart — height breakpoints for scan window

## Decisions made during execution

- **Beacon detail — iPhone SE / narrow pass (2026-04):** Overview coordination collapsed summary uses `TenturaText.status` (not `body`); expanded diagnosis title uses `TenturaText.typeLabel` to match commitment coordination labels; `BeaconViewScreen` app bar title uses `titleLarge`; `CardTriageActionRow` and owner `BeaconPrimaryCtaBar` buttons set `textTheme.labelLarge`; commitments tab summary subline uses `bodySmall`; activity section headers use plain `titleSmall`; `TenturaUnderlineTabs` vertical padding uses `context.tt.rowGap`.
- **Beacon detail typography (post–Phase 5):** Beacon header title uses optional `titleStyle` on `BeaconCardHeaderRow` (`titleMedium` on detail only). Overview section cards use `titleSmall` + `bodyMedium` prose + `bodySmall` metadata; commitment tiles use `titleSmall` for names; `TenturaUnderlineTabs` uses ellipsis instead of `FittedBox` shrink; `CardTriageActionRow` / `BeaconPrimaryCtaBar` stack tertiary or owner actions on a second row when width &lt; `kCardTriageActionRowNarrowMaxWidth` (~380 logical px).
- **Phase 3:** Inbox / My Work `+N` overflow badges: `labelMedium` + **w700**, avatar ring size raised **20 → 24** (`_kAvatarSize`, `CompactForwarderAvatars` default) so 13px+ text fits.
- **Phase 3:** `forward_search_overlay` search field: `TenturaText.body(tt.text)` for 15px body (was `bodySmall` + 15 override).
- **Chat bubbles:** `chat_tile_mine.dart` / `chat_tile_sender.dart` keep `MediaQuery.size.width * 0.75` for `maxWidth` — intentional proportional layout, not typography scaling.

## Deferred / out-of-scope

- **`rating_scatter_view.dart` CustomPainter axis labels:** may use literal `fontSize` (currently 18); must stay ≥ 13. No `Theme.of` in painter — exception to “no inline fontSize” rule.

## Phase 5 — Enforcement & tests

- **`no_inline_font_size` (`tentura_lints`):** flags numeric literal `fontSize:` on `TextStyle(` in `packages/client/lib/features/**` and `lib/ui/**`. Allow-list: `design_system/`, `rating_scatter_view.dart`, `colors_drawer.dart`. Enabled in `packages/client/analysis_options.yaml`.
- **Golden tests:** `packages/client/test/golden/typography_overhaul_test.dart` — 30 PNGs under `test/golden/goldens/` (inbox-style card, my-work-style card, beacon header, forward composer, bottom nav × 360×800 / 600×900 / 1024×800 × text scaler 1.0 and 1.3). Run: `flutter test test/golden/typography_overhaul_test.dart`; refresh: add `--update-goldens`.

## Manual QA matrix (devices)


| Target                        | Text scale / width         | Result                    |
| ----------------------------- | -------------------------- | ------------------------- |
| Android physical (360–393 dp) | 1.0, 1.15, 1.3             | *Pending — run on device* |
| iOS Simulator                 | Largest Dynamic Type       | *Pending*                 |
| Chrome desktop                | 390 / 520 / 1024 / 1440 px | *Pending*                 |


**Automated (2026-04-26, Linux CI dev):** `dart analyze --fatal-infos` + `dart run custom_lint` clean for `packages/client` and `packages/tentura_lints`; `dart analyze --fatal-infos` clean for `packages/server`; `flutter test test/golden/typography_overhaul_test.dart` pass.

## Closeout summary

- **Audit scope:** all journal checklist rows above (~120+ feature/ui paths) marked verified during Phases 2–4; inline numeric `TextStyle.fontSize` removed from operational UI except documented exceptions (`rating_scatter_view` painter; proportional `avatar_rated`; design-system `TenturaText`).
- **New enforcement:** `no_inline_font_size` custom lint + 30 typography goldens.
- **Journal lifecycle:** **Keep** this file in `docs/` permanently (no delete-after-merge); status line set to **Archived** at closeout.

