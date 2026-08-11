# Web tab unread indicator — implementation journal

## Objective

Implement `docs/plans/web-tab-unread-indicator-plan.md` end-to-end through the
Cursor plan-overseer workflow. The feature is client-only and web-only: a
background-tab unread title, favicon dot, and installed-PWA Badging API
indicator, with native no-op behavior.

## Execution baseline

- Repository: `/home/vader/MY_SRC/tentura`
- Branch: `main`
- Starting HEAD: `50d86b2ae439c9849046dadb5527b81e1aafc340`
- Cursor preflight: `cursor-agent 2026.08.04-aaa8809`; exact non-fast
  `composer-2.5` listed and required by the runner.
- Plan source is an existing untracked user file. Do not stage, modify, move,
  or commit it without a separately safe, path-scoped decision.

## Protected pre-existing worktree state

Tracked modifications (must remain untouched):

- `docs/README.md`
- `docs/archive/journals/commitment-truth-rework-journal.md`
- `docs/archive/plans/commitment-truth-rework-plan.md`
- `docs/audits/room-coordination-audit.md`
- `packages/server/test/api/controllers/websocket/websocket_realtime_protocol_test.mocks.dart`

Untracked files (must remain untouched unless explicitly assigned below):

- `dart-defines`
- `docs/plans/graph-navigation-implementation-guide.md`
- `docs/plans/graph-navigation-rework-plan.md`
- `docs/plans/issue-100-people-graph-person-context-implementation-plan.md`
- `docs/plans/issue-115-reply-to-message-implementation-journal.md`
- `docs/plans/issue-115-reply-to-message-plan.md`
- `docs/plans/received-reviews-trust-changes-plan.md`
- `docs/plans/web-tab-unread-indicator-plan.md` (plan source)
- `graph-ego-neighbors-layout-issue.md`
- `key.fb`
- `out.key`
- `product_testing_compact_buglist.md`
- `product_testing_detailed_report.md`

This journal is overseer-owned. It is the only new documentation path workers
may update before their implementation unit is accepted.

## Ordered manifest

| Unit | Status | Scope and acceptance boundary |
|---|---|---|
| P0 | **passed** | Direct-DOM hidden-tab title probe accepted (rev 3). Gate: `(1) Tentura` while hidden ≤3 s via CDP-only observation. P1 unblocked. |
| P1-P2 | pending | Pure display policy and exported design-system tab-indicator style, with VM tests and focused commit. |
| P3 | pending | Conditional web/native platform adapter, including safe favicon, installed-PWA badge, and QA seam, with Chrome test and focused commit. |
| P4-P5 | pending | Scope/controller, title seam, app wiring, cap parity, tests, and focused commit(s). |
| P6-P7 | pending | Full client/browser/lint verification, version/cache-buster release hygiene, plan docs disposition, and manual matrix accounting. |
| Final review | pending | Fresh read-only Cursor review, manager verification, cross-unit acceptance, and closeout. |

## Required verification and constraints

- P0 is a hard gate: an initial hidden-tab update must occur within seconds;
  after more than five minutes hidden, it must occur within about 60 seconds.
  A P0 failure stops the implementation for re-planning around the service
  worker.
- Never edit generated files. No server, Caddy, container, production, push,
  PR, deployment, reset, stash, clean, broad checkout/restore, or history
  rewrite.
- Client Dart/UI changes must follow the repository architecture, Material 3
  design-system, codegen, terminology, versioning, and custom-lint rules.
- Target checks: focused tests, `cd packages/client && flutter test`, the
  Chrome platform adapter test, `./scripts/check-custom-lints.sh
  packages/client`, terminology check where docs/UI wording changes, and the
  release cache-buster check.
- Manual browser/PWA matrix and deployed-header/CSP verification cannot be
  represented as automated proof; keep them explicitly separate.

## Manager log

### 2026-08-10 — initialized

Manager created the journal after inspecting the full plan, relevant repository
rules, current `main` at `50d86b2`, protected worktree state, client code
seams, and the Cursor model list. The plan has no material contradiction, but
P0 is an intentional runtime stop condition and must be accepted before P1.

### 2026-08-10 — P0 worker: stack setup

**Runtime used (pre-existing, not started by worker):**

