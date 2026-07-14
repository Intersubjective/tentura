# Running the Flutter web integration tests locally

**Audience:** an engineer or LLM who wants to run the real `integration_test`
suite (headless browser, live backend) against the local dev stack, and to
understand how it is wired so failures can be diagnosed.

**TL;DR:**

```bash
./scripts/run_client_integration_web_local.sh
```

That one command starts whatever local infra isn't already running, downloads a
matching chromedriver, and runs all four lifecycle tests headless. It exits 0
on success, non-zero on the first failing test.

For simultaneous realtime convergence and reconnect proof, run:

```bash
./scripts/run_realtime_multiclient_web_local.sh
```

That runner keeps two independently authenticated Chrome sessions open against
the HTTPS Caddy origin, executes five consecutive positive journeys, records a
p95 timing summary, then verifies the same driver fails when live delivery and
catch-up are each disabled through the QA socket gate.

---

## 1. What these tests are

`packages/client/integration_test/*_test.dart` drive the **real Flutter web
app** in a **headless Chrome** against a **live local backend** (Postgres +
Hasura + Tentura API). They are not widget tests with mocks — they create real
beacons, forward them, offer/admit help, chat, and close/review, asserting on
real UI and real data.

Four scenarios (each its own `flutter drive` process):

| File | Scenario |
|---|---|
| `request_lifecycle_create_forward_inbox_test.dart` | create a request, publish, forward to a helper, confirm it reaches their inbox |
| `request_lifecycle_offer_admit_chat_test.dart` | offer help, admit, chat, create/resolve coordination items, remove from chat |
| `request_lifecycle_close_review_test.dart` | close a request (wrap-up-for-review) and complete the contribution review |
| `request_lifecycle_review_trust_control_test.dart` | post-close review two-step trust control: save validation gates (category → intensity → reason), trust-impact preview, saved status on the participant list |

Shared helpers: `integration_test/support/e2e_test_helpers.dart`.
Test IDs used to find widgets: `packages/client/lib/ui/test_ids.dart`.

## 2. Architecture — how the app reaches the backend

```
 headless Chrome ──HTTP──> Flutter dev server (localhost:8888)
                                   │  proxies (web_dev_config.yaml):
                                   ├── /api/v2/*        → Tentura API  :2080
                                   ├── /api/v1/graphql  → Hasura       :8080
                                   └── /_qa/*           → Tentura API  :2080
```

**Caddy is NOT in the loop for these tests.** The Flutter dev server
(`flutter drive -d web-server`) serves the app on `localhost:8888` and proxies
API calls to the backend itself (see `packages/client/web_dev_config.yaml`).
Only the docker-compose infra and the Tentura API server need to be running.

Because the app is served from `localhost:8888`, `SERVER_NAME` is set to
`http://localhost:8888` for the test build (`packages/client/env/integration-web.env`)
so the session cookie stays first-party and API calls dodge CORS. The dev
server can't proxy WebSockets, so `WS_SERVER_NAME` points straight at the API
(`http://localhost:2080`).

## 3. The two dart-defines that make it work

Both are passed by the runner script; you only need them if invoking
`flutter drive` by hand.

- **`QA_AUTH_TOKEN`** — read from repo-root `.env`; authorizes the
  `/_qa/integration/bootstrap` endpoint that seeds the two test users
  (author + helper) and befriends them.
- **`QA_INTEGRATION_TEST_MODE=true`** — a compile-time flag
  (`kQaIntegrationTestMode` in `consts.dart`) that:
  - suppresses web top-level navigations to the static landing (the
    unauthenticated bounce and the post-sign-out redirect) — those unload the
    page and would kill a running `integration_test`;
  - skips the startup `ensureSemantics()` call, whose SemanticsHandle is never
    disposed and would fail flutter_test's end-of-test verification.

## 4. Prerequisites

- **Local stack config** in repo-root `.env` (copy from `.env.example`) with:
  - `QA_AUTH_ENABLED=true` and a `QA_AUTH_TOKEN`
  - `QA_SIMPLE_LOGIN_MODE=true` (instant `POST /api/v2/auth/email/test-login`)
  - `ENVIRONMENT` not `prod` (QA routes are disabled in prod)
- **Google Chrome** installed (`google-chrome`). The script auto-downloads a
  matching `chromedriver` into `.local/chromedriver/` (gitignored).
