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
| P0 | **blocked** | Measure hidden-tab unread propagation; gate P1. Record the exact evidence and do not implement P1 if foreground or long-hidden criteria fail. |
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
