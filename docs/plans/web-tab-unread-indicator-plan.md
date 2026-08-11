---
status: accepted-with-pending-manual-validation
kind: plan
---

# Web tab unread indicator (title + favicon dot + Badging API)

**Status:** accepted with pending external manual validation (rev 3). The
original Flutter-rendered P0 route is rejected; P0–P7 are implemented and
accepted through client `5.11.0` (`6bd0a80b`). On 2026-08-11 the product owner
explicitly accepted the remaining browser/PWA manual matrix as **pending**;
those rows are follow-up validation, not merge gates for this delivery.
One adversarial review round by Codex CLI against rev 1 (16 findings: 1 claimed
BLOCKER, 9 MAJOR, 6 MINOR). All are folded in; §8 records every disposition,
including the two findings that were **rejected as over-stated** and the one
whose severity was **re-derived from code** rather than accepted as filed.
**Date:** 2026-08-11.
**Scope:** client-only, web-only. No server, no new endpoint, no Caddy /
container change. Native builds compile and behave exactly as today (no-op).

---

## 1. Current state (verified against live code)

| Fact | Evidence |
|---|---|
| The unread number already exists as a stream | `packages/client/lib/domain/attention/attention_case.dart:85` — `Stream<AttentionSummary> get unreadSummary` |
| …and as a synchronous seed | `attention_case.dart:90` — `AttentionFeedSnapshot get snapshot` |
| The number itself | `packages/client/lib/domain/attention/entity/attention_summary.dart:8` — `@Default(0) int unreadTotal` |
| …but `.distinct()` there is over the **whole summary**, which also carries `needsYouTotal` | `attention_case.dart:85-86`; `attention_summary.dart:8-9`. So it does *not* dedupe by unread count — see P4. |
| The in-app Updates badge reads the same field | `packages/client/lib/features/home/ui/widget/updates_navbar_item.dart:15-16,21` |
| …via `Badge.count`, whose cap is **`maxCount = 999`**, not 99 | `$FLUTTER_ROOT/packages/flutter/lib/src/material/badge.dart:78,83` — `int maxCount = 999` … `count > maxCount ? '$maxCount+' : '$count'` |
| `AttentionCase` is a `@lazySingleton` resolved via GetIt | `packages/client/lib/app/di/di.config.dart:834` |
| Conditional-export platform-adapter pattern | `packages/client/lib/app/platform/lifecycle_handler.dart:1-2`, `.../web_semantics.dart:1`, `.../qa_attention_latency_probe.dart:1-2` |
| Web visibility is already observed once | `packages/client/lib/app/platform/lifecycle_handler_web.dart:29-37` (`document.onVisibilityChange` → realtime catch-up on *visible*) |
| **Nothing in `data/` or `domain/` reacts to visibility or app lifecycle** — the realtime socket is never torn down when the tab hides | `grep -rn "visibilityState\|AppLifecycleState\|didChangeAppLifecycleState" packages/client/lib/data packages/client/lib/domain` → **no matches** |
| Realtime heartbeat: ping period is env-driven, default **10 s**; pong timeout is `max(10 s, 3 × ping)` = **30 s**; the timeout check runs *inside* the ping timer | `packages/client/lib/env.dart:46-53`; `packages/client/lib/data/service/remote_api_client/remote_api_client_ws.dart:54,68-69,341-359` |
| `package:web` is a direct dependency and *declares* the Badging API | `packages/client/pubspec.yaml:46` (`web: ^1.1.1`); `~/.pub-cache/.../web-1.1.1/lib/src/dom/html.dart:11851,11857` |
| `js_interop_unsafe` property access is already used here | `packages/client/lib/domain/attention/qa_attention_latency_probe_web.dart:1-13` |
| Static favicon: **16×16 RGBA PNG**, one `<link rel="icon">` | `packages/client/web/index.html:14`; `file packages/client/web/favicon.png` |
| Static `<title>` (overwritten by Flutter at startup) | `packages/client/web/index.html:17` |
| App title source | `packages/client/lib/app/app.dart:111`, `:132-133`; `lib/consts.dart:65` (`kAppTitle = 'Tentura'`) |
| App root composition point | `packages/client/lib/app/app.dart:71-75` — `Globals(child: LifecycleHandler(child: App()))` |
| Theme is **user-selected**, not OS-derived | `packages/client/lib/app/app.dart:99-107` — `BlocSelector<SettingsCubit, …, ({ThemeMode themeMode, …})>` |
| `TenturaTheme.light()/dark()` build a full `ThemeData` incl. `ColorScheme.fromSeed` on every call | `packages/client/lib/design_system/tentura_theme.dart:12-14` |
| Release state must be reconciled at implementation time | this checkout already has unrelated, uncommitted `5.10.1` / cache-buster work; P7 must preserve it and select the next minor from the accepted baseline |
| No CSP is configured **in this checkout's Caddyfiles** (an upstream proxy/CDN could still inject one — verify deployed headers) | `grep -n 'Content-Security-Policy' Caddyfile Caddyfile.local` → no match |

**Nothing exists yet** for tab chrome: `grep -rn "setAppBadge\|document.title\|favicon"` over
`packages/client/lib` returns zero hits.

### 1.1 The load-bearing constraint: Flutter does not repaint while hidden

The prior architecture assumed that an `InheritedNotifier` update would rebuild
`MaterialApp.onGenerateTitle` while hidden. A causally valid CDP-only P0
disproved that assumption: `AttentionCase` completed its head refresh in
**139 ms**, but the Updates badge semantics remained at zero for 10 s while
`document.visibilityState` stayed `hidden`. Flutter's `Title` engine path may
be correct when it runs, but Flutter does not schedule that rebuild in the
background, so it cannot be the tab-attention delivery path.

