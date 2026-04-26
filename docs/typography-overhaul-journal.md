# Typography & Responsive Overhaul — Journal

**Status:** Active (archive header will be updated at closeout)

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

- [ ] features/auth/ui/screen/auth_login_screen.dart
- [ ] features/auth/ui/screen/auth_register_screen.dart
- [ ] features/intro/ui/screen/intro_screen.dart
- [ ] features/settings/ui/screen/settings_screen.dart
- [ ] features/profile/ui/screen/profile_screen.dart
- [ ] features/profile/ui/widget/profile_app_bar.dart
- [ ] features/profile/ui/widget/profile_body.dart
- [ ] features/profile_view/ui/screen/profile_view_screen.dart
- [ ] features/profile_view/ui/widget/profile_view_app_bar.dart
- [ ] features/profile_view/ui/widget/profile_view_body.dart
- [ ] features/profile_view/ui/widget/mutual_friends_sheet.dart
- [ ] features/profile_view/ui/widget/mutual_friends_button.dart
- [ ] features/profile_edit/ui/screen/profile_edit_screen.dart
- [ ] features/friends/ui/screen/friends_screen.dart
- [ ] features/chat/ui/screen/chat_screen.dart
- [ ] features/chat/ui/widget/chat_peer_list_tile.dart
- [ ] features/chat/ui/widget/peer_presence_subtitle.dart
- [ ] features/chat/ui/widget/chat_list.dart
- [ ] features/chat/ui/widget/chat_tile_mine.dart
- [ ] features/chat/ui/widget/chat_tile_sender.dart
- [ ] features/chat/ui/widget/chat_message_actions.dart
- [ ] features/chat/ui/widget/chat_separator.dart
- [ ] features/home/ui/screen/home_screen.dart
- [ ] features/home/ui/widget/inbox_navbar_item.dart
- [ ] features/home/ui/widget/my_work_navbar_item.dart
- [ ] features/home/ui/widget/friends_navbar_item.dart
- [ ] features/home/ui/widget/profile_navbar_item.dart
- [ ] features/home/ui/widget/new_stuff_dot.dart
- [ ] features/home/ui/widget/new_stuff_reason_l10n.dart
- [ ] features/home/ui/widget/home_bottom_nav_listener.dart
- [ ] features/inbox/ui/screen/inbox_screen.dart
- [ ] features/inbox/ui/screen/inbox_rejected_screen.dart
- [ ] features/inbox/ui/widget/inbox_item_tile.dart
- [ ] features/inbox/ui/widget/inbox_card_meta_chips.dart
- [ ] features/inbox/ui/widget/inbox_card_forwards_fold.dart
- [ ] features/inbox/ui/widget/inbox_card_action_row.dart
- [ ] features/inbox/ui/widget/inbox_forward_provenance_panel.dart
- [ ] features/inbox/ui/widget/inbox_tombstone_card.dart
- [ ] features/inbox/ui/widget/rejection_dialog.dart
- [ ] features/my_work/ui/screen/my_work_screen.dart
- [ ] features/my_work/ui/widget/my_work_cards.dart
- [ ] features/my_work/ui/widget/compact_forwarder_avatars.dart
- [ ] features/my_work/ui/widget/my_work_status_line.dart
- [ ] features/my_work/ui/widget/my_work_card_status_strip.dart
- [ ] features/beacon/ui/screen/beacon_screen.dart
- [ ] features/beacon/ui/widget/beacon_info.dart
- [ ] features/beacon/ui/widget/beacon_tile.dart
- [ ] features/beacon/ui/widget/beacon_overflow_menu.dart
- [ ] features/beacon/ui/widget/beacon_tile_control.dart
- [ ] features/beacon/ui/widget/beacon_mine_control.dart
- [ ] features/beacon/ui/widget/coordination_ui.dart
- [ ] features/beacon_create/ui/screen/beacon_create_screen.dart
- [ ] features/beacon_create/ui/screen/beacon_icon_picker_screen.dart
- [ ] features/beacon_create/ui/widget/beacon_color_selector.dart
- [ ] features/beacon_create/ui/widget/info_tab.dart
- [ ] features/beacon_create/ui/widget/image_tab.dart
- [ ] features/beacon_create/ui/widget/polling_tab.dart
- [ ] features/beacon_view/ui/screen/beacon_view_screen.dart
- [ ] features/beacon_view/ui/screen/beacon_forwards_screen.dart
- [ ] features/beacon_view/ui/widget/beacon_operational_collapsible_header.dart
- [ ] features/beacon_view/ui/widget/beacon_primary_cta_bar.dart
- [ ] features/beacon_view/ui/widget/beacon_mine_control.dart
- [ ] features/beacon_view/ui/widget/activity_list.dart
- [ ] features/beacon_view/ui/widget/unified_forward_row.dart
- [ ] features/beacon_view/ui/widget/self_aware_plain_mini_avatar.dart
- [ ] features/beacon_view/ui/widget/plain_mini_avatar.dart
- [ ] features/beacon_view/ui/widget/coordination_response_bottom_sheet.dart
- [ ] features/beacon_view/ui/widget/overview/beacon_overview_tab.dart
- [ ] features/beacon_view/ui/widget/commitments_summary_card.dart
- [ ] features/beacon_view/ui/widget/commitment_tile.dart
- [ ] features/forward/ui/screen/forward_beacon_screen.dart
- [ ] features/forward/ui/widget/forward_top_bar.dart
- [ ] features/forward/ui/widget/forward_bottom_composer.dart
- [ ] features/forward/ui/widget/forward_recipient_row.dart
- [ ] features/forward/ui/widget/forward_scope_links.dart
- [ ] features/forward/ui/widget/forward_search_overlay.dart
- [ ] features/forward/ui/widget/per_recipient_note_input.dart
- [ ] features/forward/ui/widget/compact_beacon_context_strip.dart
- [ ] features/evaluation/ui/screen/review_contributions_screen.dart
- [ ] features/evaluation/ui/widget/evaluation_detail_sheet.dart
- [ ] features/evaluation/ui/widget/evaluation_summary_card.dart
- [ ] features/evaluation/ui/widget/review_banner.dart
- [ ] features/evaluation/ui/widget/beacon_evaluation_hooks.dart
- [ ] features/evaluation/ui/widget/beacon_review_countdown_row.dart
- [ ] features/rating/ui/screen/rating_screen.dart
- [ ] features/rating/ui/widget/rating_list_tile.dart
- [ ] features/rating/ui/widget/rating_scatter_view.dart
- [ ] features/graph/ui/screen/graph_screen.dart
- [ ] features/graph/ui/screen/forwards_graph_screen.dart
- [ ] features/graph/ui/widget/graph_node_widget.dart
- [ ] features/graph/ui/widget/graph_body.dart
- [ ] features/complaint/ui/screen/complaint_screen.dart
- [ ] features/favorites/ui/screen/favorites_screen.dart
- [ ] features/updates/ui/screen/updates_screen.dart
- [ ] features/connect/ui/widget/connect_bottom_sheet.dart
- [ ] features/comment/ui/widget/comment_tile.dart
- [ ] features/context/ui/widget/context_drop_down.dart
- [ ] features/like/ui/widget/like_control.dart
- [ ] features/opinion/ui/widget/opinion_tile.dart
- [ ] features/opinion/ui/widget/opinion_list.dart
- [ ] features/polling/ui/widget/polling_question_input.dart
- [ ] features/polling/ui/widget/polling_variant_input.dart
- [ ] features/polling/ui/widget/poll_button.dart
- [ ] features/geo/ui/widget/place_name_text.dart
- [ ] features/auth/ui/widget/account_list_tile.dart
- [ ] features/settings/ui/widget/theme_switch_button.dart
- [ ] features/dev/ui/widget/colors_drawer.dart

