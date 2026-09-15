# Issue #163 — Description required while typing request title

**GitHub:** [Intersubjective/tentura#163](https://github.com/Intersubjective/tentura/issues/163)  
**Related:** [#92](https://github.com/Intersubjective/tentura/issues/92), [#103](https://github.com/Intersubjective/tentura/issues/103) (create-form validation / touch semantics)

**Source:** 2026-09-14 product testing

## Symptom

On **Create request**, each keystroke in the **title** field shows the red inline error **“Description is required”** under the description field, even though the user has **not** focused or edited description yet.

## User-facing expectation

| Action | Description error |
|--------|-------------------|
| Type title only (description untouched) | **Hidden** |
| Tap **Next** / submit with empty description | **Shown** (`beaconDescriptionRequired` → “Description is required”) |

User-facing noun: **Request** (internal `Beacon`). l10n key stays `beaconDescriptionRequired`.

## Product path (create info step)

| Step | Surface | Implementation |
|------|---------|----------------|
| Title + description fields | Create request — info tab | [`InfoTab`](../../packages/client/lib/features/beacon_create/ui/widget/info_tab.dart) |
| Inline description error | `errorText` on description `TextFormField` | `_descriptionError(show: _descriptionBlurred \|\| state.showValidationHints)` |
| Blur / touch tracking | Local `State` flags | `_descriptionBlurred`, `_onDescriptionFocusChange` |
| Title edits | `onChanged` | `_cubit.setTitle(v)` + `setState(() {})` on `_InfoTabState` |
| Reveal all hints | **Next** (recipients step) | [`BeaconCreateScreen._onNext`](../../packages/client/lib/features/beacon_create/ui/screen/beacon_create_screen.dart) → `validate()` then `revealValidationHints()` when `publishBlocker != null` |
| Cubit typing | `setTitle` / `setDescription` | [`BeaconCreateCubit`](../../packages/client/lib/features/beacon_create/ui/bloc/beacon_create_cubit.dart) — `validate()` updates `canTryToPublish` only; does **not** set `showValidationHints` |

## Validation decision tree (description field)

| `show` in `_descriptionError` | Error visible when description empty |
|---------------------------------|--------------------------------------|
| `_descriptionBlurred == false` && `showValidationHints == false` | No |
| `_descriptionBlurred == true` | Yes |
| `showValidationHints == true` (after failed Next) | Yes |

`beaconDescriptionValidator` returns `l10n.beaconDescriptionRequired` when trimmed text is empty ([`string_input_validator.dart`](../../packages/client/lib/ui/utils/string_input_validator.dart)).

## Root cause (engineering)

Two mechanisms interact on the info tab:

1. **`_onDescriptionFocusChange`** sets `_descriptionBlurred = true` whenever the description `FocusNode` listener runs while `!_descriptionFocus.hasFocus` ([`info_tab.dart` L101–105](../../packages/client/lib/features/beacon_create/ui/widget/info_tab.dart)). That conflates “field was blurred by the user” with “field is merely unfocused,” and focus notifications can fire during rebuilds without the user ever touching description.

2. **Title `onChanged`** calls **`setState(() {})`** on the parent [`_InfoTabState`](../../packages/client/lib/features/beacon_create/ui/widget/info_tab.dart) (L574–577), rebuilding the whole tab including `_descriptionField`. The description field’s `BlocBuilder` only gates on `showValidationHints`, but the parent rebuild still recomputes `show = _descriptionBlurred || state.showValidationHints` and paints `errorText`. Once `_descriptionBlurred` is true, every title keystroke keeps showing **Description is required** while description remains empty.

`revealValidationHints()` is correctly confined to **Next**; the premature error is from local blur state + full-tab `setState`, not from the cubit.

## Expected behavior (fix acceptance)

- Title-only editing: no description error until description is blurred after edit or **Next** is pressed with empty description.
- **Next** with valid title and empty description: still show **Description is required** and focus description (`BeaconPublishBlocker.description`).

## Fix direction (not implemented in TDD pass)

- Track description **touch/blur** explicitly (e.g. set `_descriptionBlurred` only on transition from focused → unfocused after the user focused description), or stop treating every `!hasFocus` notification as blur.
- Optionally narrow title `onChanged` rebuild scope so title typing does not rebuild description error chrome (secondary; blur semantics fix is primary).

## Observed test run (2026-09-15)

**Command:**

```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 10m -- flutter test \
  --dart-define=ENV=test \
  --dart-define-from-file=env/test.env \
  test/features/beacon_create/issue_163_title_keystroke_description_required_test.dart
```

**Result:** `+2 -1` (bug reproduced in widget harness).

| Test | Result (2026-09-15) | Role |
|------|---------------------|------|
| `title typing after spurious description focus notify hides required error` | **Fail** | Reproduces #163: toggle description field `FocusNode.canRequestFocus` (listener fires while `!hasFocus`) → title `enterText` → **Description is required** visible |
| `typing only in title does not show Description is required` | **Pass** | Baseline without spurious notify (harness-only green) |
| `Next with empty description still shows Description is required` | **Pass** | Regression guard (`revealValidationHints` path) |

**Repro harness (acceptance test):** pump `InfoTab` → read description `EditableText.focusNode` → `canRequestFocus = false` then `true` (spurious `notifyListeners`) → type title → expect no description error (**fails on current code**).

## Files touched (TDD only)

- `packages/client/test/features/beacon_create/issue_163_title_keystroke_description_required_test.dart` — failing acceptance + regression
- `docs/plans/qa-2026-09-14-engineering/issue-163-anamnesis.md` — this note

**No production code changes** in this pass.
