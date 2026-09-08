# Browser flow repair verification

Base HEAD: c097d4712ab66d68b1c72011fab4d1e7003688a4. Client now **7.1.3** (split management overflow + deferred ForwardCubit; prior 7.1.1 AppBar/QA seams, 7.1.2 create flush).

## Codex handoff (token limit) — resumed

Codex had left two browser failures after close/review went green: threads navigation and tab-attention clear.

### Fixed and verified

- **Publish helper** checkpoints + `forwardRecipientCheckbox` (Codex): still green in nine-gate rerun.
- **Child journey** (`offer_admit_chat`): PASS.
- **Close/review**, **review trust**, **create/forward/inbox**, **back navigation web**, **threads navigation**, **tab attention**: PASS in `/tmp/tentura-browser-nine-rerun.log` and focused reruns.
- **Threads**: warm deep links now `pushPath` above mounted Home (not `replaceAll`); AppBar back finds `BackButton` or `Icons.arrow_back`; `AutoLeadingWithFallback` keeps a tappable fallback when `AutoLeadingButton` would render empty. Evidence: `/tmp/tentura-browser-threads-rerun3.log`.
- **Tab attention**: QA `__tenturaReemitTabBackground` hook; test clears force via that hook. Evidence: `/tmp/tentura-browser-two-rerun.log`.
- **Server** system-message `authorId` empty-string projection + pg regression: already accepted by Codex.
- **Lint/terminology**: client baseline 32 OK, server 0 OK, terminology OK (`/tmp/tentura-*-rerun.log`).
- **Focused unit**: wasm preload + forward picker PASS.

### Landed (was still failing)

1. **`request_lifecycle_closed_to_archive_test.dart`** — PASS (`/tmp/tentura-browser-closed-witness-fix5.log`).
   - Desk reclaim / Archive path was already green; final assert failed because wide split (1600×1024) mounted overflow only on the thread pane with `inRoomSurface: true`, so **Delete Request** never appeared.
   - Fix: content-pane management overflow (`inRoomSurface: false`) + room overflow on the thread pane; test prefers content overflow / Now when present.

2. **`witness_admission_forward_band_test.dart`** — PASS (same log).
   - `IndexedStack` always built the recipients child, so `ForwardCubit` fetched on the title-only draft (empty `needs`) and cached `filled=false` (`forward_band_composed … filled=false` before the later `needs=transport` UPDATE).
   - Fix: defer `_buildRecipientsTab` / `ForwardCubit` until the recipients step (after `_prepareRecipientsTab` flush); e2e also flushes needs before opening Recipients.

### Eleven-file runner

**All 11 PASS** — `/tmp/tentura-browser-eleven-gate2.log`.

Earlier partial run (`eleven-gate.log`) was 10/11; cover then fixed (icon key, close sheet, Make live wait, checkbox + confirmation). Cover alone: `/tmp/tentura-browser-cover-fix4.log`.

Lint/terminology after 7.1.3: client baseline 32 OK, server 0 OK, terminology OK.

### Remaining acceptance (plan)

- Fresh profile+WASM build with one `WEB_BUILD_ID`, trim/version/preload/verify.
- Preserve unrelated `docs/Tentura_current_status_quo.md` and pre-existing untracked files; keep build output ignored and `web/manifest.json` skip-worktree.
- Commit when asked (client **7.1.3** + product/test fixes).