### Shared `packages/client/lib/ui/`

- [ ] ui/widget/beacon_card_primitives.dart
- [ ] ui/widget/beacon_card_author_subline.dart
- [ ] ui/widget/self_user_highlight.dart
- [ ] ui/widget/linear_pi_active.dart
- [ ] ui/widget/card_triage_action_row.dart
- [ ] ui/widget/beacon_image_gallery.dart
- [ ] ui/widget/beacon_photo_count.dart
- [ ] ui/widget/inbox_style_app_bar.dart
- [ ] ui/widget/qr_code.dart
- [ ] ui/widget/self_aware_profile_avatar.dart
- [ ] ui/widget/share_code_icon_button.dart
- [ ] ui/widget/beacon_image.dart
- [ ] ui/widget/show_more_text.dart
- [ ] ui/widget/collapsible_section.dart
- [ ] ui/widget/rating_indicator.dart
- [ ] ui/widget/bottom_text_input.dart
- [ ] ui/widget/beacon_gallery_viewer.dart
- [ ] ui/widget/profile_app_bar_title.dart
- [ ] ui/widget/avatar_rated.dart
- [ ] ui/widget/author_info.dart
- [ ] ui/widget/side_outline_cta_button.dart
- [ ] ui/widget/tentura_icons.dart
- [ ] ui/widget/beacon_identity_tile.dart
- [ ] ui/dialog/qr_scan_dialog.dart

## Decisions made during execution

(empty; append as needed)

## Deferred / out-of-scope

- **`rating_scatter_view.dart` CustomPainter axis labels:** may use literal `fontSize` (currently 18); must stay ≥ 13. No `Theme.of` in painter — exception to “no inline fontSize” rule.

## Decisions made during execution (Phase 3)

- Inbox / My Work `+N` overflow badges: `labelMedium` + **w700**, avatar ring size raised **20 → 24** (`_kAvatarSize`, `CompactForwarderAvatars` default) so 13px+ text fits.
- `forward_search_overlay` search field: `TenturaText.body(tt.text)` for 15px body (was `bodySmall` + 15 override).
