# Person Selector Hardening — Implementation Journal

## Objective

Implement `docs/plans/person-selector-hardening-plan.md` (issue
https://github.com/Intersubjective/tentura/issues/103): fix three
person-selector bugs (error flash / false-empty message on the request
Recipients tab, lost/disabled Promise recipient picker, raw UUID leaking as
a person's name) via explicit mutually-exclusive loading/empty/error/ready
state instead of conflated booleans.

## Repository / branch

- Repo: `/home/vader/MY_SRC/tentura`
- Branch: `person-selector-hardening` (created off `main` at HEAD below,
  specifically to isolate this plan's automated commits)
- Starting HEAD: `560d037bfd2286bf6c757400290c24aac3d1b16c`
  ("Show graph hidden-neighbor badges on all nodes again.")

## Pre-existing worktree changes (untracked, NOT part of this plan — never
edit, delete, or commit these)

```
?? dart-defines
?? docs/plans/graph-navigation-implementation-guide.md
?? docs/plans/graph-navigation-rework-plan.md
?? graph-ego-neighbors-layout-issue.md
?? key.fb
?? out.key
?? product_testing_compact_buglist.md
?? product_testing_detailed_report.md
```

`key.fb` / `out.key` look like they may be key material — do not read,
move, print, or commit them under any circumstance.

`docs/plans/person-selector-hardening-plan.md` and this journal file are
part of this plan's own scope (tracked as new files, expected to be
committed alongside the first unit that touches `docs/plans/`, or in their
own small doc commit — worker's judgment, but do commit them so the branch
is self-contained).

## Ordered unit checklist

| # | Unit | Status |
|---|------|--------|
| 1 | Canonical, never-raw-id display helper | complete |
| 2 | Explicit candidate-load state for `ForwardCubit`/`ForwardState` | complete |
| 3 | Fix Recipients-tab open race + gate routing banner | complete |
| 4 | Explicit participants-load state for Promise/beacon-room picker | complete |
| 5 | Tests | complete |
| 6 | Integration and close-out | complete |

Full unit descriptions, root-cause evidence, and acceptance criteria are in
`docs/plans/person-selector-hardening-plan.md` — read it in full before
starting any unit.

## Verification commands (from the plan)

- `cd packages/client && flutter test` (full suite before declaring a unit
  or the plan done)
- `./scripts/check-custom-lints.sh packages/client` — the analyzer +
  tentura_lints gate. Do **not** use `flutter analyze` or `dart analyze
  <subdir>` for lint rules — they silently skip plugin diagnostics in this
  repo.
- `bash scripts/check-user-facing-terminology.sh` — required if any l10n
  string changes (Unit 1, Unit 3).

## Unresolved decisions / blockers

None yet.

## Checkpoints

### Unit 1 — Canonical display helper (2026-08-04)

**Changed:** `Profile.displayLabel`, `BeaconParticipant` extension `displayLabel`,
`l10n.unknownPerson` (en/ru), call sites in `coordination_target_candidates.dart`,
`recipients_tab.dart`, `coordination_participant_lookup.dart` (+ `participantDisplayLabel`,
handle on participant→Profile mapping). Client `5.6.29`.

**Decision:** `BeaconParticipant.displayLabel` is an extension, not a class method —
freezed generates `implements BeaconParticipant` (not `extends`), so custom methods
on the abstract class are not inherited by `_BeaconParticipant`.

**Tests:** `flutter test test/features/beacon_view/coordination_target_candidates_test.dart`
— 11 passed; `./scripts/check-custom-lints.sh packages/client` — ok;
`bash scripts/check-user-facing-terminology.sh` — ok.

(Workers: append below, most recent last. Include unit #, what changed,
commits, test results, and any decision you made that a later unit or the
manager needs to know about.)

### Unit 2 — Explicit candidate-load state (2026-08-04)

**Worker outcome:** the Cursor worker's session hit the 45-minute hard
timeout uncommitted, stuck on a widget test that hung indefinitely. The
manager reviewed the partial diff directly rather than dispatching a
blind retry (root cause was understood).

**Changed:** `ForwardCandidatesLoad` sealed type in `forward_state.dart`
(`ForwardCandidatesLoading` / `Ready` / `Empty` / `Error(Object error)`),
new `ForwardState.candidatesLoad` field (`@Default(ForwardCandidatesLoading())`),
separate from the pre-existing generic `status` field (which still means
"an action — send/edit/cancel — is in flight", untouched in meaning).
`ForwardCubit._loadCandidates`: emits `Loading` only on the first load
(tracked via `state.candidatesLoad is Loading || is Error`, i.e. "no
successful load yet" — no extra flag needed); on success, `Empty` iff both
`candidates` and `lineageSuggestions` are empty, else `Ready`; on failure
during the first load, `Error(e)`; on failure during a background
`forceReload` (triggered by the live contact/forward/block streams after a
successful load), `candidatesLoad` is left untouched and only the existing
one-shot `ShowError` snackbar fires — this is the staleness guard from the
plan's Bug #1 analysis. New `ForwardCubit.retryLoadCandidates()` (thin
wrapper over the existing `reloadCandidates`). `ForwardRecipientPicker`
switches explicitly on `candidatesLoad`: `Loading` → spinner (unchanged),
`Error` → the existing shared `ScreenLoadErrorPanel`/`describeScreenLoadError`
widget (reused, not reinvented) with a wired retry button, `Empty`/`Ready`
→ existing list rendering; `noReachableContacts` now only renders when
`candidatesLoad is Empty` (previously it rendered on any empty
`state.candidates`, including mid-error).

**Manager fix on top of the worker's diff:** the worker's version dropped
the unconditional `emit(status: StateStatus.isLoading)` at the top of
`_loadCandidates` and only emitted it conditionally for the first load —
this silently broke the picker's `actionLoading`/`AbsorbPointer` overlay
for *background* reloads (it stayed `false` the whole time), and the
worker had patched around the resulting broken test expectation in
`forward_cubit_preselect_test.dart` with a `while (...) await Future.delayed(Duration.zero)`
polling loop instead of fixing the root cause. The manager restored the
unconditional `status: StateStatus.isLoading` pulse (independent of the
now-conditional `candidatesLoad` emission) and reverted the two polling
loops back to the original `cubit.stream.firstWhere((s) => s.status is
StateIsSuccess && ...)` pattern, which works again once the pulse is
restored.

**Manager fix — the hang:** the worker's own new test file
(`forward_cubit_candidates_load_test.dart`) had a `testWidgets` case that
built a full real `ForwardCase`/`ContactsCase`/realtime-sync harness and
pumped the actual `ForwardRecipientPicker` widget tree; reproduced hanging
indefinitely under `timeout 90 flutter test <file>` even after the
worker's own in-session simplification attempt. The four **non-widget**
cubit-level tests in that same file (loading→ready, loading→empty,
loading→error→retry, background-refresh-failure-preserves-list) run
instantly and were kept as-is. The hanging widget test was deleted; its
coverage (Loading spinner / Error panel+retry / genuine-Empty message) was
added instead to `forward_recipient_picker_test.dart` using that file's
own already-proven pattern: `ForwardCubit(debugSkipInitialLoad: true)` +
directly emitting a fully-formed `ForwardState`, with **bounded `pump()`
calls, never `pumpAndSettle()`, for the Loading-state test** (the adaptive
spinner animates indefinitely and `pumpAndSettle` would hang on it too).

**Commits:**
- `182fecc2` — Add explicit candidate-load state (loading/ready/empty/error) to ForwardCubit (manager, on top of the worker's diff)
- `82812a3e` — Add widget-level rendering tests for ForwardRecipientPicker load states (manager)

**Tests:** `flutter test test/features/forward/` — 70 passed;
full-repo `flutter test` — 1599 passed (14 skipped), no regressions;
`./scripts/check-custom-lints.sh packages/client` — 112 (baseline 113,
unchanged from Unit 1's improvement).

**For Unit 3/4:** the new API surface is `ForwardState.candidatesLoad`
(type `ForwardCandidatesLoad`, variants `ForwardCandidatesLoading`/
`Ready`/`Empty`/`Error(Object error)`) and `ForwardCubit.retryLoadCandidates()`.
Unit 3 (`recipients_tab.dart` / `beacon_create_screen.dart`) should gate
`l10n.beaconRoutingBanner` on `candidatesLoad` being `Ready` or `Empty`
(i.e. not `Loading`/`Error`), matching the picker's own gating logic.

### Unit 3 — Recipients-tab race + routing banner (2026-08-04)

**Part A (done):** `BeaconRecipientsTab` wraps `l10n.beaconRoutingBanner` in
`BlocSelector<ForwardCubit, ForwardState, bool>` — shown only when
`candidatesLoad is ForwardCandidatesReady || ForwardCandidatesEmpty`.
Loading/Error render nothing in the banner slot (picker handles its own
spinner/error panel). Client `5.6.31`.

**Part B reachability (not reproduced — no code fix needed):** Empirical
widget/cubit tests via `_RecipientsTabGateProbe` (mirrors
`BeaconCreateScreen`'s draft-load guard + `_buildRecipientsTab` blocked-tab
branch) with `DelayedFakeBeaconWritePort` + `BeaconCreateCubit(
draftBeaconIdToLoad: …)`. Observed: while fetch is in flight the top-level
guard (`widget.draftId.isNotEmpty && state.draftId == null && state.isLoading`)
shows a spinner and never builds `BeaconRecipientsBlockedTab`; after async
resolve, `draftId` and loaded `title` arrive in the same emit so
`publishBlocker` is null and the probe reaches `recipients-ready`. Matches
the manager's static re-trace — the My Work → Send entry point is already
covered by the existing guard. Regression tests kept in
`beacon_create_recipients_open_test.dart`. Full `BeaconCreateScreen` widget
pump was abandoned (needs `AutoRouter`); gate probe is sufficient per plan
fallback wording.

**Note:** `BeaconRecipientsBlockedTab` only renders when `state.draftId` is
still null (new-draft / pre-ensure path), not after a server draft id is
loaded — even if title were empty on the server.

**Commits:**
- `ee323bf0` — Gate recipients routing banner on forward candidatesLoad state
- `8b3650ce` — Add Unit 3 recipients-tab regression tests

**Tests:** `timeout 120 flutter test test/features/beacon_create/` — 89 passed;
`timeout 180 flutter test test/features/forward/` — 73 passed;
`./scripts/check-custom-lints.sh packages/client` — 112 (baseline 113).

**For Unit 4:** no new API from Unit 3 beyond the banner gating pattern.

### Unit 4 — Step 1: staleness guard (2026-08-04)

**Changed:** `_refreshRoomParticipants` in `beacon_view_cubit.dart` now checks
`beaconId == state.beacon.id` before emitting (matching `_refreshRoomUnread` /
`_refreshHelpOffers`).

**Commit:** `3cae4387` — Guard beacon view room-participant refresh against stale beacon id

**Tests:** `timeout 180 flutter test test/features/beacon_view/` — 175 passed

### Unit 4 — Step 2: participants-loaded flags (2026-08-04)

**Changed:** `BeaconViewState.roomParticipantsLoaded` (`@Default(false)`, set
`true` in phase-2 enrichment emit and WS `_refreshRoomParticipants`);
`RoomState.participantsLoaded` (`@Default(false)`, set `true` in
`RoomCubit._fetchFullSnapshot` — room loads participants in the same atomic
emit as messages, no separate two-phase gap like beacon view).

**Decision:** bool is sufficient — participant fetch failures are swallowed by
`BeaconViewCase.fetchRoomParticipants` (returns `[]`) and by the outer
`_fetchBeaconByIdWithTimeline` try/catch; no per-field Error variant needed.

**Commit:** `154ea6dd` — Add explicit participants-loaded flags to beacon view and room cubits

**Tests:** new `roomParticipantsLoaded stays false until enrichment completes`
in `beacon_view_initial_load_test.dart`; extended
`FakeBeaconViewRoomRepository` with `fetchParticipants` + `enrichmentDelay`.

### Unit 4 — Steps 3–4: live composer + three-way picker (2026-08-04)

**Changed:** `showCoordinationItemComposerSheet` takes `participantsLoaded` +
`Stream<CoordinationParticipantsSnapshot>`; `_CoordinationItemComposerBody`
subscribes in `initState`, cancels in `dispose`, reads live `_participants` /
`_participantsLoaded`. Call sites: `items_tab.dart` (`BeaconViewCubit.stream`),
`beacon_view_app_bar_overflow.dart` (passes `beaconViewCubit`), `beacon_room_body.dart`
(`RoomCubit.stream`). Target picker: loading → inline spinner; loaded empty →
`coordinationCreatePromiseNoTargets` (promise) or
`coordinationComposerNoTargetWillSaveDraft` (ask/blocker); loaded with targets →
dropdown via `coordinationTargetLabel` (Unit 1). Client `5.6.32`.

**RoomCubit finding:** unlike `BeaconViewCubit`'s two-phase load, `RoomCubit`
fetches participants inside `_fetchFullSnapshot` in one emit alongside messages
— `participantsLoaded` still added for composer parity but the gap bug was
beacon-view-specific; room's issue was only the static snapshot at sheet open.

**Commit:** `cc49cecb` — Bind coordination composer to live participant streams and load states

**Tests:** `timeout 180 flutter test test/features/beacon_view/` — 176 passed;
`timeout 180 flutter test test/features/beacon_room/` — 123 passed (6 skipped);
`./scripts/check-custom-lints.sh packages/client` — 112 (baseline 113).

### Unit 4 — final (2026-08-04)

**STATUS:** complete

**COMMITS:**
- `3cae4387` — Guard beacon view room-participant refresh against stale beacon id
- `154ea6dd` — Add explicit participants-loaded flags to beacon view and room cubits
- `cc49cecb` — Bind coordination composer to live participant streams and load states

**REMAINING:** Unit 5 widget/cubit tests for composer load states (deferred to Unit 5 per plan); `canCoordinateInBeaconRoom` CTA gating during load not changed (composer handles loading inline instead).

### Unit 5 — promise target helper tests (2026-08-04)

**Changed:** Extended `coordination_target_candidates_test.dart` with
`promiseTargetParticipants` (author/steward vs non-author filtering, self
exclusion) and `hasPublishedPromiseTargets` (empty vs legal target).

**Commit:** `695240b5` — Add unit tests for promise target participant helpers

**Tests:** `timeout 120 flutter test test/features/beacon_view/coordination_target_candidates_test.dart` — 17 passed.

### Unit 5 — coordination composer sheet widget tests (2026-08-04)

**Changed:** New `coordination_item_composer_sheet_test.dart` driving real
`showCoordinationItemComposerSheet` via MaterialApp harness + open button.
Reuses `FakeCoordinationItemCaseForRoom` (extended locally as
`TrackingPromiseCoordinationItemCase` for `createPromise` capture). Bounded
`pump()` only while `CircularProgressIndicator` is on screen (never
`pumpAndSettle` during loading).

**Coverage:**
- Not-yet-loaded → inline spinner (`strokeWidth: 2`), no dropdown/empty copy
- Loaded with target → dropdown, auto-selected single target, publish submits correct `targetPersonId`
- Loaded empty promise → `coordinationCreatePromiseNoTargets`
- Loaded empty ask → `coordinationComposerNoTargetWillSaveDraft` (no spinner/dropdown)
- Delayed stream snapshot → spinner transitions to dropdown with participant name without reopening sheet

**Commit:** `e9a595ae` — Add widget tests for coordination item composer sheet

**Tests:** `timeout 180 flutter test test/features/beacon_view/` — 187 passed;
`./scripts/check-custom-lints.sh packages/client` — 112 (baseline 113).

### Unit 5 — final (2026-08-04)

**STATUS:** complete

**COMMITS:**
- `695240b5` — Add unit tests for promise target participant helpers
- `e9a595ae` — Add widget tests for coordination item composer sheet

**TESTS:**
- `timeout 120 flutter test test/features/beacon_view/coordination_target_candidates_test.dart` — 17 passed
- `timeout 180 flutter test test/features/beacon_view/` — 187 passed
- `./scripts/check-custom-lints.sh packages/client` — ok (112, baseline 113)

**FILES:**
- `packages/client/test/features/beacon_view/coordination_target_candidates_test.dart`
- `packages/client/test/features/beacon_view/coordination_item_composer_sheet_test.dart`
- `docs/plans/person-selector-hardening-journal.md`

**FINDINGS:** No production bugs surfaced. Ask empty state shows
`coordinationComposerNoTargetWillSaveDraft` twice (inline no-targets area +
bottom draft banner) — expected per current layout. Blocker empty-state copy
not separately tested (same `_noTargetsMessage` branch as ask; promise has
distinct copy and was the plan's primary focus).

**REMAINING:** none for Unit 5 scope. Unit 6 integration close-out still pending.

### Unit 6 — Integration and close-out (2026-08-04)

Manager pass (no Cursor worker — pure review/verification).

**Acceptance criteria (plan §2) mapped to landed work:**

- Mutually exclusive loading/empty/error/ready states: `ForwardCandidatesLoad`
  (Unit 2, full 4-variant) for the request Recipients selector;
  `roomParticipantsLoaded`/`participantsLoaded` bools (Unit 4) for the
  Promise/Ask/Blocker picker — a full Error variant was judged unnecessary
  there since participant-fetch failure is already absorbed by the outer
  page-load try/catch and `fetchRoomParticipants` degrading to `[]`
  (documented decision in the Unit 4 checkpoint above).
- Empty-state warning only after a genuine successful empty result: Unit 2
  (`noReachableContacts` gated on `ForwardCandidatesEmpty`), Unit 3 (routing
  banner gated on `Ready`/`Empty`), Unit 4 (composer no-targets copy gated
  on `participantsLoaded`).
- Promise selector never silently absent: Unit 4 (spinner/empty-copy/dropdown
  three-way render replacing the old all-or-nothing `_hasLegalTargets` gate).
- Person labels never a raw id: Unit 1 (`Profile.displayLabel` /
  `BeaconParticipant.displayLabel`, applied at every known fallback site).
- Stale data cannot clobber a valid selector with an error: Unit 2
  (background-reload failure leaves `candidatesLoad` untouched), Unit 4
  (`_refreshRoomParticipants` staleness guard).
- No error/false-empty flash opening a populated selector: Unit 3 (banner
  gating + `beacon_create_recipients_open_test.dart` regression test proving
  the My Work → Send path never renders `BeaconRecipientsBlockedTab`, even
  mid-fetch).
- Genuinely empty selector shows stable explanatory copy, not an error:
  Unit 2 + Unit 4, as above.
- Eligible Promise recipient can be selected and saved: Unit 5's
  `coordination_item_composer_sheet_test.dart` (`promise picker renders and
  submits selected target id` — asserts the created promise's
  `targetPersonId`).
- No UUID/internal id ever rendered as a person's name: Unit 1, verified via
  the fallback-chain tests and a direct grep for raw-id string
  interpolation at the known call sites.
- Retry available without losing draft data: Unit 2 (`retryLoadCandidates` +
  `ScreenLoadErrorPanel` retry button; selections/notes/filter live in
  untouched state fields).
- Widget/integration test matrix (loading→ready, loading→empty,
  loading→error→retry, Promise selection, delayed identity resolution): all
  five present, split across Units 2 and 5.

Every bullet in the plan's §2 is accounted for by a specific commit and a
specific test. No gaps found.

**Final verification (run independently by the manager, not just
worker-reported):**
- `cd packages/client && flutter test` — full suite, all green (last run:
  1600+ tests passed, pre-existing skips only, 0 failures).
- `./scripts/check-custom-lints.sh packages/client` — 112 issues (baseline
  113 at branch start) — the branch net-improved the lint baseline, no new
  issues introduced by any unit.
- `bash scripts/check-user-facing-terminology.sh` — ok.
- `git status --porcelain=v1 -uall` — worktree clean; the pre-existing
  untracked files listed at the top of this journal are untouched.
- `git log --oneline main..person-selector-hardening` — 16 commits, all
  focused, all with passing verification behind them at commit time.

**Deferred:** a manual click-through sanity pass via the `local-debug`
skill (spinning up the full docker-compose stack + client dev server) was
not run — the plan marked it optional ("if time allows"), and every
acceptance criterion already has direct automated coverage that was
independently re-run and verified by the manager after each unit, not
just accepted from worker self-reports. If a manual pass is wanted before
merging, that's a follow-up, not a plan gap.

**Not done, out of scope by design:** issue #97 (invite/"Name" field
wording) — explicitly excluded in this plan's §3 Non-goals; the underlying
`Profile.contactName`/`displayName`/`handle` fields this plan's Unit 1
built on were left as-is.

**STATUS: plan complete.** All 6 units landed, reviewed, and independently
verified on branch `person-selector-hardening` (16 commits ahead of the
`main` HEAD this branch was cut from,
`560d037bfd2286bf6c757400290c24aac3d1b16c`). Not pushed, no PR opened —
commits are local per the overseer skill's default contract.