The same P0 injected a QA-only direct `package:web` assignment at
`AttentionCase._emit()`. With the app tab still hidden and never refocused,
`document.title` changed from `Tentura` to `(1) Tentura` in **206 ms**. The
browser DOM mutation executes independently of Flutter widget repaint.

**Architecture decision:** the web adapter owns the active tab title, favicon,
and installed-PWA badge through direct DOM/Badging calls. Flutter remains the
source of the ordinary localized base title while visible; a small reporter
updates the adapter's stored base title on locale changes. The adapter restores
that base title on every clear. It must not depend on `Title`, `StreamBuilder`,
`setState`, or an `InheritedNotifier` to paint attention.

Evidence: `/tmp/p0-title-hypothesis-artifacts/results.json` and `run.log`
(ephemeral, local-only); the probe source was reverted after the run.

---

## 2. Locked UX contract

| # | Question | **Decision** | Why |
|---|---|---|---|
| 1 | Clear indicators on tab focus, or only at `N == 0`? | **Clear on focus, always.** | `tab-badge` "clear after user visits". The in-app Updates badge keeps the real count; tab chrome is a *background-only* channel. |
| 2 | Show while the tab is active? | **No — background only.** | Mutating the title of a tab the user is looking at is noise and causes needless AT announcements. |
| 3 | Threshold? | **Any `N > 0`**, title capped at `99+`. | Keeps the title short. See §2.3 for the honest cap-parity caveat. |

**The rule, in one line:**

```
displayed = isBackground ? unreadTotal : 0
```

`isBackground` ≡ `document.visibilityState == 'hidden'` (web) / always `false`
(native). Nothing is remembered or acknowledged: focus does not mutate any
count, it only gates display. So the tab number and the Updates badge cannot
disagree — while hidden they are the same number; while visible the tab shows
nothing.

**Rejected alternative:** "sticky clear" — snapshot `unreadTotal` on focus and
show only the delta on the next blur. It reads nicer for a user who tabs away
without reading, but makes the tab show a *different* number than the Updates
badge, which the UX review forbids. Revisit only with a product decision.

### 2.1 Channel contract

| Channel | Status | Value when active | Value when clear |
|---|---|---|---|
| `document.title` | **Mandatory / primary.** Acceptance hinges on this. | `(N) Tentura`, `N` = `1..99` then `99+` | current localized base title, written directly by the adapter |
| Favicon dot | Reinforcement | static contrasting dot, top-right, **no digit** | original `favicon.png` |
| Badging API | Reinforcement, best-effort, **installed-PWA contexts only** (§2.4) | `setAppBadge(unreadTotal)` — raw count, OS caps it | `clearAppBadge()` |

**Hard "do not do" list** (encoded as review-checklist items):

- No animation, blinking, or pulsing — neither favicon nor title.
- No digits rendered into the 16×16 favicon.
- No title mutation while the tab is visible.
- No notification-permission prompt for Badging (it needs none; asking would
  regress the existing FCM permission flow in `features/notification/`).
- No in-app fallback UI when Badging is unsupported — it degrades silently.
- No new backend endpoint, no new stream, no second source of truth.
- **Never assign `PlatformDispatcher.instance.onPlatformBrightnessChanged`** —
  see P4.

### 2.2 Update pacing

Two guards, both required, plus one exemption:

1. **Dedupe on the *rendered* value, per channel.** The channels have different
   sensitivities and must not share one equality check:
   - title + favicon key on **`(isBackground, label)`** — `100` and `101` both
     render `99+`, so neither channel does any work;
   - the OS badge keys on **`(isBackground, count)`** — it shows the exact
     number, so `100 → 101` must still be pushed.
2. **Leading-edge throttle, 250 ms**, applied *only to non-clearing updates*.
   Apply the first change immediately, coalesce further changes for 250 ms, and
   apply the **latest pending value** (never a captured stale one) at window
   end.

   *Why leading-edge:* Chrome applies intensive timer throttling to hidden tabs
   (`setTimeout` at most ~1×/min after ~5 min hidden) — and hidden is exactly
   when this paints. A plain trailing debounce would make the badge appear up to
   a minute late. Leading edge paints instantly; the trailing edge only corrects.
3. **Clears bypass the throttle entirely.** Any transition to
   `tabAttentionNone` — tab became visible, logout/account switch, widget
   dispose — cancels the pending timer, drops the pending value, and applies
   synchronously. Without this exemption a focus landing inside an open 250 ms
   window would leave `(N) Tentura` on screen after the user is already looking
   at the tab, contradicting §7.3.

### 2.3 Cap parity — the honest version

`TenturaCountBadge` caps at `99+` (`tentura_count_badge.dart:29`) but the
Updates navbar badge does **not** use it — it uses `Badge.count`, which caps at
`999+` (`badge.dart:78`). So with a `99+` tab cap, a user with 100 unread sees
`(99+)` on the tab and `100` in the navbar.

**Decision: keep `99+` in the title** (a four-character title prefix is the
point) **and close the gap with a one-line alignment**: pass `maxCount: 99` to
`Badge.count` in `updates_navbar_item.dart:21`. It is one parameter, it is
inside this feature's own consistency requirement (UX review §7, "one source"),
and it makes the parity claim true instead of decorative.

*If the reviewer prefers not to touch the navbar badge*, drop that edit and
accept the divergence above 99 — but then delete every parity claim from this
plan rather than leaving it unqualified.

### 2.4 Multi-context semantics (explicit, previously unstated)

**Multiple browser tabs.** The rule is per-tab and deliberately local: focusing
tab A clears A; tab B, now hidden, keeps showing `(N)`. This is correct under
"the tab chrome tells *this tab* there is something to come back to", and it is
the only behavior achievable without cross-tab coordination. **Documented, and
on the manual matrix.** Cross-tab clearing via `BroadcastChannel` with an
elected writer is deferred — it buys little and adds an election protocol plus a
whole class of leader-death bugs.

