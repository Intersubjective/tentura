# Typing survives clear buttons and tooltip transitions

These tests use real Chrome pointer and keyboard input on the full application,
with real authentication and transport. `run.sh` compiles a fresh **profile +
Wasm** build with semantics enabled (`ENV` defaults to `dev`). It deliberately
does not use the integration-test entry point, which disables semantics.

## Prerequisites

Use the existing local Docker services and the QA test-login settings described
in `.claude/skills/local-debug/SKILL.md`. The runner starts the API and static
Caddy when absent and stops only those processes it started. An existing local
Caddy must already serve the test's profile build in static mode.
Generate `packages/client/env/local-web.env` with
`bash scripts/sync-client-local-config.sh` if absent. For a manually started
Caddy, use static mode:

```sh
LOCAL_USE_FLUTTER_PROXY=off LOCAL_APP_ROOT=/tmp/tentura-focus-profile-web \
  caddy run --config Caddyfile.local
```

Node 20+ and installed Google Chrome are required. The runner installs the locked
Playwright dependency. No browser download is needed. The default QA account is
the original trace's `society-bravo3@test.tentura.local`; `EMAIL` can select
another QA account. Each run uses a fresh browser context and blocks service
workers, so a previous build cannot supply cached application code.

## Mandatory acceptance gate

From the repository root:

```sh
./scripts/run_with_test_cleanup.sh --timeout 15m -- bash scripts/e2e_focus/run.sh all 10
```

`typing_survives_interactions_on_all_surfaces.mjs` executes every row below,
sequentially, with at least ten cycles per row. It builds once and shares the
local stack, while each row uses a fresh browser context. It runs later rows
even if earlier ones fail and prints the exit code for every row. The gate
passes only when **all seven rows pass**.
`run.sh` with no arguments and the package's `npm test` also select this gate.

| Surface | Mandatory interaction |
| --- | --- |
| Rating search | Clear X, then typing without a click and after one field click |
| Rating search | Tooltip appears and disappears while typing |
| Updates search | Clear X, then typing without a click and after one field click |
| Forward recipient search | Clear/Cancel X, then typing without a click and after one field click |
| Forward recipient search | Tooltip appears and disappears while typing |
| Chat composer | Emoji tooltip appears and disappears while typing |
| Chat composer | Back tooltip appears and disappears while typing |

Run through `alloy job start -- <command>` and bounded `alloy job wait` calls
when executing interactively. A check handed to Alloy uses the plain command.

## Focused diagnostics

An individual row can still be selected with `run.sh close 10` or
`run.sh hover 10` and the environment variables below. Individual invocations
do not replace the mandatory gate. To rerun one row against an already rebuilt
profile app and running stack, use
`node scripts/e2e_focus/typing_survives_clear_and_tooltip.mjs close 10`.

`close` verifies the query clears, then asserts the next keys appear without a
click and that typing continues after one click. `hover` verifies typing both
while the tooltip is shown and after it hides. Both modes exercise ten cycles,
including failures, and print actual versus expected field text per cycle.
`backspace` is the diagnostic control and is expected to pass before the fix;
it is not a failing baseline check.

The chat composer rows kept all keys in ten cycles on the original code; they
guard that the app-wide repair does not break the composer.

Exit **2** means typed keys were lost. Exit **1** means a prerequisite failed
(login, profile/Wasm app, semantics, labeled field/action, or initial typing).
Exit **0** means every checkpoint in every required cycle passed. The aggregate
gate reports **1** if any row has a setup error, otherwise **2** if any row
loses keys, otherwise **0**. The test never
repairs browser focus, fills DOM values, or dispatches synthetic blur events.

The configurable `BASE`, `ROUTE`, `FIELD_LABEL`, `CLEAR_LABEL`, `HOVER_LABEL`,
`PRE_CLICK_LABEL`, `RESET_XY` and `EMAIL` allow the same trace on other fields.
Routes containing `{requestId}` create a private Request through the public
GraphQL API as the signed-in test user, then delete it in `finally`. This keeps
the sibling checks independent of durable Request fixtures. The tests do not
send messages or forwards.

