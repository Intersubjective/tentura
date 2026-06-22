# Flutter Client UI Inventory (`packages/client`)

Complete inventory of screens, routes, dialogs, bottom sheets, and overlay entry points in the Tentura Flutter client.

**Generated:** 2026-06-22 (source scan of `packages/client/lib`)

---

## Methodology

Searched `packages/client/lib` for:

| Pattern | Purpose |
|---------|---------|
| `@RoutePage()` | Auto Route screens |
| `*_screen.dart` glob | Screen files |
| `root_router.dart` `AutoRoute(...)` | Registered route tree (source only; no deep `*.gr.dart` reads) |
| `showModalBottomSheet`, `showBottomSheet`, `showDialog`, `showGeneralDialog`, `showAdaptiveDialog` | Imperative overlays |
| `*dialog*`, `*sheet*`, `*modal*`, `*popup*`, `*bottom_sheet*` file globs | Named overlay widgets |
| `Navigator.push` + `MaterialPageRoute` | Non–Auto Route full-screen pushes |
| `PopupMenuButton`, `showMenu`, `showAnchoredPopupMenu` | Menus |
| `showDatePicker`, `showDateRangePicker`, `showCupertinoModalPopup` | System pickers |
| `DraggableScrollableSheet`, `ModalBottomSheet` | Sheet implementations |
| `ScreenCubit.navigateTo` / `pushPath` | Programmatic navigation targets |

Cross-checked `root_router.dart` against all `@RoutePage()` annotations. **Widgetbook:** no screen mirrors found under `packages/widgetbook`.

---

## Flat List

### Routes / Screens

#### Registered in `root_router.dart`

| Name | Path | File | Notes |
|------|------|------|-------|
| **HomeScreen** (tab shell) | `/home` | `lib/features/home/ui/screen/home_screen.dart` | Bottom nav / side rail; hosts 4 tabs |
| ↳ **MyWorkScreen** (default tab) | `/home/work` | `lib/features/my_work/ui/screen/my_work_screen.dart` | Primary home feed |
| ↳ **InboxScreen** | `/home/inbox` | `lib/features/inbox/ui/screen/inbox_screen.dart` | Inbox triage tab |
| ↳ **FriendsScreen** | `/home/network` | `lib/features/friends/ui/screen/friends_screen.dart` | Network / friends tab |
| ↳ **ProfileScreen** | `/home/profile` | `lib/features/profile/ui/screen/profile_screen.dart` | "Me" tab |
| **InboxRejectedScreen** | `/home/inbox/rejected` | `lib/features/inbox/ui/screen/inbox_rejected_screen.dart` | Full-screen rejected archive (no tabs) |
| **IntroScreen** | (guard-only) | `lib/features/intro/ui/screen/intro_screen.dart` | Native 3-page onboarding; web skips |
| **AuthLoginScreen** | `/sign/in` | `lib/features/auth/ui/screen/auth_login_screen.dart` | Login / seed entry |
| **RecoverScreen** | `/recover-seed` | `lib/features/auth/ui/screen/recover_screen.dart` | Seed recovery hub |
| **AuthRegisterScreen** | `/sign/up/:id` | `lib/features/auth/ui/screen/auth_register_screen.dart` | Fullscreen dialog; invite signup |
| **AcceptInviteScreen** | `/accept-invite/:id` | `lib/features/invitation/ui/screen/accept_invite_screen.dart` | Fullscreen dialog; existing user accepts invite |
| **ProfileViewScreen** | `/profile/view/:id` | `lib/features/profile_view/ui/screen/profile_view_screen.dart` | Other user's profile |
| **ProfileEditScreen** | `/profile/edit` | `lib/features/profile_edit/ui/screen/profile_edit_screen.dart` | Fullscreen dialog |
| **SettingsScreen** | `/settings` | `lib/features/settings/ui/screen/settings_screen.dart` | Fullscreen dialog |
| **CredentialsScreen** | `/settings/sign-in-methods` | `lib/features/credentials/ui/screen/credentials_screen.dart` | Fullscreen dialog; linked accounts |
| **BeaconCreateScreen** | `/beacon/new` | `lib/features/beacon_create/ui/screen/beacon_create_screen.dart` | Fullscreen dialog; create/edit draft |
| **ItemDiscussionScreen** | `/beacon/view/:beaconId/discussion/:itemId` | `lib/features/coordination_item/ui/screen/item_discussion_screen.dart` | Coordination item thread |
| **BeaconViewScreen** | `/beacon/view/:id` | `lib/features/beacon_view/ui/screen/beacon_view_screen.dart` | Unified beacon view; room is a surface/tab here |
| **BeaconRoomScreen** ⚠ | `/beacon/room/:id` | `lib/features/beacon_room/ui/screen/beacon_room_screen.dart` | **Registered but router guard always redirects** to `BeaconViewScreen` with `?tab=room` |
| **ReviewContributionsScreen** | `/beacon/review/:id` | `lib/features/evaluation/ui/screen/review_contributions_screen.dart` | Post-close contribution review |
| **ForwardBeaconScreen** | `/forward/:id` | `lib/features/forward/ui/screen/forward_beacon_screen.dart` | Fullscreen dialog |
| **BeaconScreen** ("view all") | `/beacon/all/:id` | `lib/features/beacon/ui/screen/beacon_screen.dart` | All beacons by profile |
| **RatingScreen** | `/rating` | `lib/features/rating/ui/screen/rating_screen.dart` | Merit scatter / rating view |
| **ForwardsGraphScreen** | `/graph/forwards/:id` | `lib/features/graph/ui/screen/forwards_graph_screen.dart` | Forward lineage graph |
| **GraphScreen** | `/graph/:id` | `lib/features/graph/ui/screen/graph_screen.dart` | Trust graph |
| **ComplaintScreen** | `/complaint/:id` | `lib/features/complaint/ui/screen/complaint_screen.dart` | Fullscreen dialog |