**Installed PWA + browser tab open simultaneously.** The OS app badge is a
single global slot shared by every context of the same app, so unsynchronized
writers race: a focused PWA clears the badge, and a hidden browser tab
immediately sets it again. **Fix: only installed-PWA contexts write the badge**
— gate on `window.matchMedia('(display-mode: standalone)').matches ||
window.matchMedia('(display-mode: window-controls-overlay)').matches`. In a
normal Chrome tab `setAppBadge` has no visible effect anyway, so nothing is
lost, the race is eliminated by construction, and this matches the task spec
("бейдж через Badging API для установленной PWA").

**Known limitation:** a PWA closed while unread remains leaves its last badge
value on the dock/taskbar. Clearing on `pagehide` is not reliable, and the
correct owner of closed-app badging is the FCM service worker — out of scope.

---

## 3. Architecture

```
        domain (unchanged)                    presentation                    platform
   ┌───────────────────────────┐   ┌─────────────────────────────┐   ┌────────────────────────┐
   │ AttentionCase             │   │ TabAttentionScope (Stateful)│   │ TabAttentionIndicator  │
   │  .unreadSummary ──────────┼──►│  • per-channel dedupe       │──►│ _web: title + favicon  │
   │  .snapshot.summary        │   │  • throttle (clears bypass) │   │       + PWA badge       │
   └───────────────────────────┘   │  • direct apply, no rebuild │   │ _stub: no-op            │
   ┌───────────────────────────┐   │  • base-title reporter      │   └────────────┬───────────┘
   │ SettingsCubit.themeMode ──┼──►│  • brightness observer       │                │ isBackground
   └───────────────────────────┘   └─────────────────────────────┘                │ (visibilitychange)
                                                                             direct DOM mutation
```

Layering check against `.cursor/rules/architecture.mdc` / the `clean-architecture`
skill:

- **domain**: untouched. `AttentionCase` already exposes everything needed.
- **No new use case, repository, port, or DI registration.** This is a
  presentation adapter over an existing use case; a `TabIndicatorCase` would own
  no rule the UI doesn't already own.
- Count-shaping (gate + cap + format) is *presentation policy* → `lib/ui/model/`
  beside `person_action_policy.dart`, pure Dart, no Flutter import, VM-testable.
- DOM work → `lib/app/platform/`, matching `lifecycle_handler`, `web_semantics`,
  `orientation_policy`. It is an outer, humble adapter; neither `domain/` nor
  `AttentionCase` imports web/Flutter APIs.
- Colors come from the design system, never as literals in the adapter.

---

## 4. Implementation

### P0 — Direct-DOM delivery spike (**accepted; prerequisite for P1**)

The original P0 tested a Flutter-widget proxy (`updates-unread-count-N`) and
correctly failed: state refresh occurred but Flutter did not repaint while
hidden. The revised P0 tests the mechanism that will ship: a direct DOM write
from a Dart callback reached by the unread update path.

**Accepted measurement:** with `QA_HIDDEN_TAB_TITLE_PROBE=true`, a local-only,
reverted `package:web` probe assigned the title in `AttentionCase._emit()`.
WebDriver kept `about:blank` focused, and CDP `Runtime.evaluate` read the app
page target without activation, focus, navigation, reload, or a post-receipt
`visibilitychange`.

| Field | Result |
|---|---|
| receipt trigger | `2026-08-11T12:00:29.006349Z` UTC |
| visibility | `hidden` throughout |
| head refresh | 139 ms |
| title | `Tentura` → `(1) Tentura` |
| title latency | 206 ms |

This proves the required scheduling boundary: direct DOM work in the unread
callback is not gated on Flutter repaint. It does **not** prove long-hidden
heartbeat behavior. P6 must repeat this exact non-focusing observation against
the implemented controller after a genuine >5 minute hide and record whether it
lands within ~60 s; heartbeat churn remains a separate follow-up if ugly.

### P1 — Pure display policy

**New:** `packages/client/lib/ui/model/tab_attention_display.dart`

```dart
/// Rendered state of the browser-tab attention indicator.
///
/// [count] is the raw unread total (fed to the OS app badge, which caps it
/// itself); [label] is the capped, title-safe rendering. The two are deduped
/// separately — see the plan §2.2.
typedef TabAttentionDisplay = ({int count, String label});

const tabAttentionNone = (count: 0, label: '');

/// Above this the title shows `99+`.
const kTabAttentionDisplayCap = 99;

/// The whole product rule: tab chrome mirrors unread only while the tab is in
/// the background; focusing clears it (the in-app Updates badge keeps the real
/// count). See docs/plans/web-tab-unread-indicator-plan.md §2.
TabAttentionDisplay resolveTabAttentionDisplay({
  required int unreadTotal,
  required bool isBackground,
}) {
  if (!isBackground || unreadTotal <= 0) return tabAttentionNone;
  return (
    count: unreadTotal,
    label: unreadTotal > kTabAttentionDisplayCap
        ? '$kTabAttentionDisplayCap+'
        : '$unreadTotal',
  );
}

String composeTabTitle({
  required String baseTitle,
  required TabAttentionDisplay display,
}) => display.label.isEmpty ? baseTitle : '(${display.label}) $baseTitle';
```

A record typedef gives structural equality for free (no `equatable` dependency
in this package, and this does not warrant Freezed). **Note the trap:** record
equality compares `count` too, so `100 → 101` is a *different* record with an
*identical* `label`. That is why P4 dedupes per channel rather than on the
record as a whole.

### P2 — Design-system style token

