# Adaptive Router Refactor — Persistent Shell & Per-Tab Stacks (Phase 2)

Plan date: 2026-07-04. Scope: `packages/client` routing layer
(`app/router/root_router.dart`, `home_screen.dart`, and — in the final steps —
the `beacon_view_screen.dart` room lifecycle machine).

## Implementation status (2026-07-06, branch `adaptive-router-phase2`)

Steps 0–5 landed. Key artifacts and deviations:

- **Step 0** — `scripts/e2e_backnav/suite.js` (12 scenarios, run via
  Playwright MCP `browser_run_code_unsafe` with `filename:`). Clears the SW
  caches at startup (cache-first SW with fixed CACHE_VERSION hides rebuilds)
  and cold-boots via `about:blank` (same-origin hash goto does NOT reload).
- **Step 1–2** — `app/router/home_tab_branches.dart`: four `EmptyShellRoute`
  branches, `browseDetailChildren()` shared child list, `HomeTabOwner` +
  `homeTabShellFor` (warm: active tab wins; cold: semantic owner) and
  `homeBranchPathPrefixFor` (transformer stage). Root registrations of all
  browse details became redirect-target guards calling
  `_forwardIntoHomeBranch`.
- **Load-bearing discoveries** (each pinned in
  `test/app/router/home_tab_branch_routing_test.dart`):
  - `HomeScreen.wrappedRoute`'s account-arrival reparent disposed the
    `AutoTabsRouter` and dropped deep-linked branch children → GlobalKeyed
    shell subtree.
  - `AutoRouteGuard.redirect` pushes a **second** Home shell; guards must
    `navigate`/branch-push instead.
  - auto_route `navigate()` writes URL history as *replace* — warm forwards
    must `branch.push` or the browser back chain silently shortens.
  - Cross-branch reachability: `push`/`navigate` resolve scope through the
    *active* ancestor chain only; always route via
    `HomeRoute(children: [shell(children: [detail])])`.
  - `_stripRoomFromUrl` (beacon room split) must strip params from the
    nested URL in place; rebuilding a bare path re-enters the root guard as
    a push and disposes the live screen (desktop cold room-link crash).
- **Step 3** — 34 call sites converted to typed pushes; string paths remain
  in `AutoLeadingWithFallback`, `ui_effect_dispatcher`, `ScreenCubit`
  effects, `beacon_view_screen` (step 6), one `kQueryHomeTab` switch.
- **Step 4** — decided + pinned: back at branch root defers to the platform
  (backgrounds the app; `maybePopTop() == false`). Browser back = one entry
  per perceived place (e2e). **Android predictive back / iOS swipe-back not
  yet verified on device** — run the compact matrix on real hardware before
  release.
- **Step 5** — deep-link pipeline documented at `openFromNotificationLink`:
  platform links go transformer → branch prefix (one browser-owned entry);
  in-app notification taps go normalize-only → `pushPath` → root guard →
  branch push. Root redirect-target guards stay (they serve every remaining
  string-path caller); `/beacon/room/:id` and `/beacon/:id` stay forever.
- **Native gate caveat**: `flutter build linux` currently fails on this
  host (`libgtk-3-dev` missing) — install and re-run before treating the
  native gate as green.

**Related:** [`beacon-room-split-phase1-plan.md`](beacon-room-split-phase1-plan.md)
(Phase 1, shipped), [`desktop-adaptive-readiness-report.md`](desktop-adaptive-readiness-report.md),
[`telegram-adaptive-layout-port-plan.md`](telegram-adaptive-layout-port-plan.md).

This is **Phase 2 of the adaptive-layout brief**: persist the `NavigationRail`
over detail routes (beacon view, graphs, profiles) instead of pushing them over
the entire Home shell. Phase 1 (in-screen beacon|room split at expanded) landed
in `0debf180`; this phase is the router/shell restructure it deferred.

---

## Decisions already made (do not re-litigate)

1. **Stay on auto_route** (currently `^11.1.0`). Rationale, condensed:
   - Everything the target architecture needs is native auto_route capability:
     `AutoTabsRouter` shell, per-tab nested `StackRouter` branches, guards,
     `reevaluateListenable`, `deepLinkTransformer`.
   - A go_router migration would be a big-bang cutover touching every
     navigation call site **and** the `AutoRouteWrapper` bloc-provisioning
     pattern, while fixing none of the bugs we actually fight (browser-back /
     `PopScope` issues live at the Flutter Navigator 2.0 layer, which go_router
     shares).
   - Staying lets us move routes under the shell **one at a time** with legacy
     redirects, the same incremental discipline that made Phase 1 safe.
   - Known trade-off accepted: auto_route bus factor (single maintainer). A
     well-structured declarative route tree is portable if a forced migration
     ever comes; none of this work is wasted in that scenario.

