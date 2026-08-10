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
| P0 | **passed** | Measure hidden-tab unread propagation; gate P1. Record the exact evidence and do not implement P1 if foreground or long-hidden criteria fail. |
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
