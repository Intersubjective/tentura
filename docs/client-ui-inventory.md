# Flutter Client UI Inventory (`packages/client`)

Complete inventory of screens, routes, dialogs, bottom sheets, and overlay entry points in the Tentura Flutter client.

> **Note:** Regenerate before trusting this inventory against the tree. After refresh, verify home tab order (My Work default) and beacon detail surfaces (**NOW / Chat / People**; Activity log is an overflow sheet, not a tab).

**Generated:** 2026-10-30 (source scan of `packages/client/lib`; regenerated from source)

---

## Methodology

Searched `packages/client/lib` for:

| Pattern | Purpose |
|---------|---------|
| `@RoutePage()` | Auto Route screens |
| `*_screen.dart` glob | Screen files |
| `root_router.dart` `AutoRoute(...)` | Registered route tree (source only; no deep `*.gr.dart` reads) |
| `showModalBottomSheet`, `showBottomSheet`, `showDialog`, `showGeneralDialog`, `showAdaptiveDialog`, `showTenturaAdaptiveSheet` | Imperative overlays |
| `*dialog*`, `*sheet*`, `*modal*`, `*popup*`, `*bottom_sheet*` file globs | Named overlay widgets |
| `Navigator.push` + `MaterialPageRoute` | Non–Auto Route full-screen pushes |
| `PopupMenuButton`, `showMenu`, `showAnchoredPopupMenu` | Menus |
| `showDatePicker`, `showDateRangePicker`, `showCupertinoModalPopup` | System pickers |
| `DraggableScrollableSheet`, `ModalBottomSheet` | Sheet implementations |
| `ScreenCubit.navigateTo` / `pushPath` | Programmatic navigation targets |

Cross-checked `root_router.dart` against all `@RoutePage()` annotations. **Widgetbook:** no widgetbook package in the repo.

---

## Flat List

### Routes / Screens

#### Registered in `root_router.dart`