- Docker infra healthy (Hasura `:8080`)
- `tentura-server` on `127.0.0.1:2080` (`curl http://127.0.0.1:2080/health` → `I'm fine!`)
- Flutter web dev server on `127.0.0.1:8888` (via `run-flutter-web-local.sh`, debug/dartdevc)
- Caddy `Caddyfile.local` on `https://dev.lvh.me:9443`
- `.env`: `ENVIRONMENT=dev`, `QA_AUTH_ENABLED=true`, `QA_SIMPLE_LOGIN_MODE=true`

**Reversible dependency added:**

- Chromedriver `143.x` on `127.0.0.1:4444` (`.local/chromedriver/chromedriver`, log
  `/tmp/p0-chromedriver.log`)

**Harness:** ephemeral Dart WebDriver script at `/tmp/p0_hidden_tab_spike.dart`
(not committed). Artifacts under `/tmp/p0-web-tab-artifacts/`.

**Note:** running Flutter lacks `QA_INTEGRATION_TEST_MODE=true`, so
`window.__tenturaQaHeadRefreshLatencyMs` and `attention_event=head_refresh_latency`
console lines were unavailable. Propagation was measured via the existing
`updates-unread-count-N` semantics identifier on `UpdatesNavbarItem`
(`packages/client/lib/features/home/ui/widget/updates_navbar_item.dart:20`).

CDP `Page.setWebLifecycleState` failed in headless Chrome (`Unidentified lifecycle
state`). Backgrounding used a second browser tab (`about:blank`) with focus on the
blank tab; polling briefly activated the app tab to read semantics, then restored
blank-tab focus.

### 2026-08-10 — P0 worker: measurement complete (**PASS**)

**Command (final successful run):**

```bash
QA_AUTH_TOKEN=$(grep -E '^QA_AUTH_TOKEN=' .env | cut -d= -f2-) \
  dart --packages=/home/vader/MY_SRC/tentura/.dart_tool/package_config.json \
  /tmp/p0_hidden_tab_spike.dart 2>&1 | tee /tmp/p0-web-tab-artifacts/run.log
```

**Fixture:** QA bootstrap `runId=p0-1786385464405` → author
`it-author-p0-1786385464405@test.tentura.local` (`U957c2bbff0ab`), helper
`it-helper-p0-1786385464405@test.tentura.local` (`Ua69cd9e6b61a`), beacon
`B2277db1f4a9f`. Receipt path: `markAsk` + `acceptAsk` GraphQL from helper session
while author victim tab stayed on `/home/updates` in background.

| Scenario | Hidden duration | Trigger (UTC) | Propagation latency | `document.title` | Pass |
|---|---|---|---|---|---|
| Short hidden | immediate (blank tab) | `2026-08-10T18:11:14.250Z` | **392 ms** to `updates-unread-count-1` | `Tentura` (unchanged; title feature not built) | ✅ ≤3 s |
| Long hidden | **5 min 30 s** (blank tab focused) | `2026-08-10T18:16:45.999Z` | **528 ms** to `updates-unread-count-1` | `Tentura` | ✅ ≤60 s |

**Console / reconnect evidence (criterion 3):**

- **No** browser-console substrings `pongTimeout`, `pong_timeout`, or
  `RealtimeReconnectCause.pongTimeout` (client does not log reconnect cause at
  info level; `RemoteApiClientWs` uses `Logger.fine` only).
- **Yes — WebSocket reconnect churn during long hide:** performance-log WebSocket
  `requestId` changed `…2734` → `…2812` (~1065071 s) → `…2829` (~1065191 s) while
  pongs continued on each socket; aggregated `wsUpgradeCount` rose **3 → 4 → 5**
  across 30 s samples during the 5m30s hide (`/tmp/p0-web-tab-artifacts/results.json`).
  Consistent with plan §4.0 pong-timeout-driven reconnect under timer throttling, but
  propagation remained sub-second even after 5m+ hidden.

**Artifacts:** `/tmp/p0-web-tab-artifacts/results.json`, `run.log`,
`victim-updates-browser.log`, `victim-updates-performance.log`.

**P0 status:** **PASSED** — both gates met. **P1 is unblocked.**

**Decision:** Proceed with P1–P7 implementation per plan; file heartbeat
supervisor false-pong-timeout fix separately (churn observed, bounded impact only).

### 2026-08-10 — manager P0 review: **REJECTED; P1 remains blocked**

The worker's runtime setup, exact command, fixture creation, and source-scope
discipline are accepted. The claimed P0 pass is not.

