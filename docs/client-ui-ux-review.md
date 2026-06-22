# Client Screen UI/UX Review

Generated: 2026-06-22  
Skills: ui-ux-pro-max, flutter-build-responsive-layout, tentura-design-system

## Summary

- **Screens reviewed:** 29 (all `*_screen.dart` under `packages/client/lib/features/`)
- **Small fixes applied:** 29 files (see [Fixes applied](#fixes-applied))
- **Findings requiring follow-up:** ~85 across screens and child widgets (see per-screen tables)

### Cross-cutting themes (report-only)

| Theme | Scope | Recommendation |
|-------|-------|----------------|
| Legacy spacing constants | Many screens still use `kPadding*` / `kSpacing*` from `ui_utils.dart` | Dedicated token migration pass: replace with `context.tt.*` |
| App-level max-width | `TenturaResponsiveScope` in `app.dart` caps content on regular/expanded | Per-screen `ConstrainedBox` only where tabs need explicit full-bleed vs capped content |
| Child widget debt | Nav items, tiles, overflow menus, graph body, beacon tabs | Audit `profile_navbar_item.dart`, `beacon_overflow_menu.dart`, `graph_body.dart`, `info_tab.dart`, etc. |
| Loading UX split | Graph screens, beacon room, item discussion | Add body-level loading overlays where app-bar strip alone is insufficient |
| Orphan/stub screens | `UpdatesScreen`, `FavoritesScreen` | Register routes or remove dead `@RoutePage()` annotations |
| Raw `Colors.transparent` on TabBars | Inbox, Friends, Inbox Rejected | Migrate with parent AppBar refactor |
| Empty/error states | Beacon, Favorites, Rating, Updates | Add inline error/retry UI where cubit exposes errors |

---

## Findings by screen

### HomeScreen (`packages/client/lib/features/home/ui/screen/home_screen.dart`)

| Severity | Category | Finding | Recommendation |
|----------|----------|---------|----------------|
| medium | responsive | Tab content has no `contentMaxWidth` cap on expanded layouts | Wrap tab bodies in `TenturaResponsiveScope` or `ConstrainedBox` where product wants centered content |
| low | design_system | `VerticalDivider(width: 1, thickness: 1)` uses numeric literals | Add vertical hairline token if pattern repeats |
| low | accessibility | Profile `NavigationRailDestination` has no `selectedIcon` | Add selected state if parity with other destinations is desired |
| low | structural | Eight `BlocListener`s in `wrappedRoute` — high coupling | Consider consolidating at app root |
| low | child_widgets | `ProfileNavBarItem` lacks explicit `Semantics` on long-press target | Fix in `profile_navbar_item.dart` |

### MyWorkScreen (`packages/client/lib/features/my_work/ui/screen/my_work_screen.dart`)

| Severity | Category | Finding | Recommendation |
|----------|----------|---------|----------------|
| info | design_system | Sort button still uses `EdgeInsets.symmetric(horizontal: 4)` and `textTheme.labelLarge?.copyWith` | Migrate to `tt.tightGap * 2` and `TenturaText.labelLarge` |
| info | design_system | Magic sizes: Icon 20/48, `maxWidth: 88`, animation offset `8` | Use `context.tt.iconSize` and named layout tokens |
| info | design_system | Body list uses deprecated `kPaddingSmallV` / `kPaddingSmallH` | Migrate to `context.tt` tokens |
| warning | accessibility | Sort tooltip repeats visible label; filter has dedicated l10n tooltip | Add `myWorkSortMenuTooltip` l10n key |
| warning | touch_targets | `MaterialTapTargetSize.shrinkWrap` on filter/sort buttons | Remove shrinkWrap if tap misses reported |
| warning | responsive | No maxWidth constraint on card list for expanded screens | Wrap body in `Center` + `ConstrainedBox` |
| info | child_widgets | `MyWorkCardRouter`, `MyWorkEmptyBody`, `MyWorkFinishedArchiveHint` may carry token debt | Review separately |

### InboxScreen (`packages/client/lib/features/inbox/ui/screen/inbox_screen.dart`)

| Severity | Category | Finding | Recommendation |
|----------|----------|---------|----------------|
| info | design_system | `Colors.transparent` on AppBar/TabBar; raw `EdgeInsets.all(24)` in empty states | Token migration pass |
| info | design_system | Tombstone pill uses `BorderRadius.circular(999)` | Use design-system radius token |
| info | design_system | Magic numbers: `titleSpacing: 8`, Icon 20, `maxWidth: 88` | Replace with tokens |
| info | responsive | Custom `TabBar` on primary AppBar vs `TenturaUnderlineTabs` | Structural pattern change |
| info | accessibility | Reject/offer/dismiss actions lack in-screen loading affordance | Handled in cubit/snackbars — verify UX |
| info | child_widgets | `inbox_item_tile.dart`, `inbox_tombstone_card.dart` — additional token work | Review separately |

### FriendsScreen (`packages/client/lib/features/friends/ui/screen/friends_screen.dart`)

| Severity | Category | Finding | Recommendation |
|----------|----------|---------|----------------|
| info | design_system | `Colors.transparent` on TabBar; legacy `kPaddingAll` in invites empty state | Token migration |
| info | design_system | Hard-coded `maxWidth: 320`, `Icon(size: 64)` in invites empty | Use window-class tokens |
| warning | accessibility | Friends tab has no in-body loading/empty-error feedback during fetch | Add loading indicator like invites tab |
| info | responsive | Empty friends uses `MediaQuery.sizeOf(context).height * 0.5` | Use window-class tokens |
| info | child_widgets | `NetworkPersonCard`, invitation dialogs not reviewed | Audit separately |
| info | structural | `_FriendsTabBody` passes Theme/L10n as constructor params | Refactor to context reads |

### ProfileScreen (`packages/client/lib/features/profile/ui/screen/profile_screen.dart`)

| Severity | Category | Finding | Recommendation |
|----------|----------|---------|----------------|
| info | child_widgets | `ProfileAppBar`: raw spacing, 40dp touch targets | Fix in `profile_app_bar.dart` |
| info | child_widgets | `ProfileBody`: deprecated `kPaddingT`, `kPaddingSmallT` | Token migration in child file |
| info | structural | No Scaffold/loading/error in screen — delegated to Home tab shell | Acceptable for thin shell |

### InboxRejectedScreen (`packages/client/lib/features/inbox/ui/screen/inbox_rejected_screen.dart`)

| Severity | Category | Finding | Recommendation |
|----------|----------|---------|----------------|
| info | design_system | `Colors.transparent` on AppBar; legacy `kPaddingSmallH/V` | Migrate with inbox AppBar refactor |
| info | accessibility | AppBar title uses plain `Text` vs `TenturaText.title` | Typography consistency pass |
| warning | UX | `buildWhen` includes `hasError` but no error UI in body | Add inline error state or document snackbar-only pattern |
| info | child_widgets | `InboxItemTile` overflow/actions not audited | Review separately |

### IntroScreen (`packages/client/lib/features/intro/ui/screen/intro_screen.dart`)

| Severity | Category | Finding | Recommendation |
|----------|----------|---------|----------------|
| info | design_system | Legacy `kPaddingAll`, `kPaddingAllS`, `kPaddingV` remain | Broader token migration |
| info | design_system | Page dot width/height `8` are raw literals | Add page-indicator token if needed |
| warning | loading_feedback | "Start" triggers async persist with no loading/disabled state | Disable button during `setIntroEnabled` |
| info | accessibility | No `Semantics` for "page N of 3" on dots | Optional enhancement |

### AuthLoginScreen (`packages/client/lib/features/auth/ui/screen/auth_login_screen.dart`)

| Severity | Category | Finding | Recommendation |
|----------|----------|---------|----------------|
| info | design_system | Remaining `kPaddingAll` / `kPaddingH` on empty state, QR/clipboard buttons | Token migration pass |
| info | typography | Bare `Text()` without `TenturaText` / explicit `textTheme` roles | Align with auth form pattern |
| warning | child_widgets | `AccountListTile` `PopupMenuButton` lacks tooltip/semanticLabel | Fix in `account_list_tile.dart` |

### RecoverScreen (`packages/client/lib/features/auth/ui/screen/recover_screen.dart`)

| Severity | Category | Finding | Recommendation |
|----------|----------|---------|----------------|
| info | design_system | Legacy `kSpacing*` constants; `BorderRadius.circular(kBorderRadius)` on QR clip | Use `tt.cardRadius` |
| warning | loading_feedback | Primary actions stay enabled during load | Disable via `BlocSelector` |
| info | accessibility | QR scanner lacks `Semantics` / live-region for scan success | Add a11y wrapper |
| info | analyzer | Pre-existing `use_build_context_synchronously` in `_confirmResetLocal` | Structural fix |

### AuthRegisterScreen (`packages/client/lib/features/auth/ui/screen/auth_register_screen.dart`)

| Severity | Category | Finding | Recommendation |
|----------|----------|---------|----------------|
| info | design_system | Four `Padding(padding: kPaddingAll)` use legacy constants | Align with login/recover token pattern |
| warning | forms | No `Form` / `validate()` before `signUp` | Add validation wrapper |
| warning | loading_feedback | Register button stays enabled during loading | Wire `onPressed: state.isLoading ? null : …` |
| info | structural | Large repeated `Padding` + `TextFormField` blocks | Extract shared auth form chrome |

### AcceptInviteScreen (`packages/client/lib/features/invitation/ui/screen/accept_invite_screen.dart`)

| Severity | Category | Finding | Recommendation |
|----------|----------|---------|----------------|
| warning | UX | Blank body when confirmation dialog open (`needsConfirmation`) | Show dimmed backdrop or keep spinner |
| info | child_widgets | `invitation_accept_dialog.dart` uses `kSpacingSmall` not tokens | Token migration in dialog file |
| info | error_feedback | Errors via `commonScreenBlocListener` only; empty body when not loading | Consider inline error state |

### ProfileViewScreen (`packages/client/lib/features/profile_view/ui/screen/profile_view_screen.dart`)

| Severity | Category | Finding | Recommendation |
|----------|----------|---------|----------------|
| info | child_widgets | Visual compliance in `profile_view_app_bar.dart`, `profile_view_body.dart` | Review child widgets |
| info | structural | `isDeepLink` query param declared but unused | Remove or wire up |

### ProfileEditScreen (`packages/client/lib/features/profile_edit/ui/screen/profile_edit_screen.dart`)

| Severity | Category | Finding | Recommendation |
|----------|----------|---------|----------------|
| warning | loading_feedback | `pickImage()` has no loading state while gallery/cropper open | Add in-flight indicator |
| warning | responsive | `resizeToAvoidBottomInset: false` + non-scrollable `Column` may clip fields with keyboard | Enable inset or wrap in scroll view |
| info | design_system | Avatar uses fixed `kTenturaAvatarBigSize` (160) vs `tt.avatarSize` | Token migration |
| info | layout | Avatar stack not centered horizontally on wide layouts | Center avatar block |

### SettingsScreen (`packages/client/lib/features/settings/ui/screen/settings_screen.dart`)

| Severity | Category | Finding | Recommendation |
|----------|----------|---------|----------------|
| warning | child_widgets | `ThemeSwitchButton` lacks top-level `Semantics` label | Fix with `LanguageSwitchButton` pass |
| warning | loading_feedback | Sign-out/reset-local on `AuthCubit` — screen only listens to `SettingsCubit` | Add AuthCubit listener for progress |
| info | structural | Flat button stack vs `TenturaCommandButton` grouped list | Settings IA refactor |
| info | dialogs | `_confirmResetLocal` uses raw `AlertDialog` | Shared design-system dialog wrapper |

### CredentialsScreen (`packages/client/lib/features/credentials/ui/screen/credentials_screen.dart`)

| Severity | Category | Finding | Recommendation |
|----------|----------|---------|----------------|
| info | responsive | List stretches full width on expanded; no `contentMaxWidth` centering | Match settings sub-route pattern |
| info | i18n | Credential dates use `DateTime.toString()` | Use `DateFormat` / relative-time helper |
| info | dialogs | Remove confirm and seed-backup use default `AlertDialog` | Shared dialog pattern |
| info | UX | No pull-to-refresh (reloads on app resume only) | Add `RefreshIndicator` if desired |

### BeaconCreateScreen (`packages/client/lib/features/beacon_create/ui/screen/beacon_create_screen.dart`)

| Severity | Category | Finding | Recommendation |
|----------|----------|---------|----------------|
| warning | child_widgets | `InfoTab` uses raw `EdgeInsets.fromLTRB(16,…)`, `kPadding*` | Dedicated design-system pass |
| warning | child_widgets | `ImageTab` `_ImageCard` uses `Colors.black54`, fixed icon sizes | Fix in `image_tab.dart` |
| info | layout | Image tab gets double horizontal padding (screen + tab) | Consolidate padding ownership |

### BeaconIconPickerScreen (`packages/client/lib/features/beacon_create/ui/screen/beacon_icon_picker_screen.dart`)

| Severity | Category | Finding | Recommendation |
|----------|----------|---------|----------------|
| warning | child_widgets | `BeaconColorSelector` swatches are 36×36 dp (below 48 dp) | Fix in `beacon_color_selector.dart` |
| info | design_system | `_pickerTileColors` uses `Colors.black` / `Colors.white` fallback | Shared design-system helper |
| info | structural | ~17 `ChoiceChip`s repeat identical styling | Extract shared filter-chip wrapper |

### ItemDiscussionScreen (`packages/client/lib/features/coordination_item/ui/screen/item_discussion_screen.dart`)

| Severity | Category | Finding | Recommendation |
|----------|----------|---------|----------------|
| warning | accessibility | Status shown as raw English enum (`OPEN`, `RESOLVED`) | Add `coordinationItemStatusLabel(l10n, status)` |
| warning | loading_feedback | `ItemActionsCubit` never emits loading; menu buttons stay enabled | Emit `StateIsLoading` during mutations |
| warning | error_feedback | No `BlocListener` for action errors | Add listener or `commonScreenBlocListener` |
| warning | UX | `_ItemDiscussionHydrateLoader` has no AppBar/back on deep-link refresh | Add dismiss/back affordance |
| info | DRY | ~120 lines overflow menu logic duplicates `ItemCard` | Extract shared menu builder |

### BeaconViewScreen (`packages/client/lib/features/beacon_view/ui/screen/beacon_view_screen.dart`)

| Severity | Category | Finding | Recommendation |
|----------|----------|---------|----------------|
| warning | design_system | Material `Badge` on room button violates `no_operational_pill_widgets_in_beacon_view` | Use `TenturaCountBadge` |
| warning | child_widgets | `BeaconOverflowMenu` is 32×40 dp, no tooltip | Fix in `beacon_overflow_menu.dart` |
| warning | touch_targets | Status bottom sheet uses `ListTile(dense: true)` — may be below 48 dp | Use standard density |
| warning | UX | Initial fetch error with empty data has no dedicated error UI | Add error/empty operational state |
| info | SafeArea | Scaffold body not wrapped in `SafeArea` | Add if bottom inset issues on notched devices |
| info | maintainability | ~1500-line monolith mixing route, app bar, tabs, room, sheet | Split into focused widgets |

### BeaconRoomScreen (`packages/client/lib/features/beacon_room/ui/screen/beacon_room_screen.dart`)

| Severity | Category | Finding | Recommendation |
|----------|----------|---------|----------------|
| info | loading_feedback | No app-bar `LinearPiActive` unlike `BeaconScreen` / `BeaconViewScreen` | Add top-level indicator for refetch-with-messages |
| info | child_widgets | `BeaconRoomOverflowMenu` returns `SizedBox.shrink()` until participants load | Add skeleton/placeholder |

### ReviewContributionsScreen (`packages/client/lib/features/evaluation/ui/screen/review_contributions_screen.dart`)

| Severity | Category | Finding | Recommendation |
|----------|----------|---------|----------------|
| info | child_widgets | `EvaluationPrivacyInfoRow` uses raw icon sizes and spacing | Token pass in child widget |
| info | responsive | Single-column list; no expanded layout treatment | Common pattern — OK unless product wants grid |
| info | accessibility | Participant rows rely on default `ListTile` semantics | Add combined label for status |

### ForwardBeaconScreen (`packages/client/lib/features/forward/ui/screen/forward_beacon_screen.dart`)

| Severity | Category | Finding | Recommendation |
|----------|----------|---------|----------------|
| warning | child_widgets | `ForwardBottomComposer` hardcoded icon sizes 14/16; no in-flight forward state | Token + loading on forward button |
| warning | UX | `ForwardTopBar.onFilterPressed` is empty stub | Implement or remove filter control |
| info | child_widgets | `forward_recipient_row.dart` raw chip insets; `lineage_suggestions_sheet.dart` raw padding | Token migration in forward widgets |

### BeaconScreen (`packages/client/lib/features/beacon/ui/screen/beacon_screen.dart`)

| Severity | Category | Finding | Recommendation |
|----------|----------|---------|----------------|
| warning | UX | Raw `DropdownButton` filter in AppBar vs My Work/Inbox popup pattern | Align filter UX; verify 48 dp target |
| info | UX | No `RefreshIndicator` | Add pull-to-refresh |
| info | structural | Reuses `InboxItemTile` with synthetic `InboxItem` | Consider `BeaconTile` for profile-beacon list |
| info | error_state | No inline error UI; relies on listener | Add retry pattern like My Work |

### RatingScreen (`packages/client/lib/features/rating/ui/screen/rating_screen.dart`)

| Severity | Category | Finding | Recommendation |
|----------|----------|---------|----------------|
| warning | navigation | No `leading` / `AutoLeadingWithFallback` — may lack back affordance | Add leading control |
| info | responsive | Class column fixed `width: 100`; heatmap flex ratios don't adapt | Window-class layout pass |
| info | UX | `ContextDropDown` commented out — context switching unavailable | Re-enable or remove dead code |
| info | UX | No empty state when search filters all rows | Add empty-search UI |
| info | child_widgets | `RatingListTile`, `RatingScatterView` may carry raw tokens | Review separately |

### ForwardsGraphScreen (`packages/client/lib/features/graph/ui/screen/forwards_graph_screen.dart`)

| Severity | Category | Finding | Recommendation |
|----------|----------|---------|----------------|
| warning | loading_feedback | `GraphBody` renders graph with no overlay during fetch | Add body-level loading in `graph_body.dart` |
| warning | child_widgets | `graph_body.dart` uses `Colors.indigo` for edge highlight | Use `ColorScheme` token |
| info | structural | AppBar title reads private cubit field vs `GraphState` | Derive title from state |
| info | child_widgets | Node labels use bare `Text` without `TenturaText` | Typography pass in graph body |

### GraphScreen (`packages/client/lib/features/graph/ui/screen/graph_screen.dart`)

| Severity | Category | Finding | Recommendation |
|----------|----------|---------|----------------|
| warning | loading_feedback | No progress indicator while `GraphCubit` fetches | Add body overlay or skeleton |
| warning | child_widgets | Same `graph_body.dart` issues: `Colors.indigo`, no empty/error overlay | Shared graph body fix |
| info | structural | Commented context selector in AppBar `bottom:` | Remove or implement |

### ComplaintScreen (`packages/client/lib/features/complaint/ui/screen/complaint_screen.dart`)

| Severity | Category | Finding | Recommendation |
|----------|----------|---------|----------------|
| warning | forms | Uncontrolled fields — cubit reset/pre-fill won't update UI | Add `controller` or `initialValue` from state |
| info | testing | No screen-level widget/golden test | Add when feature matures |

### UpdatesScreen (`packages/client/lib/features/updates/ui/screen/updates_screen.dart`)

| Severity | Category | Finding | Recommendation |
|----------|----------|---------|----------------|
| critical | feature | Stub only — no cubit, repository, or data layer | Implement feature or remove route annotation |
| critical | navigation | Not registered in `root_router.dart` | Register or delete |
| info | UX | No AppBar title l10n key | Add when feature ships |
| info | typography | Empty uses `displaySmall` vs newer `TenturaText.bodyMedium` pattern | Align empty-state typography |

### FavoritesScreen (`packages/client/lib/features/favorites/ui/screen/favorites_screen.dart`)

| Severity | Category | Finding | Recommendation |
|----------|----------|---------|----------------|
| critical | navigation | `@RoutePage()` but not in `root_router.dart`; `kPathFavorites` unused | Register route or remove |
| warning | shell | No `Scaffold` / `AppBar` — unlike peer tab screens | Add shell if routed standalone |
| warning | error_state | `buildWhen: isSuccess` skips error rebuilds; no inline retry | Add error UI like My Work |
| info | UX | Generic `labelNothingHere` empty state | Favorites-specific empty with icon/CTA |
| info | child_widgets | `BeaconPinIconButton` lacks tooltip on pin/unpin | Fix in pin button widget |

---

## Fixes applied

- `home_screen.dart`: Added profile tooltip on side NavigationRail destination
- `my_work_screen.dart`: Touch targets (overflow/filter/sort → `buttonHeight`); filter label → `TenturaText`; sort Tooltip; filter padding token
- `inbox_screen.dart`: Sort tooltip; sort/overflow 48dp targets; tab `labelPadding` → `context.tt.rowGap`
- `friends_screen.dart`: Tab padding token; invite edit/delete tooltips + 44dp targets; delete color → `colorScheme.error`
- `profile_screen.dart`: `kPaddingAll` → `context.tt.cardPadding`
- `inbox_rejected_screen.dart`: Empty padding/typography tokens; app bar height → `tt.appBarHeight`
- `intro_screen.dart`: Page-dot padding → `context.tt.iconTextGap`
- `auth_login_screen.dart`: SafeArea on body; horizontal padding → `tt.screenHPadding`; removed magic bottom inset
- `recover_screen.dart`: Scroll padding → `context.tt.screenHPadding`
- `auth_register_screen.dart`: Paste IconButton tooltip + 48dp constraints
- `accept_invite_screen.dart`: SafeArea on loading body
- `profile_view_screen.dart`: `kPaddingAll` → `context.tt.cardPadding`
- `profile_edit_screen.dart`: Loading bar; SafeArea; avatar tooltips; save guard; tokens; app bar title
- `settings_screen.dart`: Tokens; SafeArea; scroll; button heights; AutoLeadingButton; logout icon fix
- `credentials_screen.dart`: Tokens; SafeArea; loading bar; TenturaHairlineDivider
- `beacon_create_screen.dart`: Tokens; tooltips on save actions; publish loading guard; SafeArea; tab bar height fix
- `beacon_icon_picker_screen.dart`: Close tooltip; grid/search tokens; grid tile Semantics
- `item_discussion_screen.dart`: Overflow menu tooltip + 48dp; header/banner token spacing
- `beacon_view_screen.dart`: Localized room status; token spacing; LinearPiActive.size
- `beacon_room_screen.dart`: AutoLeadingButton + close tooltip/semantics on fallback
- `review_contributions_screen.dart`: Tokens; SafeArea; loading bar; disabled submit; button height; section Semantics
- `forward_beacon_screen.dart`: Reason sheet tokens; empty padding; action loading overlay; shared note decoration
- `beacon_screen.dart`: SafeArea; initial loading spinner; filter tooltip; empty Semantics; TenturaText empty state
- `rating_screen.dart`: Tokens; SafeArea; loading scaffold; sort tooltips/semantics; clear button touch target
- `forwards_graph_screen.dart`: Loading bar; overflow menu tooltip + 48dp constraints
- `graph_screen.dart`: Overflow menu tooltip + 48dp; BlocBuilder for filter label
- `complaint_screen.dart`: SafeArea; tokens; FilledButton; loading bar; disabled inputs while submitting
- `updates_screen.dart`: Tokens; SafeArea; TenturaTextAction + tooltip
- `favorites_screen.dart`: Tokens; scrollable empty for pull-to-refresh; screen Semantics