#### `@RoutePage()` but **not registered** in `root_router.dart` (orphan / dead route codegen)

| Name | File | Notes |
|------|------|-------|
| **UpdatesScreen** | `lib/features/updates/ui/screen/updates_screen.dart` | Stub "nothing here" screen; no router entry |
| **FavoritesScreen** | `lib/features/favorites/ui/screen/favorites_screen.dart` | Pinned-beacons list; no router entry (`kPathFavorites` unused) |

#### Dialog-only "screens" (no `@RoutePage`, opened via `showDialog`)

| Name | File | Notes |
|------|------|-------|
| **BeaconIconPickerScreen** | `lib/features/beacon_create/ui/screen/beacon_icon_picker_screen.dart` | Icon/color picker dialog from beacon create |

#### Non–Auto Route full-screen pushes (`Navigator.push` + `MaterialPageRoute`)

| Name | File | Notes |
|------|------|-------|
| **BeaconGalleryViewer** | `lib/ui/widget/beacon_gallery_viewer.dart` | Full-screen beacon photo gallery |
| **RoomAttachmentFullscreenGallery** | `lib/features/beacon_room/ui/widget/room_attachment_widgets.dart` | Full-screen room attachment swipe gallery |

---

### Bottom Sheets

#### Dedicated sheet modules (`show*` entry points)

| Name | File | Description |
|------|------|-------------|
| **showBeaconCloseConfirmSheet** | `lib/features/beacon/ui/sheet/beacon_close_confirm_sheet.dart` | Author close confirmation with review-window branch |
| **showBeaconRoomPromiseSheet** | `lib/features/beacon_room/ui/widget/beacon_room_promise_sheet.dart` | Create promise to participant(s) from room |
| **showFactActionsSheet** (+ inline edit fact sheet) | `lib/features/beacon_room/ui/widget/fact_actions_sheet.dart` | Pinned fact actions; edit fact text sub-sheet |
| **showReactionSendersSheet** | `lib/features/beacon_room/ui/widget/reaction_senders_sheet.dart` | Who reacted with emoji |
| **showRoomFactsSheet** | `lib/features/beacon_room/ui/widget/room_facts_sheet.dart` | Browse/manage pinned facts carousel |
| **showEvaluationDetailSheet** | `lib/features/evaluation/ui/widget/evaluation_detail_sheet.dart` | Per-participant evaluation detail during review |
| **showMutualFriendsSheet** | `lib/features/profile_view/ui/widget/mutual_friends_sheet.dart` | Mutual friends list |
| **showLineageSuggestionsPreviewSheet** | `lib/features/forward/ui/widget/lineage_suggestions_sheet.dart` | Forward lineage suggestions preview |
| **showCoordinationResponseBottomSheet** | `lib/features/beacon_view/ui/widget/coordination_response_bottom_sheet.dart` | Signal coordination response (People tab) |
| **showBeaconNowDetailSheet** | `lib/features/beacon_view/ui/widget/beacon_now_detail_sheet.dart` | "Now" operational detail |
| **showBeaconCurrentLineSheet** | `lib/features/beacon_view/ui/widget/beacon_current_line_sheet.dart` | Edit beacon current-line text |
| **showCoordinationItemComposerSheet** | `lib/features/beacon_view/ui/widget/coordination_item_composer_sheet.dart` | Compose ask/promise/blocker draft |
| **showCoordinationItemEditSheet** | `lib/features/coordination_item/ui/widget/coordination_item_edit_sheet.dart` | Edit existing coordination item |
| **showBeaconYouItemsSheet** | `lib/features/coordination_item/ui/widget/beacon_you_items_sheet.dart` | "Your items" list for beacon |
| **ConnectBottomSheet.show** | `lib/features/connect/ui/widget/connect_bottom_sheet.dart` | Connect-by-code flow; **bottom sheet on compact, centered Dialog on regular+** |

