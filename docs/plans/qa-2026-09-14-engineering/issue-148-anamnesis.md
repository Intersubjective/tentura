# Issue #148 — After send, editor still shows Draft

**GitHub:** [Intersubjective/tentura#148](https://github.com/Intersubjective/tentura/issues/148)  
**Parent:** [#142](https://github.com/Intersubjective/tentura/issues/142)  
**Source:** 2026-09-14 product testing (participant note 7)

## Symptom

After choosing recipients and sending from the create flow, the UI returns to **«Редактировать черновик»** / **Edit draft** with status **Draft** and **Next: recipients**. Delivery succeeds on the server; the author cannot tell the request is published.

## User-facing expectation

- Successful send opens the **live request** (beacon detail), not the draft editor.
- Draft badge and **Edit draft** must not appear on a published request.
- Reloading the same entry point still shows **published**, not draft.

## Root cause (client)

Two gaps between **Make live** and **Send** on the recipients step:

1. **Cubit state:** [`BeaconCreateCubit.sendRequest`](../../packages/client/lib/features/beacon_create/ui/bloc/beacon_create_cubit.dart) publishes via `_case.publishDraft` on the draft path but **never sets `isLive: true`**, unlike [`makeLive`](../../packages/client/lib/features/beacon_create/ui/bloc/beacon_create_cubit.dart) which emits `isLive: true` after publish. The create screen app bar treats `draftId != null && !isLive` as draft ([`beacon_create_screen.dart`](../../packages/client/lib/features/beacon_create/ui/screen/beacon_create_screen.dart) title `editDraftTitle`).

2. **Navigation:** [`_makeLive`](../../packages/client/lib/features/beacon_create/ui/screen/beacon_create_screen.dart) calls [`popCreateAndOpenLiveBeacon`](../../packages/client/lib/features/beacon_create/ui/screen/beacon_create_screen.dart) → `StackRouter.popAndPush(BeaconViewRoute(id: …))`. [`_sendRequest`](../../packages/client/lib/features/beacon_create/ui/screen/beacon_create_screen.dart) only calls `context.router.maybePop()` after a successful confirmation dialog, which does **not** replace the create route with the live request view and can leave the user on the draft composer.

Server publish + forward can succeed while the client session remains in draft UI mode.

## Relevant code

| Area | Path | Notes |
|------|------|--------|
| Send orchestration | `packages/client/lib/features/beacon_create/ui/bloc/beacon_create_cubit.dart` | `sendRequest` publish branch without `isLive` |
| Make live parity | same | `makeLive` sets `isLive: true` + snack |
| Recipients send UI | `packages/client/lib/features/beacon_create/ui/screen/beacon_create_screen.dart` | `_sendRequest` vs `_makeLive` navigation |
| Live navigation helper | same | `popCreateAndOpenLiveBeacon` (test-visible) |
| App bar mode | same | `editDraftTitle` when `draftId` and not `isLive` |
| Existing parity tests | `packages/client/test/features/beacon_create/beacon_create_make_live_nav_test.dart` | Documents make-live navigation only |

## Observed test run (2026-09-15)

`+1 -3` on the issue #148 file (one test documents `popCreateAndOpenLiveBeacon` helper parity and passes). Log: `/tmp/issue-148-test.log`.

## Failing tests (TDD — expected red)

**File:** `packages/client/test/features/beacon_create/issue_148_after_send_draft_editor_test.dart`

| Test | Expected failure |
|------|------------------|
| `sendRequest from draft publishes and marks create session live` | `isLive` is `false` after publish+send |
| `after sendRequest app bar title is live request not edit draft` | Finds **Edit draft**, not **Live request** |
| `_sendRequest navigates to live request after successful delivery` | `_sendRequest` body lacks `popCreateAndOpenLiveBeacon`; uses `maybePop` |

**Command (from `packages/client`):**

```bash
../../scripts/run_with_test_cleanup.sh --timeout 10m -- flutter test \
  test/features/beacon_create/issue_148_after_send_draft_editor_test.dart \
  --dart-define=ENV=test \
  --dart-define-from-file=env/test.env
```

## Expected behavior (fix acceptance)

- After successful send from recipients: `isLive == true` (or equivalent published session flag) and navigation to `BeaconViewRoute` for the beacon id (same as make live).
- App bar shows live request title; draft menu / draft badge hidden (`isLive` branch already suppresses draft actions).
- Deep link / reload to create with published id should not present draft editor (may need route/query cleanup in the same fix).

## Recommended fix (for implementer)

1. In `sendRequest` draft path, after successful `publishDraft`, emit `isLive: true` (mirror `makeLive`, including already-published handling if applicable).
2. In `_sendRequest`, on non-failed `ForwardDeliveryOutcome`, call `popCreateAndOpenLiveBeacon` with `draftId` instead of (or before) `maybePop`.
3. Re-run issue #148 test file green; consider extending `beacon_create_cubit_make_live_test.dart` with an explicit `sendRequest` + `isLive` assertion for regression.

## Out of scope for this TDD pass

- Production code changes, commits, or pushes.
- `constellation_body_test.dart`, `home_tab_branch_routing_test.dart`, generated `*.g.dart`.
