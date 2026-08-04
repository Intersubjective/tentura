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
| 5 | Tests | pending |
| 6 | Integration and close-out | pending |

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