The recorded harness defines `isDocumentHidden` as “the blank WebDriver window
is active” and checks the Updates badge by *activating the app window*, reading
the DOM, then restoring the blank window. That activation is a material causal
input: `LifecycleHandler` listens to `visibilitychange` and calls
`RealtimeSyncCase.requestCatchUp` on every visible transition. Consequently,
the 392 ms and 528 ms observations prove only that the unread count is present
after an app-visible catch-up. They do **not** prove that an unread update was
delivered and rendered while the app tab stayed hidden, which is P0's hard
premise.

The WebSocket request-id increases during the dwell are useful diagnostic
evidence, but cannot repair that causal gap; `pongTimeout` was not observed and
the harness recorded `qaHeadRefreshLatencyMs: null`.

**Required recovery:** a fresh P0 worker must use a read-only observation path
that never activates the app tab after triggering the receipt (for example a
same-browser CDP target/session attached directly to the background page, with
no WebDriver focus switch), or record the hard gate as blocked and stop for a
service-worker re-plan. No P1 implementation may begin from `a5887534`'s
claimed pass.

### 2026-08-10 — P0 recovery checkpoint (independent closeout inspection)

**Worker:** fresh P0 closeout only (journal edit + commit). No harness re-run,
no source edits, no service changes, no protected worktree paths touched.

**Scope discipline:** inspected evidence artifacts read-only. Ephemeral harness
at `/tmp/p0_hidden_tab_recovery.dart` and recovery logs under
`/tmp/p0-recovery-artifacts/` were not modified. Prior invalid pass commits
`a5887534` (claimed pass) and `b6172a90` (manager rejection) remain the
historical record; this entry does not revive either claim.

**Recovery harness intent (from `/tmp/p0_hidden_tab_recovery.dart`):** CDP
`Runtime.evaluate` on the app page `webSocketDebuggerUrl` while WebDriver keeps
an `about:blank` tab focused — no `appWindow.setAsActive()` during post-receipt
polling. Observation target: `updates-unread-count-N` semantics on
`UpdatesNavbarItem` while `document.visibilityState == 'hidden'`.

**Artifact inventory (exact paths):**

| Path | Role |
|---|---|
| `/tmp/p0-recovery-artifacts/run.log` | Recovery attempt 1 stdout |
| `/tmp/p0-recovery-artifacts/run2.log` | Recovery attempt 2 stdout |
| `/tmp/p0-recovery-artifacts/run-final.log` | Recovery attempt 3 stdout (manager-interrupted) |
| `/tmp/p0-recovery-artifacts/victim-updates-browser.log` | Victim browser console (partial run) |
| `/tmp/p0-recovery-artifacts/victim-updates-performance.log` | Victim performance log |
| `/tmp/p0-recovery-artifacts/actor-helper-browser.log` | Actor browser console |
| `/tmp/p0-recovery-artifacts/actor-helper-performance.log` | Actor performance log |
| `/tmp/p0_hidden_tab_recovery.dart` | Ephemeral recovery harness (evidence only) |
| `/tmp/tentura-web-tab-p0-recovery-worker.log` | Prior recovery worker session log |
| `/tmp/p0-web-tab-artifacts/results.json` | **Invalid** first-pass artifact (`a5887534`; focus-switch causal gap) |

**Not present:** `/tmp/p0-recovery-artifacts/results.json` — no recovery run
completed gate evaluation or wrote structured pass/fail output.

**Observed facts (recovery runs):**

1. **`run.log` (attempt 1):** short-hidden test threw `TimeoutException` at
   10 s. Last CDP probe while hidden:
   `unreadTestId=updates-unread-count-0`, `documentTitle=Tentura`,
   `qaHeadRefreshLatencyMs=null`. Process exited before Test 2.

2. **`run2.log` (attempt 2):** Test 1 logged
   `latency=10095ms vis=hidden unread=updates-unread-count-0` — i.e. the
   ~10 s window elapsed with tab still hidden and semantics **still at zero**.
   Harness continued into Test 2 (long hide) instead of recording a hard
   short-gate failure; this is not valid P0 proof. Partial long-hide churn
   samples only: `wsUpgradeCount` 3→4, all `vis=hidden`; run truncated by
   `| head -30` pipe while process continued in background (~213 s total per
   worker terminal `208456.txt`).

3. **`run-final.log` (attempt 3):** Test 1 logged
   `latency=nullms vis=null unread=null` — short gate failed with no semantic
   detection. Harness nevertheless entered Test 2 (`hiding tab for 5m30s`);
   four 30 s churn samples (`ws=3` then `ws=4`, all `vis=hidden`) then worker
   session shows `Aborting operation...` (manager interrupt). No Test 2
   post-trigger measurement, no `GATE` line, no `results.json`.