| Name | Path | File | Notes |
|------|------|------|-------|
| **HomeScreen** (tab shell) | `/home` | `lib/features/home/ui/screen/home_screen.dart` | Bottom nav / side rail; hosts 6 tabs |
| ↳ **MyWorkScreen** (default tab) | `/home/work` | `lib/features/my_work/ui/screen/my_work_screen.dart` | Primary home feed / My Work |
| ↳ **ConversationsScreen** | `/home/conversations` | `lib/features/inbox/ui/screen/conversations_screen.dart` | Posts conversation list beside open chat |
| ↳ **InboxScreen** | `/home/inbox` | `lib/features/inbox/ui/screen/inbox_screen.dart` | Inbox triage tab |
| ↳ **ConstellationScreen** | `/home/constellation` | `lib/features/constellation/ui/screen/constellation_screen.dart` | Request field map |
| ↳ **FriendsScreen** | `/home/network` | `lib/features/friends/ui/screen/friends_screen.dart` | Network / friends tab |
| ↳ **BlockedUsersScreen** | `/home/network/blocked` | `lib/features/block/ui/screen/blocked_users_screen.dart` | Blocked users sub-route under Network |
| ↳ **ProfileScreen** | `/home/profile` | `lib/features/profile/ui/screen/profile_screen.dart` | "Me" tab |
| **InboxRejectedScreen** | `/home/inbox/rejected` | `lib/features/inbox/ui/screen/inbox_rejected_screen.dart` | Full-screen rejected archive (no tabs) |
| **InboxWatchingScreen** | `/home/inbox/watching` | `lib/features/inbox/ui/screen/inbox_watching_screen.dart` | Full-screen watching list |
| **UpdatesScreen** | `/home/inbox/history` | `lib/features/updates/ui/screen/updates_screen.dart` | Full notification history |
| **NotificationSettingsScreen** | `/settings/notifications` | `lib/features/notification_settings/ui/screen/notification_settings_screen.dart` | Fullscreen notification preferences |
| **RoutingMuteScreen** | `/settings/routing-mute` | `lib/features/capability/ui/screen/routing_mute_screen.dart` | Capability routing mutes |
| **PeopleTagsScreen** | `/settings/people-tags` | `lib/features/people_tags/ui/screen/people_tags_screen.dart` | Manage custom contact tags |
| **PeopleAutoTagScreen** | `/settings/people-tags/auto/:kind` | `lib/features/people_tags/ui/screen/people_auto_tag_screen.dart` | Auto-tag rules configuration |
| **PeopleTagScreen** | `/settings/people-tags/:tagId` | `lib/features/people_tags/ui/screen/people_tag_screen.dart` | View/edit single contact tag |
| **DebugSettingsScreen** | `/settings/debug` | `lib/features/settings/ui/screen/debug_settings_screen.dart` | Developer debug settings |
| **IntroScreen** | (guard-only) | `lib/features/intro/ui/screen/intro_screen.dart` | Native 3-page onboarding; web skips |
| **AuthLoginScreen** | `/sign/in` | `lib/features/auth/ui/screen/auth_login_screen.dart` | Login / seed entry |
| **RecoverScreen** | `/recover-seed` | `lib/features/auth/ui/screen/recover_screen.dart` | Seed recovery hub |
| **AuthRegisterScreen** | `/sign/up/:id` | `lib/features/auth/ui/screen/auth_register_screen.dart` | Fullscreen dialog; invite signup |
| **AcceptInviteScreen** | `/accept-invite/:id` | `lib/features/invitation/ui/screen/accept_invite_screen.dart` | Fullscreen dialog; existing user accepts invite |
| **ProfileViewScreen** | `/profile/view/:id` | `lib/features/profile_view/ui/screen/profile_view_screen.dart` | Other user's profile |
| **ProfileEditScreen** | `/profile/edit` | `lib/features/profile_edit/ui/screen/profile_edit_screen.dart` | Fullscreen dialog |
| **SettingsScreen** | `/settings` | `lib/features/settings/ui/screen/settings_screen.dart` | Fullscreen settings screen |
| **CredentialsScreen** | `/settings/sign-in-methods` | `lib/features/credentials/ui/screen/credentials_screen.dart` | Fullscreen dialog; linked accounts |
| **BeaconCreateScreen** | `/beacon/new` | `lib/features/beacon_create/ui/screen/beacon_create_screen.dart` | Fullscreen dialog; create Request |
| **PostCreateScreen** | `/post/new` | `lib/features/beacon_create/ui/screen/post_create_screen.dart` | Fullscreen dialog; create Post |
| **BeaconViewHostScreen** | `/beacon/view/:id` | `lib/features/beacon_view/ui/screen/beacon_view_host_screen.dart` | Request/Post detail view host |
| **BeaconViewOperationalScreen** | (initial child of `/beacon/view/:id`) | `lib/features/beacon_view/ui/screen/beacon_view_host_screen.dart` | Request operational view (NOW / Chat / People) |
| **BeaconLobbyScreen** | `/beacon/lobby/:id` | `lib/features/beacon_lobby/ui/screen/beacon_lobby_screen.dart` | Request lobby Questions surface |
| **ForwardBeaconScreen** | `/forward/:id` | `lib/features/forward/ui/screen/forward_beacon_screen.dart` | Fullscreen dialog; forward Request/Post |
| **PersonForwardScreen** | `/forward-person/:id` | `lib/features/forward/ui/screen/person_forward_screen.dart` | Forward existing request to a specific person |
| **BeaconScreen** ("view all") | `/beacon/all/:id` | `lib/features/beacon/ui/screen/beacon_screen.dart` | All requests authored by profile |
| **InvolvedBeaconScreen** | `/beacon/involved/:id` | `lib/features/beacon/ui/screen/involved_beacon_screen.dart` | Requests authored by :id viewer was forwarded |
| **RatingScreen** | `/rating` | `lib/features/rating/ui/screen/rating_screen.dart` | Merit scatter / rating view |
| **InviteGenealogyScreen** | `/invite-genealogy` | `lib/features/invite_genealogy/ui/screen/invite_genealogy_screen.dart` | Invite tree genealogy view |
| **ForwardsGraphScreen** | `/graph/forwards/:id` | `lib/features/graph/ui/screen/forwards_graph_screen.dart` | Forward lineage graph |
| **GraphScreen** | `/graph/:id` | `lib/features/graph/ui/screen/graph_screen.dart` | Trust graph |
| **ComplaintScreen** | `/complaint/:id` | `lib/features/complaint/ui/screen/complaint_screen.dart` | Fullscreen dialog; report complaint |