#### Inline bottom sheets (no separate file; opened from parent screen/widget)

| Name | Host file | Description |
|------|-----------|-------------|
| **Update status sheet** (public + coordination status) | `beacon_view_screen.dart` | `_showUpdateStatusSheet` |
| **Recipient forward-reasons sheet** | `forward_beacon_screen.dart` | Capability/reason picker for forward recipient |
| **Requirements picker sheet** | `beacon_create/ui/widget/info_tab.dart` | `_showRequirementsSheet` |
| **Link email sheet** | `credentials_screen.dart` | `_linkEmail` email input |
| **Edit capabilities sheet** | `profile_view/ui/dialog/edit_capabilities_dialog.dart` | Opens as modal bottom sheet despite "Dialog" name |
| **Edit private labels sheet** | `profile_view/ui/dialog/edit_private_labels_dialog.dart` | Same pattern; **defined but no call sites found** |
| **Room message actions sheet** | `beacon_room_body.dart` | Long-press message overflow actions |
| **Create poll sheet** (`_PollCreateSheet`) | `beacon_room_body.dart` | `_showCreatePollSheet` |
| **Plan update sheet** | `beacon_room_body.dart` | `_showPlanUpdateSheet` |
| **Edit message sheet** | `beacon_room_body.dart` | `_showEditMessageSheet` |
| **Pin fact choices sheet** | `beacon_room_body.dart` | `_showPinFactChoices` |
| **Promote message sheet** | `beacon_room_body.dart` | `_showPromoteSheet` (entry to mark ask/blocker/plan) |

Supporting utility (not an entry point): `lib/ui/widget/unfocus_sheet_body.dart` — wraps sheet bodies to dismiss keyboard.

---

### Dialogs

#### Dedicated dialog modules (`show` / `showAdaptiveDialog`)