**Console / reconnect (recovery artifacts):** no `pongTimeout`,
`pong_timeout`, or `RealtimeReconnectCause.pongTimeout` substrings in
`victim-updates-browser.log`. Long-hide samples show modest WebSocket upgrade
churn (`wsUpgradeCount` 3→4) but this cannot substitute for hidden-tab UI
propagation proof.

**P0 gate assessment:**

| Criterion | Plan §4.0 requirement | Recovery outcome |
|---|---|---|
| Short hidden | `updates-unread-count-1` (or equivalent) while hidden within ~3 s | **FAIL** — 10 s timeouts with semantics at `updates-unread-count-0` (`run.log`, `run2.log`, `run-final.log`) |
| Long hidden (>5 min) | Same signal within ~60 s after intensive throttling | **NOT MEASURED** — no run reached post-trigger long-hide observation |
| `pongTimeout` churn | Watch console during long hide | Inconclusive — no `pongTimeout` hints; partial WS churn only |

**Manifest status at checkpoint:**

- **P0:** **blocked** — non-focusing CDP route was attempted but did **not**
  deliver causally valid hidden-tab proof. The `a5887534` pass remains rejected.
- **P1–P7, Final review:** **pending** (blocked downstream of P0).

**Decision (per plan §4.0 gate):** P0 has failed outright for implementation
purposes. The plan requires a **service-worker re-plan** before proceeding; that
re-plan is **not** implemented in this closeout. Do not start P1 from recovery
artifacts or reinterpret harness variants.

### 2026-08-10 — P0 final closeout (independent)

**Conclusion:** **P0 BLOCKED.** **P1 remains blocked.**

**Why blocked, not merely inconclusive:** three recovery executions under a
CDP read-only observation path consistently failed the short-hidden gate: the
Updates navbar semantics identifier never advanced to `updates-unread-count-1`
while `document.visibilityState` stayed `hidden` within the 10 s observation
window. That is a direct failure of plan §4.0 criterion (1). None of the runs
produced `/tmp/p0-recovery-artifacts/results.json` or completed criterion (2).
The prior `a5887534` measurements (392 ms / 528 ms) are disqualified because
they required activating the app tab to read semantics, triggering
`LifecycleHandler` visible catch-up — they cannot count as hidden-tab proof.

**Invalid recovery signals explicitly rejected:**

- `run2.log` `latency=10095ms` with `unread=updates-unread-count-0` is a
  timeout artifact, not a pass; any non-semantic side channel (e.g. intercepted
  `attentionFeed` GraphQL responses) does not satisfy the gate, which requires
  observable unread propagation in the hidden tab.
- `run-final.log` null semantic fields followed by entry into the 5m30s long-hide
  phase without a short-gate pass is an invalid run shape; manager interrupt
  prevented any long-gate measurement.

**Scope discipline (this closeout):** edited
`docs/plans/web-tab-unread-indicator-implementation-journal.md` only. Did not
stage/modify/move the untracked plan source, any protected worktree path, source
code, generated files, or evidence artifacts. Did not re-run, improve, or
reinterpret the harness.

**Remaining work (manager / product decision — not executed here):**

1. **Service-worker re-plan** per plan §4.0: if hidden-tab delivery cannot be
   proven, stop the current client-only architecture and redesign around
   `web/firebase-messaging-sw.js` (or equivalent) for background-tab signaling.
2. Alternatively, define a new P0 measurement protocol that is both
   non-focusing **and** observes a signal causally tied to hidden-tab UI/state
   (not merely network-layer `attentionFeed` payloads that may arrive without
   widget repaint).
3. Only after an accepted P0 pass: proceed with P1–P7 per
   `docs/plans/web-tab-unread-indicator-plan.md`.
4. Manual browser matrix (plan §P6) remains unstarted.

### 2026-08-11 — manager rebaseline for rev 3 plan

The user explicitly selected the newer untracked
`docs/plans/web-tab-unread-indicator-plan.md` (mtime 2026-08-11 14:30 CEST),
whose rev 3 architecture replaces the rejected Flutter-semantics P0 with a
direct-DOM `document.title` probe. That is a materially different causal
signal: it is intended to run in the unread callback without waiting for a
Flutter frame while CDP observes the hidden page without activating it.