2. **URL shape is free.** The app is closed — never crawlable, links never
   shared by humans. URL aesthetics and stability carry **zero** product
   weight. URLs still matter *mechanically*: notification deep links
   (`openFromNotificationLink`), invite/credential links, and legacy beacon
   paths must keep resolving, and a browser refresh must reconstruct state
   from the URL alone. But we may freely change path shapes as long as the
   transformer/redirect layer keeps old inbound links working.

3. **Per-tab back stacks.** Details push into the active tab's own branch
   (each `AutoTabsRouter` branch is its own `StackRouter`), so e.g.
   graph → profile → graph exploration keeps its stack per tab. Chosen over a
   single shared detail stack because stable exploration stacks were judged
   more valuable than canonical one-URL-per-place (see decision 2).

---

## Core principle (carries over from Phase 1 discussion)

**Navigation state describes *what* the user is looking at; layout derives
*how* to present it.** Route params + `WindowClass` in, presentation out — a
pure function evaluated every build. No stored mode flags
(`_showRoomSurface`-style) that require resize/deep-link reconciliation.
Phase 1's `beaconViewUsesExpandedRoomSplit` derivation is the pattern; this
phase extends it to the shell and eventually retires the legacy flags.

---

## Current state (census, 2026-07-04)

### Route table (`root_router.dart`, 528 lines, ~30 routes)

- `HomeRoute` hosts an `AutoTabsRouter` with exactly 4 tab children
  (MyWork / Inbox / Friends / Profile). Rail (≥600) / bar (compact) chrome
  lives in `home_screen.dart`.
- **Every detail route is a root-level push over the shell** — beacon view,
  item discussion, graphs, rating, profile view, review contributions,
  invite genealogy, complaint, inbox-rejected, notification center. The rail
  vanishes on any drill-in. This is the Phase 2 gap.
- Redirect guards already implement the "legacy path → canonical route"
  pattern we will reuse: `BeaconRoomRoute` → `BeaconViewRoute(viewTab: room)`,
  `BeaconLegacyPathRoute` → `BeaconViewRoute`.

### Navigation call sites

- **String-path navigation dominates:** 39 `pushPath`/`navigatePath` sites
  across 16 files (vs. ~10 typed `FooRoute(...)` pushes). Includes
  `ui/effect/ui_effect_dispatcher.dart` (generic effect → path) and
  `ui/widget/auto_leading_with_fallback.dart` (back-fallback via
  `navigatePath`). Consequence: **path shapes are load-bearing at call sites
  today**, so during migration old paths must keep resolving via root-level
  redirects until call sites are converted.
- `openFromNotificationLink` (`root_router.dart`) pushes transformed paths on
  the root router; it must learn to target the shell.

### Known fragile areas this refactor touches

- `beacon_view_screen.dart` (1053 lines): room lifecycle state machine
  (`_showRoomSurface`, `_roomEnteredViaPush`, `_userDismissedRoomSurface`,
  `_roomExitInProgress`, `_pendingRoomExit`), `PopScope` juggling, deep-link
  reconciliation in `didUpdateWidget`. Phase 1 added the derived `isSplit`
  branch *alongside* this machine; Phase 2's pop-semantics change is the
  natural moment to replace it (step 6).
