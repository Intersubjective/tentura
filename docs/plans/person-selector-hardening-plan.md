# Person Selector Hardening — Implementation Plan

Issue: https://github.com/Intersubjective/tentura/issues/103
[P0][Bug] Harden person selectors: no error flash, missing picker or internal IDs
Parent: #96 (usability test findings). Related: #82 (closed — recipient step at
request creation), #97 (open — invite/local-name vs canonical-identity wording,
separate scope, do not implement here).

Repository: `/home/vader/MY_SRC/tentura` (Flutter client `packages/client`,
Clean Architecture: domain/data/ui, cubits, use cases, repositories).

## 1. Problem statement (from investigation)

Three observed bugs share one root defect: the shared `StateStatus` used by
`ForwardState`/`ForwardCubit` and mirrored by `BeaconViewState`'s two-phase
beacon load only has two values, `isLoading` / `isSuccess`
(`packages/client/lib/ui/bloc/state_base.dart`). There is no `error` or
`empty` variant, so:

- a genuine fetch failure is shown for one snackbar frame and then the state
  reverts to `isSuccess` with whatever data (usually still empty) happened to
  be present — indistinguishable from "successfully empty";
- "loading" and "genuinely empty" are both represented as
  `candidates.isEmpty`, so a widget cannot tell them apart;
- nothing marks *when* a list has finished its first real load, so static
  copy ("nobody will see this request…") renders identically during loading,
  after an error, and once genuinely empty.