#### Removed screens (no longer in tree)

| Name | Former path | Notes |
|------|-------------|-------|
| **ItemDiscussionScreen** | `/beacon/view/:beaconId/discussion/:itemId` | Removed; per-item discussion threads replaced by General chat |
| **ReviewContributionsScreen** | `/beacon/review/:id` | Evaluation screen removed |

#### Non–Auto Route full-screen pushes (`Navigator.push` + `MaterialPageRoute`)

| Name | File | Notes |
|------|------|-------|
| **BeaconGalleryViewer** | `lib/ui/widget/beacon_gallery_viewer.dart` | Full-screen photo gallery |
| **TenturaFullscreenImageViewer** | `lib/ui/widget/tentura_fullscreen_image_viewer.dart` | Full-screen general image gallery |
| **RoomAttachmentFullscreenGallery** | `lib/features/beacon_threads/ui/widget/room_attachment_widgets.dart` | Full-screen chat attachment gallery |

---

### Bottom Sheets

#### Dedicated sheet modules (`show*` entry points)

| Name | File | Description |
|------|------|-------------|
| **showBeaconCloseConfirmSheet** | `lib/features/beacon/ui/sheet/beacon_close_confirm_sheet.dart` | Author close confirmation sheet |
| **showFactActionsSheet** (+ inline edit fact sheet) | `lib/features/beacon_threads/ui/widget/fact_actions_sheet.dart` | Pinned fact actions; edit fact text sub-sheet |
| **showReactionSendersSheet** | `lib/features/beacon_threads/ui/widget/reaction_senders_sheet.dart` | Who reacted with emoji |
| **showFactPickerSheet** | `lib/features/beacon_threads/ui/widget/fact_picker_sheet.dart` | Fact picker sheet |
| **showFactHistorySheet** | `lib/features/beacon_threads/ui/widget/fact_history_sheet.dart` | Pinned fact revision history |
| **showRoomReadersSheet** | `lib/features/beacon_threads/ui/widget/room_readers_sheet.dart` | Chat readers sheet |
| **showRoomBatonCreateSheet** | `lib/features/beacon_threads/ui/widget/room_baton_create_sheet.dart` | Create baton/ask in chat |
| **showRoomBatonChooseSheet** | `lib/features/beacon_threads/ui/widget/room_baton_choose_sheet.dart` | Select baton in chat |
| **showRoomBatonPlanStepSheet** | `lib/features/beacon_threads/ui/widget/room_baton_plan_step_sheet.dart` | Link baton to plan step |
| **showAuthorCommitmentSheet** | `lib/features/beacon_threads/ui/sheet/author_commitment_sheet.dart` | Request author commitment sheet |
| **showMutualFriendsSheet** | `lib/features/profile_view/ui/widget/mutual_friends_sheet.dart` | Mutual friends list |
| **showProfileInfoSheet** | `lib/features/profile_view/ui/widget/profile_info_sheet.dart` | Profile metadata sheet |
| **showLineageSuggestionsPreviewSheet** | `lib/features/forward/ui/widget/lineage_suggestions_sheet.dart` | Forward lineage suggestions preview |
| **showBeaconActivitySheet** | `lib/features/beacon_view/ui/widget/beacon_activity_sheet.dart` | Activity log overflow sheet |
| **showBeaconCurrentLineSheet** | `lib/features/beacon_view/ui/widget/beacon_current_line_sheet.dart` | Edit current line text |
| **showBeaconFactComposerSheet** | `lib/features/beacon_view/ui/widget/beacon_fact_composer_sheet.dart` | Compose pinned fact |
| **showBeaconPinnedFactsSheet** | `lib/features/beacon_view/ui/widget/beacon_pinned_facts_sheet.dart` | Browse pinned facts |
| **showBeaconViewDetailsSheet** | `lib/features/beacon_view/ui/widget/beacon_view_details_sheet.dart` | Request details sheet |
| **showBeaconViewStatusBottomSheet** | `lib/features/beacon_view/ui/widget/beacon_view_status_bottom_sheet.dart` | Status update bottom sheet |
| **showHelpOfferTileSheet** | `lib/features/beacon_view/ui/sheet/help_offer_tile_sheet.dart` | Help offer actions sheet |
| **ConnectBottomSheet.show** | `lib/features/connect/ui/widget/connect_bottom_sheet.dart` | Connect-by-code flow; **bottom sheet on compact, centered Dialog on regular+** |
| **showAvailabilitySheet** | `lib/features/profile/ui/sheet/availability_sheet.dart` | Profile availability status sheet |
| **showAddToTagSheet** | `lib/features/people_tags/ui/widget/add_to_tag_sheet.dart` | Add contacts to tag sheet |
| **showAddPeopleSheet** | `lib/features/people_tags/ui/widget/add_people_sheet.dart` | Add people sheet |
| **showBlockUserSheet** | `lib/features/block/ui/sheet/block_user_sheet.dart` | Block user confirm sheet |
| **showCoverSymbolSheet** | `lib/features/beacon_create/ui/widget/cover_symbol_sheet.dart` | Choose cover icon/symbol |
| **showConstellationArrangeSheet** | `lib/features/constellation/ui/widget/constellation_arrange_sheet.dart` | Arrange constellation field layout |
| **showConstellationLayoutHistorySheet** | `lib/features/constellation/ui/widget/constellation_layout_history_sheet.dart` | Constellation layout history |
| **showConstellationPostPreviewSheet** | `lib/features/constellation/ui/widget/constellation_post_preview_sheet.dart` | Constellation post preview sheet |
| **showConstellationRequestPreviewSheet** | `lib/features/constellation/ui/widget/constellation_request_preview_sheet.dart` | Constellation request preview sheet |
| **showForwardCandidateContextSheet** | `lib/features/forward_candidate_context/ui/widget/forward_candidate_context_sheet.dart` | Forward candidate context sheet |
| **showRequestAttentionTimelineSheet** | `lib/features/attention/ui/widget/request_attention_timeline_sheet.dart` | Attention timeline sheet |
| **showPostInfoSheet** | `lib/features/post_view/ui/widget/post_info_sheet.dart` | Post info and action sheet |
| **showHowTenturaWorksSheet** | `lib/features/home/ui/sheet/how_tentura_works_sheet.dart` | "How Tentura Works" onboarding sheet |
| **showPromptBatchSheet** | `lib/features/updates/ui/widget/prompt_batch_sheet.dart` | Batch prompt updates sheet |
| **showInviteAcceptedSetupSheet** | `lib/features/updates/ui/widget/invite_accepted_setup_sheet.dart` | Setup wizard for accepted invite |
| **showPlanStepSheet** | `lib/features/beacon_plan/ui/widget/plan_step_sheet.dart` | Plan step detail sheet |
| **showPlanStepEditSheet** | `lib/features/beacon_plan/ui/widget/plan_step_edit_sheet.dart` | Edit plan step |
| **showPlanCopySheet** | `lib/features/beacon_plan/ui/widget/plan_copy_sheet.dart` | Copy plan steps |
| **showTrustInfoSheet** | `lib/ui/widget/trust_info_sheet.dart` | Trust graph info sheet |