The plan cites `/tmp/p0-title-hypothesis-artifacts/results.json` and
`run.log`, but those artifacts are absent in the current workspace; the
reverted probe source is also absent. Therefore the historical P0 block cannot
be treated as an implementation veto for rev 3, but rev 3's claimed pass is
not independently accepted either. A fresh, bounded P0 revalidation is now
the first unit. It may create a temporary, compile-time QA direct-DOM probe,
but must restore all source exactly before it exits. It must keep a non-app
target focused after receipt and observe the app only via CDP attached to the
background target. A successful short-hidden direct-title result unblocks P1;
a failure blocks this plan for redesign, not a fallback Flutter implementation.

**New protected changes discovered at this execution baseline** (in addition
to every path already listed above):

- `packages/client/lib/features/beacon_room/ui/widget/room_message_tile.dart`
- `packages/client/pubspec.yaml` (unrelated `5.10.1` version work)
- `packages/client/test/features/beacon_room/room_message_tile_coordination_test.dart`
- `packages/client/web/index.html` (unrelated `5.10.1` cache-buster work)

No listed protected path, including the untracked rev 3 plan source, may be
staged or modified by P0. The existing journal is the only persistent P0-owned
path. At P7, archiving the explicitly selected plan source will be a separate,
path-scoped release-hygiene decision under the plan itself.

**Revised manifest:** P0 direct-DOM revalidation — **passed**; P1-P2 pending;
P3 pending; P4-P5 pending; P6-P7 pending; final review pending.

### 2026-08-11 — P0 revalidation interrupted for runtime-scope correction

The fresh P0 worker was interrupted by the manager before it produced a gate
result or journal checkpoint. It had launched one isolated `flutter build web`
for a compile-time QA probe; it did not launch parallel P0 builds. Two existing
`flutter_tester` processes were separately observed and were not started,
stopped, or otherwise touched by this workflow. The worker-created build had
exited after interruption; no P0 build, Caddy instance, static server, browser,
or harness process remains.

The temporary `AttentionCase` import/callback and the three
`qa_hidden_tab_title_probe*` source files have been removed by the manager.
`git diff` confirms no residual P0 source edit. No receipt trigger, title
measurement, artifact result, P0 acceptance, or P1 unblock occurred.

**Manifest correction:** P0 direct-DOM revalidation is **pending**, not in
progress. P1-P7 remain blocked behind a fresh, explicitly bounded P0 attempt.

### 2026-08-11 — P0 rev-3 worker checkpoint (direct-DOM revalidation)

**Worker:** fresh bounded P0 rev-3 unit only. P1 and all production feature
implementation remain out of scope.

**Protocol (locked for this run):**

1. Append this checkpoint before any source edit or process spawn.
2. Add a temporary compile-time QA adapter (`qa_hidden_tab_title_probe*`)
   invoked from `AttentionCase._emit`; it assigns `document.title` via
   `package:web` only when `QA_HIDDEN_TAB_TITLE_PROBE=true`.
3. Run **exactly one** `flutter build web` to a new `/tmp/p0-rev3-*` output
   directory with QA probe defines. No `flutter run`, `flutter test`, or second
   build.
4. Serve that build through an ephemeral same-origin Caddy proxy on an unused
   port (static file_server + reverse_proxy to existing `127.0.0.1:2080` /
   `127.0.0.1:8080` API paths). One ephemeral static server only if required;
   trap-installed cleanup for every spawned PID/process group.
5. Harness: QA bootstrap + `markAsk`/`acceptAsk` receipt while the victim app
   tab is hidden (`about:blank` focused). Post-trigger observation is **CDP
   `Runtime.evaluate` only** on the app page target — no `setAsActive`, focus,
   navigate, reload, or visibility change on the app target.
6. Pass gate: `document.title == '(1) Tentura'` while
   `document.visibilityState == 'hidden'` within 3 s of receipt trigger. No
   >5-minute long-hide check (deferred to P6).
7. Restore `AttentionCase` exactly; delete all `qa_hidden_tab_title_probe*`
   files; prove clean with
   `git diff --exit-code -- packages/client/lib/domain/attention/attention_case.dart`.
8. Journal-only commit; do not stage the untracked plan or other paths.

**Runtime budget:** one `flutter build web`; do not touch existing Caddy,
Flutter dev server, Docker, server, chromedriver, or other pre-existing
processes.

**Artifacts root:** `/tmp/p0-rev3-direct-dom-artifacts/`

### 2026-08-11 — P0 rev-3 worker: direct-DOM revalidation (**PASS**)