| Name | File | Description |
|------|------|-------------|
| **BeaconCloseConfirmDialog** | `lib/features/beacon/ui/dialog/beacon_close_confirm_dialog.dart` | Simple close confirm (cards/lists) |
| **BeaconDeleteDialog** | `lib/features/beacon/ui/dialog/beacon_delete_dialog.dart` | Delete draft or published beacon |
| **BeaconPublishDialog** | `lib/features/beacon_create/ui/dialog/beacon_publish_dialog.dart` | Confirm publish on create |
| **HelpOfferMessageDialog** | `lib/features/beacon_view/ui/dialog/help_offer_message_dialog.dart` | Offer / withdraw / can't-help message |
| **AccountRemoveDialog** | `lib/features/auth/ui/dialog/account_remove_dialog.dart` | Remove saved account from device |
| **InvitationAcceptDialog** | `lib/features/invitation/ui/dialog/invitation_accept_dialog.dart` | Confirm befriending inviter |
| **InvitationRemoveDialog** | `lib/features/invitation/ui/dialog/invitation_remove_dialog.dart` | Remove pending invitation |
| **InvitationAddresseeDialog** | `lib/features/invitation/ui/dialog/invitation_addressee_dialog.dart` | Name invitee when creating invite |
| **FriendRemoveDialog** ⚠ | `lib/features/friends/ui/dialog/friend_remove_dialog.dart` | **Defined; no call sites found** |
| **RenameContactDialog** | `lib/features/profile_view/ui/dialog/rename_contact_dialog.dart` | Private rename for subjective contact |
| **EditCapabilitiesDialog** | `lib/features/profile_view/ui/dialog/edit_capabilities_dialog.dart` | Edit viewer-visible capability cues (sheet UI) |
| **EditPrivateLabelsDialog** ⚠ | `lib/features/profile_view/ui/dialog/edit_private_labels_dialog.dart` | **Defined; no call sites found** |
| **MyProfileDeleteDialog** ⚠ | `lib/features/profile/ui/dialog/my_profile_delete.dart` | **Defined; no call sites found** |
| **ContextAddDialog** | `lib/features/context/ui/dialog/context_add_dialog.dart` | Add beacon context tag |
| **ContextRemoveDialog** | `lib/features/context/ui/dialog/context_remove_dialog.dart` | Remove context tag |
| **ChooseLocationDialog** | `lib/features/geo/ui/dialog/choose_location_dialog.dart` | Map pin / location picker |
| **ShowSeedDialog** | `lib/ui/dialog/show_seed_dialog.dart` | Display recovery seed |
| **ShareCodeDialog** | `lib/ui/dialog/share_code_dialog.dart` | Share profile/beacon QR + code |
| **QRScanDialog** | `lib/ui/dialog/qr_scan_dialog.dart` | Camera QR scan |
| **showRejectionDialog** | `lib/features/inbox/ui/widget/rejection_dialog.dart` | Inbox reject-with-message |
| **confirmDeleteCoordinationDraft** | `lib/features/beacon_view/ui/widget/coordination_item_composer_sheet.dart` | Delete coordination draft confirm |

#### Inline dialogs (AlertDialog in screen/widget code)

| Name | Host file | Description |
|------|-----------|-------------|
| Reset local auth confirm | `settings_screen.dart`, `recover_screen.dart` | `_confirmResetLocal` |
| Remove credential confirm | `credentials_screen.dart` | `_confirmRemove` |
| Seed backup reminder | `credentials_screen.dart` | After linking seed |
| All-no-basis evaluation confirm | `review_contributions_screen.dart` | Before finalize |
| Propose resolution dialog | `item_discussion_screen.dart` | `_showProposeResolutionSheet` (dialog, not sheet) |
| Evaluation privacy info | `evaluation_privacy_info_row.dart` | Full privacy text |
| Review reopen confirm | `review_window_banner_host.dart` | Reopen closed beacon for review |
| Lineage forward help | `lineage_forward_section.dart` | Info about auto-select |
| Discard composer confirm | `coordination_item_composer_sheet.dart` | Unsaved draft (if present in body) |
| Unpin fact confirm | `beacon_room_body.dart` | `_confirmUnpinFactFromMessage` |
| Delete message confirm | `beacon_room_body.dart` | `_confirmDeleteMessage` |
| Promote fields dialog | `beacon_room_body.dart` | `_showPromoteFieldsDialog` (mark ask/blocker/plan/done) |
| Need-info dialog | `beacon_room_body.dart` | `_showNeedInfoSheet` (dialog) |
| Mark done dialog | `beacon_room_body.dart` | `_showMarkDoneSheet` |
| Remove fact confirm | `fact_actions_sheet.dart` | `_confirmRemoveFact` |

#### Dialog-style overlay (transparent barrier)

| Name | File | Description |
|------|------|-------------|
| **showRoomReactionPicker** | `lib/features/beacon_room/ui/widget/room_reaction_picker.dart` | Anchored emoji reaction strip (`showDialog`, transparent barrier) |

---

### Menus / Pickers / Other Overlays

#### Popup menus (`PopupMenuButton` / `showMenu`)

