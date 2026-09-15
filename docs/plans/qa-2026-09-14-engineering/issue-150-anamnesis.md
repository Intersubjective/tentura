# Issue #150 — Discussion composer loses keyboard focus after first send

**GitHub:** [Intersubjective/tentura#150](https://github.com/Intersubjective/tentura/issues/150)  
**Related:** [#115](https://github.com/Intersubjective/tentura/issues/115) (reply-to-message / composer UX)

**Source:** 2026-09-14 product testing

## Symptom

In the **discussion** workspace (beacon room chat), the message **composer** loses **keyboard focus** after the **first successful send**. The user cannot immediately type a second message; they must click back into the input. The same focus drop is reported when **saving an edited message** (edit flow uses a bottom sheet, then returns to the room — the main composer does not regain focus).

## User-facing expectation

- After **Send**, focus returns to the discussion composer so **type → send → type → send** works without the mouse.
- After **Edit message → Save**, focus returns to the main composer (or the edit surface hands off to it) so continued typing in the thread does not require an extra click.

## Product path (discussion send)

| Step | Surface | Implementation |
|------|---------|----------------|
| Room body | [`BeaconRoomBody`](../../packages/client/lib/features/beacon_threads/ui/widget/beacon_room_body.dart) | Embeds shared chat surface |
| Chat surface | [`BasicChatBody`](../../packages/client/lib/ui/widget/basic_chat_body.dart) | Message list + [`BeaconRoomComposer`](../../packages/client/lib/ui/widget/basic_chat_body.dart) |
| Send | `_BeaconRoomComposerState._submit()` | Clears text / pending uploads on success; toggles `_submitting` |
| Cubit | [`RoomCubit.sendMessage`](../../packages/client/lib/features/beacon_threads/ui/bloc/room_cubit.dart) | Persists message via [`BeaconThreadsCase`](../../packages/client/lib/features/beacon_threads/domain/use_case/beacon_threads_case.dart) |

## Product path (edit message)

| Step | Surface | Implementation |
|------|---------|----------------|
| Action | Message actions → Edit | [`beacon_room_body.dart`](../../packages/client/lib/features/beacon_threads/ui/widget/beacon_room_body.dart) `_showEditMessageSheet` |
| Editor | [`_BeaconRoomTextBottomSheet`](../../packages/client/lib/features/beacon_threads/ui/widget/beacon_room_body.dart) | Adaptive sheet `TextField` + Save pops trimmed body |
| Persist | `RoomCubit.editMessage` | Server mutation; sheet closes — **no** refocus hook on main composer |

## Focus behavior (client, as implemented)

| Location | Behavior |
|----------|----------|
| Composer `FocusNode` | [`_composerFocus`](../../packages/client/lib/ui/widget/basic_chat_body.dart) on discussion `TextField` |
| After mention insert | `requestFocus()` when focus was lost |
| After tap on field | `_requestComposerKeyboardFromTap()` requests focus + keyboard (native) |
| After successful `_submit()` | Clears controller and pending attachments only — **does not** `requestFocus()` on composer |
| Send `IconButton` | `onPressed` → `_submit()`; tap moves primary focus to the button |
| `onSubmitted` (keyboard send) | Calls `_submit()`; focus retention not restored after async send |
| Native keyboard helper | `_onComposerFocusChange` / `requestKeyboard()` — **skipped on web** (`kIsWeb`) |
| Edit sheet | Separate `TextField` without `FocusNode` wiring back to room composer on `Navigator.pop` |

## Root cause (engineering)

1. **Send path:** [`_BeaconRoomComposerState._submit`](../../packages/client/lib/ui/widget/basic_chat_body.dart) completes successfully but never re-asserts composer focus after the send control or IME action steals or releases focus during the async `onSend` / rebuild cycle.
2. **Send button:** Tapping [`Icons.send_rounded`](../../packages/client/lib/ui/widget/basic_chat_body.dart) focuses the `IconButton`; nothing refocuses the composer afterward.
3. **Edit path (related):** Edit uses a modal sheet; closing it after save does not schedule `requestFocus` on the discussion composer — same user-visible “must click to type again” class.

## Observed test run (2026-09-15)

**Command:**

```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 10m -- flutter test \
  test/features/beacon_threads/issue_150_composer_focus_after_send_test.dart \
  --dart-define=ENV=test \
  --dart-define-from-file=env/test.env
```

**Result:** `+0 -3` (all acceptance tests red; bug reproduced).

| Test | Result | Observation |
|------|--------|-------------|
| `send button keeps keyboard focus…` | **Fail** | `_composerFocus.hasFocus` is `false` after first send via send icon |
| `keyboard send action keeps focus…` | **Fail** | Same after `TextInputAction.send` |
| `primary focus stays on composer…` | **Fail** | `FocusManager.primaryFocus` is modal scope, not composer `FocusNode` |

| Test | Intent |
|------|--------|
| `send button keeps keyboard focus on composer for immediate second message` | Two sends via send icon without refocusing composer |
| `keyboard send action keeps focus for type-send-type-send without mouse` | `TextInputAction.send` twice in a row |
| `primary focus stays on composer not send control after successful send` | `FocusManager.primaryFocus` equals composer `FocusNode` |

## Expected behavior (fix acceptance)

- Successful send (button or keyboard) leaves **primary focus** on the discussion composer `TextField`.
- User can send multiple messages in sequence without pointer refocus.
- After edit save, main composer is focused (or edit UX is unified so focus is never dropped from a typing surface).

## Fix direction (not implemented in TDD pass)

- In `_submit()` `finally` or post-success post-frame callback: `if (sent) _composerFocus.requestFocus()` (and web-safe keyboard if product requires).
- Send button: `FocusNode(canRequestFocus: false)` on send control or explicit refocus after tap handling.
- Edit sheet dismiss: post-frame `requestFocus` on room composer (or shared helper used by send).

## Out of scope for this document

- Constellation / home tab routing regressions.
- Server-side message persistence (send succeeds; focus-only defect).
