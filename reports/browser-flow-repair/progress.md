# Browser flow repair verification

Base HEAD: c097d4712ab66d68b1c72011fab4d1e7003688a4. Client bumped to **7.1.1** (AppBar leading fallback + QA tab-attention reemit seam).

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

### Still failing (nine-gate)

1. `request_lifecycle_closed_to_archive_test.dart` — after last review package **auto-closes**, hangs with a raw `TimeoutException` (outside `runE2eStep`) while URL stays on closed `/beacon/view/…?entry=my_work`. Suspect logout/login vs auto-closed detail. Latest: `/tmp/tentura-browser-closed-rerun9.log`.
2. `witness_admission_forward_band_test.dart` — Alice’s recipients tab never shows `Seen helping with` after auto-close (Carol/Bob/Eve Unseen). `/tmp/tentura-browser-archive-witness-rerun2.log`.

`triggerCloseNow` treats Finished+Archive as already closed; logout pops root details before `signOut`. Desk reclaim still not green.

### Remaining acceptance (plan)

- Land closed-to-archive + witness.
- Full eleven-file browser runner.
- Fresh profile+WASM build with one `WEB_BUILD_ID`, trim/version/preload/verify.
- Final custom lint + terminology (already green on current patch).
- Preserve unrelated `docs/Tentura_current_status_quo.md` and pre-existing untracked files; keep build output ignored and `web/manifest.json` skip-worktree.