| Name | Host file | Trigger context |
|------|-----------|-----------------|
| **My Work filter menu** | `my_work_screen.dart` | `showAnchoredPopupMenu` on filter chip |
| **My Work overflow** | `my_work_screen.dart` | Archive filter shortcut |
| **Inbox overflow** | `inbox_screen.dart` | Open rejected archive |
| **Profile app bar menu** | `profile/ui/widget/profile_app_bar.dart` | Rating shortcut |
| **Profile view app bar menu** | `profile_view_app_bar.dart` | Rename, remove friend, complaint |
| **Friends screen** | `friends_screen.dart` | Per-invitation actions (via list tiles) |
| **Beacon overflow menu** | `beacon/ui/widget/beacon_overflow_menu.dart` | Canonical beacon ⋮ menu (lists, cards) |
| **Beacon HUD close overflow** | `beacon_view/.../beacon_operational_header_card.dart` | Close beacon from HUD |
| **Beacon room overflow** | `beacon_room_overflow_menu.dart` | Create promise |
| **Room message actions** | `beacon_room_body.dart` | Long-press → sheet (see above) |
| **Item discussion overflow** | `item_discussion_screen.dart` | Remind / accept / resolve / propose resolution |
| **Item card overflow** | `coordination_item/ui/widget/item_card.dart` | Edit/delete item actions |
| **Graph screen menu** | `graph_screen.dart` | Jump to ego, toggle positive-only |
| **Forwards graph menu** | `forwards_graph_screen.dart` | Jump to ego |
| **Auth account list tile menu** | `auth/ui/widget/account_list_tile.dart` | Share code, show seed, remove account |
| **Chat attachment menu** | `ui/widget/basic_chat_body.dart` | Attach photo/file in room composer |
| **showAnchoredPopupMenu** (utility) | `ui/widget/show_anchored_popup_menu.dart` | Generic anchored menu helper |

#### System pickers

| Picker | Host file |
|--------|-----------|
| **showDatePicker** | `beacon_create/ui/widget/info_tab.dart` |
| **showDateRangePicker** | `beacon_create/ui/widget/info_tab.dart` |

