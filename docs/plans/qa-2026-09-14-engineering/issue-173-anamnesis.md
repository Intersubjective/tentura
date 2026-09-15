# Issue #173 — Clipboard image paste opens file picker; keyboard paste missing

**GitHub:** [Intersubjective/tentura#173](https://github.com/Intersubjective/tentura/issues/173)  
**Parent:** [#142](https://github.com/Intersubjective/tentura/issues/142)  
**Related:** [#116](https://github.com/Intersubjective/tentura/issues/116) (discussion composer paste/upload)  
**Source:** 2026-09-14 product testing (participant note 23)

## Symptom (bug scope only)

With an **image on the system clipboard**, focusing the **discussion** message composer and pressing **Ctrl/Cmd+V** does **not** attach the image. On **Flutter web**, the default text-field paste path often opens a **file picker** instead of consuming clipboard image bytes. The attach menu item **Paste image** can work when chosen explicitly, but that discoverability complaint is **out of scope** for this engineering note.

User-facing nouns: **Request** / **discussion** workspace (internal `Beacon`, `beacon_room`).

## User-facing expectation (acceptance)

- Copy an image → focus discussion composer → paste → image appears as a pending attachment **without** a file dialog.

## Product path

| Step | Surface | Implementation |
|------|---------|------------------|
| Room body | [`BeaconRoomBody`](../../packages/client/lib/features/beacon_threads/ui/widget/beacon_room_body.dart) | Embeds shared chat surface |
| Chat surface | [`BasicChatBody`](../../packages/client/lib/ui/widget/basic_chat_body.dart) | Message list + [`BeaconRoomComposer`](../../packages/client/lib/ui/widget/basic_chat_body.dart) |
| Clipboard read | [`ClipboardImageRepository.readImage`](../../packages/client/lib/data/repository/clipboard_image_repository.dart) | `super_clipboard` / web interop; returns [`RoomPendingUpload`](../../packages/client/lib/domain/entity/room_pending_upload.dart) |
| Paste (menu only today) | [`_BeaconRoomComposerState._pasteImage`](../../packages/client/lib/ui/widget/basic_chat_body.dart) | Called from attach [`PopupMenuButton`](../../packages/client/lib/ui/widget/basic_chat_body.dart) value `'paste'` |
| File picker path | [`_pickImages`](../../packages/client/lib/ui/widget/basic_chat_body.dart) → `ImageRepository.pickMultipleImages` | Must **not** run for keyboard paste |

## Keyboard / focus behavior (client, as implemented)

| Location | Behavior |
|----------|----------|
| Composer `FocusNode` | [`_composerFocus`](../../packages/client/lib/ui/widget/basic_chat_body.dart) with [`_handleComposerKeyEvent`](../../packages/client/lib/ui/widget/basic_chat_body.dart) |
| Handled keys | Escape (mention overlay / reply banner), arrow/enter/tab for **mention** suggestions only |
| **Not handled** | Ctrl/Cmd+V — no `Shortcuts`, `Actions`, or `PasteTextIntent` override on the composer |
| Platform paste default | [`TextField`](../../packages/client/lib/ui/widget/basic_chat_body.dart) / `EditableText` owns text paste; on web, image paste may degrade to file-input / picker UX |
| Working path | Attach menu → **Paste image** → `_pasteImage()` → `clipboardImageRepository.readImage()` (covered in [`basic_chat_body_test.dart`](../../packages/client/test/ui/widget/basic_chat_body_test.dart)) |

## Root cause (engineering)

1. **No keyboard wiring:** `_pasteImage()` is only reachable from the attach popup menu (`onSelected: 'paste'`). There is no composer-level shortcut or key handler that invokes the same path on Ctrl/Cmd+V.
2. **Key handler gap:** `_handleComposerKeyEvent` returns `KeyEventResult.ignored` for all keys except escape and mention-navigation when the mention overlay is open — paste shortcuts never reach `_pasteImage`.
3. **Web default paste:** Without an explicit image-paste handler, the framework text field paste behavior runs first; for binary/image clipboard content this matches QA’s “asks for a file” report instead of [`ClipboardImageRepository`](../../packages/client/lib/data/repository/clipboard_image_repository.dart).

Repository and menu-path logic from #116 are largely in place; the defect is **input routing**, not missing clipboard decode.

## Failing test (TDD — expected red)

**File:** `packages/client/test/features/beacon_threads/issue_173_composer_clipboard_image_paste_test.dart`

**Command:**

```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 10m -- flutter test \
  --dart-define=ENV=test \
  --dart-define-from-file=env/test.env \
  test/features/beacon_threads/issue_173_composer_clipboard_image_paste_test.dart
```

**Assertions:**

- Focused discussion composer + Ctrl/Cmd+V calls `ClipboardImageRepository.readImage`.
- `ImageRepository.pickMultipleImages` is **not** invoked.
- Pending attachment preview (`Image` under `BeaconRoomComposer`) appears.

## Observed test run (2026-09-15)

**Command:**

```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 10m -- flutter test \
  --dart-define=ENV=test \
  --dart-define-from-file=env/test.env \
  test/features/beacon_threads/issue_173_composer_clipboard_image_paste_test.dart
```

**Result:** `+0 -1` (acceptance red; bug reproduced).

| Test | Result | Observation |
|------|--------|-------------|
| `Ctrl/Cmd+V attaches clipboard image without opening file picker` | **Fail** | `readImageCalls` stays `0` after Ctrl+V and Cmd+V simulation; no pending `Image` preview |

## Fix direction (not implemented in TDD pass)

- Intercept paste at composer scope (e.g. `Shortcuts` + `Actions` / `CallbackShortcuts` wrapping the composer row, or extend `_handleComposerKeyEvent` for Ctrl/Cmd+V) and call `_pasteImage()` when attachments are enabled.
- On web, ensure the handler runs **before** default `EditableText` paste so clipboard images do not fall through to file-input paste.
- Reuse existing `_pasteImage` + `_tryAdd` limits (size, slot count, snackbars) — do not duplicate menu-only logic.
- Keep attach-menu **Paste image** as-is for this bug fix (discoverability is a separate product item).

## Out of scope for this document

- Paste image button placement / labeling (issue UX half).
- Constellation / home tab routing tests.
- Version bump or production code changes in the TDD-only pass.