- Browser back on Flutter Web is a recurring bug class here
  (`5833770e` "Fix direct room route admission timing", `66db7e29` "Revert
  browser back fixes for beacon and room photo viewers"). Every step below
  must re-run the back-navigation matrix.
- The room message-action sheet's `useRootNavigator: true` workaround
  (documented in [`responsive-design-audit.md`](responsive-design-audit.md)
  Task R1) interacts with root-vs-nested navigators — re-verify once beacon
  view lives in a nested branch.

---

## Target architecture

```
RootStackRouter
├── HomeRoute (shell: rail/bar + AutoTabsRouter)          «rail persists here»
│   ├── MyWork branch (StackRouter)
│   │   ├── MyWorkRoute (branch root)
│   │   ├── beacon/view/:id          → BeaconViewRoute
│   │   ├── beacon/view/:b/discussion/:i → ItemDiscussionRoute
│   │   ├── review/:id               → ReviewContributionsRoute
│   │   └── … (detail routes reachable while working)
│   ├── Inbox branch
│   │   ├── InboxRoute
│   │   ├── rejected                 → InboxRejectedRoute
│   │   └── beacon/view/:id, profile/:id, …
│   ├── Network branch
│   │   ├── FriendsRoute
│   │   ├── graph/:id, graph/forwards/:id, genealogy, rating
│   │   ├── profile/:id              → ProfileViewRoute
│   │   └── beacon/view/:id, beacon/all/:id
│   └── Me branch
│       ├── ProfileRoute
│       └── graph/:id, notifications, notification settings, …
├── Full-screen (outside shell — deliberate takeovers)
│   ├── auth: intro, login, register, recover, accept-invite
│   ├── modal editors: beacon create, forward beacon, profile edit,
│   │   settings, credentials, complaint, debug settings
│   └── (fullscreen media viewers stay root-navigator overlays)
└── Legacy redirects (kept until step 5 cleanup)
    ├── /beacon/view/:id → active-branch BeaconViewRoute
    ├── /beacon/room/:id → … (existing)
    ├── /beacon/:id      → … (existing)
    └── '*' → /home
```

Notes:

- **Duplicated registration is fine.** The same `@RoutePage` may be declared
  under multiple branches; child paths are relative to the parent so
  uniqueness is automatic (`/home/work/beacon/view/:id` vs
  `/home/net/beacon/view/:id`). Ugly URLs are explicitly acceptable
  (decision 2). Extract the shared child lists into helper functions so the
  route table doesn't quadruplicate by hand.
- **In-shell vs. full-screen rule:** inside = anything reached while
  *browsing* (details, drill-ins); outside = auth/onboarding and modal
  editors that are full-screen dialogs today (`fullscreenDialog: true`
  routes keep their current root-level registration).
- **`usesPathAsKey: true`** must carry over to the nested registrations
  (beacon → beacon navigation relies on it).
- `AutoTabsRouter` keeps all four branch stacks alive (that's what preserves
  per-tab exploration stacks). Memory cost accepted — Inbox split already
  lives with it. Audit `maintainState`/`keepHistory` per moved route: the
  root-level registrations set these deliberately (see the ProfileEdit
  comment in `root_router.dart`) and the semantics must survive the move.

### Deep-link tab ownership (decision point — recommendation included)

A notification/invite link arrives as a bare path with no tab context. Rule:

- **Cold start / no active shell:** land in the semantically-owning tab —
  inbox-ish links (help offers, admissions) → Inbox branch; beacon room /
  coordination links → MyWork branch; profile/graph → Network branch.
- **Warm app:** push onto the **currently active** tab's branch (don't yank
  the user to another tab; the content is one back-press from their stack).

Implement as a small resolver used by `openFromNotificationLink` and the
legacy-path redirect guards. Keep it in one file so the mapping is auditable.

### Pop/back semantics (must agree across all three back affordances)

Browser back, Android (predictive) back, and the in-app leading arrow must
all consult the same derivation:

- Active branch stack has >1 page → pop the branch (rail stays).
- Branch at root → app-level back (browser: history; Android: background the
  app or switch to initial tab — pick one, test it, document it).
- `AutoLeadingWithFallback` gains shell-awareness: fallback should `navigate`
  within the active branch, not the root router.

---

## Migration steps (each independently shippable, analyzer-clean)

Ordering principle: change the tree shape first with behavior pinned by
redirects, convert call sites second, retire state machines last.

### Step 0 — Pin current behavior with an e2e back-nav suite
Playwright/Obscura flows (see [`local-e2e-playwright-obscura`] memory) for:
open beacon from each tab → browser back; beacon → room → back (compact);
graph → profile → graph → back ×3; notification link cold/warm;
`/beacon/room/:id` legacy redirect; refresh mid-stack. These are the
regression tripwires for every later step. No product code changes.

### Step 1 — Teach the shell to host children (pilot: `BeaconViewRoute`)
- Add `BeaconViewRoute` as a child of each tab branch (helper-generated).
- Convert the existing root-level `/beacon/view/:id` registration into a
  **redirect guard** that forwards to the active branch (tab-ownership
  resolver above) — mirroring today's `BeaconRoomRoute` redirect. All 39
  `pushPath` sites keep working unmodified.
- Rail must stay mounted over beacon view at ≥600px; compact behavior
  byte-identical (bar hidden under pushed detail is *current* compact
  behavior — decide explicitly whether compact keeps bottom bar hidden on
  details; recommendation: yes, keep hidden, matching today).
- Home shell (`home_screen.dart`): the `TenturaContentColumn` wrapping of tab
  content (`home_screen.dart:97-101`) must not double-wrap detail routes that
  manage their own width (beacon view does; the expanded-Inbox exception
  pattern generalizes to "branch root vs. pushed detail").
- Gate: step 0 suite green on web + one native target.

### Step 2 — Migrate the remaining browse cluster
In cohorts, same recipe as step 1 (children + root redirect):
1. `ItemDiscussionRoute`, `BeaconRoute` (view-all), `ReviewContributionsRoute`
2. `ProfileViewRoute`, `GraphRoute`, `ForwardsGraphRoute`,
   `InviteGenealogyRoute`, `RatingRoute`
