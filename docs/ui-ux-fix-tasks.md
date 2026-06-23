# UI/UX Fix Tasks

Source: `docs/client-ui-ux-review.md` (generated 2026-06-22)

---

## Agent Instructions

You are operating in a loop. Each invocation must complete **exactly one task** then stop.

**Protocol for each invocation:**

1. Read this file and find the **first unchecked task** (`- [ ]`). If all tasks are checked, print "All UI/UX tasks complete." and stop — do **not** schedule or arm the next wake; let the loop terminate naturally.
2. **Investigate** the affected file(s): read the screen, its child widgets, the relevant cubit/state, and any design-system tokens involved. Use `ollama_explore.py` or Serena MCP for broader context; read only what you need.
3. **Plan** (in your thinking): write a concise step-by-step fix plan before touching any file.
4. **Implement** the fix — surgical edits only; do not touch unrelated code.
5. **Check for lints**: run `cd packages/client && flutter analyze --no-fatal-warnings --no-fatal-infos` on changed paths; fix any issues you introduced.
6. **Run affected tests** if the file has a test counterpart: `cd packages/client && flutter test <path>`.
7. **Mark the task complete** in this file: change `- [ ]` to `- [x]`.
8. **Commit** all changes (task file + source files) with a message of the form:
   `fix(ui): <short description> [TASK-NN]`
9. **End your turn.** Do not start the next task. The loop will re-invoke you with a fresh context window.

**Constraints:**
- Read `DEV_GUIDELINES.md` and `.cursor/rules/tentura-design-system.mdc` before any UI edit.
- Never inline `fontSize`, raw `Color(0x…)`, `Colors.*`, raw `EdgeInsets`-from-numbers, or `BorderRadius`-from-numbers in feature/shared UI — use `context.tt.*` tokens and `TenturaText.*`.
- Use `commonScreenBlocListener` for standard navigation/messaging/error handling in screens.
- After codegen-affecting changes run `dart run build_runner build -d` inside `packages/client`.

---

## Tasks

### Loading & Feedback

- [x] TASK-01: `IntroScreen` — disable the "Start" button and show a loading indicator while `setIntroEnabled` is in flight; wire `onPressed: state.isLoading ? null : …`
- [x] TASK-02: `RecoverScreen` — disable primary action buttons during loading via `BlocSelector`; button should be null-pressed while `state.isLoading`
- [x] TASK-03: `AuthRegisterScreen` — wire register button to `onPressed: state.isLoading ? null : …`; wrap fields in a `Form` with `validate()` called before `signUp`
- [x] TASK-04: `ProfileEditScreen` — add an in-flight indicator (e.g. `LinearPiActive` or overlay) while `pickImage()` is open (gallery/cropper)
- [x] TASK-05: `SettingsScreen` — add a `BlocListener` (or `MultiBlocListener`) for `AuthCubit` to surface sign-out / reset-local progress and errors; the screen currently only listens to `SettingsCubit`
- [x] TASK-06: `ItemDiscussionScreen` / `ItemActionsCubit` — emit `StateIsLoading` before mutations (resolve, close, reopen) and return to `StateIsSuccess` on completion so menu buttons disable during the call
- [x] TASK-07: `BeaconRoomScreen` — add a top-level `LinearPiActive` progress indicator (matching `BeaconScreen` / `BeaconViewScreen` pattern) for refetch-with-messages states
- [x] TASK-08: `graph_body.dart` — add a body-level loading overlay or `LinearPiActive` while the graph is fetching; this fixes both `ForwardsGraphScreen` and `GraphScreen`

### Error & Empty States

- [x] TASK-09: `InboxRejectedScreen` — `buildWhen` already watches `hasError`; add inline error UI in the body (or document the snackbar-only pattern with a comment)
- [x] TASK-10: `ItemDiscussionScreen` — add a `BlocListener` (or extend `commonScreenBlocListener`) for `ItemActionsCubit` errors so they surface to the user
- [x] TASK-11: `BeaconViewScreen` — add a dedicated error/empty state widget when the initial fetch fails and `state.data` is empty
- [x] TASK-12: `BeaconScreen` — add inline error UI with a retry action (matching the My Work pattern); screen currently relies only on the listener
- [x] TASK-13: `AcceptInviteScreen` — when `state.needsConfirmation` is true and the confirmation dialog is open, show a dimmed backdrop or keep a loading spinner visible so the body is not blank

### Touch Targets & Accessibility

