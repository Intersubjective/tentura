# Issue #174 — Request edit buttons feel slow / ignore taps

**GitHub:** [Intersubjective/tentura#174](https://github.com/Intersubjective/tentura/issues/174)  
**Parent:** [#142](https://github.com/Intersubjective/tentura/issues/142)  
**Source:** 2026-09-14 product testing (participant note 5)

## Symptom

On **edit request**, primary actions (especially **Save Changes** and detail rows that open sheets) feel **unresponsive**. Authors **double-tap**, trigger duplicate work, or **leave** the editor.

User-facing nouns: **Request** / **discussion** workspace (internal `Beacon`, `beacon_create`).

## User-facing expectation

- Every tap gets **immediate** pressed/busy feedback.
- Work that takes noticeable time must show **progress** (not a silent UI).
- Acceptance from the issue: edit actions acknowledge within a perceived instant — **disabled control + spinner** when save is slow.

## Product path

| Step | Surface | Implementation |
|------|---------|------------------|
| Edit route | Open published request editor | [`BeaconCreateScreen`](../../packages/client/lib/features/beacon_create/ui/screen/beacon_create_screen.dart) with `editId` → `BeaconCreateCubit.loadEdit` |
| Save | Bottom **Save Changes** | `FilledButton` key `BeaconEdit.SaveChangesButton` → `saveEdit` when `state.isEditMode` |
| Global busy | App bar | `BlocSelector` → `TenturaTopBar.loadingBar` on `state.isLoading` |
| Form lock | Body | `AbsorbPointer(absorbing: isLoading)` around `InfoTab` |
| Detail rows | Timing / Requirements / Cover / Location | [`InfoTab`](../../packages/client/lib/features/beacon_create/ui/widget/info_tab.dart) — `onTap` → `_show*Sheet` after `await _flushDraft()` → `flushAutosave()` |
| Images / crop | Gallery & cover | [`BeaconCreateCubit.pickImages` / `adjustCoverCrop`](../../packages/client/lib/features/beacon_create/ui/bloc/beacon_create_cubit.dart) — `await flushAutosave()` before picker/crop UI |
| Persist | Use case | [`BeaconCreateCase.saveEdit`](../../packages/client/lib/domain/use_case/beacon_create_case.dart) → `update` + `_reconcile` (stage media, `setMedia`) |

## Root cause (engineering)

**1. Save Changes lacks local progress affordance.**  
`saveEdit` sets `StateStatus.isLoading` at entry ([`beacon_create_cubit.dart`](../../packages/client/lib/features/beacon_create/ui/bloc/beacon_create_cubit.dart) ~L1024), and the screen disables the button via `onPressed: state.isLoading ? null : …`. The **FilledButton child is plain text** — no `CircularProgressIndicator` on the control users tap. The only progress cue is the thin `LinearPiActive` bar under the app bar; on web it is easy to miss, so the flow reads as “nothing happened” until navigation or completion.

**2. Detail rows and media actions can block before any busy state.**  
`InfoTab` awaits `_flushDraft()` (commit fields + `flushAutosave()`) **before** opening timing/requirements/cover/location sheets. On **draft** flows, quiet autosave uses `isAutosaving` and deliberately **does not** flip `state.isLoading` ([`saveDraft(quiet: true)`](../../packages/client/lib/features/beacon_create/ui/bloc/beacon_create_cubit.dart) ~L892–897). While that persist or `flushAutosave` waits on the network, the tapped row stays visually idle — silence until the sheet appears.

**3. `pickImages` / `adjustCoverCrop` call `flushAutosave()` with no loading emit** before opening the picker or running crop work, so the same silent gap appears on image actions tied to edit/create.

**4. Double-submit risk under perceived lag.**  
If the user taps **Save Changes** twice before the first rebuild disables the button, two `saveEdit` calls can overlap (each emits loading but both may reach `_beacons.update`). That matches QA reports of duplicate actions when the UI felt frozen.

Contributing factor: any **synchronous** work on the UI isolate before the first `await` in a handler (form commit, building `BeaconSaveCommand`, image reconciliation setup) delays the frame that paints busy state even when `emit(isLoading)` already ran.

## Fix direction (not implemented in TDD pass)

- Add **explicit in-button** loading (spinner + label) on `BeaconEdit.SaveChangesButton` and parallel create/live save buttons; keep top-bar `LinearPiActive` as secondary cue.
- For row taps and picker entry: set a **row-level or cubit `pendingAction`** (or use `isLoading` when not quiet) **before** `await flushAutosave()` / sheet open; clear on completion or error.
- Consider **`flushAutosave` in edit mode** if future edits ever queue draft-like work; today `_shouldQuietPersist` skips edit/live, but `_flushDraft` still awaits the flush path.
- Guard `saveEdit` with an **in-flight latch** so overlapping taps are ignored.
- Re-test double-tap on slow network after UI feedback lands.

## Failing test (TDD — expected red)

**File:** `packages/client/test/features/beacon_create/issue_174_edit_buttons_slow_test.dart`

**Command:**

```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 10m -- flutter test \
  --dart-define=ENV=test \
  --dart-define-from-file=env/test.env \
  test/features/beacon_create/issue_174_edit_buttons_slow_test.dart
```

**Assertions (edit mode, held `update`):**

- After one `pump` following **Save Changes** tap: `FilledButton` shows an in-button `CircularProgressIndicator` while `isLoading`.
- Two quick taps on **Save Changes** must not start more than one `update`.

**Observed (2026-09-15):** `+0 -2` — missing in-button spinner; double-tap starts two `update` calls.

## Files touched (TDD only)

- `packages/client/test/features/beacon_create/issue_174_edit_buttons_slow_test.dart` — failing acceptance
- `docs/plans/qa-2026-09-14-engineering/issue-174-anamnesis.md` — this note

**No production code changes** in this pass.