3. `InboxRejectedRoute`, `NotificationCenterRoute` (currently full-screen "no
   bottom tabs" by design — product decision whether they join the shell;
   recommendation: yes on ≥600 where the rail is cheap, keep full-screen on
   compact, which falls out automatically once they're branch children)

Full-bleed surfaces (graph canvas) sit inside the branch outlet — verify
`TenturaFullBleed` still spans the outlet, not the window, and that graph
gesture handling tolerates the rail stealing edge pixels on desktop.

### Step 3 — Convert call sites from paths to scoped navigation
- Replace `pushPath('/beacon/view/$id?...')`-style calls (39 sites, 16 files)
  with typed pushes on the **active branch** router
  (`context.router.push(BeaconViewRoute(...))` resolves to the nearest
  `StackRouter`, which after steps 1–2 is the branch — verify per site;
  effects dispatched from blocs via `ui_effect_dispatcher.dart` need the
  tab-ownership resolver since they hold the root router).
- Convert incrementally; redirects keep unconverted sites working. Track with
  a grep count in the PR description (`pushPath|navigatePath` outside
  `root_router.dart` → target: only `AutoLeadingWithFallback` + deep-link
  plumbing remain).

### Step 4 — Shell-aware back affordances
- `AutoLeadingWithFallback`: fallback navigates within the active branch.
- Android predictive back + iOS swipe-back against nested branch stacks
  (innermost-pop verification — this is where every Flutter router is
  touchiest; test early on real devices).
- Browser back: confirm one history entry per perceived place, no double-pop
  through redirects.

### Step 5 — Cleanup
- Remove root-level redirect registrations for fully-converted routes (keep
  `/beacon/room/:id` and `/beacon/:id` forever — external legacy links).
- Collapse the tab-ownership resolver + `deepLinkTransformer` +
  `openFromNotificationLink` into one documented pipeline.

### Step 6 — Retire the beacon room mode flags (separate PR series)
With beacon view inside a branch and pop semantics settled, replace
`_showRoomSurface` / `_roomEnteredViaPush` / `_userDismissedRoomSurface` /
`_roomExitInProgress` / `_pendingRoomExit` with **route-derived** state:
`?tab=room` in the branch route is the single source of truth; compact
renders it as a pushed/priority surface, expanded renders Phase 1's split.
Every deleted flag removes a reconciliation path (`didUpdateWidget` URL
reconciliation shrinks accordingly). Keep
`beacon_view_room_split_contract_test.dart` green throughout; extend it with
the derived-from-route cases. This step has its own risk profile — plan it as
its own doc when steps 1–5 have landed, re-using the Phase 1 "never touch the
other branch" discipline.

---

## Risk register

| Risk | Severity | Mitigation |
|------|----------|------------|
| Browser-back regressions on web (recurring bug class here) | **High** | Step 0 e2e suite is a hard gate for every step; one route cohort per PR |
| Nested-branch pop vs. iOS swipe-back / Android predictive back | High | Step 4 on real devices before cleanup; innermost-pop assertions in e2e |
| `useRootNavigator: true` sheet workaround breaks under nested branch | Medium | Re-run the documented repro (room → action sheet → dismiss → exit room on web) in step 1 gate |
| Duplicated route registrations drift apart | Medium | Generate branch child lists from one helper; lint/grep check in CI |
| `maintainState`/`keepHistory` semantics silently change on move | Medium | Audit per route against current root registrations (ProfileEdit-style comments mark the load-bearing ones) |
| Deep-link/notification links break for old app versions | Medium | Root redirects stay until step 5; `/beacon/room`, `/beacon/:id` stay forever |
| Memory growth from four live branch stacks holding details | Low | Already true for tabs today; spot-check with DevTools after step 2 |
| Compact regression while chasing desktop polish | High | Compact behavior frozen per step; e2e matrix runs compact first |

---

## Test matrix (per step, minimum)

- **Compact (phone, native + web):** tab → detail → back; system back gesture;
  bottom bar visibility on details unchanged; notification link warm + cold.
- **Regular/expanded (desktop web + tablet):** rail persists over every moved
  route; rail tab switch while a detail is open (branch stacks preserved);
  graph → profile → graph → back ×3 restores each stack level.
- **Resize across 600/840** with a detail open: rail appears/disappears, no
  stranded state, beacon room split (Phase 1) still derives correctly.
- **Refresh (web)** mid-stack: state reconstructs from URL; no blank outlet.
- **Legacy links:** `/beacon/room/:id`, `/beacon/:id`, invite + credential
  links, notification `dest=room` links.

---

## Out of scope

- Any go_router (or other framework) migration — decided against, see
  "Decisions already made".
- Multi-pane layouts beyond Phase 1's beacon|room split (e.g. 3-pane at
  ≥1200) — future phase; this refactor makes them cheap but does not build
  them.
- URL beautification — explicitly a non-goal (closed app).
- The room message-action sheet width cap (Task R1 in
  [`responsive-design-audit.md`](responsive-design-audit.md)) — independent,
  can land any time.