**Bug #1 — Recipients tab (request draft) flashes an error, then a long
loading state with a false "nobody will see this" message.**
`beacon_create_screen.dart` switches to the Recipients tab
(`_openRecipientsTab`) from a `postFrameCallback` that can fire before
`BeaconCreateCubit.loadDraft()` (kicked off via `Future.microtask` in the
constructor) resolves. At that instant `state.publishBlocker != null` (title
still empty), so `_buildRecipientsTab` renders `BeaconRecipientsBlockedTab` —
an error-styled banner (`errorContainer`, `Icons.error_outline`, "Complete
required fields") — even though the draft already has a title on the server.
Once `loadDraft()` resolves, a fresh `ForwardCubit` is created and starts
loading candidates; `ForwardRecipientPicker` shows a bare spinner
(`forward_recipient_picker.dart:330-334`) for that whole window. Throughout
both phases, `BeaconRecipientsTab.build()` unconditionally renders
`l10n.beaconRoutingBanner` ("Nobody will see this request until you send it
to someone.") at the top regardless of load state — the literal false
message from the issue. If the candidate fetch itself errors,
`_emitSnackError` reverts `status` to `isSuccess` with `candidates == []`,
so the picker then shows `l10n.noReachableContacts` — a second, compounding
false-empty message that is actually an unreported error.

**Bug #2 — Promise recipient picker lost/disabled.**
`beacon_view_cubit.dart` emits beacon state in two phases: phase 1 sets
`beacon`, `status: isSuccess`, but `roomParticipants` is still `[]`
(default, `beacon_view_state.dart:229`); phase 2 (a `Future.wait`) is what
actually populates it. `canCoordinateInBeaconRoom`
(`beacon_view_state.dart:310-318`) is `true` as soon as
`isAuthorOrSteward` is true, which does not depend on `roomParticipants`.
So for the beacon author the Promise CTA
(`_ActiveCoordinationCtas` in `items_tab.dart`) is tappable during the
phase-1/phase-2 gap. `_openCoordinationComposer`
(`items_tab.dart:49-68`) passes `participants: state.roomParticipants` **by
value** — a one-shot snapshot — into the composer sheet. If opened during
the gap (or if streaming/refresh is simply slow), the sheet gets
`participants: []`; `_hasLegalTargets` becomes `false`
(`coordination_item_composer_sheet.dart:171-176`) and the entire
`_TargetPicker` block (label, guidance, dropdown) is not rendered at all —
no spinner, no retry, no distinction between "none exist" and "not loaded
yet". Separately, `_refreshRoomParticipants`
(`beacon_view_cubit.dart:735-738`, reactive off WS events) has **no
out-of-order guard**, unlike its siblings `_refreshRoomUnread` /
`_refreshHelpOffers`, which both check `beaconId == state.beacon.id` before
emitting (lines 730, 744). Two overlapping refreshes can let an earlier,
slower fetch clobber a later, fresher one, silently "losing" a previously
visible participant. `beacon_room_body.dart`'s room composer entry point has
the same static-snapshot problem via `RoomCubit`.

**Bug #3 — internal UUID rendered as a person's name.**
`recipients_tab.dart:54-88`: when a profile-route preselected recipient
(`droppedPreselectedIds`) can't be resolved against the just-loaded
candidate/lineage lists, `byId[id]?.profile.shownName` is `null` and the
banner falls back to `droppedIds.first` — the raw UUID — straight into a
`Text()` widget. `coordination_target_candidates.dart:73-98`
(`coordinationTargetLabel`, shared by Ask/Promise/Blocker picker labels) has
the same anti-pattern: when a target id isn't found in `participants` (same
staleness cause as Bug #2) or has no `userTitle`/`handle`, it falls back to
a truncated raw UUID string used directly as dropdown item text
(`coordination_item_composer_sheet.dart:576-583, 604-611`). Both call sites
independently reinvented an ad hoc `?? rawId` fallback because neither
`Profile` (`domain/entity/profile.dart`) nor `BeaconParticipant`
(`domain/entity/beacon_participant.dart`) exposes a "canonical identity,
guaranteed non-empty, never a raw id" getter.
`ui/widget/coordination_participant_lookup.dart`'s `profileForParticipant`
last-resort fallback (`return Profile(id: userId);`, line 44) is the same
gap one level up: an empty-named `Profile` whose `shownName` is empty,
pushing the raw-id fallback onto its callers.

## 2. Required behavior (acceptance criteria, from the issue)

- `loading`, `empty`, `error`, `ready` are mutually exclusive explicit
  states — no boolean-flag combinations that can be simultaneously true or
  ambiguous.
- An empty-state warning is shown only after a successful empty result,
  never during loading or after an error.
- The Promise recipient selector is present (rendered, possibly in a
  loading sub-state) whenever the workflow requires a recipient and
  eligible participants exist or might exist — never silently absent.
- Person labels use local name + canonical identity; internal IDs are never
  primary UI text, in production, ever.
- Stale/late-arriving person data cannot replace an already-valid selector
  with an error (out-of-order async guard).
- Opening a populated recipient selector never flashes an error or false
  empty warning.
- Opening a genuinely empty selector shows a stable explanatory empty
  state, not an error.
- An eligible Promise recipient can be selected and saved.
- No UUID/database/internal ID is rendered as the visible person name in
  production.
- Retry is available for a genuine fetch failure without losing draft
  data.
- Widget and integration tests: loading → ready, loading → empty,
  loading → error → retry, Promise selection, delayed identity resolution.

## 3. Non-goals

- Do not touch the invite/"Name" field wording or the local-name vs.
  canonical-handle *product copy* — that is issue #97, separate scope.
  This plan only ensures existing `Profile`/`BeaconParticipant` identity
  data is *rendered safely* (never a raw id), using the fields those
  entities already expose.
- Do not redesign `StateStatus` (`state_base.dart`) app-wide. It is used
  by many unrelated cubits; broadening its sealed-class shape would force
  every exhaustive `switch` in the app to change. Introduce new, narrowly
  scoped state types local to the person-selector components instead.
- Do not change the recipient-selection *product flow* from #82 (draft vs.
  send, routing banner copy itself) — only its state-conflation bugs.

## 4. Plan units

Ordered by dependency. Each unit is a single Cursor worker turn (split
further only if too large for one reliable turn). Every unit's worker must
read this plan file in full, the shared journal
(`docs/plans/person-selector-hardening-journal.md`), and the live code at
the referenced paths before editing — line numbers above are from
investigation and may have drifted.

### Unit 1 — Canonical, never-raw-id display helper

No dependencies. Small, isolated, do first.

**Goal:** one shared helper that turns a `Profile` or `BeaconParticipant`
into a display label that is never a raw UUID, and use it at every call
site that currently has an ad hoc `?? rawId` fallback.

**Approach:**
- Add a getter/function (e.g. `Profile.shownNameOrFallback` /
  a free function `displayNameFor(Profile)` — match this codebase's
  existing extension/getter conventions in `domain/entity/profile.dart`)
  that returns, in order: local `contactName` → `displayName` → `@handle`
  → a localized placeholder such as `l10n.unknownPerson` ("Unknown
  person") — **never** the raw `id`, truncated or not.
- Add the equivalent for `BeaconParticipant` (`userTitle` → `handle` →
  same localized placeholder), replacing the raw-id fallback in
  `coordinationTargetLabel`
  (`packages/client/lib/features/beacon_view/ui/widget/coordination_target_candidates.dart`).
- Fix `recipients_tab.dart`'s dropped-preselect banner
  (`packages/client/lib/features/beacon_create/ui/widget/recipients_tab.dart`)
  to use the helper instead of `droppedIds.first`.
- Fix `coordination_participant_lookup.dart`'s `profileForParticipant`
  last-resort fallback so the `Profile` it returns produces the localized
  placeholder via `shownName`/the new helper rather than an empty string.
- Add the localized string if one doesn't already exist
  (`ui/l10n/l10n_en.dart` and other locale files, following this
  project's l10n conventions).

**Acceptance:** grep for `.id` / `userId` used as literal `Text()` content
or string interpolation into user-facing labels in the touched files finds
nothing; a person with no local name, no display name, and no handle
renders the placeholder, never their id.

**Verification:** `cd packages/client && flutter test test/features/beacon_view/coordination_target_candidates_test.dart` (extend this file — see Unit 5) plus `./scripts/check-custom-lints.sh packages/client`.

### Unit 2 — Explicit candidate-load state for `ForwardCubit`/`ForwardState`

Depends on: Unit 1 (so the new Ready/Empty rendering can safely reuse the
identity helper on candidate labels; low coupling, mostly parallelizable
in principle but keep sequential per the overseer's one-worker-at-a-time
rule).

**Goal:** replace the reused `status: StateStatus` boolean for candidate
*loading* with a dedicated, mutually-exclusive four-state type scoped to
`ForwardState`, and stop the "load error reverts to empty-success" pattern
from destroying a previously valid list.

**Approach (adapt to live code / freezed conventions found in the
codebase — this is a design sketch, not literal source):**
- Add a small sealed type local to `forward_state.dart`, e.g.:
  ```dart
  sealed class ForwardCandidatesLoad {
    const ForwardCandidatesLoad();
  }
  class ForwardCandidatesLoading extends ForwardCandidatesLoad { const ForwardCandidatesLoading(); }
  class ForwardCandidatesReady extends ForwardCandidatesLoad { const ForwardCandidatesReady(); }
  class ForwardCandidatesEmpty extends ForwardCandidatesLoad { const ForwardCandidatesEmpty(); }
  class ForwardCandidatesError extends ForwardCandidatesLoad {
    const ForwardCandidatesError(this.error);
    final Object error;
  }
  ```
  Add a `candidatesLoad` field to `ForwardState` (default
  `ForwardCandidatesLoading()`), independent of the existing generic
  `status` field (which stays as the busy-indicator for
  send/edit/cancel actions — do not conflate the two concerns).
- In `ForwardCubit._loadCandidates()`
  (`packages/client/lib/features/forward/ui/bloc/forward_cubit.dart`):
  - On entry, if this is the *first* load (no prior successful data —
    track e.g. via a `hasLoadedOnce` flag or by checking
    `state.candidatesLoad is ForwardCandidatesLoading` at construction),
    emit `candidatesLoad: ForwardCandidatesLoading()`. A background
    `forceReload` triggered by live updates (contact/forward/block
    change streams) after a successful load must **not** flip the UI back
    to a full-screen loading state.
  - On success: emit `ForwardCandidatesEmpty()` if both `candidates` and
    `lineageSuggestions` come back empty, else `ForwardCandidatesReady()`.
  - On failure during the *first* load: emit
    `ForwardCandidatesError(e)` (do not silently revert to a fake
    "success"/empty state).
  - On failure during a *background* reload (we already have a
    previously ready/empty list): keep `candidatesLoad` as it was —
    surface the error only via the existing one-shot `ShowError`
    snackbar, never overwrite a valid selector with an error. This is
    the concrete fix for "stale data cannot replace a valid selector
    with an error".
  - Add a `retryLoadCandidates()` (or reuse `reloadCandidates`) entry
    point the UI can call from an error state without losing any other
    in-progress draft state (selected recipients, notes, filter, etc. —
    all untouched by this change since they live in separate fields).
- In `ForwardRecipientPicker`
  (`packages/client/lib/features/forward/ui/widget/forward_recipient_picker.dart`),
  replace the `state.isLoading && state.candidates.isEmpty` branch
  (~line 330) with an exhaustive switch/if-chain over `state.candidatesLoad`:
  - `Loading` → spinner (current behavior).
  - `Error` → a distinct error state (icon + message from the caught
    exception, localized where feasible) with a visible retry action
    wired to the cubit's retry method.
  - `Empty` → the current `l10n.noReachableContacts` /
    `l10n.labelNothingHere` text (this is now only reachable on a
    genuine empty result).
  - `Ready` → current list rendering.
  - The existing in-place `actionLoading` overlay (for send/edit/cancel,
    driven by the untouched generic `status` field) is unaffected.

**Acceptance:** a simulated failed first candidate fetch shows a distinct
error state with retry, not a spinner-then-fake-empty; a simulated
failed background refresh after a successful load leaves the
already-rendered list untouched (plus a snackbar); a genuinely empty
result shows the empty copy only after loading completes.

**Verification:** `cd packages/client && flutter test test/features/forward/` (extend `forward_recipient_picker_test.dart` and the cubit tests — see Unit 5).

### Unit 3 — Fix the Recipients-tab open race and gate the routing banner

Depends on: Unit 2 (reuses its error/retry pattern and the fact that
`ForwardRecipientPicker` no longer needs a synthetic "blocked" state to
paper over a mid-load draft).

**Goal:** stop `beacon_create_screen.dart` from switching into the
Recipients tab and rendering an error-styled "blocked" banner while the
draft is still loading, and stop the static routing-banner copy from
being shown during loading/error.

**Approach:**
- In `packages/client/lib/features/beacon_create/ui/screen/beacon_create_screen.dart`,
  make `_openRecipientsTab`/`_prepareRecipientsTab` (~lines 85-138)
  wait for the draft load to actually resolve (track loading via the
  cubit's own explicit state rather than inferring "blocked" from
  transient empty `title`/`description`) before deciding whether to
  render the real tab or the blocked-tab. If the draft is still loading
  when the deep-link/tab-switch fires, show a plain loading state (not
  the error-styled `BeaconRecipientsBlockedTab`) until `loadDraft()`
  resolves, then re-evaluate `publishBlocker`.
- In `packages/client/lib/features/beacon_create/ui/widget/recipients_tab.dart`,
  gate `l10n.beaconRoutingBanner` rendering on the selector actually
  being in a ready state (reachable candidates loaded, whether empty or
  populated) — not shown while `ForwardCubit`'s `candidatesLoad` is
  `Loading` or `Error` (Unit 2's new state).
- Confirm `BeaconRecipientsBlockedTab` is now only reached for a
  genuinely blocked draft (real validation failure, e.g. actually-empty
  title after load completes), not a transient pre-load snapshot.

**Acceptance:** opening a request draft directly into the Recipients tab
(deep link / `?tab=recipients`) for a draft that already has a title
never shows the red "Complete required fields" banner, even momentarily;
the "nobody will see this" banner never appears while candidates are
loading or erroring.

**Verification:** `cd packages/client && flutter test test/features/beacon_create/` (add a test — see Unit 5) plus manual run via the `local-debug` skill if time allows (open a draft with a saved title directly into the Recipients tab and watch for the flash).

### Unit 4 — Explicit participants-load state for the Promise/beacon-room picker

Depends on: Unit 1 (identity labels). Independent of Units 2/3 other than
sharing the same design vocabulary (Loading/Ready/Empty/Error) — order
after them for consistency of pattern, not because of a hard code
dependency.

**Goal:** the Promise (and Ask/Blocker) target picker must never be
silently absent — it must show a loading sub-state while participants are
still loading, distinguish "not loaded yet" from "loaded, none eligible",
and never miss a participant due to a stale overlapping refresh.

**Approach:**
- In `packages/client/lib/features/beacon_view/ui/bloc/beacon_view_state.dart`
  and `beacon_view_cubit.dart`, add an explicit load-status field for
  `roomParticipants` (same Loading/Ready/Empty/Error shape as Unit 2,
  scoped to this cubit — do not share the type across features unless a
  genuinely common one already exists; check first). Only report
  `canCoordinateInBeaconRoom`-driven CTAs as usable once participants have
  reached `Ready`/`Empty` — see next bullet for how the composer itself
  should behave, since hiding the CTA entirely is also acceptable if
  simpler and matches existing UX for other async-gated actions in this
  codebase (check `items_tab.dart` for precedent before deciding).
- In `beacon_view_cubit.dart`'s `_refreshRoomParticipants`
  (~line 735-738), add the same out-of-order guard already used by
  `_refreshRoomUnread`/`_refreshHelpOffers` (check `beaconId ==
  state.beacon.id`, or equivalent request-generation token, before
  emitting) so a slower, older refresh cannot clobber a fresher one.
- Stop passing `participants` into `showCoordinationItemComposerSheet`
  (`items_tab.dart:49-68`, and `beacon_room_body.dart`'s equivalent entry
  point) as a one-shot static list. Rebuild the sheet to read participants
  live from the owning cubit (e.g. wrap the target-picker section in a
  `BlocBuilder`/`BlocSelector` scoped to the relevant cubit and beacon/room
  id) so a participant that finishes loading *after* the sheet opens still
  appears, and a stale/emptied snapshot cannot get frozen into the sheet's
  local state.
- In `coordination_item_composer_sheet.dart`, replace the current
  `if (_hasLegalTargets) ...` all-or-nothing gate (~line 453) with an
  explicit rendering per load state: `Loading` → a small inline spinner
  in place of the picker (not the whole sheet); `Error` → inline retry;
  `Empty` (loaded, genuinely no eligible participants) → the current
  "no legal targets" explanatory copy, now correctly scoped to only that
  case; `Ready` with targets → current dropdown, using Unit 1's identity
  helper for labels.

**Acceptance:** opening the Promise composer while participants are
still loading shows a loading indicator in the picker's place, then the
real picker once data arrives — it is never simply missing; a
participant that becomes eligible after the sheet is already open is
selectable without closing/reopening; two overlapping WS-triggered
refreshes cannot make a previously-visible participant disappear.

**Verification:** `cd packages/client && flutter test test/features/beacon_view/` (add tests — see Unit 5).

### Unit 5 — Tests

Depends on: Units 1-4 (tests target the behavior they introduce).

Add/extend, following this repo's existing widget/cubit test patterns
(bloc_test or equivalent already in use — check existing test files
under `packages/client/test/features/forward/` and
`test/features/beacon_view/` before writing new ones):

- `forward_cubit`/`forward_recipient_picker` tests: loading → ready,
  loading → empty (genuine empty result), loading → error → retry
  (retry succeeds and shows the list), background-refresh-error does not
  destroy an already-rendered list (Unit 2's staleness guard).
- `coordination_target_candidates_test.dart`: extend to cover
  `promiseTargetParticipants`, `hasPublishedPromiseTargets`, and
  `coordinationTargetLabel`'s fallback chain (local name → display name →
  handle → placeholder — never a raw id), i.e. the exact function that
  had the UUID-leak bug.
- A widget test for `coordination_item_composer_sheet.dart`'s
  `_TargetPicker` covering: participants not yet loaded (loading
  sub-state visible, not absent), participants loaded with eligible
  targets (Promise selection works, selected id is submitted correctly),
  a participant arriving after the sheet opens (delayed identity
  resolution — label updates from placeholder/loading to the real name
  without needing to reopen the sheet).
- A widget test for `beacon_create_screen.dart`/`recipients_tab.dart`
  covering the direct-to-Recipients-tab open race from Unit 3 (draft
  with a real title never renders the blocked/error tab, even
  transiently) and the routing banner's gating on load state.

**Verification:** `cd packages/client && flutter test` (full suite, not just the touched files, to catch regressions) plus `./scripts/check-custom-lints.sh packages/client`.

### Unit 6 — Integration and close-out

Depends on: Units 1-5.

- Re-read this plan and the journal from the beginning; confirm every
  bullet in §2 (Required behavior) is accounted for by a specific
  change and a specific test.
- Run the full verification matrix: `cd packages/client && flutter test`,
  `./scripts/check-custom-lints.sh packages/client`,
  `bash scripts/check-user-facing-terminology.sh` (touched l10n strings
  must pass the terminology gate — recall project terminology: users see
  "Request"/"Chat" in copy; internal code paths (`beacon_view`,
  `beacon_room`, etc.) are unaffected).
- Manually sanity-check via the `local-debug` skill if time allows: open
  a populated Recipients tab (no flash), an empty one (stable empty
  state, not error), a Promise composer before/after participant load,
  and confirm no raw id is visible anywhere in these flows.
- Confirm all commits are focused per plan unit (or safely split if a
  worker bundled steps) and that no pre-existing/unrelated worktree
  changes were touched.

## 5. Shared journal

`docs/plans/person-selector-hardening-journal.md` (create if absent).
Every worker: read it fully before editing, append a checkpoint after
meaningful progress, append a final entry before exit (status, commits,
files, tests, findings, remaining work) per the `overseer` skill's
Operating Contract.