- [x] TASK-14: `MyWorkScreen` — remove `MaterialTapTargetSize.shrinkWrap` from filter and sort buttons; ensure minimum 48 dp tap targets
- [x] TASK-15: `BeaconViewScreen` — replace `ListTile(dense: true)` in the status bottom sheet with standard-density tiles (≥ 48 dp); verify all touch targets
- [x] TASK-16: `beacon_color_selector.dart` — increase swatch tap targets from 36×36 dp to ≥ 48 dp (add `InkWell` padding or `ConstrainedBox`)
- [x] TASK-17: `beacon_overflow_menu.dart` — increase `BeaconOverflowMenu` to ≥ 48 dp minimum tap target and add a `tooltip` to the button
- [x] TASK-18: `RatingScreen` — add `leading: AutoLeadingButton()` (or `AutoLeadingWithFallback`) so the screen has a back affordance when pushed
- [x] TASK-19: `FriendsScreen` — add a loading indicator and an empty/error state to the Friends tab body during fetch (currently only the Invites tab has this)
- [x] TASK-20: `HomeScreen` — add a `selectedIcon` to the Profile `NavigationRailDestination` so it has a selected visual state matching other rail destinations
- [x] TASK-21: `account_list_tile.dart` — add `tooltip` and `semanticLabel` to the `PopupMenuButton` in `AccountListTile`
- [x] TASK-22: `ItemDiscussionScreen` — replace the raw English enum string (`OPEN`, `RESOLVED`) with a localized helper `coordinationItemStatusLabel(l10n, status)`; add the l10n key if missing
- [x] TASK-23: `ThemeSwitchButton` — add a top-level `Semantics` label (mirror the approach used for `LanguageSwitchButton`)

### Forms

- [x] TASK-24: `ComplaintScreen` — add `TextEditingController`s (or `initialValue`) tied to cubit state so cubit reset / pre-fill actually updates the visible fields
- [x] TASK-25: `MyWorkScreen` — add the missing `myWorkSortMenuTooltip` l10n key and wire it to the sort tooltip so it is distinct from the visible label

### Navigation & UX Flows

- [ ] TASK-26: `ItemDiscussionScreen` — add an AppBar with a back/dismiss button to `_ItemDiscussionHydrateLoader` so users can exit on deep-link refresh without being stuck
- [ ] TASK-27: `BeaconScreen` — replace the raw `DropdownButton` filter in the AppBar with a `PopupMenuButton` pattern consistent with My Work / Inbox
- [x] TASK-28: `ForwardBeaconScreen` / `ForwardTopBar` — implement the filter callback (`onFilterPressed`) or remove the dead control entirely
- [ ] TASK-29: `BeaconScreen` — add `RefreshIndicator` wrapping the list body for pull-to-refresh
- [ ] TASK-30: `CredentialsScreen` — add `RefreshIndicator` for pull-to-refresh; replace `DateTime.toString()` credential dates with `DateFormat` or a relative-time helper
- [x] TASK-31: `RatingScreen` — remove the commented-out `ContextDropDown` (dead code); add an empty-state widget shown when the search filter returns zero rows

### Design System Token Migrations