#### Inline bottom sheets (no separate file; opened from parent screen/widget)

| Name | Host file | Description |
|------|-----------|-------------|
| **Link email sheet** | `credentials_screen.dart` | `_linkEmail` email input |
| **Edit capabilities sheet** | `profile_view/ui/dialog/edit_capabilities_dialog.dart` | Opens as modal bottom sheet via `showTenturaAdaptiveSheet` |
| **Chat message actions sheet** | `beacon_room_body.dart` | Long-press message overflow actions |
| **Create poll sheet** (`BeaconRoomPollSheet`) | `beacon_room_poll_sheet.dart` | Create poll in chat |

Supporting utility: `lib/ui/widget/unfocus_sheet_body.dart` — wraps sheet bodies to dismiss keyboard.

---

### Dialogs

#### Dedicated dialog modules (`show` / `showAdaptiveDialog`)

| Name | File | Description |
|------|------|-------------|
| **BeaconCloseConfirmDialog** | `lib/features/beacon/ui/dialog/beacon_close_confirm_dialog.dart` | Simple close confirm (cards/lists) |
| **BeaconDeleteDialog** | `lib/features/beacon/ui/dialog/beacon_delete_dialog.dart` | Delete draft or published request |
| **BeaconPublishDialog** | `lib/features/beacon_create/ui/dialog/beacon_publish_dialog.dart` | Confirm publish on create |
| **BeaconSendConfirmationDialog** | `lib/features/beacon_create/ui/dialog/beacon_send_confirmation_dialog.dart` | Confirmation dialog when sending request |
| **HelpOfferMessageDialog** | `lib/features/beacon_view/ui/dialog/help_offer_message_dialog.dart` | Offer / withdraw / can't-help message |
| **HelpOfferRoleLabelDialog** | `lib/features/beacon_view/ui/dialog/help_offer_role_label_dialog.dart` | Set help offer role label |
| **HelpOfferAdmissionReasonDialog** | `lib/features/beacon_view/ui/dialog/help_offer_admission_reason_dialog.dart` | Specify admission reason |
| **AccountRemoveDialog** | `lib/features/auth/ui/dialog/account_remove_dialog.dart` | Remove saved account from device |
| **SignOutDialog** | `lib/features/auth/ui/dialog/sign_out_dialog.dart` | Sign out confirmation dialog |
| **InvitationAcceptDialog** | `lib/features/invitation/ui/dialog/invitation_accept_dialog.dart` | Confirm befriending inviter |
| **InvitationRemoveDialog** | `lib/features/invitation/ui/dialog/invitation_remove_dialog.dart` | Remove pending invitation |
| **InvitationAddresseeDialog** | `lib/features/invitation/ui/dialog/invitation_addressee_dialog.dart` | Name invitee when creating invite |
| **FriendRemoveDialog** ⚠ | `lib/features/friends/ui/dialog/friend_remove_dialog.dart` | **Defined; no call sites found** |
| **RenameContactDialog** | `lib/features/profile_view/ui/dialog/rename_contact_dialog.dart` | Private rename for subjective contact |
| **EditCapabilitiesDialog** | `lib/features/profile_view/ui/dialog/edit_capabilities_dialog.dart` | Edit viewer-visible capability cues |
| **MyProfileDeleteDialog** ⚠ | `lib/features/profile/ui/dialog/my_profile_delete.dart` | **Defined; no call sites found** |
| **TagEditorDialog** | `lib/features/people_tags/ui/widget/tag_editor_dialog.dart` | Create or edit person tag |
| **ContextAddDialog** | `lib/features/context/ui/dialog/context_add_dialog.dart` | Add request context tag |
| **ContextRemoveDialog** | `lib/features/context/ui/dialog/context_remove_dialog.dart` | Remove context tag |
| **ChooseLocationDialog** | `lib/features/geo/ui/dialog/choose_location_dialog.dart` | Map pin / location picker |
| **ShowSeedDialog** | `lib/ui/dialog/show_seed_dialog.dart` | Display recovery seed |
| **ShareCodeDialog** | `lib/ui/dialog/share_code_dialog.dart` | Share profile/request QR + code |
| **QRScanDialog** | `lib/ui/dialog/qr_scan_dialog.dart` | Camera QR scan |
| **showRejectionDialog** | `lib/features/inbox/ui/widget/rejection_dialog.dart` | Inbox reject-with-message |
| **ForwardAttributionDialog** | `lib/features/forward/ui/widget/forward_attribution_dialog.dart` | Forward attribution path dialog |

