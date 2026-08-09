# Plan: Image paste/upload for the Room composer (issue #116)

Status: FINAL — implemented and shipped (see implementation journal). A
known Linux/Wayland-specific limitation was found post-ship and
intentionally left unfixed — see §7.
Source: https://github.com/Intersubjective/tentura/issues/116 (parent #96, split from #101)
Repo: /home/vader/MY_SRC/tentura

## How this plan was produced

Researched the issue and the live codebase, drafted a full-fidelity plan,
then ran three rounds of adversarial review (`codex exec`, independent
read-only passes against the live repository, not just the plan text).

- **Round 1** found the initial "duplicate message on retry" framing was
  factually wrong (the real bug is worse: the composer destroys the draft
  unconditionally on any failure) and flagged the full design as unsafe in
  6 places (no server idempotency, non-atomic attachment positioning, wrong
  error-taxonomy layer, clipboard-in-UI-layer architecture violation, widget
  owning workflow state instead of the Cubit, wrong progress-timing
  assumption).
- **Round 2**, reviewing a revision that added server-side idempotency and
  a Cubit-owned send-session state machine to address round 1, found that
  design correct in direction but substantially larger than a P2 issue
  warrants (transactional idempotency needs a reservation/unit-of-work
  redesign; the `RoomMessageAttachmentAdd` mutation would need a breaking
  GraphQL change to report attachment IDs; `super_clipboard`'s keyboard-
  paste-event API is a global singleton listener that would leak across
  composers and, on web, suppresses default text paste merely by being
  inspected). It also retrieved the actual issue text and confirmed a
  literal reading of "before send" could imply eager/staged upload — a
  materially bigger project (schema change, orphan-attachment cleanup).
- **Given that fork, scope was explicitly decided with the requester**:
  ship only clipboard paste plus a minimal fix for the draft-destruction
  bug; drop per-attachment progress/retry UI, server-side idempotency, and
  the send-session state machine, accepting a documented residual risk.
- **Round 3**, reviewing the rescoped minimal plan, found it directionally
  sound and did not reopen the rejected scope, but caught concrete
  implementation-blocking mistakes: `SystemClipboard.instance` is nullable
  (not "always available"), byte extraction needs `getFile()`/stream
  consumption (not `readValue()`), several test call sites need updating
  for the `bool` contract change, DI/codegen regeneration was unspecified,
  and preserving the draft measurably (not just theoretically) increases
  the odds of hitting the accepted residual duplicate-message risk since
  today's data loss accidentally suppresses it via retyping friction.

Everything below already incorporates all three rounds' findings — this is
not a first draft.

## 0. Ground truth: what already exists (read before touching anything)

Most picker/upload/quota/rendering/multi-client-sync plumbing for Room
attachments already shipped in a prior slice of #101. This plan **extends**
it; do not rebuild any of the following:

- **Composer**: `packages/client/lib/ui/widget/basic_chat_body.dart`,
  `_BeaconRoomComposerState` (L548-1170) — attach menu (`_attachMenuButton`,
  L977-1007) with "Photos" (`_pickImages`, L829, via
  `ImageRepository.pickMultipleImages()`) and "Files" (`_pickFiles`, L856,
  via `file_picker`), a `_pending` list of `RoomPendingUpload`, size/count
  caps (`kMaxRoomMessageAttachments=10`,
  `kMaxRoomMessageAttachmentBytes=10MB`,
  `domain/entity/beacon_room_consts.dart`), thumbnail/chip preview with a
  remove (×) button, and `_submit()` (L891-915) which awaits
  `widget.onSend(body, uploads)`.
- **Wiring**: `features/beacon_room/ui/widget/beacon_room_body.dart`
  builds `BasicChatBody` and passes `onSend: (body, uploads) =>
  cubit.sendMessage(body: body, uploads: uploads)` (L252-257) and
  `imageRepository: GetIt.I<ImageRepository>()` (L258).
- **Domain**: `RoomPendingUpload{bytes, fileName, mimeType}`
  (`domain/entity/room_pending_upload.dart`).
