# Issue #164 — Deleted images reappear after Create request removal

**GitHub:** [Intersubjective/tentura#164](https://github.com/Intersubjective/tentura/issues/164)  
**Source:** 2026-09-14 product testing

## Symptom

On **Create request**, after adding a gallery image and then **removing** it, the thumbnail disappears immediately but **reappears about one second later** (aligned with the quiet autosave debounce). The image can remain visible after several seconds and can still be present after **draft save / reopen**.

User-facing noun: **Request** (internal `Beacon`).

## User-facing expectation

| Action | Gallery |
|--------|---------|
| Add image → remove → wait several seconds | **Stays removed** |
| Save draft and reopen | **No removed image** |

## Product path

| Step | Surface | Implementation |
|------|---------|------------------|
| Image gallery | Create request — images tab | [`ImageTab`](../../packages/client/lib/features/beacon_create/ui/widget/image_tab.dart) → `cubit.removeImage(index)` |
| Local removal | Cubit | [`BeaconCreateCubit.removeImage`](../../packages/client/lib/features/beacon_create/ui/bloc/beacon_create_cubit.dart) — updates `state.images` only; `_scheduleAutosave()`; **no** `BeaconRepository.removeImage` |
| Quiet autosave | 1s `Timer` | `_scheduleAutosave` → `_quietPersist` → `saveDraft(quiet: true)` |
| Persist media | Use case | [`BeaconCreateCase._reconcile`](../../packages/client/lib/domain/use_case/beacon_create_case.dart) — `setMedia` with `imageIds` from the save command snapshot |
| Post-save UI merge | Cubit | `saveDraft` / `ensureDraft` success → `_applyServerMedia` sets `images:` to `result.images` from that save |

## Root cause (engineering)

Two coupled defects explain both the **~1s snap-back** and **stuck wrong state**:

1. **Stale reconcile overwrites local removal.** `saveDraft` captures `command.images` at call time via `_command(..., images: state.images)`. When an earlier quiet persist is still in flight, the user can call `removeImage`, which correctly clears local state. When that **older** `saveDraft` completes, `emit(_applyServerMedia(state.copyWith(...), result.beacon, result.images))` replaces `images` with the **stale** `result.images` list from the pre-removal command — unconditional overwrite in [`_applyServerMedia`](../../packages/client/lib/features/beacon_create/ui/bloc/beacon_create_cubit.dart).

2. **Missed follow-up autosave after removal during `isAutosaving`.** `_quietPersist` returns immediately when `state.isAutosaving` is true. If the removal’s 1s debounce fires while the stale save is still running, that autosave is **dropped** and nothing reschedules when the save finishes. The UI can stay on the resurrected image until another edit triggers save.

Save is **not** additive on the server path for duplicates: `setMedia` sends the full `imageIds` list from the command snapshot. The bug is **client-side ordering** (late completion + media merge), not a server that ignores deletes.

## Fix direction (not implemented in TDD pass)

- **Merge policy:** On save completion, do not blind-replace `images` when local state has diverged (e.g. compare keys/ids, or track a monotonic “media generation” / pending deletion set).
- **Serialization:** Await or cancel in-flight quiet persist before applying local removals, or queue a follow-up persist guaranteed to run after the in-flight one completes.
- **Autosave:** If `_quietPersist` skips because `isAutosaving`, reschedule when `isAutosaving` returns to false.

## Observed test run (2026-09-15)

**Command:**

```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 10m -- flutter test \
  --dart-define=ENV=test \
  --dart-define-from-file=env/test.env \
  test/features/beacon_create/issue_164_deleted_images_reappear_test.dart
```

**Result:** `+0 -1` (acceptance red on current code).

| Test | Role |
|------|------|
| `in-flight draft save must not restore an image removed while persisting` | Holds `setMedia` via `FakeBeaconWritePort.setMediaHold`, removes image during `flushAutosave`, expects empty gallery after complete + 2s wait |

## Files touched (TDD only)

- `packages/client/test/features/beacon_create/fake_beacon_ports.dart` — `setMediaHold` for delayed reconcile
- `packages/client/test/features/beacon_create/issue_164_deleted_images_reappear_test.dart` — failing acceptance
- `docs/plans/qa-2026-09-14-engineering/issue-164-anamnesis.md` — this note

**No production code changes** in this pass.