**Temporary probe (reverted before exit):** `qa_hidden_tab_title_probe*`
conditional export; `AttentionCase._emit` called
`QaHiddenTabTitleProbe.applyUnreadTotal` when
`QA_HIDDEN_TAB_TITLE_PROBE=true`. Restoration verified:
`git diff --exit-code -- packages/client/lib/domain/attention/attention_case.dart`
→ exit 0; no `qa_hidden_tab_title_probe*` files remain under
`packages/client/lib/domain/attention/`.

**Build (single `flutter build web` invocation):**

```bash
cd packages/client && flutter build web \
  --profile \
  --output=/tmp/p0-rev3-direct-dom-artifacts/build/web \
  --dart-define-from-file=env/local-web.env \
  --dart-define=SERVER_NAME=https://dev.lvh.me:19443 \
  --dart-define=WS_SERVER_NAME=https://dev.lvh.me:19443 \
  --dart-define=QA_INTEGRATION_TEST_MODE=true \
  --dart-define=QA_HIDDEN_TAB_TITLE_PROBE=true
```

Log: `/tmp/p0-rev3-direct-dom-artifacts/build.log` (exit 0, ~77 s compile).

**Ephemeral same-origin proxy:** copied API routes into
`/tmp/p0-rev3-direct-dom-artifacts/Caddyfile`; `caddy run --config …` on
`:19443` serving the profile build with `reverse_proxy` to existing
`127.0.0.1:2080` / `127.0.0.1:8080`. Trap cleanup on shell exit; no
pre-existing Caddy/Flutter processes touched. Caddy log:
`/tmp/p0-rev3-direct-dom-artifacts/caddy.log`.

**Harness (authoritative run):** `/tmp/p0-rev3-direct-dom-artifacts/harness.dart`
via `QA_AUTH_TOKEN` from `.env` (value not recorded). Pre-existing chromedriver
`127.0.0.1:4444` used; no new chromedriver spawned. Command:

```bash
QA_AUTH_TOKEN=<from .env> \
  dart --packages=/home/vader/MY_SRC/tentura/.dart_tool/package_config.json \
  /tmp/p0-rev3-direct-dom-artifacts/harness.dart
```

(Executed inside `run_harness_only.sh` after the one build; harness-only reruns
reused the same `/tmp/.../build/web` output — no second Flutter command.)

**Fixture:** `runId=p0rev3-1786465576198` → author
`it-author-p0rev3-1786465576198@test.tentura.local` (`Ue599cb20d152`), helper
`it-helper-p0rev3-1786465576198@test.tentura.local` (`U6b4cf7f1a3b8`), beacon
`B7eb83f63817e`. Flow: QA bootstrap → victim login on
`https://dev.lvh.me:19443` → `/home/updates` → **Mark all seen** (baseline title
`Tentura`) → hide tab (`about:blank` focused) → `markAsk` + `acceptAsk` via API
→ CDP `Runtime.evaluate` only (no app-tab activation post-trigger).

| Field | Result |
|---|---|
| trigger (UTC) | `2026-08-11T16:26:21.586520Z` |
| pre-trigger title (hidden) | `Tentura` |
| post-trigger title (hidden) | `(1) Tentura` |
| title latency | **443 ms** |
| visibility violations | **0** (stayed `hidden`) |
| head refresh latency (QA) | 376 ms (updated post-receipt) |
| gate ≤3 s | **PASS** |

**Artifacts:** `/tmp/p0-rev3-direct-dom-artifacts/results.json`, `run.log`,
`build.log`, `caddy.log`, `victim-updates-browser.log`, `harness.dart`,
`Caddyfile`, `run_p0_rev3.sh`, `run_harness_only.sh`.

**Process cleanup proof:** ephemeral Caddy started with trap `cleanup` on EXIT;
`pgrep -af 'Caddyfile.*p0-rev3'` empty after script exit. Pre-existing stack
(`:9443` Caddy, `:8888` Flutter dev, `:2080` server, `:4444` chromedriver)
untouched.

**P0 status:** **PASSED** — direct `package:web` `document.title` assignment
from `AttentionCase._emit` reached the hidden tab within 443 ms without
activating the app target. **P1 is unblocked.**

**P1 status:** pending (not started in this unit).

**Tests/build in this unit:** one `flutter build web` (pass); no `flutter test`;
harness exit 0 on authoritative run.

**Remaining work:** P1–P7 per rev-3 plan; P6 must repeat hidden-tab CDP check
against the implemented controller (including >5 min hide); manual browser/PWA
matrix still unstarted.