## Standalone pin: `cold_graph_tab.mjs` — #927: Tab after a cold Graph deep link

A cold load of `#/graph/<id>` (or a reload of it) puts Home under the Graph
in the first frame. On 7.60.14 and earlier, Home's tab shell is built there
offstage and never laid out, so the first Tab / Shift+Tab throws
`RenderBox was not laid out` and focus stays on `<flutter-view>`.

For each viewport (default desktop 1280x800 with the rail, phone 375x667 with
the bottom bar) the script runs three scenarios:

1. cold load `<BASE>/#/graph/<id>`, then Tab, Tab, Shift+Tab, Tab
2. reload, then Shift+Tab, Tab, Shift+Tab, Tab
3. reload, then Tab, Tab, Shift+Tab, Tab

After every key it asserts:

- `document.activeElement` is a `<flt-semantics>` node. Flutter web moves DOM
  focus onto the semantics node of the framework's primary focus, so this is
  the observable for both keyboard focus and what a screen reader announces.
  When traversal throws, framework focus does not move and DOM focus stays on
  `<flutter-view>` (or leaves the app for `<body>`), which is exactly the bug.
- the focused node is not in Home's shell, and Home's shell is not in the
  semantics tree at all (Home's nav item `constellation.nav_item` is absent).
  Offstage routes have no semantics, so a focused semantics node with Home
  absent can only belong to the Graph, the one route on stage. This holds in
  any locale, unlike matching button labels.
- the URL is still `#/graph/<id>`.

Over each scenario the console must carry no `RenderBox was not laid out`,
no other Flutter exception (`EXCEPTION CAUGHT BY`, `Bad state:`, null-check
errors) and no `pageerror`.

Exit code: `0` all scenarios pass, `1` a scenario failed, `2` setup failed
(sign-in, app did not boot, app left the Graph before any key).

### Sign-in

By default the script signs in with the QA test login
(`POST /api/v2/auth/email/test-login`, dev / staging only, needs
`QA_SIMPLE_LOGIN_MODE=true` on the server) as `tab-qa-01@test.tentura.local`
and opens that user's own graph (the id is read from the session's access
token; nothing secret is printed). Alternatively pass an already signed-in
persistent Chromium profile; pass a copy, Chromium writes into it.

| Env | Default | |
|---|---|---|
| `E2E_BASE_URL` | `https://dev.tentura.io` | local stack: `https://dev.lvh.me:9443` with `E2E_IGNORE_HTTPS_ERRORS=1` |
| `E2E_EMAIL` | `tab-qa-01@test.tentura.local` | QA test-login email |
| `E2E_USER_ID` | the signed-in user | whose graph to open |
| `E2E_USER_DATA_DIR` | unset | persistent profile instead of test-login |
| `E2E_VIEWPORTS` | `1280x800,375x667` | comma list of `WxH` |
| `E2E_HEADED` | unset | `1` for a headed browser |
| `E2E_DEBUG` | unset | `1` prints every console line |
| `E2E_LOCAL_BUILD_DIR` | unset | serve this `flutter build web` output as `E2E_BASE_URL`'s app shell; `/api/**` and files not in the dir stay live |

### Run

```bash
cd scripts/e2e_focus
npm install
node cold_graph_tab.mjs            # against dev
E2E_BASE_URL=https://dev.lvh.me:9443 E2E_IGNORE_HTTPS_ERRORS=1 node cold_graph_tab.mjs
```

### Before deploy: a local build against dev

`E2E_LOCAL_BUILD_DIR` lets you check a branch before it reaches dev. The
browser loads the local bundle under dev's own origin, so the session cookie,
the API and the data are dev's.

```bash
cd packages/client
flutter build web --profile --wasm --base-href=/ -o /tmp/web927 \
  --dart-define=SERVER_NAME=https://dev.tentura.io \
  --dart-define=IMAGE_SERVER=https://dev.tentura.io --dart-define=NEED_INVITE_CODE=true
cd ../../scripts/e2e_focus
E2E_LOCAL_BUILD_DIR=/tmp/web927 node cold_graph_tab.mjs
```