---

### Menus / Pickers / Other Overlays

#### Popup menus (`PopupMenuButton` / `showMenu` / `showAnchoredPopupMenu`)

| Name | Host file | Trigger context |
|------|-----------|-----------------|
| **My Work filter menu** | `my_work_screen.dart` | `showAnchoredPopupMenu` on filter chip |
| **Inbox overflow** | `inbox_screen.dart` | Open rejected / watching archive |
| **Profile app bar menu** | `profile/ui/widget/profile_app_bar.dart` | Rating shortcut |
| **Profile view app bar menu** | `profile_view_app_bar.dart` | Rename, remove friend, complaint |
| **Friends screen** | `friends_screen.dart` | Per-invitation actions |
| **Beacon overflow menu** | `beacon/ui/widget/beacon_overflow_menu.dart` | Canonical request ⋮ menu |
| **Beacon room overflow** | `beacon_room_overflow_menu.dart` | Create promise / baton actions |
| **Graph screen menu** | `graph_screen.dart` | Jump to ego, toggle positive-only |
| **Forwards graph menu** | `forwards_graph_screen.dart` | Jump to ego |
| **Auth account list tile menu** | `auth/ui/widget/account_list_tile.dart` | Share code, show seed, remove account |
| **Chat attachment menu** | `ui/widget/basic_chat_body.dart` | Attach photo/file in chat composer |
| **showAnchoredPopupMenu** (utility) | `ui/widget/show_anchored_popup_menu.dart` | Generic anchored menu helper |