- **Use case**: `BeaconRoomCase.createMessage`
  (`features/beacon_room/domain/use_case/beacon_room_case.dart` L133-162)
  sends the first upload inline with the create mutation, then loops the
  rest through `addMessageAttachment` one at a time — this is why a
  partial failure can leave a message with some, but not all, attachments
  server-side (see §2).
- **Sync**: `RoomCubit.sendMessage` (`features/beacon_room/ui/bloc/room_cubit.dart`
  L708-782) forces a messages refetch when `uploads.isNotEmpty` (L763-765);
  attachments already survive reload and multi-client sync — not touched
  by this plan.
- **Precedent repository pattern to mirror**: `ImageRepository`
  (`data/repository/image_repository.dart`) — `@Singleton`, dev/prod split,
  with a test double registered in
  `data/repository/mock/client_repository_mocks.dart:96`.

## 1. Scope

**In scope**
1. Clipboard image paste via an explicit, discoverable "Paste image" item
   in the existing attach menu (tap-triggered clipboard read) — works
   uniformly on every platform this repo targets, subject to the browser
   limitation noted in §3.
2. Stop the composer from unconditionally destroying the draft (body +
   pending attachments) when a send fails — preserve it so the user can
   see what happened and decide to retry, edit, or abandon.
3. l10n (en+ru), semver bump, lint baseline respected, tests for both
   changes.

**Explicitly out of scope — deliberately cut after review, not forgotten**
- Per-attachment upload progress indicators/spinners beyond the existing
  composer-wide busy/disabled state.
- Per-attachment retry UI or retry semantics of any kind.
- Server-side idempotency keys/migrations, and the pre-existing
  non-atomic attachment-position race in
  `packages/server/lib/domain/use_case/beacon_room_case.dart` (~L1028,
  `position = await countAttachmentsForMessage(...)` then insert, no
  unique constraint) — real, latent, **not fixed by this plan**.
- A Cubit-owned send-session state machine / typed failure taxonomy.
- Automatic keyboard-shortcut clipboard paste (Ctrl+V/Cmd+V) — `super_clipboard`'s
  `ClipboardEvents` paste-listener API is a global singleton (not scoped
  per-widget: two mounted composers would both react to one event) and,
  on web, merely inspecting the event for an image format calls
  `preventDefault()` internally, which would suppress ordinary text paste
  even when only images were meant to be intercepted. Avoiding that whole
  class of problem is exactly why this plan uses only the explicit,
  tap-triggered `SystemClipboard.read()` API instead (see §3) — this is a
  deliberate mechanism choice, not an oversight.