- [x] TASK-32: `MyWorkScreen` — migrate sort button to `tt.tightGap * 2` and `TenturaText.labelLarge`; replace magic icon sizes (20/48), `maxWidth: 88`, animation offset `8`, and deprecated `kPaddingSmallV`/`kPaddingSmallH` with `context.tt` tokens
- [x] TASK-33: `InboxScreen` — migrate `Colors.transparent` on AppBar/TabBar; replace `BorderRadius.circular(999)` tombstone pill with a design-system radius token; replace magic `titleSpacing: 8`, icon 20, `maxWidth: 88`
- [ ] TASK-34: `FriendsScreen` — migrate `Colors.transparent` on TabBar; replace `kPaddingAll` in invites empty state; replace hard-coded `maxWidth: 320`, `Icon(size: 64)`, and `MediaQuery.sizeOf(context).height * 0.5` with `context.tt` / window-class tokens
- [x] TASK-35: `InboxRejectedScreen` — migrate `Colors.transparent` and `kPaddingSmallH`/`kPaddingSmallV`; replace plain `Text` in AppBar title with `TenturaText.title`
- [x] TASK-36: `IntroScreen` — migrate `kPaddingAll`, `kPaddingAllS`, `kPaddingV`; replace raw `8` width/height for page dots with a named token or `tt.iconTextGap`
- [x] TASK-37: `AuthLoginScreen` — migrate remaining `kPaddingAll`/`kPaddingH` on empty state and QR/clipboard buttons; replace bare `Text()` with `TenturaText` variants
- [ ] TASK-38: `RecoverScreen` — migrate `kSpacing*` constants; replace `BorderRadius.circular(kBorderRadius)` with `tt.cardRadius`
- [ ] TASK-39: `AuthRegisterScreen` — migrate the four `Padding(padding: kPaddingAll)` to `context.tt.cardPadding` or equivalent
- [x] TASK-40: `ProfileEditScreen` — replace `kTenturaAvatarBigSize` (160) with `tt.avatarSize`; center the avatar stack horizontally on wide layouts
- [ ] TASK-41: `SettingsScreen` — replace `_confirmResetLocal` raw `AlertDialog` with the shared design-system dialog wrapper
- [ ] TASK-42: `CredentialsScreen` — center the list on expanded screens with `contentMaxWidth`; migrate dialog(s) to shared design-system dialog wrapper
- [ ] TASK-43: `BeaconIconPickerScreen` — replace `Colors.black` / `Colors.white` fallback in `_pickerTileColors` with semantic `ColorScheme` tokens
- [ ] TASK-44: `info_tab.dart` (BeaconCreate) — migrate raw `EdgeInsets.fromLTRB(16,…)` and `kPadding*` constants to `context.tt` tokens
- [ ] TASK-45: `image_tab.dart` (BeaconCreate) — replace `Colors.black54` and fixed icon sizes in `_ImageCard` with design-system tokens and `ColorScheme` roles
- [ ] TASK-46: `BeaconCreateScreen` — consolidate the double horizontal padding (screen wrapper + tab content) so padding is owned at one level only
- [x] TASK-47: `forward_recipient_row.dart` + `lineage_suggestions_sheet.dart` — migrate raw chip insets and padding to `context.tt` tokens
- [x] TASK-48: `forward_bottom_composer.dart` — replace hardcoded icon sizes 14/16 with `tt.iconSize` tokens
- [x] TASK-49: `graph_body.dart` — replace `Colors.indigo` edge-highlight color with a `ColorScheme` token; replace bare `Text` node labels with `TenturaText`
- [ ] TASK-50: `BeaconViewScreen` — wrap the Scaffold body in `SafeArea` to prevent bottom-inset issues on notched devices
- [x] TASK-51: `EvaluationPrivacyInfoRow` — migrate raw icon sizes and spacing to `context.tt` tokens; add combined `Semantics` label to participant-status rows in `ReviewContributionsScreen`
- [x] TASK-52: `HomeScreen` + `profile_navbar_item.dart` — add a vertical hairline token for `VerticalDivider(width:1, thickness:1)`; add `Semantics` to the `ProfileNavBarItem` long-press target
- [ ] TASK-53: `RecoverScreen` / QR scanner widget — add `Semantics` wrapper and a live-region announcement on successful scan
- [ ] TASK-54: `RecoverScreen` — fix the pre-existing `use_build_context_synchronously` warning in `_confirmResetLocal` (use mounted guard or pass a reference before async gap)
- [x] TASK-55: `profile_app_bar.dart` + `profile_body.dart` — fix `ProfileAppBar` raw spacing and 40 dp touch targets; migrate deprecated `kPaddingT` / `kPaddingSmallT` in `ProfileBody`

### Structural Issues

- [ ] TASK-56: `FriendsScreen` — refactor `_FriendsTabBody` to read `Theme` and `L10n` from `BuildContext` internally instead of receiving them as constructor parameters
- [x] TASK-57: `ProfileViewScreen` — remove the unused `isDeepLink` `@QueryParam` declaration (or wire it up if intended)
- [ ] TASK-58: `AuthRegisterScreen` — extract a shared auth form widget (e.g. `AuthFormField`) to deduplicate the repeated `Padding` + `TextFormField` blocks shared with login/recover
- [ ] TASK-59: `SettingsScreen` — refactor the flat `Column` of `TextButton`s to a `TenturaCommandButton`-based grouped list (Settings IA pass)
- [ ] TASK-60: `BeaconIconPickerScreen` — extract a shared `_FilterChoiceChip` wrapper to replace the ~17 nearly-identical `ChoiceChip` definitions
- [ ] TASK-61: `ItemDiscussionScreen` — extract the ~120-line overflow menu logic into a shared builder/widget reused by both `ItemDiscussionScreen` and `ItemCard`
- [ ] TASK-62: `BeaconViewScreen` — split the ~1500-line file into focused widget files (AppBar widget, tab-page widgets, room-button widget, status bottom-sheet widget)
- [ ] TASK-63: `BeaconScreen` — evaluate replacing the synthetic `InboxItem` wrapper passed to `InboxItemTile` with a dedicated `BeaconTile` widget for the profile-beacon list
- [x] TASK-64: `ForwardsGraphScreen` — derive the AppBar title from `GraphState` instead of reading a private cubit field directly
- [x] TASK-65: `GraphScreen` — remove or implement the commented-out context selector in the AppBar `bottom:` slot