**New:** `packages/client/lib/design_system/tentura_tab_indicator.dart`,
**exported from `tentura_design_system.dart`** (the barrel is the public entry
point; a new file that isn't exported is invisible to callers by convention).

```dart
/// Colors for the browser-tab favicon dot. Resolved outside the widget tree
/// (the indicator lives above MaterialApp), so it takes an explicit Brightness.
@immutable
final class TenturaTabIndicatorStyle {
  const TenturaTabIndicatorStyle({required this.dot, required this.halo});
  final Color dot;   // the unread dot
  final Color halo;  // separating ring, so the dot reads on any icon pixel
}

abstract final class TenturaTabIndicator {
  /// Built at most once per brightness: TenturaTheme.light()/dark() construct a
  /// full ThemeData including ColorScheme.fromSeed (tentura_theme.dart:12-14),
  /// which is far too expensive to call per repaint.
  static final _cache = <Brightness, TenturaTabIndicatorStyle>{};

  static TenturaTabIndicatorStyle resolve(Brightness brightness) =>
      _cache.putIfAbsent(brightness, () {
        final scheme = (brightness == Brightness.dark
                ? TenturaTheme.dark()
                : TenturaTheme.light())
            .colorScheme;
        return TenturaTabIndicatorStyle(dot: scheme.error, halo: scheme.surface);
      });
}
```

`colorScheme.error` is chosen because it is what `Badge.count` already renders
in `UpdatesNavbarItem` (M3's badge default), so the tab dot and the in-app
badge carry the same semantic color. `AttentionMarker` uses `scheme.primary`
for a different concept (per-card "new stuff") and is not the reference.

**Which brightness** is decided in P4 from the *app's* resolved theme, not from
OS brightness alone — the user can pin light/dark in settings
(`app.dart:99-107`).

### P3 — Platform adapter

**New, three files**, mirroring `lifecycle_handler.dart`:

```dart
// packages/client/lib/app/platform/tab_attention_indicator.dart
export 'tab_attention_indicator_stub.dart'
    if (dart.library.js_interop) 'tab_attention_indicator_web.dart';
```

Contract (identical in both implementations):

```dart
class TabAttentionIndicator {
  /// `true` while the tab/window is hidden. Never fires on native.
  Stream<bool> get backgroundChanges;
  bool get isBackground;

  /// Writes all web tab chrome synchronously. Never waits for a Flutter frame.
  /// [baseTitle] is the current localized title supplied while the app is visible.
  void apply(
    TabAttentionDisplay display,
    TenturaTabIndicatorStyle style, {
    required String baseTitle,
  });

  void dispose();
}
```

**`_stub.dart`** — `isBackground => false`, `backgroundChanges =>
const Stream<bool>.empty()`, `apply`/`dispose` empty. Because `isBackground` is
pinned to `false`, `resolveTabAttentionDisplay` returns `tabAttentionNone`
forever on native and the shared controller is inert — one code path, no
`kIsWeb` branches in the widget layer.

**`_web.dart`** — five concerns:

**(0) Title — direct DOM, never Flutter-rendered.** On every accepted apply,
assign `web.document.title = composeTabTitle(baseTitle: baseTitle, display:
display)`. This is the direct path accepted by P0; it must execute in the stream
callback path and never be deferred through `setState`, `Title`, or a frame
callback. Clear writes the reporter-supplied `baseTitle`. The adapter owns only
the active attention title; Flutter may still write its ordinary title while
visible, and the controller clears before that can be user-visible.

**(a) Visibility source.**

```dart
web.document.onVisibilityChange.listen(
  (_) => _controller.add(web.document.visibilityState == 'hidden'),
);
```

Visibility only — deliberately *not* `window.onblur`/`document.hasFocus()`,
which would flip on every devtools click or second-monitor glance. This coexists
with `lifecycle_handler_web.dart:29` (which listens for the *visible* transition
to request a catch-up); two independent listeners on one event keep the concerns
separate.

**Page lifecycle / bfcache.** Also listen to `pageshow`: when a page is restored
from the back-forward cache, `visibilitychange` may not fire but the DOM (and our
managed `<link>`, and the cached base image) survive. On `pageshow` with
`event.persisted == true`, re-read `document.visibilityState` and re-apply the
current display. No `pagehide`/`freeze` teardown is performed — tearing the
favicon down on `pagehide` would fight bfcache restore for no benefit. Init is
idempotent (see (b)), so a restore cannot double-append anything.

**(b) Favicon — idempotent by construction.**

Hot restart re-runs `main()` but leaves the DOM in place, so "append a link at
init" would accumulate duplicates and could capture a *previous run's data URL*
as if it were the original icon. The recipe avoids captured state entirely:

- At init, look up `#tentura-tab-attention-favicon`.
  - **Found** (hot restart / bfcache restore): reuse it; read the pristine path
    back from its `data-static-href` attribute.
  - **Not found**: read the existing static link's `href`
    (`link[rel~="icon"]`, default `'favicon.png'`), remove *all* existing icon
    links, create one managed link (`rel="icon"`, our id,
    `data-static-href="<pristine path>"`), append it.
- Removing the other icon links removes the "which link wins?" question rather
  than betting on "browsers use the last one" — that ordering rule is what
  dynamic-favicon libraries rely on, but it is not worth depending on when
  owning the single link is this cheap.
- **Clear** → `href = dataset['staticHref']` (a constant path, never captured
  runtime state, so hot-restart safe). The element stays; we never remove it.
- Relative paths resolve against `<base href>` (`index.html:2`), so this is
  correct under any deploy prefix.
- **Dispose** → clear, then leave the managed link in place.
- **Active state**, rendered once per `label` change:

  ```
  canvas 32×32
  ctx.imageSmoothingEnabled = false          // integer 2× of the 16×16 source, no blur
  ctx.drawImage(baseImage, 0, 0, 32, 32)
  ctx.fillStyle = halo;  arc(cx: 22, cy: 10, r: 9)  fill()   // separating ring
  ctx.fillStyle = dot;   arc(cx: 22, cy: 10, r: 7)  fill()   // the dot
  link.href = canvas.toDataURL('image/png')
  ```

  Centre at (22, 10) with halo r = 9 keeps the whole halo inside the 32×32 box
  (22 + 9 = 31, 10 − 9 = 1), so nothing clips; a 14 px dot on a 32 px canvas is
  ~7 px at the 16 px tab size — comfortably readable, which is why the dot is
  this large relative to the icon. No text, no animation, no timers.
- The base `HTMLImageElement` is created and decoded **once at init, while the
  tab is still visible**, then cached; `apply()` while hidden does only
  synchronous canvas work. If it has not loaded yet, the paint is deferred to
  its `onLoad`.
- Everything is wrapped in `try/catch`. `toDataURL` throws `SecurityError` on a
  tainted canvas — impossible today (same-origin `favicon.png`, no CSP in this
  checkout's Caddyfiles) — but a future cross-origin asset host or a CSP without
  `img-src data:` would break it, and the correct degradation is "title-only",
  not a crash. **Verify deployed response headers** before relying on `data:`.

**(c) Badging — installed-PWA contexts only.**

```dart
bool get _isInstalledContext =>
    web.window.matchMedia('(display-mode: standalone)').matches ||
    web.window.matchMedia('(display-mode: window-controls-overlay)').matches;

void _applyBadge(int count) {
  if (!_isInstalledContext) return;                            // §2.4: kill the cross-context race
  final navigator = web.window.navigator;
  if (!(navigator as JSObject).has('setAppBadge')) return;     // dart:js_interop_unsafe
  try {
    final promise = count > 0
        ? navigator.setAppBadge(count)
        : navigator.clearAppBadge();
    promise.toDart.catchError((Object _) => null);             // swallow rejection
  } catch (_) {/* no-op */}
}
```

Feature detection is mandatory: `package:web` binds `setAppBadge` *statically*,
so on Firefox/Safari the call would throw at runtime. Swallowing the promise
rejection matters too — an unhandled rejection surfaces as Sentry noise
(`app/sentry/`) for a purely optional capability. The raw `count` is passed, not
the capped label. No permission is requested.

**(d) QA seam — web only, `kQaIntegrationTestMode` (`consts.dart:129`)**, mirroring
`QaAttentionLatencyProbe`. It is compile-time gated by a `bool.fromEnvironment`
const, so it is tree-shaken out of production builds:

- publish `window.__tenturaTabAttention = {count, label, badgeApplied, title}`
  on every `apply()`, so the headless web suite can assert without reading
  browser chrome;
- read `window.__tenturaForceTabBackground === true` as an `isBackground`
  override, because WebDriver cannot actually background a page.

### P4 — Scope widget + controller

**New:** `packages/client/lib/ui/widget/tab_attention_scope.dart`

```dart
class TabAttentionScope extends StatefulWidget {
  const TabAttentionScope({required this.child, super.key});
  final Widget child;

  /// Access the root controller from the localized base-title reporter.
  static TabAttentionController? controllerOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_TabAttentionControllerInherited>()
          ?.controller;

  @override
  State<TabAttentionScope> createState() => _TabAttentionScopeState();
}

class _TabAttentionControllerInherited extends InheritedWidget {
  const _TabAttentionControllerInherited({
    required this.controller,
    required super.child,
  });

  final TabAttentionController controller;

  @override
  bool updateShouldNotify(_TabAttentionControllerInherited oldWidget) =>
      !identical(controller, oldWidget.controller);
}

/// Sits below MaterialApp localization and updates the controller's clear title.
class TabAttentionBaseTitleReporter extends StatefulWidget { /* see P5 */ }
```

`TabAttentionController` is a private implementation class in this same file;
the scope's `State` (a `WidgetsBindingObserver`) owns it and owns:

- a `TabAttentionController` seeded from
  `GetIt.I<AttentionCase>().snapshot.summary.unreadTotal` combined with the
  indicator's current `isBackground`; its accepted updates call the platform
  adapter immediately, rather than notifying Flutter to rebuild;
- a subscription to
  **`AttentionCase.unreadSummary.map((s) => s.unreadTotal).distinct()`** — the
  upstream `.distinct()` is over the whole `AttentionSummary`, so a
  `needsYouTotal`-only change would otherwise wake this pipeline for nothing
  (§1);
- a subscription to `TabAttentionIndicator.backgroundChanges`;
- **brightness via `didChangePlatformBrightness()`**, registering itself with
  `WidgetsBinding.instance.addObserver(this)` in `initState` and removing it in
  `dispose`. **Never assign
  `PlatformDispatcher.instance.onPlatformBrightnessChanged`**: that is a
  single-slot callback already owned by `RendererBinding`
  (`$FLUTTER_ROOT/packages/flutter/lib/src/rendering/binding.dart:60` —
  `..onPlatformBrightnessChanged = handlePlatformBrightnessChanged`), so
  assigning it would silently break `MediaQuery.platformBrightnessOf`
  app-wide and stop `ThemeMode.system` from following the OS;
- a subscription to `GetIt.I<SettingsCubit>()` for `themeMode`, resolving the
  effective brightness as `themeMode == ThemeMode.system
      ? WidgetsBinding.instance.platformDispatcher.platformBrightness
      : (themeMode == ThemeMode.dark ? Brightness.dark : Brightness.light)`,
  then `TenturaTabIndicator.resolve(brightness)`. Repaint the favicon when the
  effective brightness changes *and* the display is active;
- the pacing from §2.2:
  - recompute on every input change;
  - compute `titleKey = (isBackground, label)` and `badgeKey = (isBackground, count)`;
    skip each channel whose key is unchanged;
  - if the new display is `tabAttentionNone` → **cancel the pending timer, drop
    the pending value, apply immediately**;
  - else leading-edge throttle: apply now if the window is closed, otherwise
    store as the *pending latest* (overwriting any earlier pending value — this
    is what makes a stale repaint after an account switch impossible, since the
    trailing edge always applies the newest value, never a captured one) and let
    the timer flush it;
- on each accepted change: `_indicator.apply(display, style, baseTitle:
  _baseTitle)` writes title, favicon, and badge from one synchronous direct-DOM
  path, so the channels cannot drift or wait for Flutter repaint;
- `dispose()`: remove the binding observer, cancel subscriptions and the timer,
  `_indicator.apply(tabAttentionNone, style, baseTitle: _baseTitle)` to leave
  the tab clean, then `_indicator.dispose()`.

Constructor takes optional `AttentionCase` / `TabAttentionIndicator` /
`SettingsCubit` overrides (defaulting to `GetIt.I<…>()`), following
`UpdatesFeedCubit`'s existing `{AttentionCase? attention}` style — this is what
makes P6's widget tests possible without GetIt or a browser.

**Startup ordering.** `AttentionCase` is a `@lazySingleton`; resolving it here
instantiates it slightly earlier than today (currently first touched by
`UpdatesNavbarItem`). Safe — `_start()` only subscribes, and `_onAccountChanged`
skips fetching while `accountId` is empty (`attention_case.dart:101-110`) — but
it must resolve *after* `configureDependencies()`, which P5's placement
guarantees. Guard the lookups with `GetIt.I.isRegistered<…>()` and degrade to
inert if absent, so any widget test that pumps the tree without DI (e.g.
`test/widget_test.dart`) cannot throw.

**Base title and logout / account switch.** `TabAttentionBaseTitleReporter`
uses `didChangeDependencies` beneath `MaterialApp` to pass
`L10n.of(context)?.appTitle ?? kAppTitle` to `controller.setBaseTitle`. It does
not render attention. `AttentionCase._onAccountChanged` emits an empty snapshot
(`attention_case.dart:101-110`) → `tabAttentionNone` → the clear-bypass writes
the current base title synchronously. No generation counter is needed because
the trailing edge applies the latest value rather than a queued stale one.

### P5 — Wire it in (the only user-visible edit)

`packages/client/lib/app/app.dart`:

1. In `runner()` (currently `:71-75`), add the root lifecycle owner:

   ```dart
   Widget appWidget = const Globals(
     child: LifecycleHandler(
       child: TabAttentionScope(child: App()),
     ),
   );
   ```

   It resolves `AttentionCase` only after `configureDependencies()` and owns
   stream/timer disposal. It is **not** an `InheritedNotifier` title seam.

2. Leave `MaterialApp.title` and `onGenerateTitle` as their current ordinary
   localized-title implementation. In `MaterialApp.builder`, wrap the existing
   child in `TabAttentionBaseTitleReporter`. Its only effect is
   `controller.setBaseTitle(L10n.of(context)?.appTitle ?? kAppTitle)` when the
   normal Flutter localization changes. It does not drive active attention
   rendering or mutate the title during build.

3. *(Per §2.3, optional-but-recommended)* `updates_navbar_item.dart:21` —
   `Badge.count(count: unread, maxCount: 99, …)`.

The production title change is therefore only in
`TabAttentionIndicator._web.apply`, called directly by the controller's stream
callback. No `onGenerateTitle` code composes `(N) Tentura`.

### P6 — Tests

| Level | File / how to run | Asserts |
|---|---|---|
| unit (VM) | `test/ui/model/tab_attention_display_test.dart` | gate (`isBackground == false` → none), `N == 0` → none, `1..99` verbatim, `100` → `99+`, `composeTabTitle` → `(3) Tentura` / `Tentura`, and that `count` stays raw while `label` is capped |
| unit (VM) | `test/app/platform/tab_attention_indicator_stub_test.dart` | the conditional export resolves to the stub off-web: `isBackground` is `false`, `backgroundChanges` is empty, `apply`/`dispose` are safe |
| widget (VM) | `test/ui/widget/tab_attention_scope_test.dart` | with a fake indicator + controllable streams: (a) matching `apply(display, baseTitle:)` calls; (b) base-title reporter changes only the clear title; (c) **per-channel dedupe** — `100 → 101` pushes a badge update but performs no new title/favicon paint; (d) leading-edge throttle coalesces to the latest value; (e) clear inside an open window applies synchronously; (f) account switch cannot repaint stale data; (g) dispose clears the fake indicator and removes the binding observer |
| **browser** | `test/app/platform/tab_attention_indicator_web_test.dart`, run with **`flutter test --platform chrome`** | the VM tests cannot execute `_web.dart`. Assert direct `document.title` changes and clear without a Flutter pump, one managed icon link after init/hot restart, active data URL then pristine clear, and safe unsupported Badging behavior |
| integration (browser) | `packages/client/integration_test/`, via `scripts/run_client_integration_web_local.sh` | forced-background regression: trigger a receipt and assert `window.__tenturaTabAttention.title`, `document.title`, and the direct adapter state |
| P0 re-verification (real browser) | direct-CDP harness, profile build, second QA session | genuine hidden app target is never activated post-receipt; direct controller title changes within seconds, then after >5 min within ~60 s; record visibility history, title latency, and reconnect evidence |

Run: `cd packages/client && flutter test`, then `flutter test --platform chrome
test/app/platform/tab_attention_indicator_web_test.dart`, then
`./scripts/check-custom-lints.sh packages/client` (never `flutter analyze` — it
does not load the plugin; the count is ratcheted against
`scripts/custom-lint-baseline.txt`).

> **CI note:** the pipeline runs plain `flutter test`, which does **not** pick up
> the `--platform chrome` suite. Either add that invocation to
> `.github/workflows/pipeline.yml` or accept that the browser adapter test is
> developer/pre-merge-run only — decide explicitly rather than by omission.

**Manual browser matrix (external follow-up — not automatable):**

| Browser | Title `(N)` | Favicon dot | Badge |
|---|---|---|---|
| Chrome, normal tab | ✅ expected | ✅ expected | **not written** (installed-context gate, §2.4) |
| Chrome, installed PWA | n/a (no tab strip) | n/a | ✅ expected on taskbar/dock |
| Firefox | ✅ expected | ✅ expected | absent → silently skipped |
| Safari | ✅ expected | best-effort (inconsistent dynamic-favicon support) | absent → silently skipped |

Plus these scenarios, each of which broke a rev-1 assumption:

- **Two Tentura tabs**, one focused: confirm the hidden one keeps `(N)` (§2.4).
- **PWA + browser tab** open together: confirm the tab never clears the PWA's badge.
- **Hot restart** with an active indicator: exactly one icon link, no stale data URL.
- **bfcache**: navigate away and back; confirm the indicator state is correct.
- **Logout** with unread pending: confirm all channels clear immediately.
- **Login screen** (no account): confirm no indicator ever appears.
- **Theme pinned to light/dark in settings** while the OS is the opposite:
  confirm the dot matches the *app's* theme.

**Closeout disposition (2026-08-11):** The product owner accepted every
unexecuted row above as pending external validation. They remain intentionally
unclaimed: installed-PWA physical OS badge and PWA+tab race require a real
installed PWA; Firefox tab chrome requires a suitable visual-capture context;
Safari requires macOS/iOS Safari. The accepted implementation and automated
evidence are recorded in the implementation journal; a later manual pass may
append evidence without reopening this delivery.

### P7 — Release hygiene

- **Semver bump** in `packages/client/pubspec.yaml`: choose the next **minor**
  release from the accepted implementation baseline (new user-visible,
  backward-compatible capability). The current uncommitted `5.10.1` work is
  unrelated and must not be staged, adopted, or overwritten by this plan.
- **Cache-buster sync**: after the scoped version bump, run the app once
  (`flutter run -d chrome` or `flutter build web`) so `hook/build.dart` rewrites
  `web/index.html` to that exact version, and **include that scoped diff in the
  feature commit**. `build_runner` does not do this; CI's
  `tool/verify_web_version_consistency.dart` only checks build output, so a
  stale committed `index.html` passes CI and then serves users a cached bundle.
- **Do not commit `web/manifest.json`** — deliberately `skip-worktree`.
- **`kDefaultMinClientVersion`** in `packages/server/lib/env.dart`: **no
  change**. This forces nothing on clients.
- **Docs**: add a row to `docs/README.md`'s active-plans table
  (`docs/README.md:41-44`); move this plan to `docs/archive/plans/` once shipped.
- **No `index.html` hand-edits.** The static `<link rel="icon">` and `<title>`
  stay as they are; everything is added at runtime.

---

## 5. Risks and how each is handled

| # | Risk | Handling |
|---|---|---|
| 1 | **Flutter does not repaint `Title` while hidden; a later visible Flutter write could overwrite a DOM title** (§1.1) | Active attention title is direct DOM by design. A reporter supplies the current localized base title, clear happens synchronously on visible, and P6 covers direct title writes without a Flutter pump. |
| 2 | **Hidden-tab timer throttling** delays the indicator | Leading-edge throttle (§2.2): the first change paints synchronously. |
| 3 | **The count may lag while hidden** — heartbeat pong-timeout false positives under intensive throttling can churn the socket | P0 proved short-hidden direct-DOM delivery only. P6 repeats the real direct-CDP test after >5 min and records whether delivery remains within ~60 s; a supervisor fix is separate work. |
| 4 | **Cross-context badge race** (PWA vs tab) | Only installed contexts write the badge (§2.4). |
| 5 | **Multi-tab chrome disagrees** | Accepted and documented as per-tab semantics (§2.4); on the manual matrix. |
| 6 | **Hot restart / bfcache duplicate the favicon link or capture a data URL as "original"** | Idempotent init keyed by element id + `data-static-href`; all icon links removed once; clear restores a constant path (P3b). Covered by the Chrome-platform test. |
| 7 | Safari ignores dynamic favicon updates | Accepted. Title is the mandatory channel (§2.1); matrix records favicon as best-effort there. |
| 8 | Badging throws where unsupported (static binding in `package:web`) | `has('setAppBadge')` + `try/catch` + swallowed promise rejection. |
| 9 | `toDataURL` `SecurityError`, or a future CSP without `img-src data:` | `try/catch` → degrades to title-only. Flagged for whoever adds a CSP; deployed headers to be verified. |
| 10 | Full-app rebuild on every count change | No Flutter rebuild is used for attention; the controller directly calls the platform adapter from its stream callback. |
| 11 | **Breaking system theme switching** by assigning the dispatcher's brightness callback | Forbidden in §2.1; P4 uses `WidgetsBindingObserver.didChangePlatformBrightness`. |
| 12 | Expensive `ThemeData` construction per repaint | `TenturaTabIndicator.resolve` memoizes per brightness (P2). |
| 13 | QA seam shipping to production | Compile-time `bool.fromEnvironment` const → tree-shaken (P3d). |
| 14 | Native regression | The stub pins `isBackground` to `false`, so the composed title is byte-identical to today's. Covered by the stub test. |

---

## 6. Out of scope (and the follow-ups they imply)

- Aggregating per-room (Chat) unread into the tab count — the number stays
  `AttentionCase.unreadTotal`, the same one the Updates navbar badge shows.
- Badging / notifications while the tab is **closed** — FCM + service worker.
- Cross-tab coordination (`BroadcastChannel`) for global clear-on-visit.
- Fixing the realtime heartbeat's throttled-timer pong-timeout false positives
  (P0 characterizes it; the fix is its own task).
- A digit rendered onto the favicon.
- Any server, container, or Caddy change.
- Native (mobile/desktop) app-icon badging.

## 7. Definition of done

1. Background tab + `unreadTotal > 0` → `(N) Tentura` (or `(99+) Tentura`),
   favicon shows a static dot; installed-PWA Chrome shows an OS badge.
2. `unreadTotal == 0` → no indication on any channel.
3. Count changes are reflected without a page reload, and **clear immediately**
   on focus — including when focus lands inside an open throttle window.
4. Firefox/Safari: title (and favicon on Firefox) work; Badging is silently
   skipped, with no in-app fallback UI and no permission prompt.
5. Nothing animates or blinks; the title never changes while the tab is visible.
6. The implemented direct controller passes the real CDP hidden-tab check: no
   app-tab activation after receipt; title changes while `visibilityState` is
   `hidden` within seconds, and again within ~60 s after >5 minutes hidden.
7. `flutter test` green; the `--platform chrome` adapter suite green;
   `./scripts/check-custom-lints.sh packages/client` green at baseline; native
   build unaffected.
8. The feature's next-minor `pubspec.yaml` version and `web/index.html`'s `?v=`
   match in the same scoped commit; unrelated version work remains untouched.

### Closeout disposition

Items 1–3 and 5–8 are accepted by the implementation, tests, and no-focus CDP
evidence recorded in the implementation journal. The manual portions of items
1 and 4 are explicitly accepted as pending external validation by the product
owner on 2026-08-11; they are not represented as passed browser observations.

---

## 8. Review dispositions (rev 1 → rev 3)

Codex CLI, adversarial pass against rev 1. Recorded so the corrections are not
silently re-lost. Every claim below was independently re-verified against the
code before acceptance.

| # | Finding (as filed) | Disposition |
|---|---|---|
| 1 | *BLOCKER:* the plan cannot meet its background-update criterion; hidden-tab delivery must be implemented via service worker now | **Superseded by measured P0.** `AttentionCase` refreshes while hidden, but Flutter does not repaint. A direct `package:web` title write from the unread callback changed the hidden title in 206 ms. Service workers cannot write a page DOM; direct page-DOM adapter is the minimal route. |
| 2 | `99+` does not match the Updates badge (`Badge.count` caps at 999) | **Accepted.** Verified `badge.dart:78`. Parity claim removed; §2.3 states the divergence and adds the one-line `maxCount: 99` alignment. |
| 3 | Record equality makes the claimed dedupe impossible above the cap | **Accepted.** Split into per-channel keys (§2.2); the trap is documented at the typedef and covered by test (c). |
| 4 | The throttle can delay clear-on-focus | **Accepted.** Clears now bypass the throttle entirely (§2.2.3); test (e). |
| 5 | Account switch can repaint stale data from a queued callback | **Accepted, simpler fix.** Trailing edge applies the *latest pending* value, never a captured one, so no generation counter is needed (P4); test (f). |
| 6 | Assigning `onPlatformBrightnessChanged` misuses a singleton callback | **Accepted, and worse than filed.** `RendererBinding` owns that slot (`rendering/binding.dart:60`), so assigning it would break `ThemeMode.system` app-wide. Now an explicit prohibition (§2.1) + `WidgetsBindingObserver`. |
| 7 | PWA/tab Badging race | **Accepted.** Installed-context gate (§2.4) removes the race by construction. |
| 8 | Multi-tab contradicts "clear after user visits" | **Accepted as a documentation gap.** Per-tab semantics stated explicitly (§2.4) + matrix scenario; cross-tab coordination deferred with rationale. |
| 9 | Favicon link management is not idempotent | **Accepted.** Id lookup + `data-static-href` + remove-all-icon-links (P3b); covered by the Chrome test. |
| 10 | Theme resolution is expensive and keys off OS brightness despite user-selected `themeMode` | **Accepted.** Memoized per brightness (P2); effective brightness derived from `SettingsCubit.themeMode` (P4). |
| 11 | VM tests cannot prove the web behavior | **Accepted.** Added a `flutter test --platform chrome` adapter suite + a browser integration case, with an explicit CI note. |
| 12 | The CSP claim is overstated | **Accepted.** Scoped to "this checkout's Caddyfiles" + verify deployed headers. |
| 13 | Engine citation off by five lines | **Accepted.** Now `:524` (assignment), with `:519` noted as the `case`. |
| 14 | The version target is stale | **Accepted, rechecked in rev3.** Select the next minor only from the accepted scoped baseline; do not infer it from unrelated uncommitted version work. |
| 15 | No bfcache/`pagehide` policy | **Accepted.** `pageshow`-with-`persisted` re-apply; no `pagehide` teardown, with rationale (P3a). |
| 16 | `unreadSummary.distinct()` is not unread-only | **Accepted.** Now `.map((s) => s.unreadTotal).distinct()` (P4), with the reason in §1. |

The rev-1 `onGenerateTitle` + `InheritedNotifier` mechanism remains valid only
when Flutter schedules its build; P0 proves it is not a background-tab delivery
mechanism, so rev3 does not use it. The `JSObject.has` / `JSPromise.toDart` /
`setAppBadge` / `onVisibilityChange` API surface is valid in the installed SDK
and `web-1.1.1`.

### Rev 3 measured disposition

The direct-CDP hypothesis run supersedes the journal's P0 block only for the
old Flutter-rendered route: direct page-DOM title writes are accepted as the
new implementation boundary. The implementation is still pending and must
repeat the real hidden/long-hidden check in P6 against its own controller.