#### System pickers

| Picker | Host file |
|--------|-----------|
| **showDatePicker** | `beacon_create/ui/widget/info_tab.dart` |
| **showDateRangePicker** | `beacon_create/ui/widget/info_tab.dart` |

#### ConnectBottomSheet platform split

On **compact** width → `showModalBottomSheet`; on **regular/expanded** → `showDialog` wrapping same widget (`connect_bottom_sheet.dart`).

---

## Tree (ASCII)

```
App (RootRouter — packages/client/lib/app/router/root_router.dart)
│
├── [Guard: intro pending, native only]
│   └── IntroScreen
│       └── (completes → Auth or Home)
│
├── [Unauthenticated]
│   ├── AuthLoginScreen (/sign/in)
│   │   ├── [Dialog: QRScanDialog]
│   │   └── → RecoverScreen (/recover-seed)
│   │       └── [Dialog: reset local auth confirm]
│   ├── AuthRegisterScreen (/sign/up/:id) [fullscreen dialog]
│   └── AcceptInviteScreen (/accept-invite/:id) [fullscreen dialog]
│       └── [Dialog: InvitationAcceptDialog]
│
├── HomeScreen (/home) ← tab shell (AutoTabsRouter)
│   ├── Tab 0: MyWorkScreen (/home/work)
│   │   ├── → BeaconViewHostScreen, BeaconCreateScreen, PostCreateScreen, ForwardBeaconScreen,
│   │   │         ComplaintScreen, GraphScreen, …
│   │   ├── [Menu: filter (showAnchoredPopupMenu)]
│   │   └── [Dialogs: ShareCode, BeaconCloseConfirm, BeaconDelete]
│   │
│   ├── Tab 1: ConversationsScreen (/home/conversations)
│   │   └── Posts conversation list & chat pane
│   │
│   ├── Tab 2: InboxScreen (/home/inbox)
│   │   ├── → InboxRejectedScreen (/home/inbox/rejected)
│   │   ├── → InboxWatchingScreen (/home/inbox/watching)
│   │   ├── → UpdatesScreen (/home/inbox/history)
│   │   ├── → BeaconViewHostScreen (inbox entry)
│   │   ├── [Menu: inbox overflow → rejected / watching archive]
│   │   └── [Dialog: showRejectionDialog, HelpOfferMessageDialog]
│   │
│   ├── Tab 3: ConstellationScreen (/home/constellation)
│   │   ├── Request / Post field map surface
│   │   └── [Sheets: ConstellationArrange, LayoutHistory, PostPreview, RequestPreview]
│   │
│   ├── Tab 4: FriendsScreen (/home/network)
│   │   ├── → BlockedUsersScreen (/home/network/blocked)
│   │   ├── [Sheet/Dialog: ConnectBottomSheet.show]
│   │   └── [Dialogs: InvitationAddressee, InvitationRemove, ShareCode]
│   │
│   └── Tab 5: ProfileScreen (/home/profile)
│       ├── → ProfileEditScreen, SettingsScreen, RatingScreen,
│       │         GraphScreen, BeaconScreen (all requests)
│       ├── [Menu: rating]
│       └── [Dialog: ShareCode via icon button]
│
├── InboxRejectedScreen (/home/inbox/rejected) [full-screen, no tabs]
│   └── → BeaconViewHostScreen
│
├── InboxWatchingScreen (/home/inbox/watching) [full-screen, no tabs]
│   └── → BeaconViewHostScreen
│
├── UpdatesScreen (/home/inbox/history) [full-screen, no tabs]
│   └── Notification history list
│
├── NotificationSettingsScreen (/settings/notifications) [full-screen]
├── RoutingMuteScreen (/settings/routing-mute) [full-screen]
├── PeopleTagsScreen (/settings/people-tags) [full-screen]
│   ├── PeopleAutoTagScreen (/settings/people-tags/auto/:kind)
│   └── PeopleTagScreen (/settings/people-tags/:tagId)
│
├── DebugSettingsScreen (/settings/debug) [full-screen]
│
├── ProfileViewScreen (/profile/view/:id)
│   ├── → GraphScreen, BeaconScreen, ComplaintScreen
│   ├── [Menu: rename, remove friend, complaint]
│   ├── [Dialog: RenameContactDialog]
│   ├── [Sheet: EditCapabilitiesDialog.show, MutualFriendsSheet, ProfileInfoSheet]
│   └── [Dialog: ShareCode]
│
├── ProfileEditScreen (/profile/edit) [fullscreen dialog]
│
├── SettingsScreen (/settings) [fullscreen page]
│   ├── → CredentialsScreen, NotificationSettingsScreen, DebugSettingsScreen
│   └── [Dialog: ShowSeedDialog]
│
├── CredentialsScreen (/settings/sign-in-methods) [fullscreen dialog]
│   ├── [Sheet: link email]
│   └── [Dialogs: ShowSeedDialog, remove credential confirm]
│
├── BeaconCreateScreen (/beacon/new) [fullscreen dialog]
│   ├── [Dialog: BeaconPublishDialog, BeaconSendConfirmationDialog, ChooseLocationDialog]
│   ├── [Sheet: CoverSymbolSheet]
│   └── [Pickers: showDatePicker, showDateRangePicker]
│
├── PostCreateScreen (/post/new) [fullscreen dialog]
│
├── BeaconViewHostScreen (/beacon/view/:id) ← Request / Post view host
│   └── BeaconViewOperationalScreen (initial child route)
│       ├── Surfaces: NOW / Chat / People (tab row below app bar)
│       │   ├── NOW: coordination header, child-request cards, pinned facts
│       │   ├── Chat: inline General (`BeaconRoomSurface`)
│       │   ├── People: participants, help offers, responses
│       │   ├── [Sheet: Activity log (`showBeaconActivitySheet`), BeaconCurrentLine,
│       │   │          BeaconViewDetails, BeaconFactComposer, BeaconPinnedFacts,
│       │   │          HelpOfferTileSheet, FactActions]
│       │   └── [Dialog: HelpOfferMessage, HelpOfferRoleLabel, HelpOfferAdmissionReason,
│       │             BeaconDelete, ShareCode, BeaconCloseConfirmSheet]
│       │
│       └── Expanded split (≥840 dp, latched): left = NOW + People tabs; right = General room pane
│
├── BeaconLobbyScreen (/beacon/lobby/:id) ← Questions surface
│   └── Pre-commitment Q&A list for invited people
│
├── ForwardBeaconScreen (/forward/:id) [fullscreen dialog]
│   ├── [Sheet: recipient reasons, LineageSuggestionsPreview]
│   └── [Dialog: InvitationAddressee, ShareCode, ForwardAttributionDialog]
│
├── PersonForwardScreen (/forward-person/:id)
│   └── Forward request to specific profile
│
├── BeaconScreen (/beacon/all/:id) — all requests for profile
│   └── → BeaconViewHostScreen
│
├── InvolvedBeaconScreen (/beacon/involved/:id) — forwarded requests for profile
│   └── → BeaconViewHostScreen
│
├── RatingScreen (/rating)
├── InviteGenealogyScreen (/invite-genealogy)
│
├── GraphScreen (/graph/:id)
│   └── [Menu: ego jump, positive/negative toggle]
│
├── ForwardsGraphScreen (/graph/forwards/:id)
│   └── [Menu: ego jump]
│
├── ComplaintScreen (/complaint/:id) [fullscreen dialog]
│
├── [Non–Auto Route pushes]
│   ├── BeaconGalleryViewer (from request photos)
│   ├── TenturaFullscreenImageViewer (from profile / profile-view image galleries)
│   └── RoomAttachmentFullscreenGallery (from chat attachments)
```