- Reply-to-message (#101's other half — separate issue).
- Eager/staged upload decoupled from pressing Send.

**Accepted residual risk** (confirmed by round 3, stated honestly rather
than downplayed): preserving the draft on failure makes it *easier* than
today to hit the pre-existing partial-success duplicate-message edge case
(message created server-side, a later attachment upload then fails, user
sees their unchanged draft and presses Send again unchanged) — today's
draft-destruction bug accidentally suppresses this via the friction of
having to retype everything from scratch. This plan makes that tradeoff
knowingly: `RoomCubit.sendMessage` already performs an authoritative
message refetch before reporting failure (`room_cubit.dart:766`), so a
successfully created message will typically become visible in the thread
before the user has a chance to blindly resend — bounding, not eliminating,
the risk. **Do not add an artificial post-failure Send cooldown as
mitigation** — it doesn't address the actual cause and `_submitting`
already prevents concurrent double-sends (`basic_chat_body.dart:891`).
Revisit with real server idempotency (see prior draft rounds, available on
request) only if this turns out to be a reported problem in practice.

## 2. Composer fix: preserve the draft on send failure

**Current behavior**: `RoomCubit.sendMessage` catches every exception that
occurs *after its own try block begins* (`room_cubit.dart:735`) and
returns normally without rethrowing (L766-780: shows a snack, rolls back
the optimistic local message, refetches). Note precisely, per round 3: the
cubit does **not** literally catch every exception in the method — some
setup runs before the try block (L716-734); an exception thrown there would
still propagate to the composer. The composer's `_submit()`
(`basic_chat_body.dart:891-915`) `await`s the cubit method as `widget.onSend`
and, because that call almost always resolves without throwing, almost
always takes its "success" branch: `_text.clear(); _pending.clear();`
(L907-908) — regardless of whether the send actually succeeded.

**Fix**: change the contract so the composer can tell success from a
handled failure, and only clear on real success.

- Change `RoomCubit.sendMessage`'s return type from `Future<void>` to
  `Future<bool>`. Exact branches (per round 3, spelled out precisely so an
  implementer can't get this wrong):
  - The current blank-input early return at `room_cubit.dart:712-714`
    (`if (trimmed.isEmpty && uploads.isEmpty) { return; }`) becomes
    `return false;`.
  - `true` is returned only after the full existing success path
    completes (i.e., at the end of the `try` block, after L765).
  - `false` is returned at the end of the existing `catch (Object e)`
    block (after L780), preserving every existing side effect in that
    block unchanged (snack error, optimistic-message rollback, silent
    refetch).
- Update the `onSend` callback type on `BasicChatBody`
  (`ui/widget/basic_chat_body.dart:96-97`) and `BeaconRoomComposer`
  (same file, ~L535) from `Future<void> Function(String, List<RoomPendingUpload>)`
  to `Future<bool> Function(String, List<RoomPendingUpload>)`. The only
  production call site is `features/beacon_room/ui/widget/beacon_room_body.dart:252`
  — update it to return the cubit's result directly (it already forwards
  the call; no other production caller of `RoomCubit.sendMessage` exists).
- `_submit()` (`basic_chat_body.dart:891-915`): only run
  `_text.clear(); _pending.clear();` when the awaited result is `true`.
  On `false`, leave the composer's text and pending attachments exactly as
  they were — the cubit has already shown the error snack; no additional
  UI is needed here beyond *not* destroying the draft. Keep the existing
  `on Object catch (_) {}` around the `await widget.onSend(...)` call as a
  defensive fallback for the pre-try-block exception path noted above —
  it is not dead code.
- **Test call-site ripple** (round 3 — these currently return `void` and
  must be updated to return `true`, or the change won't compile against
  existing tests): `packages/client/test/ui/widget/basic_chat_body_test.dart`
  L75, L157, L223; `packages/client/test/ui/widget/mention_suggestions_overlay_test.dart`
  L75. `packages/client/test/features/beacon_room/room_cubit_unread_test.dart:632`
  calls `sendMessage` directly and ignores its return value — confirmed
  unaffected, no change needed there.

**New/updated tests**
- `RoomCubit.sendMessage` returns `true` on success.
- `RoomCubit.sendMessage` returns `false` when the use case throws
  **before** any message is created (existing mocked-repository failure
  pattern).
- `RoomCubit.sendMessage` returns `false` specifically for the
  **post-create, extra-attachment failure** case too (not only pre-create)
  — reuse the fake-repository setup already proven in
  `packages/client/test/features/beacon_room/beacon_room_case_test.dart:137`
  (a later attachment fails after the message and first attachment
  succeeded).
- Composer widget test: `onSend` resolves to `false` → text field still
  contains the typed body, pending attachments are still present
  afterward (regression test for the exact bug being fixed).
- Composer widget test: `onSend` resolves to `true` → composer clears
  (prevents a future regression of existing behavior).

## 3. Clipboard image paste: explicit "Paste image" action only

**Mechanism, and why**: use only `super_clipboard`'s explicit, tap-triggered
read API — never its keyboard paste-*event*-listener API. See §1's "out of
scope" entry for the concrete reasons (global singleton listener,
web `preventDefault()` on inspection). Because this mechanism never touches
the paste-event pipeline, it cannot interfere with ordinary text paste
anywhere in the app, and it works the same way regardless of how many
composers happen to be mounted.