- **docker compose** for the infra services.
- **Flutter** on PATH (channel/stable, the repo's pinned version).

The script fails fast with a clear message if any of these are missing.

## 5. Running

```bash
# all four tests
./scripts/run_client_integration_web_local.sh

# a single test
./scripts/run_client_integration_web_local.sh \
  integration_test/request_lifecycle_offer_admit_chat_test.dart
```

The script is **idempotent about services**: it reuses a running
docker-compose infra / Tentura API / chromedriver if it finds them, and only
starts what's missing. Anything it starts itself, it stops on exit; anything
that was already up, it leaves running.

It requires port **8888** to be free (it's where `flutter drive` binds the app
dev server). If your interactive local dev server is on 8888, stop it first:
`fuser -k 8888/tcp`.

## 6. Running a single test by hand (for debugging)

```bash
cd packages/client
QA_AUTH_TOKEN=$(grep '^QA_AUTH_TOKEN=' ../../.env | cut -d= -f2-)

# chromedriver must already be running on :4444, e.g.
#   ../../.local/chromedriver/chromedriver --port=4444 &

flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/request_lifecycle_create_forward_inbox_test.dart \
  -d web-server --browser-name=chrome \
  --dart-define-from-file=env/integration-web.env \
  --dart-define=QA_AUTH_TOKEN="$QA_AUTH_TOKEN" \
  --dart-define=QA_INTEGRATION_TEST_MODE=true
```

## 7. Debugging a failing test

`flutter drive -d web-server` reports the final verdict but **not** the app's
own console output. When a test times out or throws, the useful detail is in the
browser console. Two ways to capture it:

1. **CDP console stream (recommended).** chromedriver launches Chrome with a
   DevTools endpoint. `scripts/…` and the ad-hoc helper
   `cdp_console.py` (see below) attach to the page's WebSocket and stream
   `Runtime.consoleAPICalled` events to a file. The `[e2e]` breadcrumbs printed
   by the helpers (`loginAs`, `goToPath`, `tapAndSettle`, and a `TIMEOUT url=…
   texts:…` dump on every failed wait) tell you exactly which step hung and
   what was on screen.

2. **chrome_debug.log.** Each chromedriver Chrome writes a
   `/tmp/.org.chromium.Chromium.scoped_dir.*/chrome_debug.log` containing the
   same `INFO:CONSOLE` lines. Grep it for `[e2e]` / `EXCEPTION`.

A minimal CDP console streamer (Python, needs `websockets`):

```python
import glob, json, urllib.request, asyncio, websockets
d = sorted(glob.glob("/tmp/.org.chromium.Chromium.scoped_dir.*"))[-1]
port = open(f"{d}/DevToolsActivePort").read().split()[0]
t = next(t for t in json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/json"))
         if t["type"] == "page" and t["url"].startswith("http"))
async def main():
    async with websockets.connect(t["webSocketDebuggerUrl"], max_size=50_000_000) as ws:
        await ws.send(json.dumps({"id": 1, "method": "Runtime.enable"}))
        while True:
            m = json.loads(await ws.recv())
            if m.get("method") == "Runtime.consoleAPICalled":
                print(" ".join(str(a.get("value","")) for a in m["params"]["args"]))
asyncio.run(main())
```

### Common failure signatures

| Symptom | Cause |
|---|---|
| Test hangs forever, never fails | app boot overrode `FlutterError.onError`; `launchApp()` restores it — if you add a new test entrypoint, call `launchApp` |
| `Bad state: POST /_qa/integration/bootstrap failed (500)` | QA token / email-domain mismatch, or a server-side bug in `QaIntegrationController` |
| `ProviderNotFoundException: Provider<InboxCubit>` after sign-out | account-scoped provider torn down during in-place sign-out — kept alive by `_InboxScope` in `home_screen.dart` |
| `Looking up a deactivated widget's ancestor is unsafe` | a `late final AnimationController` initialized from `dispose()`; make it nullable/lazy |
| `A SemanticsHandle was active at the end of the test` | `QA_INTEGRATION_TEST_MODE` not set (semantics not skipped) |
| Timed out waiting on a nav that "should" have happened | `goToPath` uses `router.navigatePath(..., includePrefixMatches: true)` — a plain `pushPath` silently no-ops inside a tab shell |

## 8. What was fixed to make these pass (bugs, not test hacks)

These were real app/product bugs surfaced by the suite (see git log):

- `lifecycle_handler_web.dart`: `dispose()` was `async` and awaited before
  `super.dispose()` → framework "failed to call super.dispose" assert.
- `focus_flash_highlight.dart`: `late final AnimationController` lazily built
  from `dispose()` → deactivated-ancestor crash on teardown.
- `home_screen.dart`: `InboxCubit` provider was dropped the instant
  `currentAccountId` went empty during sign-out, crashing the still-mounted
  Inbox screen; now kept alive by `_InboxScope`.
- `QaIntegrationController` (server): contact name built from the runId could
  exceed the 32-char cap → 500 on bootstrap.

Test-only additions: `QA_INTEGRATION_TEST_MODE` redirect/semantics guards,
`env/integration-web.env`, and several widget `TestIds` (admission-reason
dialog, status-sheet rows, HUD author action).

## 9. Simultaneous realtime runner

`scripts/run_realtime_multiclient_web_local.sh` owns one Flutter profile web
server, ChromeDriver, and (when not already running) the local Caddy HTTPS
proxy. Its Dart WebDriver process creates two isolated browser sessions; it
does not switch accounts inside one app instance.

The journey keeps the receiving projection mounted while another browser
mutates Inbox, People, Chat, My Work, and Profile state. It also uses the
QA-only `/_qa/integration/realtime-socket` route to close and temporarily deny
one user's socket, then proves authenticated reconnect catch-up without reloads
or duplicate content. The route accepts only users issued by that run's QA
bootstrap and is absent when QA auth is disabled.

Artifacts are written under a timestamped
`reports/realtime-multiclient/<session>/` directory:

- `timings-summary.json` contains all samples and nearest-rank p95 values;
- browser and network logs are retained for every run;
- failure page source and screenshots are retained only for failed runs;
- server, Flutter web, ChromeDriver, and locally started Caddy logs are kept at
  the session root.

For a quick positive-only iteration:

```bash
REALTIME_MULTICLIENT_RUNS=1 \
REALTIME_MULTICLIENT_NEGATIVE_PROOFS=false \
  ./scripts/run_realtime_multiclient_web_local.sh
```

The release gate is the default: five positive runs plus both expected-failure
proofs. Every connected transition must be at most 1.5 seconds, reconnect
catch-up at most 3 seconds, and no browser may log an uncaught Flutter error.

The server protocol suite separately instantiates two independent notification
services and WebSocket routers. A single published envelope must reach sessions
owned by both modeled workers, while recovery on one LISTEN connection must
send catch-up only to that worker's sessions. This is the deterministic
multi-worker topology proof; the QA suspension gate remains intentionally
isolate-local for the single-worker browser recovery journey.