---

## Top App Bar Audit

Best-practice references:

- [AppBar](https://api.flutter.dev/flutter/material/AppBar-class.html) - fixed-height top app bar on `Scaffold`, with primary actions and overflow.
- [SliverAppBar](https://api.flutter.dev/flutter/material/SliverAppBar-class.html) - scroll-linked app bar that participates in a `CustomScrollView`.
- [Adaptive and responsive design in Flutter](https://docs.flutter.dev/ui/adaptive-responsive) - adapt layouts so they remain usable in the available space.
- [Large screen devices](https://docs.flutter.dev/ui/adaptive-responsive/large-screens) - switch navigation and chrome as the window grows.

### Unified top bars

Normal screens use `TenturaTopBar` instead of raw `AppBar`, `SliverAppBar`, or custom headers. The bar background spans the pane, while bar internals align to the same content geometry as the body. Height follows `tt.appBarHeight` (56 compact, 60 regular/expanded). Loading indicators use the 4dp `progress:` slot instead of ad-hoc `bottom` strips.

- **Primary tone roots:** MyWork, Conversations, Inbox, Constellation, Friends, and Profile.
- **Surface tone pushed/standalone screens:** auth, settings, credentials, complaint, profile edit/view, BeaconCreate, PostCreate, Beacon lists, BeaconViewHostScreen, BeaconLobbyScreen, notifications, rating, graph, invite genealogy, Forward.
- **Full-width alignment:** graph routes, rating, invite genealogy, and split/multi-pane custom rows.

### Full-screen overlays with top bars

- **QRScanDialog** (`packages/client/lib/ui/dialog/qr_scan_dialog.dart`): fullscreen dialog with an `AppBar`; desktop and mobile bodies diverge, but the top chrome is consistent. Good for a scanning utility.
- **ChooseLocationDialog** (`packages/client/lib/features/geo/ui/dialog/choose_location_dialog.dart`): fullscreen dialog with an `AppBar`, transparent foreground, and body drawn behind it. This is a good fit for a map picker.
- **BeaconGalleryViewer** (`packages/client/lib/ui/widget/beacon_gallery_viewer.dart`): fullscreen image viewer with a black `AppBar` and an optional image-count title. Good for an immersive gallery.
- **TenturaFullscreenImageViewer** (`packages/client/lib/ui/widget/tentura_fullscreen_image_viewer.dart`): same pattern as the beacon gallery viewer, with a black `AppBar` and page count title when multiple images exist.
- **RoomAttachmentFullscreenGallery** (`packages/client/lib/features/beacon_threads/ui/widget/room_attachment_widgets.dart`): fullscreen gallery viewer for chat attachments; follows the same top-bar model as other image viewers.

### No top app bar or legacy-only surfaces

- **HomeScreen** (`packages/client/lib/features/home/ui/screen/home_screen.dart`): no top app bar. Intentional because the shell chrome is the navigation rail or bottom bar, which is the adaptive control point for this surface.
- **IntroScreen** (`packages/client/lib/features/intro/ui/screen/intro_screen.dart`): no top app bar. Immersive onboarding.
- **AcceptInviteScreen** (`packages/client/lib/features/invitation/ui/screen/accept_invite_screen.dart`): no top app bar; loading/redirect surface that hands off to a dialog or registration route.

---

## Notes

1. **General chat is inline on request detail** — Chat is a `BeaconSurface.room` tab (compact/regular) or the permanent right pane (expanded split) on `BeaconViewHostScreen`.
2. **Questions surface** — Pre-commitment questions live on `BeaconLobbyScreen` (`/beacon/lobby/:id`).
3. **Two dialog modules appear unwired:** `FriendRemoveDialog`, `MyProfileDeleteDialog`.
4. **Fullscreen-dialog routes** (slide-up on mobile): Register, AcceptInvite, ProfileEdit, Settings, Credentials, BeaconCreate, PostCreate, ForwardBeacon, Complaint.