*(No `showTimePicker` or `showCupertinoModalPopup` call sites found.)*

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
│   │   ├── → BeaconViewScreen, BeaconCreateScreen, ForwardBeaconScreen,
│   │   │         ReviewContributionsScreen, ComplaintScreen, GraphScreen, …
│   │   ├── [Menu: filter (showAnchoredPopupMenu), overflow archive]
│   │   └── [Dialogs: ShareCode, BeaconCloseConfirm, BeaconDelete]
│   │
│   ├── Tab 1: InboxScreen (/home/inbox)
│   │   ├── → InboxRejectedScreen (/home/inbox/rejected)
│   │   ├── → BeaconViewScreen (inbox entry)
│   │   ├── [Menu: inbox overflow → rejected archive]
│   │   ├── [Dialog: showRejectionDialog, HelpOfferMessageDialog]
│   │   └── → ForwardBeaconScreen
│   │
│   ├── Tab 2: FriendsScreen (/home/network)
│   │   ├── [Sheet/Dialog: ConnectBottomSheet.show]
│   │   ├── [Dialogs: InvitationAddressee, InvitationRemove, ShareCode,
│   │   │            InvitationAccept (via connect flow)]
│   │   └── → ProfileViewScreen
│   │
│   └── Tab 3: ProfileScreen (/home/profile)
│       ├── → ProfileEditScreen, SettingsScreen, RatingScreen,
│       │         GraphScreen, BeaconScreen (all beacons)
│       ├── [Menu: rating]
│       └── [Dialog: ShareCode via icon button]
│
├── InboxRejectedScreen (/home/inbox/rejected) [full-screen, no tabs]
│   └── → BeaconViewScreen
│
├── ProfileViewScreen (/profile/view/:id)
│   ├── → GraphScreen, BeaconScreen, ComplaintScreen
│   ├── [Menu: rename, remove friend, complaint]
│   ├── [Dialog: RenameContactDialog]
│   ├── [Sheet: EditCapabilitiesDialog.show, MutualFriendsSheet]
│   └── [Dialog: ShareCode]
│
├── ProfileEditScreen (/profile/edit) [fullscreen dialog]
│
├── SettingsScreen (/settings) [fullscreen dialog]
│   ├── → CredentialsScreen
│   ├── [Dialog: ShowSeedDialog, reset local confirm]
│   └── (replay intro flag → IntroScreen on next launch)
│
├── CredentialsScreen (/settings/sign-in-methods) [fullscreen dialog]
│   ├── [Sheet: link email]
│   └── [Dialogs: ShowSeedDialog, seed backup, remove credential confirm]
│
├── BeaconCreateScreen (/beacon/new) [fullscreen dialog]
│   ├── [Dialog: BeaconPublishDialog, BeaconIconPickerScreen.show,
│   │          ChooseLocationDialog]
│   ├── [Sheet: requirements picker]
│   └── [Pickers: showDatePicker, showDateRangePicker]
│
├── BeaconViewScreen (/beacon/view/:id) ← unified beacon hub
│   ├── Surface: operational tabs (items / people / log)
│   │   ├── [Sheet: UpdateStatus, BeaconCurrentLine, BeaconNowDetail,
│   │   │          CoordinationItemComposer, CoordinationItemEdit,
│   │   │          BeaconYouItems, CoordinationResponse, FactActions]
│   │   ├── [Dialog: HelpOfferMessage, BeaconDelete, ShareCode,
│   │   │          confirmDeleteCoordinationDraft, BeaconCloseConfirmSheet]
│   │   └── → ItemDiscussionScreen, ForwardBeaconScreen, ComplaintScreen,
│   │             GraphScreen, ForwardsGraphScreen, ReviewContributionsScreen
│   │
│   └── Surface: room (tab=room / surface=room) — embedded chat
│       ├── BeaconRoomBody (BasicChatBody)
│       │   ├── [Sheet: message actions, create poll, plan update, edit message,
│       │   │          pin fact, promote, FactActions, RoomFacts, Promise,
│       │   │          ReactionSenders]
│       │   ├── [Dialog: delete message, unpin fact, promote fields, need-info,
│       │   │          mark done, remove fact]
│       │   ├── [Overlay: showRoomReactionPicker]
│       │   ├── [Menu: room overflow → promise sheet; chat attach menu]
│       │   └── [Push: RoomAttachmentFullscreenGallery]
│       └── → ItemDiscussionScreen
│
├── ItemDiscussionScreen (/beacon/view/:beaconId/discussion/:itemId)
│   ├── [Menu: item actions overflow]
│   └── [Dialog: propose resolution]
│
├── ReviewContributionsScreen (/beacon/review/:id)
│   ├── [Sheet: EvaluationDetailSheet]
│   ├── [Dialog: all-no-basis confirm]
│   └── [Banner host: review reopen dialog]
│
├── ForwardBeaconScreen (/forward/:id) [fullscreen dialog]
│   ├── [Sheet: recipient reasons, LineageSuggestionsPreview]
│   ├── [Dialog: InvitationAddressee, ShareCode, lineage help info]
│   └── [Menu: context dropdown → ContextAdd/Remove dialogs]
│
├── BeaconScreen (/beacon/all/:id) — all beacons for profile
│   └── → BeaconViewScreen
│
├── RatingScreen (/rating)
│
├── GraphScreen (/graph/:id)
│   └── [Menu: ego jump, positive/negative toggle]
│
├── ForwardsGraphScreen (/graph/forwards/:id)
│   └── [Menu: ego jump]
│
├── ComplaintScreen (/complaint/:id) [fullscreen dialog]
│
├── [Legacy route — always redirects]
│   └── BeaconRoomRoute (/beacon/room/:id) → BeaconViewScreen?tab=room
│
├── [Non–Auto Route pushes]
│   ├── BeaconGalleryViewer (from beacon photos)
│   └── RoomAttachmentFullscreenGallery (from room attachments)
│
└── [Orphan @RoutePage — not in router]
    ├── UpdatesScreen
    └── FavoritesScreen
```

---

## Notes

1. **Room is not a separate navigable screen anymore** — `BeaconRoomRoute` redirects into `BeaconViewScreen` with room surface; `BeaconRoomScreen` still exists as dead/legacy implementation.
2. **Three dialog modules appear unwired:** `FriendRemoveDialog`, `MyProfileDeleteDialog`, `EditPrivateLabelsDialog` (profile view uses `removeFriend` cubit method directly instead).
3. **Two orphan routes:** `UpdatesScreen`, `FavoritesScreen` have `@RoutePage()` but no `AutoRoute` registration.
4. **No Tentura-prefixed sheet/dialog wrappers** in `design_system/` — overlays use Flutter primitives directly.
5. **Fullscreen-dialog routes** (slide-up on mobile): Register, AcceptInvite, ProfileEdit, Settings, Credentials, BeaconCreate, ForwardBeacon, Complaint.