**Corrections from round 3 (load-bearing, not stylistic):**
- `SystemClipboard.instance` is **nullable** in `super_clipboard` 0.9.1 —
  it is `null` when the platform/browser has no working clipboard-read API
  (explicitly including Firefox by default, which lacks the async
  Clipboard API). `null` means "clipboard reading is unsupported here,"
  which is a **distinct** state from "clipboard has no image" and must be
  messaged distinctly (e.g. "Clipboard access isn't available in this
  browser" vs. "No image on clipboard"). Do not claim uniform
  cross-platform support without this caveat.
- `reader.canProvide(Formats.png)` (etc.) only probes *availability* of a
  format — it is not how you get bytes. Bytes come from
  `reader.getFile(Formats.png, (file) { ... file.getStream() / readAll()
  ... })`; `readValue()` is not the binary-image API. Define a
  deterministic format priority (e.g. png, then jpeg, then webp, then gif)
  and a MIME/extension mapping with a fallback filename (e.g.
  `clipboard.png`) for when the clipboard source has no filename.
- The whole read (`SystemClipboard.instance` access through `getFile`'s
  async callback/error path) must be wrapped so a rejected/denied
  permission prompt or any other read failure is caught and surfaced as
  a localized "Could not read clipboard" message — this flows through an
  async `PopupMenuButton.onSelected` handler, so an uncaught rejection
  there is a real crash/silent-failure risk, not a theoretical one.
- `SystemClipboard` has a private constructor, so the new repository needs
  its own internal test seam (e.g. an injectable read-function parameter,
  or a testing constructor on the new repository itself) — "mock
  SystemClipboard directly" is not viable guidance.

**Implementation**
- New repository `packages/client/lib/data/repository/clipboard_image_repository.dart`,
  mirroring `ImageRepository`'s registration pattern (`@Singleton`,
  dev/prod split; add a corresponding test double in
  `data/repository/mock/client_repository_mocks.dart` next to
  `ImageRepository`'s). Public API returns a domain DTO — reuse
  `RoomPendingUpload` (keeps plugin types out of the domain/UI layers per
  `.cursor/rules/architecture.mdc:55`) — with a result type that
  distinguishes: image found → `RoomPendingUpload`; no image on an
  available clipboard → a clean "not found" result; clipboard unsupported
  on this platform → a distinct "unsupported" result; read failed →
  propagate as a catchable error for the caller to turn into a snack
  message (do not silently swallow it inside the repository).
- Add `super_clipboard` to `packages/client/pubspec.yaml` (`0.9.1` as of
  this plan — reconfirm current/compatible version at implementation
  time), run `flutter pub get` (this is a pub workspace — the root
  `pubspec.lock` update is part of this same commit), then run `dart run
  build_runner build -d` to regenerate DI/codegen for the new
  `@Singleton` (CI does this before tests, `.github/workflows/pipeline.yml:85`
  — a worker skipping it will pass locally-stale and fail CI).
- Wire dependency propagation explicitly:
  `BeaconRoomBody` (`features/beacon_room/ui/widget/beacon_room_body.dart:252`,
  already resolves `ImageRepository` via `GetIt.I<...>()` here) resolves
  the new repository the same way and passes it down through
  `BasicChatBody` → `BeaconRoomComposer` as a constructor parameter,
  matching the existing `imageRepository` plumbing exactly.
  `packages/client/test/features/beacon_room/beacon_room_message_actions_sheet_test.dart:93`
  currently registers only `ImageRepository` in GetIt before building
  `BeaconRoomBody` — update that test's setup to also register the new
  repository (or a mock of it), or the new lookup will crash that test.
- New attach-menu item ("Paste image") in `_attachMenuButton`
  (`basic_chat_body.dart:977-1007`), alongside "Photos"/"Files" — same
  `PopupMenuItem` styling, no new design-system component needed. On
  success, route the resulting `RoomPendingUpload` through the existing
  `_tryAdd` (`basic_chat_body.dart:796-809`) — identical size/count
  enforcement as Photos/Files, no parallel validation path. On "no image"/
  "unsupported"/"error", show the existing `_snack(...)` pattern with a
  new, localized, state-specific message (not one generic string for all
  three cases).

**New/updated tests**
- `ClipboardImageRepository` unit tests via the injected test seam:
  image present → returns populated `RoomPendingUpload`; clipboard
  supported but no image (text-only or empty) → "not found" result;
  clipboard unsupported → distinct "unsupported" result; `getFile`
  error/rejected permission → propagates catchably, does not throw
  unhandled inside the repository.
- Composer widget test: tapping "Paste image" with a repository mock
  returning an image adds it to the pending-attachment tray via the same
  path as picking from Photos (assert identical resulting state shape).
- Composer widget test: tapping "Paste image" with a mock returning
  "not found" shows the correct message and adds nothing.
- Composer widget test: tapping "Paste image" with a mock returning an
  oversized image is rejected via `_tryAdd` (proves the size cap is
  actually enforced on this new path, not just assumed).
- Composer widget test: tapping "Paste image" with a mock that throws
  (simulating a read/permission error) shows the "could not read
  clipboard" message and adds nothing, without crashing.
- No automated Ctrl+V/two-composer regression test is required — since no
  paste-event listener is ever registered, there is no shared mechanism
  to regress. Manual check (§5) confirms ordinary text paste is unaffected.

## 4. l10n, versioning, lint

- Add ARB entries to `packages/client/l10n/app_en.arb` and `app_ru.arb`
  (paths and generation confirmed via `packages/client/l10n.yaml`) for:
  "Paste image" menu label, "No image on clipboard", "Clipboard access
  isn't available" (unsupported-platform case), "Could not read
  clipboard" (error case). Run `cd packages/client && flutter gen-l10n`
  after editing.
- Bump the client version: current is `5.7.1`
  (`packages/client/pubspec.yaml:5`, confirmed directly, not assumed) →
  `5.8.0` (minor bump per `.cursor/rules/versioning.mdc` — new
  user-visible capability). No server API changes in this plan, so
  `MIN_CLIENT_VERSION` is unaffected.
- Lint baseline (confirmed against `scripts/custom-lint-baseline.txt:19`:
  client 111, server 0) must not regress. The checker takes a package
  path argument: `./scripts/check-custom-lints.sh packages/client` (and
  `packages/server` if server files are touched, which this plan does not
  anticipate).

## 5. Verification

- `flutter test test/features/beacon_room/`
- `flutter test test/ui/widget/basic_chat_body_test.dart` (and
  `test/ui/widget/mention_suggestions_overlay_test.dart` for the callback
  signature ripple)
- New `flutter test test/data/repository/clipboard_image_repository_test.dart`
- `./scripts/check-custom-lints.sh packages/client`
- Standard web build gate already run by CI includes a `--wasm` build
  (`.github/workflows/pipeline.yml:290`) — ordinary widget tests don't
  prove plugin/Wasm compatibility, so this must pass as part of
  verification, not be assumed from unit tests alone. iOS cannot be
  build-verified on a Linux host — note that limitation explicitly rather
  than claiming four-platform local proof; rely on `super_clipboard`'s
  published iOS support and the app/TestFlight pipeline for that leg.
- Manual pass via the `local-debug` skill: pick an image via the system
  dialog (confirm no regression); paste an image via the new menu action
  on web; trigger each of the three non-happy-path clipboard states if
  feasible (no image, unsupported browser via Firefox if available,
  permission-denied); force a send failure (e.g. disconnect network
  mid-send) and confirm the draft (text + attachments) remains in the
  composer instead of vanishing; confirm ordinary text paste (Ctrl+V) into
  the message field and at least one other text field elsewhere in the
  app is unaffected.
- No server-side changes in this plan; no server test delta expected.

## 6. Implementation units (for `/overseer`)

Two independently committable, independently testable units, in this
order (A has no new dependency and is lower risk; B depends on nothing
from A but is sequenced second since it's the larger unit):

- **Unit A** — §2 (composer draft-preservation fix) + its tests. No new
  dependencies, no DI/codegen changes, no l10n changes.
- **Unit B** — §3 (clipboard paste) + §4 (l10n/version/lint) + its tests.
  Depends on `super_clipboard` being added and `build_runner` regenerated
  before the repository can be used anywhere.

Both units' acceptance criteria, exact file:line targets, and test lists
are fully specified above — an implementation worker should not need to
make undocumented design decisions for either unit.

## 7. Known bug (post-ship, intentionally not fixed): clipboard image paste unreliable on Linux/Wayland

**Symptom**: on Ubuntu GNOME (Wayland session, Chrome running under
Xwayland), copying an actual image (via a screenshot tool, or "Copy Image"
from a browser/viewer — not a file-manager file copy) and then either
pressing Ctrl+V in the composer's text field or using the "Paste image"
menu action fails: Ctrl+V inserts a text file path instead of the image,
and "Paste image" reports "No image on clipboard" even though a real image
was on the clipboard moments earlier. Other web apps reading the same
clipboard content in the same browser session (e.g. WhatsApp Web)
successfully paste the image, so this is not a case of the OS clipboard
lacking real image data.

**Root cause, confirmed by live reproduction** (not theoretical — tested
directly in a real local browser session via Playwright against the
running dev stack): real `image/png` bytes written to the OS clipboard
degrade to a `text/plain`-only representation within roughly 300ms when
read back through the browser's **Async Clipboard API**
(`navigator.clipboard.read()`):

```js
await navigator.clipboard.write([new ClipboardItem({'image/png': blob})]);
await navigator.clipboard.read();                // -> item.types: []
// ...~300ms later...
await navigator.clipboard.read();                // -> item.types: ["text/plain"]
```

This happens in-process, with nothing else touching the clipboard — it is
consistent with Mutter (GNOME's Wayland compositor) acting as the
clipboard-manager bridge for Xwayland clients (Chrome) and not preserving
rich MIME types when it caches/re-serves clipboard ownership. It is a
platform/desktop-environment behavior, not something this app's code
controls.

**Why both paste paths hit it**: `ClipboardImageRepository` (§3, Unit B)
reads only via `super_clipboard`'s `SystemClipboard.instance.read()`, i.e.
the Async Clipboard API — the exact path that degrades above. Ctrl+V hits
it too because the composer deliberately never registers a `paste` event
listener (see §1/§3 "out of scope"), so it falls through to the browser's
own default plain-text paste, which surfaces the same degraded
`text/plain` fallback (a file path, when the image-producing tool also
sets one as a secondary clipboard format).

**Why WhatsApp Web (and similar) are unaffected**: they read the classic,
synchronous `paste` DOM event (`event.clipboardData.items`) instead of the
Async Clipboard API. That reads the "live" clipboard selection at the
instant of the keypress, before the Wayland-side degradation occurs.
`super_native_extensions` (the library backing `super_clipboard`) already
contains exactly this mechanism (`ClipboardEventsImpl`,
`lib/src/web/clipboard_events.dart`), but this plan's §1/§3 deliberately
chose not to use it, for reasons unrelated to this bug (global
`window`-level listener, `preventDefault()` as a side effect of event
inspection — see §1's "out of scope" entry).

**A concrete fix exists but was deliberately not implemented**: a
narrowly-scoped native `paste` listener (bypassing `super_clipboard`'s
`ClipboardEvents` wrapper, checking `event.clipboardData.items` directly,
calling `preventDefault()` only when an image item is actually found, and
gated on the composer's own `FocusNode` having focus) would fix Ctrl+V and
match WhatsApp Web's behavior. It was scoped out because: it reopens an
architectural risk this plan's round-1 review already rejected once
(global paste-event interception risking ordinary text paste elsewhere in
the app); the failure is Linux-desktop-specific and cannot be exercised in
CI (no real desktop clipboard manager in headless test environments); and,
as of this writing, it is known to affect only the original developer's
own Linux desktop, not a reported multi-user problem. It would also not
fix the "Paste image" button itself, which is inherently tied to the Async
Clipboard API with no browser-side workaround.

**Revisit if**: this is reported by more than one Linux desktop user, or
`super_clipboard`/`super_native_extensions` ships an Async Clipboard API
fix upstream for this class of clipboard-manager interaction.

**Workaround**: use the "Photos" picker (select the saved image file from
disk) instead of paste. macOS/Windows and non-Wayland-affected Linux setups
are not known to hit this.
