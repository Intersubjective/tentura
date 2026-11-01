# Focus e2e (Playwright)

Standalone browser pins for keyboard / screen-reader focus on Flutter web.
They live here until the Playwright focus suite of #603 lands; then they
move into it.

## `cold_graph_tab.mjs` — #927: Tab after a cold Graph deep link

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
